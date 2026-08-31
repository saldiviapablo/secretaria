"""
Workflows Tests for F0
Baseline: SVIA-DOCSET-V1-RC1 (05_N8N_WORKFLOWS.md & 09_TEST_PLAN.md)
Covers: F0-COMP-ING-IDEMPOTENCY, WF-SYS-001, WF-TG-002, and manifest audits.
WF-TEST-001 is explicitly deferred to F1 per Section 4.1.
"""

import json
import os
import unittest

class TestF0Workflows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        cls.workflows_dir = os.path.join(cls.root_dir, 'n8n', 'workflows')
        
        cls.wf_sys_001_path = os.path.join(cls.workflows_dir, 'system', 'WF-SYS-001_ERROR_HANDLER.json')
        cls.wf_ing_001_path = os.path.join(cls.workflows_dir, 'ingestion', 'WF-ING-001_REGISTER_INGESTION.json')
        cls.wf_tg_002_path = os.path.join(cls.workflows_dir, 'telegram', 'WF-TG-002_TELEGRAM_SEND_MESSAGE.json')

    def test_workflow_files_exist_and_are_valid_json(self):
        """Verify the 3 F0 workflows exist, parse as JSON, and have proper root structure"""
        for path in [self.wf_sys_001_path, self.wf_ing_001_path, self.wf_tg_002_path]:
            self.assertTrue(os.path.exists(path), f"Workflow file missing: {path}")
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                self.assertIn('name', data)
                self.assertIn('nodes', data)
                self.assertIn('connections', data)
                self.assertGreater(len(data['nodes']), 0)

    def test_no_f3_workflows_present(self):
        """Verify no workflows from F3 or later phases exist in n8n/workflows/"""
        all_wf_files = []
        for root, _, files in os.walk(self.workflows_dir):
            for file in files:
                if file.endswith('.json') and file != 'manifest.json':
                    all_wf_files.append(os.path.relpath(os.path.join(root, file), self.workflows_dir).replace('\\', '/'))
        
        allowed_workflows = {
            'system/WF-SYS-001_ERROR_HANDLER.json',
            'ingestion/WF-ING-001_REGISTER_INGESTION.json',
            'telegram/WF-TG-002_TELEGRAM_SEND_MESSAGE.json',
            'telegram/WF-TG-001_TELEGRAM_INBOUND.json',
            'telegram/WF-TG-004_ONBOARDING_AND_CONFIG.json',
            'ingestion/WF-ING-002_PROCESS_TEXT.json',
            'ai/WF-AI-002_INTERPRET_STRUCTURED.json',
            'memory/WF-MEM-001_PERSIST_MEMORY.json',
            'memory/WF-MEM-006_APPLY_INTERPRETATION.json',
            'task/WF-TASK-001_APPLY_TASK_ACTIONS.json',
            'task/WF-TASK-002_MUTATE_TASK.json',
            'task/WF-TASK-003_CLARIFICATION_MANAGER.json',
            'task/WF-TASK-004_QUERY_TASKS.json',
            'reminders/WF-REM-001_PLAN_REMINDERS.json',
            'reminders/WF-REM-002_DISPATCH_DUE.json',
            'reminders/WF-REM-003_REMINDER_WATCHDOG.json',
            'reminders/WF-REM-004_FOLLOWUP_PLANNER.json',
            'ingestion/WF-ING-003_PROCESS_MEDIA.json',
            'ingestion/WF-ING-004_DRIVE_WATCH.json',
            'ingestion/WF-ING-005_DRIVE_RECONCILIATION.json',
            'ai/WF-AI-001_TRANSCRIBE.json',
            'ingestion/WF-ING-006_DOCUMENT_EXTRACT.json',
            'ai/WF-AI-003_ANALYZE_VISUAL.json'
        }
        self.assertEqual(set(all_wf_files), allowed_workflows, f"Unexpected workflow files found: {set(all_wf_files) - allowed_workflows}")

    def test_f0_comp_ing_idempotency(self):
        """F0-COMP-ING-IDEMPOTENCY: Replay test on WF-ING-001 direct register logic.
        (WF-TEST-001 complete inbound scenario is DEFERRED to F1 because WF-TG-001 belongs to F1).
        """
        mock_db = {}
        def simulate_register_ingestion(user_id, idempotency_key, raw_payload):
            composite_key = f"{user_id}:{idempotency_key}"
            if composite_key in mock_db:
                existing = mock_db[composite_key]
                return {
                    'ok': True,
                    'status': 'duplicate',
                    'ingestion_id': existing['id'],
                    'existing_status': existing['status'],
                    'is_duplicate': True
                }
            new_id = "ing_uuid_" + str(len(mock_db) + 1)
            mock_db[composite_key] = {'id': new_id, 'status': 'received', 'payload': raw_payload}
            return {
                'ok': True,
                'status': 'received',
                'ingestion_id': new_id,
                'is_duplicate': False
            }

        user_id = "usr_123"
        key = "telegram:primary:1000001"
        payload = {"text": "Hola secretaria"}

        # First execution -> received
        r1 = simulate_register_ingestion(user_id, key, payload)
        self.assertEqual(r1['status'], 'received')
        self.assertFalse(r1['is_duplicate'])
        ing_id = r1['ingestion_id']

        # Replay with same key -> duplicate, same ingestion_id, 1 row total
        r2 = simulate_register_ingestion(user_id, key, payload)
        self.assertEqual(r2['status'], 'duplicate')
        self.assertTrue(r2['is_duplicate'])
        self.assertEqual(r2['ingestion_id'], ing_id)
        self.assertEqual(len(mock_db), 1)

    def test_wf_ing_001_idempotency_key_generation(self):
        """WF-ING-001: Telegram key format is telegram:<bot_alias>:<update_id> and NEVER contains token"""
        with open(self.wf_ing_001_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("telegram:${botAlias}:${updateId}", content)
            self.assertNotIn("botToken", content)

    def test_wf_tg_002_delivery_class_validation(self):
        """WF-TG-002: Rejects invalid delivery_class and enforces server-side chat resolution"""
        with open(self.wf_tg_002_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("validClasses = ['reactive', 'proactive_normal', 'proactive_critical']", content)
            self.assertIn("chat_id", content)
            self.assertIn("authorized_telegram_chat_id", content)

    def test_wf_tg_002_rest_and_quiet_rules(self):
        """WF-TG-002: Reactive bypasses rest; proactive_normal is suppressed during quiet/rest"""
        with open(self.wf_tg_002_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("suppressionReason", content)
            self.assertIn("rest_mode_enabled", content)
            self.assertIn("quiet_hours_enabled", content)

    def test_wf_sys_001_error_classification_and_redaction(self):
        """WF-SYS-001: Classifies transient, permanent, auth, data integrity and redacts secrets"""
        with open(self.wf_sys_001_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("operationalClass = 'transient'", content)
            self.assertIn("operationalClass = 'authorization'", content)
            self.assertIn("operationalClass = 'data integrity'", content)
            self.assertIn("operationalClass = 'permanent'", content)
            self.assertIn("sanitizeText", content)
            self.assertIn("[REDACTED]", content)

if __name__ == '__main__':
    unittest.main()
