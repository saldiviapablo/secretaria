-- Migration: 20260830000010_functions_and_triggers.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)

-- ============================================================================
-- 1. Helper / Internal Functions in Schema `private`
-- ============================================================================

-- Function: private.set_updated_at()
CREATE OR REPLACE FUNCTION private.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    NEW.updated_at = pg_catalog.now();
    RETURN NEW;
END;
$$;

-- Function: private.prevent_historical_delete()
CREATE OR REPLACE FUNCTION private.prevent_historical_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION 'DELETE operation is blocked on historical/permanent table %', TG_TABLE_NAME;
    RETURN NULL;
END;
$$;

-- Function: private.normalize_search_text(text)
CREATE OR REPLACE FUNCTION private.normalize_search_text(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
AS $$
    SELECT pg_catalog.lower(
        public.unaccent(
            pg_catalog.regexp_replace(
                pg_catalog.btrim(COALESCE(p_text, '')),
                '\s+',
                ' ',
                'g'
            )
        )
    );
$$;

-- Function: private.normalize_entity_name()
CREATE OR REPLACE FUNCTION private.normalize_entity_name()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    NEW.normalized_name = private.normalize_search_text(NEW.canonical_name);
    RETURN NEW;
END;
$$;

-- Function: private.normalize_entity_alias()
CREATE OR REPLACE FUNCTION private.normalize_entity_alias()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    NEW.normalized_alias = private.normalize_search_text(NEW.alias);
    RETURN NEW;
END;
$$;

-- Function: private.sync_task_due_at()
CREATE OR REPLACE FUNCTION private.sync_task_due_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_tz text;
BEGIN
    IF NEW.time_known = false OR NEW.time_known IS NULL THEN
        IF NEW.due_time IS NOT NULL OR NEW.due_at IS NOT NULL THEN
            RAISE EXCEPTION 'due_time and due_at must be NULL when time_known is false';
        END IF;
        NEW.due_time = NULL;
        NEW.due_at = NULL;
        NEW.time_known = false;
    ELSE
        IF NEW.due_date IS NULL OR NEW.due_time IS NULL THEN
            RAISE EXCEPTION 'When time_known is true, due_date and due_time are required';
        END IF;
        IF NEW.due_timezone IS NULL OR pg_catalog.btrim(NEW.due_timezone) = '' THEN
            SELECT timezone INTO v_tz FROM public.profiles WHERE id = NEW.user_id;
            NEW.due_timezone = COALESCE(v_tz, 'America/Argentina/Buenos_Aires');
        END IF;
        NEW.due_at = (NEW.due_date + NEW.due_time) AT TIME ZONE NEW.due_timezone;
    END IF;
    RETURN NEW;
END;
$$;

-- Function: private.prevent_source_text_mutation()
CREATE OR REPLACE FUNCTION private.prevent_source_text_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF OLD.text_content <> NEW.text_content
       OR OLD.source_key <> NEW.source_key
       OR OLD.version_no <> NEW.version_no
       OR OLD.provider IS DISTINCT FROM NEW.provider
       OR OLD.model IS DISTINCT FROM NEW.model THEN
        RAISE EXCEPTION 'Cannot mutate source_texts content. Create a new version instead.';
    END IF;
    RETURN NEW;
END;
$$;

-- Function: private.capture_assistant_name_history()
CREATE OR REPLACE FUNCTION private.capture_assistant_name_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.assistant_name IS NOT NULL) OR
       (TG_OP = 'UPDATE' AND NEW.assistant_name IS NOT NULL AND OLD.assistant_name IS DISTINCT FROM NEW.assistant_name) THEN
        -- 1. Close previous active name history
        UPDATE public.assistant_name_history
        SET valid_to = pg_catalog.now()
        WHERE user_id = NEW.user_id AND valid_to IS NULL;

        -- 2. Insert new active name history
        INSERT INTO public.assistant_name_history (
            user_id,
            assistant_name,
            valid_from,
            valid_to,
            change_source,
            source_ingestion_id,
            created_at
        ) VALUES (
            NEW.user_id,
            NEW.assistant_name,
            pg_catalog.now(),
            NULL,
            COALESCE(NEW.last_modified_source, 'system'),
            NEW.assistant_name_source_ingestion_id,
            pg_catalog.now()
        );
    END IF;
    RETURN NEW;
