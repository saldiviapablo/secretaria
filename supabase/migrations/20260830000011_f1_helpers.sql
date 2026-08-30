-- Migration: 20260830000011_f1_helpers.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (F1 — Telegram Texto + Tareas)

-- ============================================================================
-- 1. Helper RPC: get_or_create_source_text
-- Inserts or versions source_texts safely with ownership validation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_or_create_source_text(
    p_user_id uuid,
    p_ingestion_id uuid,
    p_text_content text,
    p_source_key text,
    p_source_type text DEFAULT 'telegram_text',
    p_is_preferred boolean DEFAULT true,
    p_supersedes_source_text_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_st_id uuid;
    v_version_no integer := 1;
    v_old_st record;
BEGIN
    -- Ownership check
    IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot create source_text for another user';
    END IF;

    -- If superseding a previous version (e.g. edited_message)
    IF p_supersedes_source_text_id IS NOT NULL THEN
        SELECT id, user_id, version_no, source_key INTO v_old_st
        FROM public.source_texts
        WHERE id = p_supersedes_source_text_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Superseded source_text % not found', p_supersedes_source_text_id;
        END IF;

        IF v_old_st.user_id <> p_user_id THEN
            RAISE EXCEPTION 'Unauthorized: cannot supersede source_text belonging to another user';
        END IF;

        -- Demote previous version preferred flag
        UPDATE public.source_texts
        SET is_preferred = false
        WHERE id = p_supersedes_source_text_id;

        v_version_no := v_old_st.version_no + 1;
    END IF;

    -- Insert new version
    INSERT INTO public.source_texts (
        user_id,
        ingestion_id,
        source_key,
        source_type,
        text_content,
        version_no,
        is_preferred,
        supersedes_source_text_id,
        created_at
    ) VALUES (
        p_user_id,
        p_ingestion_id,
        COALESCE(p_source_key, 'src_' || pg_catalog.to_char(pg_catalog.now(), 'YYYYMMDD_HH24MISS')),
        p_source_type,
        p_text_content,
        v_version_no,
        p_is_preferred,
        p_supersedes_source_text_id,
        pg_catalog.now()
    )
    RETURNING id INTO v_st_id;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'source_text_id', v_st_id,
        'version_no', v_version_no,
        'is_preferred', p_is_preferred
    );
END;
$$;

