-- Migration: 20260830000012_f2_reminder_runtime.sql
-- Project: Secretaria Virtual con IA
-- Baseline: SVIA-DOCSET-V1-RC1
-- Phase: F2 — Recordatorios
--
-- Additive F2 runtime hardening. No product tables are added or removed.
-- The 25-table V1 model is preserved.
--
-- IMPORTANT:
-- The exact long-term retry/backoff policy and final lease duration remain
-- pending baseline decisions. This migration therefore:
--   * keeps the existing 5-minute claim default as a callable default;
--   * allows an explicit lease duration parameter;
--   * never invents a retry time after FAILED/UNKNOWN;
--   * only makes an expired lease immediately retryable when no external
--     attempt was recorded (worker-crash recovery, not provider backoff).

CREATE INDEX IF NOT EXISTS reminders_retry_due_idx
    ON public.reminders (next_retry_at)
    WHERE status = 'retry' AND next_retry_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS notification_deliveries_reminder_attempt_idx
    ON public.notification_deliveries (reminder_id, attempt_number DESC);

-- ============================================================================
-- 1. PLAN REMINDERS FOR A TASK
-- ============================================================================
CREATE OR REPLACE FUNCTION public.plan_task_reminders(
    p_user_id uuid,
    p_task_id uuid,
    p_additional_reminders jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_default_minutes integer;
    v_default_at timestamptz;
    v_elem jsonb;
    v_kind text;
    v_planned_at timestamptz;
    v_reason text;
    v_key text;
    v_id uuid;
    v_existing_id uuid;
    v_created_count integer := 0;
    v_existing_count integer := 0;
    v_ids jsonb := '[]'::jsonb;
    v_skipped jsonb := '[]'::jsonb;
BEGIN
    IF p_user_id IS NULL OR p_task_id IS NULL THEN
        RAISE EXCEPTION 'user_id and task_id are required';
    END IF;

    IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot plan reminders for another user';
    END IF;

    SELECT *
    INTO v_task
    FROM public.tasks
    WHERE id = p_task_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task % not found', p_task_id;
    END IF;

    IF v_task.user_id <> p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: task does not belong to supplied user';
    END IF;

    IF v_task.status IN ('completed', 'cancelled') THEN
        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'status', 'no_op',
            'reason', 'task_terminal',
            'task_id', p_task_id,
            'created_count', 0,
            'existing_count', 0,
            'reminder_ids', '[]'::jsonb,
            'skipped', pg_catalog.jsonb_build_array('task_terminal')
        );
    END IF;

    SELECT COALESCE(us.default_reminder_minutes_before, 180)
    INTO v_default_minutes
    FROM public.user_settings us
    WHERE us.user_id = p_user_id;

    v_default_minutes := COALESCE(v_default_minutes, 180);

    -- No base reminder when the task has no real due_at.
    -- A date-only task MUST NOT receive an invented clock time.
    IF v_task.due_at IS NOT NULL THEN
        v_default_at := v_task.due_at - pg_catalog.make_interval(mins => v_default_minutes);

        IF v_default_at > pg_catalog.now() THEN
            v_key :=
                'reminder:' || p_task_id::text || ':base:' ||
                pg_catalog.to_char(
                    v_default_at AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS"Z"'
                );

            v_id := NULL;
            INSERT INTO public.reminders (
                user_id,
                task_id,
                reminder_kind,
                planned_at,
                status,
                can_break_silence,
                reason,
                idempotency_key,
                created_at,
                updated_at
            )
            VALUES (
                p_user_id,
                p_task_id,
                'base',
                v_default_at,
                'pending',
                false,
                'default_reminder_' || v_default_minutes::text || '_minutes_before',
                v_key,
                pg_catalog.now(),
                pg_catalog.now()
            )
            ON CONFLICT (user_id, idempotency_key) DO NOTHING
            RETURNING id INTO v_id;

            IF v_id IS NULL THEN
                SELECT id INTO v_existing_id
                FROM public.reminders
                WHERE user_id = p_user_id
                  AND idempotency_key = v_key;

                v_existing_count := v_existing_count + 1;
                v_ids := v_ids || pg_catalog.jsonb_build_array(v_existing_id);
            ELSE
                v_created_count := v_created_count + 1;
                v_ids := v_ids || pg_catalog.jsonb_build_array(v_id);
            END IF;
        ELSE
            v_skipped := v_skipped || pg_catalog.jsonb_build_array(
                'default_reminder_would_be_in_the_past'
            );
        END IF;
    ELSE
        v_skipped := v_skipped || pg_catalog.jsonb_build_array(
            'default_reminder_not_created_time_unknown'
        );
    END IF;

    IF p_additional_reminders IS NULL THEN
        p_additional_reminders := '[]'::jsonb;
    END IF;

    IF pg_catalog.jsonb_typeof(p_additional_reminders) <> 'array' THEN
        RAISE EXCEPTION 'additional_reminders must be a JSON array';
    END IF;

    FOR v_elem IN
        SELECT value
        FROM pg_catalog.jsonb_array_elements(p_additional_reminders)
    LOOP
        v_kind := COALESCE(NULLIF(pg_catalog.btrim(v_elem->>'kind'), ''), 'ai');

        IF v_kind NOT IN ('ai', 'followup', 'manual') THEN
            v_skipped := v_skipped || pg_catalog.jsonb_build_array(
                'invalid_additional_reminder_kind'
            );
            CONTINUE;
        END IF;

        IF v_elem->>'planned_at' IS NULL OR pg_catalog.btrim(v_elem->>'planned_at') = '' THEN
            v_skipped := v_skipped || pg_catalog.jsonb_build_array(
                'additional_reminder_missing_planned_at'
            );
            CONTINUE;
        END IF;

        BEGIN
            v_planned_at := (v_elem->>'planned_at')::timestamptz;
        EXCEPTION WHEN OTHERS THEN
            v_skipped := v_skipped || pg_catalog.jsonb_build_array(
                'additional_reminder_invalid_planned_at'
            );
            CONTINUE;
        END;

        -- Pre-event reminders require a known absolute due time.
        -- Follow-ups are post-task operational events and may use scheduler time.
        IF v_kind <> 'followup' AND v_task.due_at IS NULL THEN
            v_skipped := v_skipped || pg_catalog.jsonb_build_array(
                'pre_event_reminder_rejected_task_time_unknown'
            );
            CONTINUE;
        END IF;

        IF v_kind <> 'followup'
           AND v_task.due_at IS NOT NULL
           AND v_planned_at > v_task.due_at THEN
            v_skipped := v_skipped || pg_catalog.jsonb_build_array(
                'pre_event_reminder_after_task_due_at'
            );
            CONTINUE;
        END IF;

        IF v_kind <> 'followup' AND v_planned_at <= pg_catalog.now() THEN
            v_skipped := v_skipped || pg_catalog.jsonb_build_array(
                'pre_event_reminder_in_the_past'
            );
            CONTINUE;
        END IF;

        v_reason := NULLIF(pg_catalog.btrim(v_elem->>'reason'), '');
        v_key :=
            'reminder:' || p_task_id::text || ':' || v_kind || ':' ||
            pg_catalog.to_char(
                v_planned_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS"Z"'
            );

        v_id := NULL;
        INSERT INTO public.reminders (
            user_id,
            task_id,
            reminder_kind,
            planned_at,
            status,
            can_break_silence,
            reason,
            idempotency_key,
            created_at,
            updated_at
        )
        VALUES (
            p_user_id,
            p_task_id,
            v_kind,
            v_planned_at,
            'pending',
            false,
            v_reason,
            v_key,
            pg_catalog.now(),
            pg_catalog.now()
        )
        ON CONFLICT (user_id, idempotency_key) DO NOTHING
        RETURNING id INTO v_id;

        IF v_id IS NULL THEN
            SELECT id INTO v_existing_id
            FROM public.reminders
            WHERE user_id = p_user_id
              AND idempotency_key = v_key;

            v_existing_count := v_existing_count + 1;
            v_ids := v_ids || pg_catalog.jsonb_build_array(v_existing_id);
        ELSE
            v_created_count := v_created_count + 1;
            v_ids := v_ids || pg_catalog.jsonb_build_array(v_id);
        END IF;
    END LOOP;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'status', 'planned',
        'task_id', p_task_id,
        'created_count', v_created_count,
        'existing_count', v_existing_count,
        'reminder_ids', v_ids,
        'skipped', v_skipped
    );
