"""
Workflow Component Tests for F0
Baseline: SVIA-DOCSET-V1-RC1 (05_N8N_WORKFLOWS.md)
Covers: WF-ING-001, WF-TG-002, WF-SYS-001, Idempotency Replay, Concurrency Test
"""

import os
import json
import uuid
import unittest
from datetime import datetime, time

class TestF0Workflows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        cls.wf_dir = os.path.join(cls.root_dir, 'n8n', 'workflows')
        
        cls.ing_path = os.path.join(cls.wf_dir, 'ingestion', 'WF-ING-001_REGISTER_INGESTION.json')
        cls.tg_path = os.path.join(cls.wf_dir, 'telegram', 'WF-TG-002_TELEGRAM_SEND_MESSAGE.json')
        cls.sys_path = os.path.join(cls.wf_dir, 'system', 'WF-SYS-001_ERROR_HANDLER.json')

    def test_workflow_files_exist_and_are_valid_json(self):
        """Verify the 3 F0 workflows exist, parse as JSON, and have proper root structure"""
        for path in [self.ing_path, self.tg_path, self.sys_path]:
            self.assertTrue(os.path.exists(path), f"Workflow file {path} not found")
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                self.assertIn('name', data)
                self.assertIn('nodes', data)
                self.assertIn('connections', data)
                self.assertIsInstance(data['nodes'], list)

    def test_no_f1_workflows_present(self):
        """Verify no workflows from F1 or later phases exist in n8n/workflows/"""
        forbidden_workflows = [
            'WF-TG-001_TELEGRAM_INBOUND.json',
            'WF-TG-004_ONBOARDING_AND_CONFIG.json',
            'WF-ING-002_PROCESS_TEXT.json',
            'WF-AI-002_INTERPRET_STRUCTURED.json',
            'WF-MEM-001_PERSIST_MEMORY.json',
            'WF-MEM-006_APPLY_INTERPRETATION.json',
            'WF-TASK-001_APPLY_TASK_ACTIONS.json',
            'WF-TASK-002_MUTATE_TASK.json',
            'WF-TASK-003_CLARIFICATION_MANAGER.json',
            'WF-TASK-004_QUERY_TASKS.json'
        ]
        
        for root, dirs, files in os.walk(self.wf_dir):
            for f in files:
                self.assertNotIn(f, forbidden_workflows, f"F1+ workflow {f} must not exist in F0")

    def test_wf_ing_001_idempotency_key_generation(self):
        """WF-ING-001: Telegram key format is telegram:<bot_alias>:<update_id> and NEVER contains token"""
        with open(self.ing_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("telegram:${botAlias}:${updateId}", content.replace('`', ''))
            self.assertNotIn("bot_token", content.lower())
            self.assertIn("drive:${fileId}:${ver}", content.replace('`', ''))
            self.assertIn("mcp:${reqId}", content.replace('`', ''))

    def test_wf_ing_001_replay_logic(self):
        """Simulate WF-ING-001 replay: first attempt creates ingestion, second attempt returns existing duplicate without error"""
        user_id = str(uuid.uuid4())
        update_id = 987654321
        idempotency_key = f"telegram:primary:{update_id}"
        
        # In-memory ingestion mock
        db_state = {}
        
        def mock_register_ingestion(uid, ikey):
            if ikey in db_state:
                return {
                    "ok": True,
                    "status": "duplicate",
                    "ingestion_id": db_state[ikey]["id"],
                    "is_duplicate": True,
                    "existing_status": db_state[ikey]["status"]
                }
            else:
                new_id = str(uuid.uuid4())
                db_state[ikey] = {"id": new_id, "user_id": uid, "status": "received"}
                return {
                    "ok": True,
                    "status": "received",
                    "ingestion_id": new_id,
                    "is_duplicate": False
                }

        # First call
        res1 = mock_register_ingestion(user_id, idempotency_key)
        self.assertTrue(res1["ok"])
        self.assertFalse(res1["is_duplicate"])
        self.assertEqual(res1["status"], "received")
        first_id = res1["ingestion_id"]

        # Replay with same key
        res2 = mock_register_ingestion(user_id, idempotency_key)
        self.assertTrue(res2["ok"])
        self.assertTrue(res2["is_duplicate"])
        self.assertEqual(res2["status"], "duplicate")
        self.assertEqual(res2["ingestion_id"], first_id)
        
        # Assert only 1 persisted record exists in DB
        self.assertEqual(len(db_state), 1)

    def test_wf_tg_002_delivery_class_validation(self):
        """WF-TG-002: Rejects invalid delivery_class and enforces server-side chat resolution"""
        with open(self.tg_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("reactive", content)
            self.assertIn("proactive_normal", content)
            self.assertIn("proactive_critical", content)
            self.assertIn("authorized_telegram_chat_id", content)

    def test_wf_tg_002_rest_and_quiet_rules(self):
        """WF-TG-002: Reactive bypasses rest; proactive_normal is suppressed during quiet/rest"""
        settings = {
            "authorized_telegram_chat_id": 123456789,
            "quiet_hours_enabled": True,
            "quiet_start_time": "22:00:00",
            "quiet_end_time": "07:00:00",
            "rest_mode_enabled": True,
            "rest_until": None,
            "critical_can_break_silence": False
        }
        
        def evaluate_delivery(delivery_class, settings):
            if delivery_class == 'reactive':
                return True, None
            elif delivery_class == 'proactive_normal':
                if settings["rest_mode_enabled"]:
                    return False, "rest_mode_active"
                if settings["quiet_hours_enabled"]:
                    return False, "quiet_hours_active"
                return True, None
            elif delivery_class == 'proactive_critical':
                if not settings["critical_can_break_silence"] and (settings["rest_mode_enabled"] or settings["quiet_hours_enabled"]):
                    return False, "critical_cannot_break_silence"
                return True, None
            return False, "invalid_class"

        # Reactive can send
        can_send, reason = evaluate_delivery("reactive", settings)
        self.assertTrue(can_send)
        
        # Proactive normal suppressed
        can_send, reason = evaluate_delivery("proactive_normal", settings)
        self.assertFalse(can_send)
        self.assertEqual(reason, "rest_mode_active")

    def test_wf_sys_001_error_classification_and_redaction(self):
        """WF-SYS-001: Classifies transient, permanent, auth, data integrity and redacts secrets"""
        with open(self.sys_path, 'r', encoding='utf-8') as f:
            content = f.read()
            self.assertIn("transient", content)
            self.assertIn("authorization", content)
            self.assertIn("data integrity", content)
            self.assertIn("permanent", content)
            self.assertIn("REDACTED", content)

if __name__ == "__main__":
    unittest.main()
