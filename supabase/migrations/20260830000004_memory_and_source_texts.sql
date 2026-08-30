-- Migration: 20260830000004_memory_and_source_texts.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)

-- Table 4: memory_items
CREATE TABLE IF NOT EXISTS public.memory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    memory_type TEXT NOT NULL,
    title TEXT,
    normalized_content TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'superseded', 'invalid', 'archived')),
    importance SMALLINT CHECK (importance IS NULL OR (importance >= 0 AND importance <= 100)),
    event_date DATE,
    event_time TIME,
    event_timezone TEXT,
    event_at TIMESTAMPTZ,
    event_time_known BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT memory_items_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT memory_items_time_consistency CHECK (
        (event_time_known = false AND event_time IS NULL AND event_at IS NULL)
        OR
        (event_time_known = true AND event_date IS NOT NULL AND event_time IS NOT NULL)
    )
);

-- Table 5: memory_relations
CREATE TABLE IF NOT EXISTS public.memory_relations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    from_memory_id UUID NOT NULL REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    to_memory_id UUID NOT NULL REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    relation_type TEXT NOT NULL,
    confidence NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    created_by TEXT NOT NULL DEFAULT 'user',
    interpretation_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT memory_relations_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT memory_relations_no_self CHECK (from_memory_id <> to_memory_id),
    CONSTRAINT memory_relations_unique_link UNIQUE (user_id, from_memory_id, to_memory_id, relation_type),
    CONSTRAINT fk_mem_rel_from_composite FOREIGN KEY (user_id, from_memory_id)
        REFERENCES public.memory_items(user_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_mem_rel_to_composite FOREIGN KEY (user_id, to_memory_id)
        REFERENCES public.memory_items(user_id, id) ON DELETE RESTRICT
);

-- Table 8: memory_asset_links
CREATE TABLE IF NOT EXISTS public.memory_asset_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    memory_id UUID NOT NULL REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE RESTRICT,
    role TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT memory_asset_links_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT memory_asset_links_unique UNIQUE (user_id, memory_id, asset_id, role),
    CONSTRAINT fk_mem_asset_mem_composite FOREIGN KEY (user_id, memory_id)
        REFERENCES public.memory_items(user_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_mem_asset_asset_composite FOREIGN KEY (user_id, asset_id)
        REFERENCES public.assets(user_id, id) ON DELETE RESTRICT
);

-- Table 9: source_texts
CREATE TABLE IF NOT EXISTS public.source_texts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    asset_id UUID REFERENCES public.assets(id) ON DELETE RESTRICT,
    memory_id UUID REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    source_type TEXT NOT NULL,
    source_key TEXT NOT NULL,
    version_no INTEGER NOT NULL DEFAULT 1 CHECK (version_no >= 1),
    text_content TEXT NOT NULL,
    language TEXT,
    provider TEXT,
    model TEXT,
    prompt_version TEXT,
    is_preferred BOOLEAN NOT NULL DEFAULT false,
    supersedes_source_text_id UUID REFERENCES public.source_texts(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT source_texts_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT source_texts_target_check CHECK (
        ingestion_id IS NOT NULL OR asset_id IS NOT NULL OR memory_id IS NOT NULL
    ),
    CONSTRAINT source_texts_version_unique UNIQUE (user_id, source_key, version_no)
);

CREATE UNIQUE INDEX IF NOT EXISTS source_text_one_preferred
    ON public.source_texts (user_id, source_key)
    WHERE is_preferred = true;

-- Table 10: memory_chunks
CREATE TABLE IF NOT EXISTS public.memory_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    memory_id UUID NOT NULL REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    source_text_id UUID NOT NULL REFERENCES public.source_texts(id) ON DELETE RESTRICT,
    chunk_index INTEGER NOT NULL CHECK (chunk_index >= 0),
    chunking_version TEXT NOT NULL,
    text_content TEXT NOT NULL,
    char_start INTEGER CHECK (char_start IS NULL OR char_start >= 0),
    char_end INTEGER CHECK (char_end IS NULL OR char_end >= char_start),
    start_ms BIGINT CHECK (start_ms IS NULL OR start_ms >= 0),
    end_ms BIGINT CHECK (end_ms IS NULL OR end_ms >= start_ms),
    token_count INTEGER CHECK (token_count IS NULL OR token_count >= 0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    fts TSVECTOR GENERATED ALWAYS AS (to_tsvector('simple', coalesce(text_content, ''))) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT memory_chunks_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT memory_chunks_source_version_idx UNIQUE (source_text_id, chunking_version, chunk_index),
    CONSTRAINT fk_mem_chunks_mem_composite FOREIGN KEY (user_id, memory_id)
        REFERENCES public.memory_items(user_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_mem_chunks_src_composite FOREIGN KEY (user_id, source_text_id)
        REFERENCES public.source_texts(user_id, id) ON DELETE RESTRICT
);

-- Table 11: embeddings
CREATE TABLE IF NOT EXISTS public.embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    chunk_id UUID NOT NULL REFERENCES public.memory_chunks(id) ON DELETE RESTRICT,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    model_version TEXT,
    dimensions INTEGER NOT NULL CHECK (dimensions > 0),
    distance_metric TEXT NOT NULL DEFAULT 'cosine' CHECK (distance_metric IN ('cosine', 'l2', 'inner_product')),
    embedding VECTOR NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT embeddings_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT fk_embeddings_chunk_composite FOREIGN KEY (user_id, chunk_id)
        REFERENCES public.memory_chunks(user_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS embeddings_chunk_model_unique
    ON public.embeddings (chunk_id, provider, model, (coalesce(model_version, '')));

-- Table 12: interpretations
CREATE TABLE IF NOT EXISTS public.interpretations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    ingestion_id UUID REFERENCES public.ingestions(id) ON DELETE RESTRICT,
    source_text_id UUID REFERENCES public.source_texts(id) ON DELETE RESTRICT,
    asset_id UUID REFERENCES public.assets(id) ON DELETE RESTRICT,
    memory_id UUID REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    purpose TEXT NOT NULL,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    run_key TEXT,
    output_json JSONB,
    output_text TEXT,
    confidence NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    status TEXT NOT NULL CHECK (status IN ('proposed', 'validated', 'rejected', 'superseded', 'error')),
    validated_by TEXT,
    validation_note TEXT,
    validated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT interpretations_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT interpretations_target_check CHECK (
        ingestion_id IS NOT NULL OR source_text_id IS NOT NULL OR asset_id IS NOT NULL OR memory_id IS NOT NULL
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS interpretations_run_key_unique
    ON public.interpretations (user_id, run_key)
    WHERE run_key IS NOT NULL;