END;
$$;

-- ============================================================================
-- 2. CLAIM DUE REMINDERS — F2 delivery-aware implementation
-- ============================================================================
DROP FUNCTION IF EXISTS public.claim_due_reminders(integer, interval);

CREATE FUNCTION public.claim_due_reminders(
    p_limit integer DEFAULT 10,
    p_lease_duration interval DEFAULT INTERVAL '5 minutes'
)
RETURNS TABLE (
    id uuid,
    user_id uuid,
    task_id uuid,
    reminder_kind text,
    planned_at timestamptz,
    reason text,
    can_break_silence boolean,
    retry_count integer,
    attempt_number integer,
    lease_token uuid,
    lease_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
        RAISE EXCEPTION 'p_limit must be between 1 and 100';
    END IF;

    IF p_lease_duration IS NULL OR p_lease_duration <= INTERVAL '0 seconds' THEN
        RAISE EXCEPTION 'p_lease_duration must be positive';
    END IF;

    RETURN QUERY
    WITH due_candidates AS (
        SELECT
            r.id,
            (
                SELECT COALESCE(pg_catalog.max(d.attempt_number), 0) + 1
                FROM public.notification_deliveries d
                WHERE d.reminder_id = r.id
            )::integer AS next_attempt
        FROM public.reminders r
        WHERE (
                (r.status = 'pending' AND r.planned_at <= pg_catalog.now())
                OR
                (r.status = 'retry'
                 AND r.next_retry_at IS NOT NULL
                 AND r.next_retry_at <= pg_catalog.now())
              )
          AND (r.suppressed_until IS NULL OR r.suppressed_until <= pg_catalog.now())
          AND NOT EXISTS (
              SELECT 1
              FROM public.notification_deliveries d_sent
              WHERE d_sent.reminder_id = r.id
                AND d_sent.status = 'sent'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.notification_deliveries d_unknown
              WHERE d_unknown.reminder_id = r.id
                AND d_unknown.status = 'unknown'
                AND d_unknown.attempt_number = (
                    SELECT pg_catalog.max(d2.attempt_number)
                    FROM public.notification_deliveries d2
                    WHERE d2.reminder_id = r.id
                )
          )
        ORDER BY
            CASE WHEN r.status = 'retry' THEN r.next_retry_at ELSE r.planned_at END ASC,
            r.id
        FOR UPDATE OF r SKIP LOCKED
        LIMIT p_limit
    ),
    claimed AS (
        UPDATE public.reminders r
        SET status = 'sending',
            lease_token = pg_catalog.gen_random_uuid(),
            lease_expires_at = pg_catalog.now() + p_lease_duration,
            updated_at = pg_catalog.now()
        FROM due_candidates dc
        WHERE r.id = dc.id
        RETURNING
            r.id,
            r.user_id,
            r.task_id,
            r.reminder_kind,
            r.planned_at,
            r.reason,
            r.can_break_silence,
            r.retry_count,
            dc.next_attempt,
            r.lease_token,
            r.lease_expires_at
    )
    SELECT
        c.id,
        c.user_id,
        c.task_id,
        c.reminder_kind,
        c.planned_at,
        c.reason,
        c.can_break_silence,
        c.retry_count,
        c.next_attempt AS attempt_number,
        c.lease_token,
        c.lease_expires_at
    FROM claimed c;
END;
$$;

-- ============================================================================
-- 3. RECORD NOTIFICATION ATTEMPT / FINAL RESULT
-- ============================================================================
DROP FUNCTION IF EXISTS public.record_notification_result(
    uuid, uuid, text, integer, text, text, text, text, text, jsonb
);

CREATE FUNCTION public.record_notification_result(
    p_reminder_id uuid,
    p_user_id uuid,
    p_channel text,
    p_attempt_number integer,
    p_idempotency_key text,
    p_status text,
    p_provider_message_id text DEFAULT NULL,
    p_error_code text DEFAULT NULL,
    p_error_message text DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb,
    p_next_retry_at timestamptz DEFAULT NULL,
    p_lease_token uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_reminder public.reminders%ROWTYPE;
    v_delivery public.notification_deliveries%ROWTYPE;
    v_delivery_id uuid;
    v_was_duplicate boolean := false;
    v_current_reminder_status text;
BEGIN
    IF p_status NOT IN ('attempting', 'sent', 'failed', 'unknown') THEN
        RAISE EXCEPTION 'Invalid notification delivery status %', p_status;
    END IF;

    IF p_attempt_number IS NULL OR p_attempt_number < 1 THEN
        RAISE EXCEPTION 'attempt_number must be >= 1';
    END IF;

    IF p_idempotency_key IS NULL OR pg_catalog.btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'delivery idempotency_key is required';
    END IF;

    SELECT *
    INTO v_reminder
    FROM public.reminders
    WHERE id = p_reminder_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reminder % not found', p_reminder_id;
    END IF;

    IF p_user_id <> v_reminder.user_id
       OR (auth.uid() IS NOT NULL AND auth.uid() <> v_reminder.user_id) THEN
        RAISE EXCEPTION 'Unauthorized: cross-user notification delivery blocked';
    END IF;

    SELECT *
    INTO v_delivery
    FROM public.notification_deliveries
    WHERE reminder_id = p_reminder_id
      AND attempt_number = p_attempt_number;

    IF FOUND THEN
        IF v_delivery.user_id <> p_user_id
           OR v_delivery.idempotency_key <> p_idempotency_key THEN
            RAISE EXCEPTION 'Delivery attempt identity conflict';
        END IF;

        IF v_delivery.status = p_status THEN
            v_delivery_id := v_delivery.id;
            v_was_duplicate := true;
        ELSIF v_delivery.status = 'attempting'
              AND p_status IN ('sent', 'failed', 'unknown') THEN
            IF p_lease_token IS NOT NULL
               AND v_reminder.lease_token IS DISTINCT FROM p_lease_token
               AND v_reminder.status <> 'sent' THEN
                RAISE EXCEPTION 'Stale reminder lease while finalizing delivery';
            END IF;

            UPDATE public.notification_deliveries
            SET status = p_status,
                sent_at = CASE WHEN p_status = 'sent' THEN pg_catalog.now() ELSE sent_at END,
                provider_message_id = COALESCE(p_provider_message_id, provider_message_id),
                error_code = p_error_code,
                error_message = p_error_message,
                response_metadata = COALESCE(response_metadata, '{}'::jsonb)
                                    || COALESCE(p_metadata, '{}'::jsonb)
            WHERE id = v_delivery.id
            RETURNING id INTO v_delivery_id;
        ELSE
            RAISE EXCEPTION
                'Delivery result conflict: existing status %, incoming status %',
                v_delivery.status,
                p_status;
        END IF;
    ELSE
        IF EXISTS (
            SELECT 1
            FROM public.notification_deliveries d
            WHERE d.user_id = p_user_id
              AND d.idempotency_key = p_idempotency_key
        ) THEN
            RAISE EXCEPTION 'Delivery idempotency_key already used by another attempt';
        END IF;

        IF p_lease_token IS NOT NULL
           AND v_reminder.lease_token IS DISTINCT FROM p_lease_token THEN
            RAISE EXCEPTION 'Stale reminder lease';
        END IF;

        IF p_status = 'attempting' AND v_reminder.status <> 'sending' THEN
            RAISE EXCEPTION
                'Cannot begin delivery attempt while reminder status is %',
                v_reminder.status;
        END IF;

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
        )
        VALUES (
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
        )
        RETURNING id INTO v_delivery_id;
    END IF;

    IF NOT v_was_duplicate THEN
        IF p_status = 'sent' THEN
            UPDATE public.reminders
            SET status = 'sent',
                sent_at = COALESCE(sent_at, pg_catalog.now()),
                next_retry_at = NULL,
                lease_token = NULL,
                lease_expires_at = NULL,
                last_error_code = NULL,
                last_error_message = NULL,
                updated_at = pg_catalog.now()
            WHERE id = p_reminder_id;

        ELSIF p_status = 'failed' THEN
            -- No retry time is invented here.
            UPDATE public.reminders
            SET status = 'retry',
                next_retry_at = p_next_retry_at,
                last_error_code = p_error_code,
                last_error_message = p_error_message,
                retry_count = retry_count + 1,
                lease_token = NULL,
                lease_expires_at = NULL,
                updated_at = pg_catalog.now()
            WHERE id = p_reminder_id;

        ELSIF p_status = 'unknown' THEN
            -- Conservative quarantine. retry + NULL next_retry_at is not claimable.
            UPDATE public.reminders
            SET status = 'retry',
                next_retry_at = NULL,
                last_error_code = COALESCE(p_error_code, 'DELIVERY_RESULT_UNKNOWN'),
                last_error_message = p_error_message,
                lease_token = NULL,
                lease_expires_at = NULL,
                updated_at = pg_catalog.now()
            WHERE id = p_reminder_id;
        END IF;
    END IF;

    SELECT status
    INTO v_current_reminder_status
    FROM public.reminders
    WHERE id = p_reminder_id;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'delivery_id', v_delivery_id,
        'delivery_status', p_status,
        'reminder_status', v_current_reminder_status,
        'is_duplicate', v_was_duplicate
    );
