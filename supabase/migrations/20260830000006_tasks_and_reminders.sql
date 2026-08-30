-- Migration: 20260830000006_tasks_and_reminders.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)

-- Table 17: tasks
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending',
        'in_progress',
        'waiting_confirmation',
        'completed',
        'postponed',
        'cancelled'
    )),
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('urgent', 'high', 'normal', 'low')),
    priority_source TEXT NOT NULL DEFAULT 'default' CHECK (priority_source IN ('user', 'ai', 'default')),
    due_date DATE,
    due_time TIME,
    due_timezone TEXT,
    due_at TIMESTAMPTZ,
    time_known BOOLEAN NOT NULL DEFAULT false,
    raw_date_expression TEXT,
    captured_at TIMESTAMPTZ,
    source_memory_id UUID REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    source_interpretation_id UUID REFERENCES public.interpretations(id) ON DELETE RESTRICT,
    idempotency_key TEXT,
    completion_note TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    postponed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    last_modified_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT tasks_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT tasks_time_known_check CHECK (
        time_known = false
        OR (
            due_date IS NOT NULL
            AND due_time IS NOT NULL
            AND due_timezone IS NOT NULL
            AND due_at IS NOT NULL
        )
    ),
    CONSTRAINT tasks_time_unknown_check CHECK (
        time_known = true
        OR (
            due_time IS NULL
            AND due_at IS NULL
        )
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS tasks_idempotency_unique
    ON public.tasks (user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- Table 24: task_entity_links
CREATE TABLE IF NOT EXISTS public.task_entity_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
    entity_id UUID NOT NULL REFERENCES public.entities(id) ON DELETE RESTRICT,
    role TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT task_entity_links_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT task_entity_links_unique UNIQUE (user_id, task_id, entity_id, role),
    CONSTRAINT fk_task_entity_task_composite FOREIGN KEY (user_id, task_id)
        REFERENCES public.tasks(user_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_entity_entity_composite FOREIGN KEY (user_id, entity_id)
        REFERENCES public.entities(user_id, id) ON DELETE RESTRICT
);

-- Table 18: reminders
CREATE TABLE IF NOT EXISTS public.reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
    reminder_kind TEXT NOT NULL CHECK (reminder_kind IN ('base', 'ai', 'followup', 'manual')),
    planned_at TIMESTAMPTZ NOT NULL,
    original_planned_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending',
        'sending',
        'sent',
        'retry',
        'cancelled'
    )),
    can_break_silence BOOLEAN NOT NULL DEFAULT false,
    suppressed_until TIMESTAMPTZ,
    suppression_reason TEXT,
    reason TEXT,
    idempotency_key TEXT NOT NULL,
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    next_retry_at TIMESTAMPTZ,
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    last_error_code TEXT,
    last_error_message TEXT,
    sent_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reminders_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT reminders_idempotency_unique UNIQUE (user_id, idempotency_key),
    CONSTRAINT fk_reminders_task_composite FOREIGN KEY (user_id, task_id)
        REFERENCES public.tasks(user_id, id) ON DELETE RESTRICT
);

-- Table 19: notification_deliveries
CREATE TABLE IF NOT EXISTS public.notification_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    reminder_id UUID NOT NULL REFERENCES public.reminders(id) ON DELETE RESTRICT,
    channel TEXT NOT NULL,
    attempt_number INTEGER NOT NULL CHECK (attempt_number >= 1),
    idempotency_key TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('attempting', 'sent', 'failed', 'unknown')),
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ,
    provider_message_id TEXT,
    error_code TEXT,
    error_message TEXT,
    response_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT notification_deliveries_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT notification_deliveries_reminder_attempt_unique UNIQUE (reminder_id, attempt_number),
    CONSTRAINT notification_deliveries_idempotency_unique UNIQUE (user_id, idempotency_key),
    CONSTRAINT fk_notif_delivery_reminder_composite FOREIGN KEY (user_id, reminder_id)
        REFERENCES public.reminders(user_id, id) ON DELETE RESTRICT
);

-- Table 20: pending_clarifications
CREATE TABLE IF NOT EXISTS public.pending_clarifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    related_ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    related_memory_id UUID REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    related_task_id UUID REFERENCES public.tasks(id) ON DELETE RESTRICT,
    question_type TEXT NOT NULL,
    question_text TEXT NOT NULL,
    channel TEXT NOT NULL,
    channel_context_key TEXT,
    context_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'expired', 'cancelled')),
    expires_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    answer_text TEXT,
    answer_ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pending_clarifications_user_id_unique UNIQUE (user_id, id)
);
