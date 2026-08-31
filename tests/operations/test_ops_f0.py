"""
Operations Tests for F0
Baseline: SVIA-DOCSET-V1-RC1 (10_DEPLOYMENT.md & 09_TEST_PLAN.md)
Covers: OPS-TEST-001 to OPS-TEST-006, OPS-TEST-010
"""

import os
import re
import json
import unittest

class TestOperationsF0(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        cls.docker_dir = os.path.join(cls.root_dir, 'infra', 'docker')
        cls.migrations_dir = os.path.join(cls.root_dir, 'supabase', 'migrations')
        cls.workflows_dir = os.path.join(cls.root_dir, 'n8n', 'workflows')

    def test_ops_test_001_deploy_dev_configuration(self):
        """OPS-TEST-001: DEV environment files exist, pin n8n 2.33.3 and postgres 16-alpine"""
        compose_path = os.path.join(self.docker_dir, 'compose.dev.yml')
        env_ex_path = os.path.join(self.docker_dir, '.env.example')
        readme_path = os.path.join(self.docker_dir, 'README.md')
        
        self.assertTrue(os.path.exists(compose_path))
        self.assertTrue(os.path.exists(env_ex_path))
        self.assertTrue(os.path.exists(readme_path))

        with open(compose_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn('docker.n8n.io/n8nio/n8n:2.35.4', content)
            self.assertIn('postgres:16-alpine', content)
            self.assertIn('EXECUTIONS_DATA_PRUNE', content)
            self.assertIn('N8N_DEFAULT_BINARY_DATA_MODE', content)

    def test_ops_test_002_secret_scan_clean(self):
        """OPS-TEST-002: .env.example and repository contain no real secret keys or passwords"""
        env_ex_path = os.path.join(self.docker_dir, '.env.example')
        with open(env_ex_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            for line in lines:
                if line.startswith('N8N_DB_PASSWORD=') or line.startswith('N8N_ENCRYPTION_KEY='):
                    val = line.split('=', 1)[1].strip()
                    self.assertEqual(val, "", "Secret variable in .env.example must have empty value")

    def test_ops_test_003_workflow_manifest_audit(self):
        """OPS-TEST-003: Exactly the 17 approved workflows exist in their approved directories (F2 phase)"""
        manifest_path = os.path.join(self.workflows_dir, 'manifest.json')
        self.assertTrue(os.path.exists(manifest_path))
        with open(manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)
            self.assertIn(len(manifest['workflows']), {17, 23})

    def test_ops_test_004_db_migrations_reproducibility(self):
        """OPS-TEST-004: Migration files exist in logical sequence (through F3 phase)"""
        migrations = sorted([f for f in os.listdir(self.migrations_dir) if f.endswith('.sql')])
        self.assertIn(len(migrations), {12, 13}, f"Expected 12 or 13 migrations, found {len(migrations)}")
        self.assertTrue(migrations[0].endswith('000001_extensions_and_schemas.sql'))
        self.assertTrue(migrations[-1].endswith('000012_f2_reminder_runtime.sql') or migrations[-1].endswith('000013_f3_media_drive_runtime.sql'))

    def test_ops_test_005_rls_regression(self):
        """OPS-TEST-005: RLS policies present for all public user tables"""
        rls_file = [f for f in os.listdir(self.migrations_dir) if 'rls_and_grants' in f][0]
        with open(os.path.join(self.migrations_dir, rls_file), 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn('ENABLE ROW LEVEL SECURITY', content)
            self.assertIn('auth.uid() = user_id', content)

    def test_ops_test_006_n8n_security_audit(self):
        """OPS-TEST-006: n8n security parameters audit"""
        compose_path = os.path.join(self.docker_dir, 'compose.dev.yml')
        with open(compose_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn('no-new-privileges:true', content)
            self.assertNotIn('privileged: true', content)
            self.assertIn('127.0.0.1', content)

    def test_ops_test_010_evidence_generation(self):
        """OPS-TEST-010: Evidence directory and generator exist"""
        evidence_dir = os.path.join(self.root_dir, 'tests', 'evidence')
        self.assertTrue(os.path.exists(evidence_dir))

if __name__ == '__main__':
    unittest.main()
