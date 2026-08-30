-- Migration: 20260830000005_entities_and_facts.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)

-- Table 13: entities
CREATE TABLE IF NOT EXISTS public.entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('person', 'organization', 'project', 'place', 'topic', 'other')),
    canonical_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'historical', 'merged', 'invalid')),
    merged_into_entity_id UUID REFERENCES public.entities(id) ON DELETE RESTRICT,
    source_memory_id UUID REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT entities_user_id_unique UNIQUE (user_id, id)
    -- Intentionally NO unique constraint on (user_id, normalized_name) to support disambiguation
);

-- Table 14: entity_aliases
CREATE TABLE IF NOT EXISTS public.entity_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    entity_id UUID NOT NULL REFERENCES public.entities(id) ON DELETE RESTRICT,
    alias TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    alias_type TEXT NOT NULL DEFAULT 'nickname',
    confidence NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    source_memory_id UUID REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT entity_aliases_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT entity_aliases_unique UNIQUE (user_id, entity_id, normalized_alias),
    CONSTRAINT fk_entity_aliases_entity_composite FOREIGN KEY (user_id, entity_id)
        REFERENCES public.entities(user_id, id) ON DELETE RESTRICT
);

-- Table 15: memory_entity_links
CREATE TABLE IF NOT EXISTS public.memory_entity_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    memory_id UUID NOT NULL REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    entity_id UUID NOT NULL REFERENCES public.entities(id) ON DELETE RESTRICT,
    link_type TEXT NOT NULL,
    confidence NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    interpretation_id UUID REFERENCES public.interpretations(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT memory_entity_links_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT memory_entity_links_unique UNIQUE (user_id, memory_id, entity_id, link_type),
    CONSTRAINT fk_mem_entity_mem_composite FOREIGN KEY (user_id, memory_id)
        REFERENCES public.memory_items(user_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_mem_entity_entity_composite FOREIGN KEY (user_id, entity_id)
        REFERENCES public.entities(user_id, id) ON DELETE RESTRICT
);

-- Table 16: facts
CREATE TABLE IF NOT EXISTS public.facts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    subject_entity_id UUID REFERENCES public.entities(id) ON DELETE RESTRICT,
    subject_text TEXT,
    predicate TEXT NOT NULL,
    object_entity_id UUID REFERENCES public.entities(id) ON DELETE RESTRICT,
    object_text TEXT,
    object_value JSONB,
    polarity TEXT NOT NULL DEFAULT 'positive' CHECK (polarity IN ('positive', 'negative')),
    status TEXT NOT NULL DEFAULT 'current' CHECK (status IN ('current', 'historical', 'superseded', 'invalid')),
    valid_from_date DATE,
    valid_to_date DATE,
    valid_from_at TIMESTAMPTZ,
    valid_to_at TIMESTAMPTZ,
    temporal_granularity TEXT NOT NULL DEFAULT 'unknown' CHECK (temporal_granularity IN ('unknown', 'date', 'datetime')),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_memory_id UUID NOT NULL REFERENCES public.memory_items(id) ON DELETE RESTRICT,
    source_interpretation_id UUID REFERENCES public.interpretations(id) ON DELETE RESTRICT,
    supersedes_fact_id UUID REFERENCES public.facts(id) ON DELETE RESTRICT,
    confidence NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT facts_user_id_unique UNIQUE (user_id, id),
    CONSTRAINT facts_subject_check CHECK (subject_entity_id IS NOT NULL OR subject_text IS NOT NULL),
    CONSTRAINT facts_object_check CHECK (object_entity_id IS NOT NULL OR object_text IS NOT NULL OR object_value IS NOT NULL),
    CONSTRAINT facts_date_range_check CHECK (valid_to_date IS NULL OR valid_from_date IS NULL OR valid_to_date >= valid_from_date),
    CONSTRAINT facts_at_range_check CHECK (valid_to_at IS NULL OR valid_from_at IS NULL OR valid_to_at >= valid_from_at),
    CONSTRAINT fk_facts_mem_composite FOREIGN KEY (user_id, source_memory_id)
        REFERENCES public.memory_items(user_id, id) ON DELETE RESTRICT
);
