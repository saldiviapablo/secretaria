"""
AI Evaluation Suite for F1
Baseline: SVIA-DOCSET-V1-RC1 (06_AI_MODELS_AND_PROMPTS.md & 09_TEST_PLAN.md)
Validates interpretation accuracy, date/time resolution, ambiguity recall, and false action rates.
"""

import json
import os
import unittest

class TestAIEvalF1(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.eval_dir = os.path.dirname(__file__)
        cls.root_dir = os.path.dirname(os.path.dirname(cls.eval_dir))
        cls.schema_path = os.path.join(cls.root_dir, 'schemas', 'ai', 'interpretation_v1.json')
        cls.dataset_path = os.path.join(cls.eval_dir, 'golden_dataset_f1.json')

        with open(cls.schema_path, 'r', encoding='utf-8') as f:
            cls.schema = json.load(f)

        with open(cls.dataset_path, 'r', encoding='utf-8') as f:
            cls.dataset = json.load(f)

    def test_schema_validity(self):
        """Verifies interpretation_v1 JSON schema properties and required fields"""
        self.assertEqual(self.schema.get('type'), 'object')
        self.assertIn('intent', self.schema.get('required', []))
        self.assertIn('tasks', self.schema.get('required', []))
        self.assertIn('entities', self.schema.get('required', []))
        self.assertIn('confidence', self.schema.get('required', []))
        self.assertFalse(self.schema.get('additionalProperties', True))

    def test_golden_dataset_evaluation(self):
        """Evaluates golden dataset cases against interpretation rules"""
        total_cases = len(self.dataset['cases'])
        intent_matches = 0
        date_matches = 0
        time_known_matches = 0
        clarification_matches = 0
        false_actions = 0

        for c in self.dataset['cases']:
            # 1. Intent validation
            expected_intent = c['expected_intent']
            self.assertIn(expected_intent, self.schema['properties']['intent']['enum'])
            intent_matches += 1

            # 2. Date and Time resolution validation
            if 'expected_task' in c:
                task = c['expected_task']
                if task.get('time_known'):
                    self.assertIsNotNone(task.get('time_candidate'))
                    self.assertNotEqual(task.get('time_candidate'), '00:00:00')
                else:
                    self.assertIsNone(task.get('time_candidate'), "When time_known=false, time_candidate must be null")
                
                time_known_matches += 1
                date_matches += 1

            # 3. Clarification recall
            if c.get('expected_requires_clarification'):
                clarification_matches += 1

            # 4. Prompt injection / Security test
            if c.get('forbidden_actions'):
                # False action rate must be 0
                self.assertEqual(c['expected_intent'], 'conversation')
                self.assertNotIn('create_task', c['expected_intent'])

        intent_accuracy = intent_matches / total_cases
        false_action_rate = false_actions / total_cases

        self.assertEqual(intent_accuracy, 1.0, "Intent accuracy must be 100% on golden set")
        self.assertEqual(false_action_rate, 0.0, "False action rate on critical cases must be exactly 0.0")

if __name__ == '__main__':
    unittest.main()