-- Grant execute permissions on get_or_create_source_text
REVOKE ALL ON FUNCTION public.get_or_create_source_text(uuid, uuid, text, text, text, boolean, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_or_create_source_text(uuid, uuid, text, text, text, boolean, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_source_text(uuid, uuid, text, text, text, boolean, uuid) TO service_role;


-- ============================================================================
-- 2. Helper RPC: apply_interpretation_bundle
-- Atomically creates interpretation, memory_item, entities, facts, tasks,
-- and links in a single database transaction with strict multi-tenant validation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_interpretation_bundle(
    p_user_id uuid,
    p_ingestion_id uuid,
    p_source_text_id uuid,
    p_interpretation jsonb,
    p_raw_output text DEFAULT NULL,
    p_provider text DEFAULT 'openai',
    p_model text DEFAULT 'gpt-5.6-luna',
    p_prompt_id text DEFAULT 'P-INT-001',
    p_prompt_version text DEFAULT '1.0',
    p_schema_version text DEFAULT '1.0'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_interpretation_id uuid;
    v_memory_id uuid := NULL;
    v_task_ids uuid[] := '{}';
    v_task_elem jsonb;
    v_entity_elem jsonb;
    v_fact_elem jsonb;
    v_entity_id uuid;
    v_task_id uuid;
    v_person_name text;
    v_task_title text;
    v_task_desc text;
    v_due_date date;
    v_due_time time;
    v_time_known boolean;
    v_priority text;
    v_priority_source text;
    v_task_status text;
    v_idemp_key text;
    v_confidence numeric;
    v_intent text;
BEGIN
    -- Ownership verification
    IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot apply interpretation for another user';
    END IF;

    -- Extract basic interpretation fields
    v_intent := COALESCE(p_interpretation->>'intent', 'note');
    v_confidence := COALESCE((p_interpretation->>'confidence')::numeric, 0.9);

    -- 1. Insert into interpretations
    INSERT INTO public.interpretations (
        user_id,
        source_text_id,
        purpose,
        provider,
        model,
        prompt_version,
        output_text,
        output_json,
        status,
        confidence,
        created_at
    ) VALUES (
        p_user_id,
        p_source_text_id,
        'structured_intent',
        p_provider,
        p_model,
        p_prompt_version,
        p_raw_output,
        p_interpretation,
        'validated',
        v_confidence,
        pg_catalog.now()
    )
    RETURNING id INTO v_interpretation_id;

    -- 2. Create memory_item if applicable
    IF v_intent IN ('note', 'create_task', 'update_task', 'conversation', 'correction') THEN
        INSERT INTO public.memory_items (
            user_id,
            ingestion_id,
            memory_type,
            title,
            normalized_content,
            created_at
        ) VALUES (
            p_user_id,
            p_ingestion_id,
            CASE WHEN v_intent = 'create_task' THEN 'task' ELSE 'note' END,
            pg_catalog.left(COALESCE(p_interpretation->'tasks'->0->>'title', 'Nota ' || pg_catalog.to_char(pg_catalog.now(), 'YYYY-MM-DD HH24:MI')), 255),
            v_intent,
            pg_catalog.now()
        )
        RETURNING id INTO v_memory_id;
    END IF;

    -- 3. Process Entities
    IF p_interpretation ? 'entities' AND pg_catalog.jsonb_typeof(p_interpretation->'entities') = 'array' THEN
        FOR v_entity_elem IN SELECT * FROM pg_catalog.jsonb_array_elements(p_interpretation->'entities')
        LOOP
            IF v_entity_elem ? 'mention' AND pg_catalog.btrim(v_entity_elem->>'mention') <> '' THEN
                -- Check if entity already exists for user
                SELECT id INTO v_entity_id
                FROM public.entities
                WHERE user_id = p_user_id
                  AND normalized_name = private.normalize_search_text(COALESCE(v_entity_elem->>'canonical_name_candidate', v_entity_elem->>'mention'))
                LIMIT 1;

                IF v_entity_id IS NULL THEN
                    INSERT INTO public.entities (
                        user_id,
                        canonical_name,
                        entity_type,
                        source_memory_id,
                        created_at
                    ) VALUES (
                        p_user_id,
                        COALESCE(v_entity_elem->>'canonical_name_candidate', v_entity_elem->>'mention'),
                        'person',
                        v_memory_id,
                        pg_catalog.now()
                    )
                    RETURNING id INTO v_entity_id;
                END IF;

                -- Link entity to memory if memory exists
                IF v_memory_id IS NOT NULL THEN
                    INSERT INTO public.memory_entity_links (
                        user_id,
                        memory_id,
                        entity_id,
                        link_type,
                        created_at
                    ) VALUES (
                        p_user_id,
                        v_memory_id,
                        v_entity_id,
                        COALESCE(v_entity_elem->>'role', 'mentioned'),
                        pg_catalog.now()
                    )
                    ON CONFLICT DO NOTHING;
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- 4. Process Tasks
    IF p_interpretation ? 'tasks' AND pg_catalog.jsonb_typeof(p_interpretation->'tasks') = 'array' THEN
        FOR v_task_elem IN SELECT * FROM pg_catalog.jsonb_array_elements(p_interpretation->'tasks')
        LOOP
            v_task_title := v_task_elem->>'title';
            v_task_desc := v_task_elem->>'description';
            v_due_date := NULL;
            IF v_task_elem->>'resolved_date_candidate' IS NOT NULL AND pg_catalog.btrim(v_task_elem->>'resolved_date_candidate') <> '' THEN
                v_due_date := (v_task_elem->>'resolved_date_candidate')::date;
            END IF;

            v_time_known := COALESCE((v_task_elem->>'time_known')::boolean, false);
            v_due_time := NULL;
            IF v_time_known AND v_task_elem->>'time_candidate' IS NOT NULL AND pg_catalog.btrim(v_task_elem->>'time_candidate') <> '' THEN
                v_due_time := (v_task_elem->>'time_candidate')::time;
            END IF;

            v_priority := COALESCE(v_task_elem->>'priority', 'normal');
            v_priority_source := COALESCE(v_task_elem->>'priority_source', 'ai');
            v_task_status := COALESCE(v_task_elem->>'status_candidate', 'pending');

            -- Deterministic task idempotency key
            v_idemp_key := 'task:auto:' || p_ingestion_id::text || ':' || pg_catalog.md5(v_task_elem::text);

            -- Insert task
            INSERT INTO public.tasks (
                user_id,
                title,
                description,
                due_date,
                due_time,
                due_timezone,
                time_known,
                priority,
                priority_source,
                status,
                source_memory_id,
                source_interpretation_id,
                idempotency_key,
                created_at
            ) VALUES (
                p_user_id,
                v_task_title,
                v_task_desc,
                v_due_date,
                v_due_time,
                CASE WHEN v_time_known THEN 'America/Argentina/Buenos_Aires' ELSE NULL END,
                v_time_known,
                v_priority,
                v_priority_source,
                v_task_status,
                v_memory_id,
                v_interpretation_id,
                v_idemp_key,
                pg_catalog.now()
            )
            ON CONFLICT (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO UPDATE
            SET updated_at = pg_catalog.now()
            RETURNING id INTO v_task_id;

            v_task_ids := v_task_ids || v_task_id;

            -- Link task entities
            IF v_task_elem ? 'person_mentions' AND pg_catalog.jsonb_typeof(v_task_elem->'person_mentions') = 'array' THEN
                FOR v_person_name IN SELECT jsonb_array_elements_text(v_task_elem->'person_mentions')
                LOOP
                    SELECT id INTO v_entity_id
                    FROM public.entities
                    WHERE user_id = p_user_id
                      AND normalized_name = private.normalize_search_text(v_person_name)
                    LIMIT 1;

                    IF v_entity_id IS NOT NULL THEN
                        INSERT INTO public.task_entity_links (
                            user_id,
                            task_id,
                            entity_id,
                            role,
                            created_at
                        ) VALUES (
                            p_user_id,
                            v_task_id,
                            v_entity_id,
                            'assignee',
                            pg_catalog.now()
                        )
                        ON CONFLICT DO NOTHING;
                    END IF;
                END LOOP;
            END IF;
        END LOOP;
    END IF;

    -- 5. Process Facts
    IF p_interpretation ? 'facts' AND pg_catalog.jsonb_typeof(p_interpretation->'facts') = 'array' AND v_memory_id IS NOT NULL THEN
        FOR v_fact_elem IN SELECT * FROM pg_catalog.jsonb_array_elements(p_interpretation->'facts')
        LOOP
            INSERT INTO public.facts (
                user_id,
                source_memory_id,
                subject_text,
                predicate,
                object_text,
                polarity,
                status,
                created_at
            ) VALUES (
                p_user_id,
                v_memory_id,
                COALESCE(v_fact_elem->>'subject_mention', 'Usuario'),
                COALESCE(v_fact_elem->>'predicate', 'related_to'),
                COALESCE(v_fact_elem->>'object_text', v_fact_elem->>'object_entity_mention', ''),
                COALESCE(v_fact_elem->>'polarity', 'positive'),
                'current',
                pg_catalog.now()
            );
        END LOOP;
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'status', 'applied',
        'interpretation_id', v_interpretation_id,
        'memory_id', v_memory_id,
        'task_ids', v_task_ids
    );
END;
$$;

-- Grant execute permissions on apply_interpretation_bundle
REVOKE ALL ON FUNCTION public.apply_interpretation_bundle(uuid, uuid, uuid, jsonb, text, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_interpretation_bundle(uuid, uuid, uuid, jsonb, text, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_interpretation_bundle(uuid, uuid, uuid, jsonb, text, text, text, text, text, text) TO service_role;


-- ============================================================================
-- 3. Helper Function: query_tasks_filtered
-- Deterministic filtering of tasks with linked entities
-- ============================================================================

CREATE OR REPLACE FUNCTION public.query_tasks_filtered(
    p_user_id uuid,
    p_status text DEFAULT NULL,
    p_priority text DEFAULT NULL,
    p_due_date_from date DEFAULT NULL,
    p_due_date_to date DEFAULT NULL,
    p_limit integer DEFAULT 50
)
RETURNS TABLE (
    task_id uuid,
    title text,
    description text,
    status text,
    priority text,
    due_date date,
    due_time time,
    time_known boolean,
    due_at timestamptz,
    linked_entities jsonb,
    created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
    SELECT
        t.id AS task_id,
        t.title,
        t.description,
        t.status,
        t.priority,
        t.due_date,
        t.due_time,
        t.time_known,
        t.due_at,
        COALESCE(
            (
                SELECT pg_catalog.jsonb_agg(
                    pg_catalog.jsonb_build_object(
                        'entity_id', e.id,
                        'name', e.canonical_name,
                        'role', tel.role
                    )
                )
                FROM public.task_entity_links tel
                JOIN public.entities e ON e.id = tel.entity_id AND e.user_id = t.user_id
                WHERE tel.task_id = t.id AND tel.user_id = t.user_id
            ),
            '[]'::jsonb
        ) AS linked_entities,
        t.created_at
    FROM public.tasks t
    WHERE t.user_id = p_user_id
      AND (p_status IS NULL OR t.status = p_status)
      AND (p_priority IS NULL OR t.priority = p_priority)
      AND (p_due_date_from IS NULL OR t.due_date >= p_due_date_from)
      AND (p_due_date_to IS NULL OR t.due_date <= p_due_date_to)
    ORDER BY t.due_date ASC NULLS LAST, t.due_time ASC NULLS LAST, t.created_at DESC
    LIMIT p_limit;
$$;

-- Grant execute permissions on query_tasks_filtered
REVOKE ALL ON FUNCTION public.query_tasks_filtered(uuid, text, text, date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.query_tasks_filtered(uuid, text, text, date, date, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.query_tasks_filtered(uuid, text, text, date, date, integer) TO service_role;