END;
$$;

-- Function: private.audit_row_change()
CREATE OR REPLACE FUNCTION private.audit_row_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid;
    v_record_id uuid;
    v_changed_fields text[] := ARRAY[]::text[];
    v_key text;
    v_old_json jsonb;
    v_new_json jsonb;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_user_id := OLD.user_id;
        IF TG_TABLE_NAME = 'user_settings' THEN
            v_record_id := OLD.user_id;
        ELSE
            v_record_id := OLD.id;
        END IF;
        v_old_json := pg_catalog.to_jsonb(OLD);
    ELSIF TG_OP = 'INSERT' THEN
        v_user_id := NEW.user_id;
        IF TG_TABLE_NAME = 'user_settings' THEN
            v_record_id := NEW.user_id;
        ELSE
            v_record_id := NEW.id;
        END IF;
        v_new_json := pg_catalog.to_jsonb(NEW);
    ELSE -- UPDATE
        v_user_id := NEW.user_id;
        IF TG_TABLE_NAME = 'user_settings' THEN
            v_record_id := NEW.user_id;
        ELSE
            v_record_id := NEW.id;
        END IF;
        v_old_json := pg_catalog.to_jsonb(OLD);
        v_new_json := pg_catalog.to_jsonb(NEW);

        -- Detect changed keys
        FOR v_key IN SELECT pg_catalog.jsonb_object_keys(v_new_json) LOOP
            IF (v_old_json -> v_key) IS DISTINCT FROM (v_new_json -> v_key) THEN
                v_changed_fields := pg_catalog.array_append(v_changed_fields, v_key);
            END IF;
        END LOOP;
    END IF;

    INSERT INTO public.audit_log (
        user_id,
        table_name,
        record_id,
        action,
        actor_type,
        actor_id,
        db_role,
        before_data,
        after_data,
        changed_fields,
        occurred_at
    ) VALUES (
        v_user_id,
        TG_TABLE_NAME,
        v_record_id,
        TG_OP,
        'system',
        pg_catalog.current_setting('request.jwt.claim.sub', true),
        CURRENT_USER,
        v_old_json,
        v_new_json,
        v_changed_fields,
        pg_catalog.now()
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================================
-- 2. Triggers on Tables
-- ============================================================================

-- A. Updated_at triggers
CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_user_settings_updated_at BEFORE UPDATE ON public.user_settings
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_ingestions_updated_at BEFORE UPDATE ON public.ingestions
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_memory_items_updated_at BEFORE UPDATE ON public.memory_items
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_asset_locations_updated_at BEFORE UPDATE ON public.asset_locations
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_source_texts_updated_at BEFORE UPDATE ON public.source_texts
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_interpretations_updated_at BEFORE UPDATE ON public.interpretations
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_entities_updated_at BEFORE UPDATE ON public.entities
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_tasks_updated_at BEFORE UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_reminders_updated_at BEFORE UPDATE ON public.reminders
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_pending_clarifications_updated_at BEFORE UPDATE ON public.pending_clarifications
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER trg_reports_updated_at BEFORE UPDATE ON public.reports
    FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

-- B. Name & Alias Normalization Triggers
CREATE TRIGGER trg_entities_normalize_name BEFORE INSERT OR UPDATE OF canonical_name ON public.entities
    FOR EACH ROW EXECUTE FUNCTION private.normalize_entity_name();
CREATE TRIGGER trg_entity_aliases_normalize_alias BEFORE INSERT OR UPDATE OF alias ON public.entity_aliases
    FOR EACH ROW EXECUTE FUNCTION private.normalize_entity_alias();

-- C. Task Dates Synchronization Trigger
CREATE TRIGGER trg_tasks_sync_due_at BEFORE INSERT OR UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION private.sync_task_due_at();

-- D. Assistant Name History Capture Trigger
CREATE TRIGGER trg_user_settings_name_history AFTER INSERT OR UPDATE OF assistant_name ON public.user_settings
    FOR EACH ROW EXECUTE FUNCTION private.capture_assistant_name_history();

-- E. Source Text Immutability Trigger
CREATE TRIGGER trg_source_texts_immutable BEFORE UPDATE ON public.source_texts
    FOR EACH ROW EXECUTE FUNCTION private.prevent_source_text_mutation();

-- F. Prevent Historical Delete Triggers (on all 21 permanent tables)
DO $$
DECLARE
    t text;
    historical_tables text[] := ARRAY[
        'assistant_name_history',
        'ingestions',
        'memory_items',
        'memory_relations',
        'assets',
        'asset_locations',
        'memory_asset_links',
        'source_texts',
        'memory_chunks',
        'interpretations',
        'entities',
        'entity_aliases',
        'memory_entity_links',
        'facts',
        'tasks',
        'task_entity_links',
        'reminders',
        'notification_deliveries',
        'pending_clarifications',
        'reports',
        'ai_usage_events',
        'audit_log'
    ];
BEGIN
    FOREACH t IN ARRAY historical_tables LOOP
        EXECUTE format('
            CREATE TRIGGER "trg_prevent_delete_%I" BEFORE DELETE ON public.%I
                FOR EACH ROW EXECUTE FUNCTION private.prevent_historical_delete();
        ', t, t);
    END LOOP;
END $$;

-- G. Automatic Audit Triggers on Critical Tables
DO $$
DECLARE
    t text;
    audit_tables text[] := ARRAY[
        'user_settings',
        'memory_items',
        'entities',
        'facts',
        'tasks',
        'reminders',
        'pending_clarifications',
        'reports'
    ];
BEGIN
    FOREACH t IN ARRAY audit_tables LOOP
        EXECUTE format('
            CREATE TRIGGER "trg_audit_%I" AFTER INSERT OR UPDATE ON public.%I
                FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
        ', t, t);
    END LOOP;
END $$;

-- ============================================================================
-- 3. Public RPC Functions (04_DATABASE_SCHEMA.md Section 44)
-- ============================================================================

-- RPC 1: set_assistant_name
CREATE OR REPLACE FUNCTION public.set_assistant_name(
    p_user_id UUID,
    p_new_name TEXT,
    p_change_source TEXT DEFAULT 'system',
    p_source_ingestion_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_clean_name text;
BEGIN
    v_clean_name := pg_catalog.btrim(COALESCE(p_new_name, ''));
    IF v_clean_name = '' THEN
        RAISE EXCEPTION 'Assistant name cannot be empty';
    END IF;

    UPDATE public.user_settings
    SET assistant_name = v_clean_name,
        assistant_name_source_ingestion_id = p_source_ingestion_id,
        last_modified_source = p_change_source,
        updated_at = pg_catalog.now()
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User settings not found for user %', p_user_id;
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'assistant_name', v_clean_name,
        'user_id', p_user_id
    );
END;
$$;

-- RPC 2: transition_task_status
CREATE OR REPLACE FUNCTION public.transition_task_status(
    p_task_id UUID,
    p_target_status TEXT,
    p_source TEXT DEFAULT 'system',
    p_completion_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
BEGIN
    SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task % not found', p_task_id;
    END IF;

    IF p_target_status NOT IN ('pending', 'in_progress', 'waiting_confirmation', 'completed', 'postponed', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid target status %', p_target_status;
    END IF;

    UPDATE public.tasks
    SET status = p_target_status,
        last_modified_source = p_source,
        completion_note = COALESCE(p_completion_note, completion_note),
        started_at = CASE WHEN p_target_status = 'in_progress' AND started_at IS NULL THEN pg_catalog.now() ELSE started_at END,
        completed_at = CASE WHEN p_target_status = 'completed' THEN pg_catalog.now() ELSE completed_at END,
        postponed_at = CASE WHEN p_target_status = 'postponed' THEN pg_catalog.now() ELSE postponed_at END,
        cancelled_at = CASE WHEN p_target_status = 'cancelled' THEN pg_catalog.now() ELSE cancelled_at END,
        updated_at = pg_catalog.now()
    WHERE id = p_task_id;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'task_id', p_task_id,
        'previous_status', v_task.status,
        'current_status', p_target_status
    );
END;
$$;

-- RPC 3: correct_fact
CREATE OR REPLACE FUNCTION public.correct_fact(
    p_fact_id UUID,
    p_new_object_text TEXT DEFAULT NULL,
    p_new_object_entity_id UUID DEFAULT NULL,
    p_source_memory_id UUID DEFAULT NULL,
    p_source_interpretation_id UUID DEFAULT NULL,
    p_confidence NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_old_fact public.facts%ROWTYPE;
    v_new_fact_id UUID;
    v_mem_id UUID;
BEGIN
    SELECT * INTO v_old_fact FROM public.facts WHERE id = p_fact_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fact % not found', p_fact_id;
    END IF;

    -- 1. Supersede old fact
    UPDATE public.facts
    SET status = 'superseded'
    WHERE id = p_fact_id;

    v_mem_id := COALESCE(p_source_memory_id, v_old_fact.source_memory_id);

    -- 2. Insert new corrected fact
    INSERT INTO public.facts (
        user_id,
        subject_entity_id,
        subject_text,
        predicate,
        object_entity_id,
        object_text,
        object_value,
        polarity,
        status,
        valid_from_date,
        valid_to_date,
        temporal_granularity,
        recorded_at,
        source_memory_id,
        source_interpretation_id,
        supersedes_fact_id,
        confidence,
        created_at
    ) VALUES (
        v_old_fact.user_id,
        v_old_fact.subject_entity_id,
        v_old_fact.subject_text,
        v_old_fact.predicate,
        COALESCE(p_new_object_entity_id, v_old_fact.object_entity_id),
        COALESCE(p_new_object_text, v_old_fact.object_text),
        v_old_fact.object_value,
        v_old_fact.polarity,
        'current',
        v_old_fact.valid_from_date,
        v_old_fact.valid_to_date,
        v_old_fact.temporal_granularity,
        pg_catalog.now(),
        v_mem_id,
        COALESCE(p_source_interpretation_id, v_old_fact.source_interpretation_id),
        p_fact_id,
        COALESCE(p_confidence, v_old_fact.confidence),
        pg_catalog.now()
    ) RETURNING id INTO v_new_fact_id;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'old_fact_id', p_fact_id,
        'new_fact_id', v_new_fact_id
    );
END;
$$;

-- RPC 4: claim_due_reminders
CREATE OR REPLACE FUNCTION public.claim_due_reminders(
    p_limit INT DEFAULT 10,
    p_lease_duration INTERVAL DEFAULT INTERVAL '5 minutes'
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    task_id UUID,
    reminder_kind TEXT,
    planned_at TIMESTAMPTZ,
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_token UUID := pg_catalog.gen_random_uuid();
    v_expires TIMESTAMPTZ := pg_catalog.now() + p_lease_duration;
BEGIN
    RETURN QUERY
    WITH due_candidates AS (
        SELECT r.id
        FROM public.reminders r
        WHERE r.status IN ('pending', 'retry')
          AND r.planned_at <= pg_catalog.now()
          AND (r.suppressed_until IS NULL OR r.suppressed_until <= pg_catalog.now())
        ORDER BY r.planned_at ASC
        FOR UPDATE SKIP LOCKED
        LIMIT p_limit
    ),
    claimed AS (
        UPDATE public.reminders r
        SET status = 'sending',
            lease_token = v_token,
            lease_expires_at = v_expires,
            updated_at = pg_catalog.now()
        FROM due_candidates dc
        WHERE r.id = dc.id
        RETURNING r.id, r.user_id, r.task_id, r.reminder_kind, r.planned_at, r.lease_token, r.lease_expires_at
    )
    SELECT * FROM claimed;
END;
$$;

-- RPC 5: release_expired_reminder_leases
CREATE OR REPLACE FUNCTION public.release_expired_reminder_leases()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE public.reminders
    SET status = 'retry',
        lease_token = NULL,
        lease_expires_at = NULL,
        retry_count = retry_count + 1,
        updated_at = pg_catalog.now()
    WHERE status = 'sending'
      AND lease_expires_at < pg_catalog.now();

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'released_count', v_count
    );
END;
$$;

-- RPC 6: record_notification_result
CREATE OR REPLACE FUNCTION public.record_notification_result(
    p_reminder_id UUID,
    p_user_id UUID,
    p_channel TEXT,
    p_attempt_number INT,
    p_idempotency_key TEXT,
    p_status TEXT,
    p_provider_message_id TEXT DEFAULT NULL,
    p_error_code TEXT DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_delivery_id UUID;
BEGIN
    -- 1. Insert delivery record
    INSERT INTO public.notification_deliveries (
        user_id,
        reminder_id,
        channel,
        attempt_number,
        idempotency_key,
        status,
        attempted_at,
        sent_at,
        provider_message_id,
        error_code,
        error_message,
        response_metadata,
        created_at
    ) VALUES (
        p_user_id,
        p_reminder_id,
        p_channel,
        p_attempt_number,
        p_idempotency_key,
        p_status,
        pg_catalog.now(),
        CASE WHEN p_status = 'sent' THEN pg_catalog.now() ELSE NULL END,
        p_provider_message_id,
        p_error_code,
        p_error_message,
        COALESCE(p_metadata, '{}'::jsonb),
        pg_catalog.now()
    ) RETURNING id INTO v_delivery_id;

    -- 2. Update reminder status
    IF p_status = 'sent' THEN
        UPDATE public.reminders
        SET status = 'sent',
            sent_at = pg_catalog.now(),
            lease_token = NULL,
            lease_expires_at = NULL,
            updated_at = pg_catalog.now()
        WHERE id = p_reminder_id;
    ELSIF p_status = 'failed' THEN
        UPDATE public.reminders
        SET status = 'retry',
            last_error_code = p_error_code,
            last_error_message = p_error_message,
            retry_count = retry_count + 1,
            lease_token = NULL,
            lease_expires_at = NULL,
            updated_at = pg_catalog.now()
        WHERE id = p_reminder_id;
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'delivery_id', v_delivery_id,
        'reminder_status', p_status
    );
END;
$$;

-- RPC 7: resolve_clarification
CREATE OR REPLACE FUNCTION public.resolve_clarification(
    p_clarification_id UUID,
    p_answer_text TEXT,
    p_answer_ingestion_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE public.pending_clarifications
    SET status = 'resolved',
        resolved_at = pg_catalog.now(),
        answer_text = p_answer_text,
        answer_ingestion_id = p_answer_ingestion_id,
        updated_at = pg_catalog.now()
    WHERE id = p_clarification_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Clarification % not found', p_clarification_id;
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'clarification_id', p_clarification_id,
        'status', 'resolved'
    );
END;
$$;

-- RPC 8: search_memory_text
CREATE OR REPLACE FUNCTION public.search_memory_text(
    p_user_id UUID,
    p_query TEXT,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    chunk_id UUID,
    memory_id UUID,
    source_text_id UUID,
    text_content TEXT,
    rank REAL
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT
        c.id AS chunk_id,
        c.memory_id,
        c.source_text_id,
        c.text_content,
        pg_catalog.ts_rank(c.fts, pg_catalog.plainto_tsquery('simple', p_query)) AS rank
    FROM public.memory_chunks c
    WHERE c.user_id = p_user_id
      AND c.is_active = true
      AND c.fts @@ pg_catalog.plainto_tsquery('simple', p_query)
    ORDER BY rank DESC
    LIMIT p_limit;
$$;

-- RPC 9: search_entities_fuzzy
CREATE OR REPLACE FUNCTION public.search_entities_fuzzy(
    p_user_id UUID,
    p_query TEXT,
    p_limit INT DEFAULT 5,
    p_similarity_threshold REAL DEFAULT 0.3
)
RETURNS TABLE (
    entity_id UUID,
    canonical_name TEXT,
    entity_type TEXT,
    matched_alias TEXT,
    similarity REAL
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH query_norm AS (
        SELECT private.normalize_search_text(p_query) AS q
    ),
    entity_matches AS (
        SELECT
            e.id AS entity_id,
            e.canonical_name,
            e.entity_type,
            e.canonical_name AS matched_alias,
            public.similarity(e.normalized_name, qn.q) AS sim
        FROM public.entities e, query_norm qn
        WHERE e.user_id = p_user_id
          AND e.status = 'active'
          AND public.similarity(e.normalized_name, qn.q) >= p_similarity_threshold

        UNION ALL

        SELECT
            a.entity_id,
            e.canonical_name,
            e.entity_type,
            a.alias AS matched_alias,
            public.similarity(a.normalized_alias, qn.q) AS sim
        FROM public.entity_aliases a
        JOIN public.entities e ON e.id = a.entity_id
        CROSS JOIN query_norm qn
        WHERE a.user_id = p_user_id
          AND a.is_active = true
          AND e.status = 'active'
          AND public.similarity(a.normalized_alias, qn.q) >= p_similarity_threshold
    )
    SELECT DISTINCT ON (entity_id)
        entity_id,
        canonical_name,
        entity_type,
        matched_alias,
        sim AS similarity
    FROM entity_matches
    ORDER BY entity_id, sim DESC
    LIMIT p_limit;
$$;

-- RPC 10: register_ingestion (atomic helper RPC)
CREATE OR REPLACE FUNCTION public.register_ingestion(
    p_user_id UUID,
    p_source_channel TEXT,
    p_source_kind TEXT,
    p_idempotency_key TEXT,
    p_captured_at TIMESTAMPTZ,
    p_source_event_key TEXT DEFAULT NULL,
    p_telegram_update_id BIGINT DEFAULT NULL,
    p_telegram_message_id BIGINT DEFAULT NULL,
    p_telegram_chat_id BIGINT DEFAULT NULL,
    p_telegram_user_id BIGINT DEFAULT NULL,
    p_telegram_file_id TEXT DEFAULT NULL,
    p_drive_file_id TEXT DEFAULT NULL,
    p_source_url TEXT DEFAULT NULL,
    p_source_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_existing_id UUID;
    v_existing_status TEXT;
    v_new_id UUID;
BEGIN
    -- Atomic INSERT with ON CONFLICT DO NOTHING
    INSERT INTO public.ingestions (
        user_id,
        source_channel,
        source_kind,
        source_event_key,
        telegram_update_id,
        telegram_message_id,
        telegram_chat_id,
        telegram_user_id,
        telegram_file_id,
        drive_file_id,
        source_url,
        idempotency_key,
        captured_at,
        received_at,
        status,
        source_metadata,
        created_at
    ) VALUES (
        p_user_id,
        p_source_channel,
        p_source_kind,
        p_source_event_key,
        p_telegram_update_id,
        p_telegram_message_id,
        p_telegram_chat_id,
        p_telegram_user_id,
        p_telegram_file_id,
        p_drive_file_id,
        p_source_url,
        p_idempotency_key,
        p_captured_at,
        pg_catalog.now(),
        'received',
        COALESCE(p_source_metadata, '{}'::jsonb),
        pg_catalog.now()
    )
    ON CONFLICT (user_id, idempotency_key) DO NOTHING
    RETURNING id INTO v_new_id;

    IF v_new_id IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'status', 'received',
            'ingestion_id', v_new_id,
            'is_duplicate', false
        );
    ELSE
        SELECT id, status INTO v_existing_id, v_existing_status
        FROM public.ingestions
        WHERE user_id = p_user_id AND idempotency_key = p_idempotency_key;

        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'status', 'duplicate',
            'ingestion_id', v_existing_id,
            'existing_status', v_existing_status,
            'is_duplicate', true
        );
    END IF;
END;
$$;

-- Grant EXECUTE on RPC functions to authenticated & service_role
GRANT EXECUTE ON FUNCTION public.set_assistant_name TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.transition_task_status TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.correct_fact TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_due_reminders TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_expired_reminder_leases TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_notification_result TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_clarification TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_memory_text TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_entities_fuzzy TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_ingestion TO authenticated, service_role;