END;
$$;

-- ============================================================================
-- 4. RELEASE EXPIRED LEASES
-- ============================================================================
CREATE OR REPLACE FUNCTION public.release_expired_reminder_leases()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_attempting_to_unknown integer := 0;
    v_unknown_quarantined integer := 0;
    v_released_retry integer := 0;
BEGIN
    -- If an external attempt had already started, a crash makes outcome UNKNOWN.
    UPDATE public.notification_deliveries d
    SET status = 'unknown',
        error_code = COALESCE(
            d.error_code,
            'LEASE_EXPIRED_AFTER_EXTERNAL_ATTEMPT_STARTED'
        ),
        error_message = COALESCE(
            d.error_message,
            'Worker lease expired after a delivery attempt began; external outcome is unknown'
        ),
        response_metadata = COALESCE(d.response_metadata, '{}'::jsonb)
            || '{"lease_recovery":"classified_unknown"}'::jsonb
    FROM public.reminders r
    WHERE r.id = d.reminder_id
      AND r.status = 'sending'
      AND r.lease_expires_at IS NOT NULL
      AND r.lease_expires_at < pg_catalog.now()
      AND d.status = 'attempting'
      AND d.attempt_number = (
          SELECT pg_catalog.max(d2.attempt_number)
          FROM public.notification_deliveries d2
          WHERE d2.reminder_id = r.id
      );

    GET DIAGNOSTICS v_attempting_to_unknown = ROW_COUNT;

    -- Quarantine expired sends whose latest delivery is UNKNOWN.
    UPDATE public.reminders r
    SET status = 'retry',
        next_retry_at = NULL,
        lease_token = NULL,
        lease_expires_at = NULL,
        last_error_code = COALESCE(
            r.last_error_code,
            'DELIVERY_UNKNOWN_REQUIRES_RECONCILIATION'
        ),
        updated_at = pg_catalog.now()
    WHERE r.status = 'sending'
      AND r.lease_expires_at IS NOT NULL
      AND r.lease_expires_at < pg_catalog.now()
      AND EXISTS (
          SELECT 1
          FROM public.notification_deliveries d
          WHERE d.reminder_id = r.id
            AND d.status = 'unknown'
            AND d.attempt_number = (
                SELECT pg_catalog.max(d2.attempt_number)
                FROM public.notification_deliveries d2
                WHERE d2.reminder_id = r.id
            )
      );

    GET DIAGNOSTICS v_unknown_quarantined = ROW_COUNT;

    -- Pure worker crash before any external delivery row existed.
    UPDATE public.reminders r
    SET status = 'retry',
        next_retry_at = pg_catalog.now(),
        lease_token = NULL,
        lease_expires_at = NULL,
        retry_count = retry_count + 1,
        last_error_code = COALESCE(r.last_error_code, 'WORKER_LEASE_EXPIRED'),
        updated_at = pg_catalog.now()
    WHERE r.status = 'sending'
      AND r.lease_expires_at IS NOT NULL
      AND r.lease_expires_at < pg_catalog.now();

    GET DIAGNOSTICS v_released_retry = ROW_COUNT;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'released_count', v_unknown_quarantined + v_released_retry,
        'attempting_classified_unknown_count', v_attempting_to_unknown,
        'unknown_quarantined_count', v_unknown_quarantined,
        'safe_retry_released_count', v_released_retry
    );
