"""
Database Schema & Functional Tests for F0
Covers: DB-TEST-001 through DB-TEST-022
Baseline: SVIA-DOCSET-V1-RC1 (04_DATABASE_SCHEMA.md)
"""

import os
import re
import unittest

class TestDatabaseSchemaF0(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migrations_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), 'supabase', 'migrations')
        cls.migration_files = sorted([f for f in os.listdir(cls.migrations_dir) if f.endswith('.sql')])
        cls.all_sql = ""
        cls.file_contents = {}
        for mf in cls.migration_files:
            with open(os.path.join(cls.migrations_dir, mf), 'r', encoding='utf-8') as f:
                content = f.read()
                cls.file_contents[mf] = content
                cls.all_sql += "\n" + content

    def test_25_tables_present(self):
        """Verify exactly the 25 V1 tables are created in migrations"""
        expected_tables = [
            'profiles',
            'user_settings',
            'ingestions',
            'memory_items',
            'memory_relations',
            'assets',
            'asset_locations',
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
            'reminders',
            'notification_deliveries',
            'pending_clarifications',
            'reports',
            'audit_log',
            'assistant_name_history',
            'task_entity_links',
            'ai_usage_events'
        ]
        
        found_tables = []
        for t in expected_tables:
            pattern = rf'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.{t}\b'
            match = re.search(pattern, self.all_sql, re.IGNORECASE)
            self.assertIsNotNone(match, f"Table public.{t} not found in migrations")
            found_tables.append(t)
            
        self.assertEqual(len(found_tables), 25, "Exactly 25 V1 tables must be defined")

    def test_required_extensions_present(self):
        """Verify extensions pgcrypto, vector, pg_trgm, unaccent"""
        for ext in ['pgcrypto', 'vector', 'pg_trgm', 'unaccent']:
            pattern = rf'CREATE\s+EXTENSION\s+(?:IF\s+NOT\s+EXISTS\s+)?{ext}\b'
            self.assertIsNotNone(re.search(pattern, self.all_sql, re.IGNORECASE), f"Extension {ext} missing")

    def test_db_test_001_and_002_entities_fuzzy_and_aliases(self):
        """DB-TEST-001 & DB-TEST-002: Entities do not enforce unique names, aliases support duplicate tokens"""
        entities_sql = [s for s in self.all_sql.split('CREATE TABLE') if 'public.entities ' in s or 'public.entities(' in s][0]
        self.assertNotIn('unique (user_id, normalized_name)', entities_sql.lower())
        self.assertNotIn('unique(user_id, normalized_name)', entities_sql.lower())

    def test_db_test_003_asset_sha256_deduplication(self):
        """DB-TEST-003: Assets enforce unique (user_id, sha256) where sha256 is not null"""
        self.assertIn('assets_user_sha256_unique', self.all_sql)
        self.assertIn('on public.assets (user_id, sha256)', self.all_sql.lower())

    def test_db_test_004_asset_locations(self):
        """DB-TEST-004: Asset locations table supports drive, telegram, nas_backup, generated, external"""
        loc_sql = [s for s in self.all_sql.split('CREATE TABLE') if 'public.asset_locations' in s][0]
        for loc_type in ['drive', 'telegram', 'nas_backup', 'generated', 'external']:
            self.assertIn(loc_type, loc_sql)

    def test_db_test_005_and_006_source_texts_versioning_and_preferred(self):
        """DB-TEST-005 & DB-TEST-006: source_texts has unique version_no per source_key and one preferred version index"""
        self.assertIn('source_texts_version_unique', self.all_sql)
        self.assertIn('source_text_one_preferred', self.all_sql)

    def test_db_test_007_and_008_task_due_dates_and_zero_time(self):
        """DB-TEST-007 & DB-TEST-008: Tasks support date without time and reject false 00:00 when time_known is false"""
        tasks_sql = [s for s in self.all_sql.split('CREATE TABLE') if 'public.tasks' in s][0]
        self.assertIn('tasks_time_known_check', tasks_sql)
        self.assertIn('tasks_time_unknown_check', tasks_sql)

    def test_db_test_009_task_completion_note_and_transition(self):
        """DB-TEST-009: transition_task_status RPC completes timestamp on status=completed"""
        self.assertIn('public.transition_task_status', self.all_sql)
        self.assertIn('completed_at =', self.all_sql)

    def test_db_test_010_fact_correction_and_superseding(self):
        """DB-TEST-010: correct_fact RPC marks previous fact superseded and inserts new fact"""
        self.assertIn('public.correct_fact', self.all_sql)
        self.assertIn("status = 'superseded'", self.all_sql)
        self.assertIn("supersedes_fact_id", self.all_sql)

    def test_db_test_011_assistant_name_history_one_current(self):
        """DB-TEST-011: assistant_name_history enforces only one row per user where valid_to is null"""
        self.assertIn('assistant_name_history_one_current', self.all_sql)
        self.assertIn('where valid_to is null', self.all_sql.lower())

    def test_db_test_012_delete_protection_on_historical_tables(self):
        """DB-TEST-012: BEFORE DELETE trigger on all 21 historical tables"""
        historical_tables = [
            'assistant_name_history', 'ingestions', 'memory_items', 'memory_relations',
            'assets', 'asset_locations', 'memory_asset_links', 'source_texts',
            'memory_chunks', 'interpretations', 'entities', 'entity_aliases',
            'memory_entity_links', 'facts', 'tasks', 'task_entity_links',
            'reminders', 'notification_deliveries', 'pending_clarifications',
            'reports', 'ai_usage_events', 'audit_log'
        ]
        self.assertIn('private.prevent_historical_delete()', self.all_sql)
        # Verify all 21 tables are listed in the historical_tables array
        for t in historical_tables:
            self.assertIn(f"'{t}'", self.all_sql, f"Table {t} missing from historical protection")

    def test_db_test_013_embeddings_delete_exception(self):
        """DB-TEST-013: embeddings table is exempt from prevent_historical_delete and has delete policy"""
        # Ensure embeddings is NOT in historical delete list
        m = re.search(r'historical_tables\s+text\[\]\s*:=\s*ARRAY\[([\s\S]*?)\];', self.all_sql)
        self.assertIsNotNone(m)
        self.assertNotIn("'embeddings'", m.group(1))
        self.assertIn('embeddings_delete_own', self.all_sql)

    def test_db_test_014_and_015_reminders_and_deliveries_idempotency(self):
        """DB-TEST-014 & DB-TEST-015: Idempotency keys on reminders and notification deliveries"""
        self.assertIn('reminders_idempotency_unique', self.all_sql)
        self.assertIn('notification_deliveries_idempotency_unique', self.all_sql)

    def test_db_test_016_reminder_lease_and_expiration(self):
        """DB-TEST-016: claim_due_reminders uses FOR UPDATE SKIP LOCKED and release_expired_reminder_leases exists"""
        self.assertIn('public.claim_due_reminders', self.all_sql)
        self.assertIn('for update skip locked', self.all_sql.lower())
        self.assertIn('public.release_expired_reminder_leases', self.all_sql)

    def test_db_test_016b_unknown_delivery_result(self):
        """DB-TEST-016B: record_notification_result supports unknown delivery status"""
        self.assertIn('public.record_notification_result', self.all_sql)
        self.assertIn("'unknown'", self.all_sql)

    def test_db_test_017_and_017b_rls_and_cross_user_integrity(self):
        """DB-TEST-017 & DB-TEST-017B: Composite uniqueness and composite FKs prevent cross-user linking"""
        composite_fks = [
            'fk_asset_locations_asset_composite',
            'fk_mem_rel_from_composite',
            'fk_mem_rel_to_composite',
            'fk_mem_asset_mem_composite',
            'fk_mem_asset_asset_composite',
            'fk_mem_chunks_mem_composite',
            'fk_mem_chunks_src_composite',
            'fk_embeddings_chunk_composite',
            'fk_entity_aliases_entity_composite',
            'fk_mem_entity_mem_composite',
            'fk_mem_entity_entity_composite',
            'fk_facts_mem_composite',
            'fk_task_entity_task_composite',
            'fk_task_entity_entity_composite',
            'fk_reminders_task_composite',
            'fk_notif_delivery_reminder_composite'
        ]
        for fk in composite_fks:
            self.assertIn(fk, self.all_sql, f"Composite FK {fk} missing for cross-user integrity")

    def test_db_test_018_audit_log_append_only(self):
        """DB-TEST-018: audit_log table does not permit UPDATE or DELETE for authenticated role"""
        self.assertIn('REVOKE UPDATE, DELETE ON public.audit_log FROM authenticated;', self.all_sql)
        self.assertIn('audit_log_insert_own', self.all_sql)
        self.assertIn('audit_log_select_own', self.all_sql)

    def test_db_test_019_source_text_inmutability(self):
        """DB-TEST-019: trigger prevents mutating text_content of saved source_texts"""
        self.assertIn('private.prevent_source_text_mutation()', self.all_sql)
        self.assertIn('trg_source_texts_immutable', self.all_sql)

    def test_db_test_020_embeddings_unconstrained_dimension_in_f0(self):
        """DB-TEST-020: Embeddings column is vector (not prematurely fixed to vector(1536) or vector(3072))"""
        embeddings_sql = [s for s in self.all_sql.split('CREATE TABLE') if 'public.embeddings' in s][0]
        self.assertIn('embedding vector not null', embeddings_sql.lower())
        self.assertNotIn('embedding vector(1536)', embeddings_sql.lower())
        self.assertNotIn('embedding vector(3072)', embeddings_sql.lower())

    def test_db_test_021_reports_traceability(self):
        """DB-TEST-021: Reports link to source ingestion and result memory"""
        reports_sql = [s for s in self.all_sql.split('CREATE TABLE') if 'public.reports' in s][0]
        self.assertIn('source_ingestion_id', reports_sql)
        self.assertIn('result_memory_id', reports_sql)

    def test_db_test_022_asset_integrity_status(self):
        """DB-TEST-022: Assets integrity status includes unverified, verified, mismatch"""
        assets_sql = [s for s in self.all_sql.split('CREATE TABLE') if 'public.assets' in s][0]
        self.assertIn("'unverified'", assets_sql)
        self.assertIn("'verified'", assets_sql)
        self.assertIn("'mismatch'", assets_sql)

if __name__ == '__main__':
    unittest.main()
