-- Migration: 20260830000003_ingestions_and_assets.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)

-- Table 3: ingestions
CREATE TABLE IF NOT EXISTS public.ingestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    source_channel TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_event_key TEXT,
    telegram_update_id BIGINT,
    telegram_message_id BIGINT,
    telegram_chat_id BIGINT,
    telegram_user_id BIGINT,
    telegram_file_id TEXT,
    drive_file_id TEXT,
    source_url TEXT,
    idempotency_key TEXT NOT NULL,
    parent_ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    duplicate_of_ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    captured_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL CHECK (status IN (
        'received',
        'processing',
        'waiting_clarification',
        'awaiting_external_file',
        'completed',
        'error',
        'duplicate'
    )),
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    next_retry_at TIMESTAMPTZ,
    processing_started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    last_error_code TEXT,
    last_error_message TEXT,
    source_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ingestions_user_idempotency_unique UNIQUE (user_id, idempotency_key),
    CONSTRAINT ingestions_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT ingestions_duplicate_target_check CHECK (
        status <> 'duplicate' OR duplicate_of_ingestion_id IS NOT NULL
    )
);

-- Foreign key from user_settings.assistant_name_source_ingestion_id
ALTER TABLE public.user_settings
    ADD CONSTRAINT fk_user_settings_ingestion
    FOREIGN KEY (assistant_name_source_ingestion_id)
    REFERENCES public.ingestions(id)
    ON DELETE RESTRICT;

-- Table 6: assets
CREATE TABLE IF NOT EXISTS public.assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    first_ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    sha256 TEXT CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
    original_filename TEXT,
    mime_type TEXT,
    media_kind TEXT NOT NULL,
    size_bytes BIGINT CHECK (size_bytes IS NULL OR size_bytes >= 0),
    duration_ms BIGINT CHECK (duration_ms IS NULL OR duration_ms >= 0),
    integrity_status TEXT NOT NULL DEFAULT 'unverified' CHECK (integrity_status IN ('unverified', 'verified', 'mismatch')),
    storage_status TEXT NOT NULL DEFAULT 'available' CHECK (storage_status IN ('available', 'missing', 'quarantined')),
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT assets_user_id_unique UNIQUE (user_id, id)
);

CREATE UNIQUE INDEX IF NOT EXISTS assets_user_sha256_unique
    ON public.assets (user_id, sha256)
    WHERE sha256 IS NOT NULL;

-- Table 7: asset_locations
CREATE TABLE IF NOT EXISTS public.asset_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
    location_type TEXT NOT NULL CHECK (location_type IN (
        'drive',
        'telegram',
        'nas_backup',
        'generated',
        'external'
    )),
    external_id TEXT,
    drive_file_id TEXT,
    telegram_file_id TEXT,
    telegram_chat_id BIGINT,
    telegram_message_id BIGINT,
    path_hint TEXT,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    is_available BOOLEAN NOT NULL DEFAULT true,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_verified_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT asset_locations_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT fk_asset_locations_asset_composite FOREIGN KEY (user_id, asset_id)
        REFERENCES public.assets(user_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS asset_location_external_unique
    ON public.asset_locations (user_id, location_type, external_id)
    WHERE external_id IS NOT NULL;