END;
$$;

-- ============================================================================
-- 5. REVALIDATE TASK + SILENCE/REST POLICY BEFORE DELIVERY
-- ============================================================================
CREATE OR REPLACE FUNCTION public.evaluate_reminder_delivery_policy(
    p_reminder_id uuid,
    p_lease_token uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid;
    v_task_id uuid;
    v_reminder_status text;
    v_can_break boolean;
    v_task_title text;
    v_task_status text;
    v_due_date date;
    v_due_time time;
    v_time_known boolean;
    v_timezone text;
    v_quiet_enabled boolean;
    v_quiet_start time;
    v_quiet_end time;
    v_rest_enabled boolean;
    v_rest_until timestamptz;
    v_critical_allowed boolean;
    v_authorized_chat bigint;
    v_local_now timestamp;
    v_local_time time;
    v_local_date date;
    v_quiet_active boolean := false;
    v_rest_active boolean := false;
    v_quiet_until timestamptz;
    v_hold_until timestamptz;
    v_reason text;
    v_attempt_number integer;
    v_latest_delivery_status text;
BEGIN
    SELECT
        r.user_id,
        r.task_id,
        r.status,
        r.can_break_silence,
        t.title,
        t.status,
        t.due_date,
        t.due_time,
        t.time_known,
        p.timezone,
        us.quiet_hours_enabled,
        us.quiet_start_time,
        us.quiet_end_time,
        us.rest_mode_enabled,
        us.rest_until,
        us.critical_can_break_silence,
        us.authorized_telegram_chat_id
    INTO
        v_user_id,
        v_task_id,
        v_reminder_status,
        v_can_break,
        v_task_title,
        v_task_status,
        v_due_date,
        v_due_time,
        v_time_known,
        v_timezone,
        v_quiet_enabled,
        v_quiet_start,
        v_quiet_end,
        v_rest_enabled,
        v_rest_until,
        v_critical_allowed,
        v_authorized_chat
    FROM public.reminders r
    JOIN public.tasks t
      ON t.id = r.task_id
     AND t.user_id = r.user_id
    JOIN public.profiles p
      ON p.id = r.user_id
    LEFT JOIN public.user_settings us
      ON us.user_id = r.user_id
    WHERE r.id = p_reminder_id
      AND r.lease_token = p_lease_token;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reminder not found or lease token is stale';
    END IF;

    IF v_reminder_status <> 'sending' THEN
        RAISE EXCEPTION 'Reminder is not in sending state';
    END IF;

    SELECT d.status
    INTO v_latest_delivery_status
    FROM public.notification_deliveries d
    WHERE d.reminder_id = p_reminder_id
    ORDER BY d.attempt_number DESC
    LIMIT 1;

    IF EXISTS (
        SELECT 1
        FROM public.notification_deliveries d
        WHERE d.reminder_id = p_reminder_id
          AND d.status = 'sent'
    ) THEN
        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'action', 'already_sent',
            'reason', 'successful_delivery_already_exists',
            'user_id', v_user_id,
            'task_id', v_task_id
        );
    END IF;

    IF v_latest_delivery_status = 'unknown' THEN
        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'action', 'hold_unknown',
            'reason', 'latest_delivery_unknown',
            'user_id', v_user_id,
            'task_id', v_task_id
        );
    END IF;

    IF v_task_status IN ('completed', 'cancelled') THEN
        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'action', 'cancel',
            'reason', 'task_terminal_' || v_task_status,
            'user_id', v_user_id,
            'task_id', v_task_id
        );
    END IF;

    IF v_authorized_chat IS NULL THEN
        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'action', 'suppress',
            'reason', 'no_authorized_telegram_chat',
            'suppressed_until', 'infinity',
            'user_id', v_user_id,
            'task_id', v_task_id
        );
    END IF;

    v_timezone := COALESCE(NULLIF(v_timezone, ''), 'UTC');
    v_local_now := pg_catalog.now() AT TIME ZONE v_timezone;
    v_local_time := v_local_now::time;
    v_local_date := v_local_now::date;

    v_rest_active := COALESCE(v_rest_enabled, false)
        AND (v_rest_until IS NULL OR v_rest_until > pg_catalog.now());

    IF COALESCE(v_quiet_enabled, false)
       AND v_quiet_start IS NOT NULL
       AND v_quiet_end IS NOT NULL
       AND v_quiet_start <> v_quiet_end THEN

        IF v_quiet_start < v_quiet_end THEN
            v_quiet_active := v_local_time >= v_quiet_start AND v_local_time < v_quiet_end;
            IF v_quiet_active THEN
                v_quiet_until := (v_local_date + v_quiet_end) AT TIME ZONE v_timezone;
            END IF;
        ELSE
            v_quiet_active := v_local_time >= v_quiet_start OR v_local_time < v_quiet_end;
            IF v_quiet_active THEN
                IF v_local_time >= v_quiet_start THEN
                    v_quiet_until :=
                        ((v_local_date + 1) + v_quiet_end) AT TIME ZONE v_timezone;
                ELSE
                    v_quiet_until := (v_local_date + v_quiet_end) AT TIME ZONE v_timezone;
                END IF;
            END IF;
        END IF;
    END IF;

    -- Critical bypass requires BOTH server-side reminder flag and user policy.
    IF (v_rest_active OR v_quiet_active)
       AND NOT (
           COALESCE(v_can_break, false)
           AND COALESCE(v_critical_allowed, false)
       ) THEN

        IF v_rest_active THEN
            v_hold_until := COALESCE(v_rest_until, 'infinity'::timestamptz);
        END IF;

        IF v_quiet_active THEN
            v_hold_until := CASE
                WHEN v_hold_until IS NULL THEN v_quiet_until
                ELSE GREATEST(v_hold_until, v_quiet_until)
            END;
        END IF;

        IF v_rest_active AND v_quiet_active THEN
            v_reason := 'rest_mode_and_quiet_hours';
        ELSIF v_rest_active THEN
            v_reason := 'rest_mode_active';
        ELSE
            v_reason := 'quiet_hours_active';
        END IF;

        RETURN pg_catalog.jsonb_build_object(
            'ok', true,
            'action', 'suppress',
            'reason', v_reason,
            'suppressed_until', v_hold_until,
            'user_id', v_user_id,
            'task_id', v_task_id
        );
    END IF;

    SELECT COALESCE(pg_catalog.max(d.attempt_number), 0) + 1
    INTO v_attempt_number
    FROM public.notification_deliveries d
    WHERE d.reminder_id = p_reminder_id;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'action', 'send',
        'reason', 'eligible',
        'user_id', v_user_id,
        'task_id', v_task_id,
        'task_title', v_task_title,
        'task_status', v_task_status,
        'due_date', v_due_date,
        'due_time', v_due_time,
        'time_known', v_time_known,
        'timezone', v_timezone,
        'critical_authorized',
            COALESCE(v_can_break, false)
            AND COALESCE(v_critical_allowed, false),
        'attempt_number', v_attempt_number
    );
