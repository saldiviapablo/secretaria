-- Migration: 20260830000008_indexes.sql
-- Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md Section 32)

-- Ingestions indexes
CREATE INDEX IF NOT EXISTS ingestions_user_id_idx ON public.ingestions (user_id);
CREATE INDEX IF NOT EXISTS ingestions_user_status_idx ON public.ingestions (user_id, status);
CREATE INDEX IF NOT EXISTS ingestions_user_received_idx ON public.ingestions (user_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ingestions_user_event_key_idx ON public.ingestions (user_id, source_event_key) WHERE source_event_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS ingestions_user_tg_msg_idx ON public.ingestions (user_id, telegram_chat_id, telegram_message_id) WHERE telegram_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ingestions_user_drive_file_idx ON public.ingestions (user_id, drive_file_id) WHERE drive_file_id IS NOT NULL;

-- Memory items indexes
CREATE INDEX IF NOT EXISTS memory_items_user_id_idx ON public.memory_items (user_id);
CREATE INDEX IF NOT EXISTS memory_items_user_created_idx ON public.memory_items (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS memory_items_user_type_status_idx ON public.memory_items (user_id, memory_type, status);
CREATE INDEX IF NOT EXISTS memory_items_user_event_date_idx ON public.memory_items (user_id, event_date) WHERE event_date IS NOT NULL;

-- Assets & locations indexes
CREATE INDEX IF NOT EXISTS assets_user_id_idx ON public.assets (user_id);
CREATE INDEX IF NOT EXISTS assets_user_first_seen_idx ON public.assets (user_id, first_seen_at DESC);
CREATE INDEX IF NOT EXISTS asset_locations_user_asset_idx ON public.asset_locations (user_id, asset_id);

-- Source texts & chunks indexes
CREATE INDEX IF NOT EXISTS source_texts_user_id_idx ON public.source_texts (user_id);
CREATE INDEX IF NOT EXISTS memory_chunks_user_id_idx ON public.memory_chunks (user_id);
CREATE INDEX IF NOT EXISTS memory_chunks_user_memory_idx ON public.memory_chunks (user_id, memory_id);
CREATE INDEX IF NOT EXISTS memory_chunks_fts_idx ON public.memory_chunks USING gin (fts);

-- Embeddings & interpretations indexes
CREATE INDEX IF NOT EXISTS embeddings_user_id_idx ON public.embeddings (user_id);
CREATE INDEX IF NOT EXISTS interpretations_user_id_idx ON public.interpretations (user_id);
CREATE INDEX IF NOT EXISTS interpretations_user_status_idx ON public.interpretations (user_id, status);

-- Entities & aliases indexes
CREATE INDEX IF NOT EXISTS entities_user_id_idx ON public.entities (user_id);
CREATE INDEX IF NOT EXISTS entities_user_type_idx ON public.entities (user_id, entity_type);
CREATE INDEX IF NOT EXISTS entities_normalized_name_trgm_idx ON public.entities USING gin (normalized_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS entity_aliases_user_entity_idx ON public.entity_aliases (user_id, entity_id);
CREATE INDEX IF NOT EXISTS entity_aliases_normalized_alias_trgm_idx ON public.entity_aliases USING gin (normalized_alias gin_trgm_ops);

-- Facts indexes
CREATE INDEX IF NOT EXISTS facts_user_id_idx ON public.facts (user_id);
CREATE INDEX IF NOT EXISTS facts_user_subject_pred_idx ON public.facts (user_id, subject_entity_id, predicate);
CREATE INDEX IF NOT EXISTS facts_user_status_idx ON public.facts (user_id, status);
CREATE INDEX IF NOT EXISTS facts_user_recorded_idx ON public.facts (user_id, recorded_at DESC);

-- Tasks & reminders indexes
CREATE INDEX IF NOT EXISTS tasks_user_id_idx ON public.tasks (user_id);
CREATE INDEX IF NOT EXISTS tasks_user_status_due_date_idx ON public.tasks (user_id, status, due_date);
CREATE INDEX IF NOT EXISTS tasks_user_priority_status_idx ON public.tasks (user_id, priority, status);
CREATE INDEX IF NOT EXISTS tasks_user_due_at_idx ON public.tasks (user_id, due_at) WHERE due_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS task_entity_links_user_task_idx ON public.task_entity_links (user_id, task_id);
CREATE INDEX IF NOT EXISTS task_entity_links_user_entity_idx ON public.task_entity_links (user_id, entity_id);

CREATE INDEX IF NOT EXISTS reminders_user_id_idx ON public.reminders (user_id);
CREATE INDEX IF NOT EXISTS reminders_due_idx ON public.reminders (planned_at) WHERE status IN ('pending', 'retry');
CREATE INDEX IF NOT EXISTS notification_deliveries_user_reminder_idx ON public.notification_deliveries (user_id, reminder_id);
CREATE INDEX IF NOT EXISTS notification_deliveries_user_attempted_idx ON public.notification_deliveries (user_id, attempted_at DESC);

-- Pending clarifications & reports indexes
CREATE INDEX IF NOT EXISTS pending_clarifications_user_id_idx ON public.pending_clarifications (user_id);
CREATE INDEX IF NOT EXISTS pending_clarifications_user_status_idx ON public.pending_clarifications (user_id, status);
CREATE INDEX IF NOT EXISTS reports_user_id_idx ON public.reports (user_id);

-- Audit log & AI usage indexes
CREATE INDEX IF NOT EXISTS audit_log_user_id_idx ON public.audit_log (user_id);
CREATE INDEX IF NOT EXISTS audit_log_user_occurred_idx ON public.audit_log (user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_user_table_record_idx ON public.audit_log (user_id, table_name, record_id);
CREATE INDEX IF NOT EXISTS ai_usage_events_user_id_idx ON public.ai_usage_events (user_id);
CREATE INDEX IF NOT EXISTS ai_usage_events_user_created_idx ON public.ai_usage_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_usage_events_user_provider_model_idx ON public.ai_usage_events (user_id, provider, model);
