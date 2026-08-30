-- Migration: 20260830000007_reports_ai_usage_audit.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)

-- Table 21: reports
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    source_ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    requested_channel TEXT NOT NULL,
    query_text TEXT NOT NULL,
    date_from DATE,
    date_to DATE,
    filters JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'generating', 'completed', 'failed', 'cancelled')),
    result_text TEXT,
    result_memory_id UUID REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reports_user_id_unique UNIQUE (user_id, id)
);

-- Table 25: ai_usage_events
CREATE TABLE IF NOT EXISTS public.ai_usage_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    operation_type TEXT NOT NULL,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    model_version TEXT,
    provider_request_id TEXT,
    input_tokens BIGINT CHECK (input_tokens IS NULL OR input_tokens >= 0),
    output_tokens BIGINT CHECK (output_tokens IS NULL OR output_tokens >= 0),
    cached_input_tokens BIGINT CHECK (cached_input_tokens IS NULL OR cached_input_tokens >= 0),
    audio_seconds NUMERIC(12,3) CHECK (audio_seconds IS NULL OR audio_seconds >= 0),
    image_count INTEGER CHECK (image_count IS NULL OR image_count >= 0),
    estimated_cost_usd NUMERIC(14,6) CHECK (estimated_cost_usd IS NULL OR estimated_cost_usd >= 0),
    pricing_version TEXT,
    ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    interpretation_id UUID REFERENCES public.interpretations(id) ON DELETE RESTRICT,
    embedding_id UUID REFERENCES public.embeddings(id) ON DELETE RESTRICT,
    report_id UUID REFERENCES public.reports(id) ON DELETE RESTRICT,
    asset_id UUID REFERENCES public.assets(id) ON DELETE RESTRICT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ai_usage_events_user_id_unique UNIQUE (user_id, id)
);

-- Table 22: audit_log
CREATE TABLE IF NOT EXISTS public.audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    table_name TEXT NOT NULL,
    record_id UUID,
    action TEXT NOT NULL,
    actor_type TEXT NOT NULL DEFAULT 'system',
    actor_id TEXT,
    source_channel TEXT,
    ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    correlation_id UUID,
    before_data JSONB,
    after_data JSONB,
    changed_fields TEXT[],
    db_role TEXT DEFAULT current_user,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT audit_log_user_id_unique UNIQUE (user_id, id)
);