END;
$$;

-- ============================================================================
-- 6. APPLY A NON-SEND DECISION
-- ============================================================================
CREATE OR REPLACE FUNCTION public.apply_reminder_dispatch_decision(
    p_reminder_id uuid,
    p_lease_token uuid,
    p_action text,
    p_suppressed_until timestamptz DEFAULT NULL,
    p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_count integer;
BEGIN
    IF p_action NOT IN ('suppress', 'cancel', 'hold_unknown', 'already_sent') THEN
        RAISE EXCEPTION 'Invalid reminder dispatch action %', p_action;
    END IF;

    IF p_action = 'suppress' THEN
        UPDATE public.reminders
        SET status = 'pending',
            suppressed_until = COALESCE(p_suppressed_until, 'infinity'::timestamptz),
            suppression_reason = p_reason,
            lease_token = NULL,
            lease_expires_at = NULL,
            updated_at = pg_catalog.now()
        WHERE id = p_reminder_id
          AND status = 'sending'
          AND lease_token = p_lease_token;

    ELSIF p_action = 'cancel' THEN
        UPDATE public.reminders
        SET status = 'cancelled',
            cancelled_at = COALESCE(cancelled_at, pg_catalog.now()),
            lease_token = NULL,
            lease_expires_at = NULL,
            updated_at = pg_catalog.now()
        WHERE id = p_reminder_id
          AND status = 'sending'
          AND lease_token = p_lease_token;

    ELSIF p_action = 'hold_unknown' THEN
        UPDATE public.reminders
        SET status = 'retry',
            next_retry_at = NULL,
            lease_token = NULL,
            lease_expires_at = NULL,
            last_error_code = COALESCE(
                last_error_code,
                'DELIVERY_UNKNOWN_REQUIRES_RECONCILIATION'
            ),
            updated_at = pg_catalog.now()
        WHERE id = p_reminder_id
          AND status = 'sending'
          AND lease_token = p_lease_token;

    ELSE
        UPDATE public.reminders r
        SET status = 'sent',
            sent_at = COALESCE(
                sent_at,
                (
                    SELECT pg_catalog.max(d.sent_at)
                    FROM public.notification_deliveries d
                    WHERE d.reminder_id = r.id
                      AND d.status = 'sent'
                ),
                pg_catalog.now()
            ),
            lease_token = NULL,
            lease_expires_at = NULL,
            next_retry_at = NULL,
            updated_at = pg_catalog.now()
        WHERE r.id = p_reminder_id
          AND r.status = 'sending'
          AND r.lease_token = p_lease_token
          AND EXISTS (
              SELECT 1
              FROM public.notification_deliveries d
              WHERE d.reminder_id = r.id
                AND d.status = 'sent'
          );
    END IF;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Reminder dispatch decision rejected due to stale lease/state';
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'ok', true,
        'action', p_action,
        'reminder_id', p_reminder_id
    );
