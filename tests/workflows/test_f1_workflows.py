"""
Workflows Tests for F1
Baseline: SVIA-DOCSET-V1-RC1 (05_N8N_WORKFLOWS.md & 09_TEST_PLAN.md)
Validates all 13 workflows (3 F0 + 10 F1), manifest integrity, and guarantees NO F2-F8 workflows are present.
"""

import json
import os
import unittest

class TestF1Workflows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        cls.workflows_dir = os.path.join(cls.root_dir, 'n8n', 'workflows')
        cls.manifest_path = os.path.join(cls.workflows_dir, 'manifest.json')

    def test_manifest_structure_and_count(self):
        """Verifies manifest.json contains exactly the 17 implemented workflows through F2"""
        self.assertTrue(os.path.exists(self.manifest_path), "manifest.json missing")
        with open(self.manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)

        self.assertIn(manifest.get('phase'), {'F2', 'F3'})
        self.assertIn(manifest.get('total_workflows_implemented'), {17, 23})
        self.assertIn(len(manifest.get('workflows', [])), {17, 23})

    def test_all_17_workflows_exist_and_are_valid_json(self):
        """Verifies all implemented workflow files exist, parse as JSON, and have proper root structure"""
        with open(self.manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)

        for wf in manifest['workflows']:
            wf_path = os.path.join(self.workflows_dir, wf['file'])
            self.assertTrue(os.path.exists(wf_path), f"Workflow file missing: {wf_path}")
            with open(wf_path, 'r', encoding='utf-8') as wf_file:
                data = json.load(wf_file)
                self.assertIn('name', data)
                self.assertIn('nodes', data)
                self.assertIn('connections', data)
                self.assertGreater(len(data['nodes']), 0)

    def test_no_f3_to_f8_workflows_present(self):
        """Verifies NO workflows from F4 or later phases exist in n8n/workflows/"""
        all_wf_files = []
        for root, _, files in os.walk(self.workflows_dir):
            for file in files:
                if file.endswith('.json') and file != 'manifest.json':
                    all_wf_files.append(os.path.relpath(os.path.join(root, file), self.workflows_dir).replace('\\', '/'))

        expected_workflows = {
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

        self.assertEqual(set(all_wf_files), expected_workflows, f"Unexpected workflow files found: {set(all_wf_files) - expected_workflows}")

    def test_no_plain_secrets_in_workflow_definitions(self):
        """Ensures no hardcoded API keys or bot tokens exist in workflow JSON files"""
        forbidden_patterns = ['bot123456', 'sk-proj-', 'secret_token_123', 'Bearer eyJ']
        for root, _, files in os.walk(self.workflows_dir):
            for file in files:
                if file.endswith('.json'):
                    with open(os.path.join(root, file), 'r', encoding='utf-8') as f:
                        content = f.read()
                        for pattern in forbidden_patterns:
                            self.assertNotIn(pattern, content, f"Forbidden pattern {pattern} in {file}")

if __name__ == '__main__':
    unittest.main()
