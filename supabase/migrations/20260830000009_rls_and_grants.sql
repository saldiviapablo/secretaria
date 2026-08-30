-- Migration: 20260830000009_rls_and_grants.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md Section 40 & 08_SECURITY.md)

-- Schema permissions
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT ALL ON SCHEMA private TO postgres, service_role;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- 1. Enable RLS on all 25 tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assistant_name_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ingestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_asset_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.source_texts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interpretations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_entity_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_entity_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pending_clarifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- 2. Policies for profiles (id = auth.uid())
CREATE POLICY "profiles_select_own" ON public.profiles FOR SELECT TO authenticated
    USING (auth.uid() IS NOT NULL AND auth.uid() = id);
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = id);
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE TO authenticated
    USING (auth.uid() IS NOT NULL AND auth.uid() = id)
    WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = id);

-- Macro/helper for standard user_id based RLS policies
DO $$
DECLARE
    t text;
    user_tables text[] := ARRAY[
        'user_settings',
        'assistant_name_history',
        'ingestions',
        'assets',
        'asset_locations',
        'memory_items',
        'memory_relations',
        'memory_asset_links',
        'source_texts',
        'memory_chunks',
        'embeddings',
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
        'ai_usage_events'
    ];
BEGIN
    FOREACH t IN ARRAY user_tables LOOP
        EXECUTE format('
            CREATE POLICY "%I_select_own" ON public.%I FOR SELECT TO authenticated
                USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);
            CREATE POLICY "%I_insert_own" ON public.%I FOR INSERT TO authenticated
                WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);
            CREATE POLICY "%I_update_own" ON public.%I FOR UPDATE TO authenticated
                USING (auth.uid() IS NOT NULL AND auth.uid() = user_id)
                WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);
        ', t, t, t, t, t, t);
    END LOOP;
END $$;

-- Policies for audit_log: SELECT and INSERT only. NO UPDATE, NO DELETE.
CREATE POLICY "audit_log_select_own" ON public.audit_log FOR SELECT TO authenticated
    USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);
CREATE POLICY "audit_log_insert_own" ON public.audit_log FOR INSERT TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

-- DELETE policy ONLY for embeddings (derived/regenerable data exception)
CREATE POLICY "embeddings_delete_own" ON public.embeddings FOR DELETE TO authenticated
    USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);

-- 3. Grants and Revocations
-- Anon role: NO access to data tables
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

-- Authenticated role permissions
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO authenticated;
REVOKE DELETE ON ALL TABLES IN SCHEMA public FROM authenticated;
GRANT DELETE ON public.embeddings TO authenticated;
REVOKE UPDATE, DELETE ON public.audit_log FROM authenticated;
