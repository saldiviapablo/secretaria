-- Migration: 20260830000002_profiles_and_settings.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)

-- Table 1: profiles
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
    display_name TEXT,
    language TEXT NOT NULL DEFAULT 'es',
    locale TEXT NOT NULL DEFAULT 'es-AR',
    timezone TEXT NOT NULL DEFAULT 'America/Argentina/Buenos_Aires',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table 2: user_settings
CREATE TABLE IF NOT EXISTS public.user_settings (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE RESTRICT,
    assistant_name TEXT,
    assistant_name_source_ingestion_id UUID,
    authorized_telegram_user_id BIGINT,
    authorized_telegram_chat_id BIGINT,
    morning_brief_enabled BOOLEAN NOT NULL DEFAULT true,
    morning_brief_time TIME DEFAULT '08:00:00',
    evening_brief_enabled BOOLEAN NOT NULL DEFAULT false,
    evening_brief_time TIME DEFAULT '20:00:00',
    quiet_hours_enabled BOOLEAN NOT NULL DEFAULT false,
    quiet_start_time TIME DEFAULT '22:00:00',
    quiet_end_time TIME DEFAULT '07:00:00',
    rest_mode_enabled BOOLEAN NOT NULL DEFAULT false,
    rest_started_at TIMESTAMPTZ,
    rest_until TIMESTAMPTZ,
    default_reminder_minutes_before INTEGER NOT NULL DEFAULT 180 CHECK (default_reminder_minutes_before >= 0),
    critical_can_break_silence BOOLEAN NOT NULL DEFAULT false,
    notification_preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
    monthly_ai_budget_usd NUMERIC(12,2) CHECK (monthly_ai_budget_usd IS NULL OR monthly_ai_budget_usd >= 0),
    monthly_ai_alert_pct NUMERIC(5,2) CHECK (monthly_ai_alert_pct IS NULL OR (monthly_ai_alert_pct >= 0 AND monthly_ai_alert_pct <= 100)),
    last_modified_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS user_settings_telegram_user_unique
    ON public.user_settings (authorized_telegram_user_id)
    WHERE authorized_telegram_user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_settings_telegram_chat_unique
    ON public.user_settings (authorized_telegram_chat_id)
    WHERE authorized_telegram_chat_id IS NOT NULL;

-- Table 23 (logical sequence): assistant_name_history
CREATE TABLE IF NOT EXISTS public.assistant_name_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    assistant_name TEXT NOT NULL,
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_to TIMESTAMPTZ,
    change_source TEXT NOT NULL,
    source_ingestion_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT assistant_name_history_valid_range CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT assistant_name_history_user_id_unique UNIQUE (user_id, id)
);

CREATE UNIQUE INDEX IF NOT EXISTS assistant_name_history_one_current
    ON public.assistant_name_history (user_id)
    WHERE valid_to IS NULL;