END;
$$;

-- ============================================================================
-- 7. WATCHDOG SNAPSHOT
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reminder_watchdog_snapshot()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT pg_catalog.jsonb_build_object(
        'expired_sending_leases',
            (
                SELECT pg_catalog.count(*)
                FROM public.reminders r
                WHERE r.status = 'sending'
                  AND r.lease_expires_at IS NOT NULL
                  AND r.lease_expires_at < pg_catalog.now()
            ),
        'overdue_pending',
            (
                SELECT pg_catalog.count(*)
                FROM public.reminders r
                WHERE r.status = 'pending'
                  AND r.planned_at <= pg_catalog.now()
                  AND (r.suppressed_until IS NULL
                       OR r.suppressed_until <= pg_catalog.now())
            ),
        'retry_due',
            (
                SELECT pg_catalog.count(*)
                FROM public.reminders r
                WHERE r.status = 'retry'
                  AND r.next_retry_at IS NOT NULL
                  AND r.next_retry_at <= pg_catalog.now()
            ),
        'unknown_quarantined',
            (
                SELECT pg_catalog.count(*)
                FROM public.reminders r
                WHERE r.status = 'retry'
                  AND r.next_retry_at IS NULL
                  AND EXISTS (
                      SELECT 1
                      FROM public.notification_deliveries d
                      WHERE d.reminder_id = r.id
                        AND d.status = 'unknown'
                        AND d.attempt_number = (
                            SELECT pg_catalog.max(d2.attempt_number)
                            FROM public.notification_deliveries d2
                            WHERE d2.reminder_id = r.id
                        )
                  )
            ),
        'failed_deliveries',
            (
                SELECT pg_catalog.count(*)
                FROM public.notification_deliveries d
                WHERE d.status = 'failed'
            )
    );
