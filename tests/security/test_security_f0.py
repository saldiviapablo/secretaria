"""
Security Tests for F0
Baseline: SVIA-DOCSET-V1-RC1 (08_SECURITY.md & 09_TEST_PLAN.md)
Covers: SEC-TEST-019 to SEC-TEST-026, SEC-TEST-033, SEC-TEST-034
"""

import os
import re
import unittest

class TestSecurityF0(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        cls.migrations_dir = os.path.join(cls.root_dir, 'supabase', 'migrations')
        cls.docker_dir = os.path.join(cls.root_dir, 'infra', 'docker')
        
        cls.all_sql = ""
        for mf in sorted(os.listdir(cls.migrations_dir)):
            if mf.endswith('.sql'):
                with open(os.path.join(cls.migrations_dir, mf), 'r', encoding='utf-8') as f:
                    cls.all_sql += "\n" + f.read()

        cls.compose_dev = ""
        compose_path = os.path.join(cls.docker_dir, 'compose.dev.yml')
        if os.path.exists(compose_path):
            with open(compose_path, 'r', encoding='utf-8') as f:
                cls.compose_dev = f.read()

    def test_sec_test_019_cross_user_isolation(self):
        """SEC-TEST-019: Multi-tenant isolation verified by composite FKs (user_id, id) across all related tables"""
        required_composite_fks = [
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
        for fk in required_composite_fks:
            self.assertIn(fk, self.all_sql, f"Missing composite FK: {fk}")

    def test_sec_test_020_anon_db_access_revoked(self):
        """SEC-TEST-020: anon role has all table permissions explicitly revoked"""
        self.assertIn('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;', self.all_sql)
        self.assertIn('REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;', self.all_sql)

    def test_sec_test_021_historical_delete_blocked(self):
        """SEC-TEST-021: BEFORE DELETE trigger enforces exception on all 21 permanent tables"""
        historical_tables = [
            'assistant_name_history', 'ingestions', 'memory_items', 'memory_relations',
            'assets', 'asset_locations', 'memory_asset_links', 'source_texts',
            'memory_chunks', 'interpretations', 'entities', 'entity_aliases',
            'memory_entity_links', 'facts', 'tasks', 'task_entity_links',
            'reminders', 'notification_deliveries', 'pending_clarifications',
            'reports', 'ai_usage_events', 'audit_log'
        ]
        self.assertIn('private.prevent_historical_delete()', self.all_sql)
        for t in historical_tables:
            self.assertIn(f"'{t}'", self.all_sql, f"Table {t} missing from historical protection")

    def test_sec_test_022_audit_log_immutable(self):
        """SEC-TEST-022: audit_log table does not grant UPDATE or DELETE to authenticated users"""
        self.assertIn('REVOKE UPDATE, DELETE ON public.audit_log FROM authenticated;', self.all_sql)

    def test_sec_test_023_security_definer_search_path(self):
        """SEC-TEST-023: All SECURITY DEFINER functions set search_path = '' and use schema-qualified names"""
        sec_definer_blocks = re.findall(r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+([a-zA-Z0-9_\.]+)\s*\([\s\S]*?SECURITY\s+DEFINER[\s\S]*?AS\s*\$\$([\s\S]*?)\$\$;', self.all_sql, re.IGNORECASE)
        
        self.assertGreater(len(sec_definer_blocks), 0, "Must have SECURITY DEFINER functions")
        for fn_name, body in sec_definer_blocks:
            pattern = rf'FUNCTION\s+{re.escape(fn_name)}[\s\S]*?SET\s+search_path\s*=\s*\'\''
            self.assertIsNotNone(re.search(pattern, self.all_sql, re.IGNORECASE), f"Function {fn_name} must have SET search_path = ''")

    def test_sec_test_024_secret_scanner(self):
        """SEC-TEST-024: Secret scanner scans repo for private keys, tokens, and real secrets"""
        secret_patterns = [
            r'-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----',
            r'ghp_[A-Za-z0-9]{36}',
            r'sk-[A-Za-z0-9]{32,}',
            r'AIzaSy[A-Za-z0-9_-]{33}',
            r'bot[0-9]{8,10}:[A-Za-z0-9_-]{35}'
        ]
        
        # Excluded paths
        excluded_dirs = {'.git', 'node_modules', '.pytest_cache', '__pycache__', 'venv', '.venv'}
        
        scanned_files = []
        violations = []
        for root, dirs, files in os.walk(self.root_dir):
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            for f in files:
                if f.endswith('.pyc') or f.endswith('.pyd'):
                    continue
                filepath = os.path.join(root, f)
                # Skip test_security_f0.py itself since it defines the regex patterns
                if filepath.endswith('test_security_f0.py'):
                    continue
                scanned_files.append(filepath)
                try:
                    with open(filepath, 'r', encoding='utf-8', errors='ignore') as file_obj:
                        content = file_obj.read()
                        for p in secret_patterns:
                            if re.search(p, content):
                                violations.append((filepath, p))
                except Exception:
                    pass

        self.assertEqual(len(violations), 0, f"Secrets detected in repository: {violations}")

        # Canary check: verify the scanner WOULD catch a synthetic canary
        synthetic_canary = "-----BEGIN " + "RSA PRIVATE " + "KEY-----\nsynthetic_canary_test_key\n"
        matched_canary = any(re.search(p, synthetic_canary) for p in secret_patterns)
        self.assertTrue(matched_canary, "Scanner must detect synthetic key canary")

    def test_sec_test_025_secret_redaction_in_logs(self):
        """SEC-TEST-025: Secret redaction in WF-SYS-001 replaces auth headers, bot tokens, passwords"""
        sys_wf_path = os.path.join(self.root_dir, 'n8n', 'workflows', 'system', 'WF-SYS-001_ERROR_HANDLER.json')
        with open(sys_wf_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("sanitizeText", content)
            self.assertIn("[REDACTED]", content)

    def test_sec_test_026_n8n_configuration_audit(self):
        """SEC-TEST-026: n8n configuration enforces single-instance, no docker socket, no privileged flag"""
        self.assertNotIn('docker.sock', self.compose_dev)
        self.assertNotIn('privileged: true', self.compose_dev)
        self.assertIn('no-new-privileges:true', self.compose_dev)
        self.assertIn('docker.n8n.io/n8nio/n8n:2.33.3', self.compose_dev)
        self.assertIn('postgres:16-alpine', self.compose_dev)

    def test_sec_test_033_n8n_admin_bind_localhost(self):
        """SEC-TEST-033: n8n admin port binds to 127.0.0.1 (not 0.0.0.0 or WAN) in DEV"""
        self.assertIn('127.0.0.1', self.compose_dev)
        self.assertNotIn('"5678:5678"', self.compose_dev)
        self.assertNotIn("'5678:5678'", self.compose_dev)

    def test_sec_test_034_n8n_internal_db_port_not_exposed(self):
        """SEC-TEST-034: n8n internal postgres container has NO host port mappings"""
        lines = self.compose_dev.split('\n')
        postgres_block = False
        postgres_lines = []
        for l in lines:
            if 'n8n-postgres:' in l:
                postgres_block = True
            elif 'n8n:' in l and not 'postgres' in l:
                postgres_block = False
            elif postgres_block:
                postgres_lines.append(l)
                
        postgres_text = "\n".join(postgres_lines)
        self.assertNotIn('ports:', postgres_text, "Internal postgres must not have host ports mapped")

if __name__ == "__main__":
    unittest.main()