$$;

-- ============================================================================
-- 8. FOLLOW-UP CANDIDATES
-- Rules first; excludes any existing follow-up reminder to avoid scheduler spam.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.list_followup_candidates(
    p_limit integer DEFAULT 50
)
RETURNS TABLE (
    user_id uuid,
    task_id uuid,
    title text,
    status text,
    priority text,
    due_date date,
    due_at timestamptz,
    time_known boolean,
    timezone text,
    candidate_reason text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        t.user_id,
        t.id AS task_id,
        t.title,
        t.status,
        t.priority,
        t.due_date,
        t.due_at,
        t.time_known,
        p.timezone,
        CASE
            WHEN t.status = 'waiting_confirmation'
                THEN 'waiting_confirmation'
            WHEN t.due_at IS NOT NULL
                 AND t.due_at < pg_catalog.now()
                THEN 'overdue_known_time'
            ELSE 'overdue_date_without_time'
        END AS candidate_reason
    FROM public.tasks t
    JOIN public.profiles p
      ON p.id = t.user_id
    WHERE t.status IN ('pending', 'in_progress', 'waiting_confirmation')
      AND (
          t.status = 'waiting_confirmation'
          OR (
              t.due_at IS NOT NULL
              AND t.due_at < pg_catalog.now()
          )
          OR (
              COALESCE(t.time_known, false) = false
              AND t.due_date IS NOT NULL
              AND t.due_date <
                  (pg_catalog.now() AT TIME ZONE p.timezone)::date
          )
      )
      AND NOT EXISTS (
          SELECT 1
          FROM public.reminders r
          WHERE r.user_id = t.user_id
            AND r.task_id = t.id
            AND r.reminder_kind = 'followup'
      )
    ORDER BY
        CASE WHEN t.status = 'waiting_confirmation' THEN 0 ELSE 1 END,
        COALESCE(t.due_at, t.due_date::timestamp AT TIME ZONE p.timezone),
        t.id
    LIMIT LEAST(GREATEST(p_limit, 1), 200);
$$;

-- ============================================================================
-- 9. PRIVILEGES — F2 worker/background functions are server-side only.
-- ============================================================================
REVOKE ALL ON FUNCTION public.plan_task_reminders(uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_due_reminders(integer, interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_notification_result(
    uuid, uuid, text, integer, text, text, text, text, text, jsonb, timestamptz, uuid
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_expired_reminder_leases() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.evaluate_reminder_delivery_policy(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_reminder_dispatch_decision(
    uuid, uuid, text, timestamptz, text
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reminder_watchdog_snapshot() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_followup_candidates(integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.plan_task_reminders(uuid, uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_due_reminders(integer, interval) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_notification_result(
    uuid, uuid, text, integer, text, text, text, text, text, jsonb, timestamptz, uuid
) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_expired_reminder_leases() TO service_role;
GRANT EXECUTE ON FUNCTION public.evaluate_reminder_delivery_policy(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_reminder_dispatch_decision(
    uuid, uuid, text, timestamptz, text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.reminder_watchdog_snapshot() TO service_role;
GRANT EXECUTE ON FUNCTION public.list_followup_candidates(integer) TO service_role;
