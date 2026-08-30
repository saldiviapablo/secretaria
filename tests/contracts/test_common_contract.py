"""
Contract Tests for Common Subworkflow Envelope v1.0
Baseline: SVIA-DOCSET-V1-RC1 (05_N8N_WORKFLOWS.md Section 4)
"""

import unittest
import uuid
from datetime import datetime

class TestCommonContract(unittest.TestCase):
    def setUp(self):
        self.valid_categories = {
            "authorization",
            "validation",
            "duplicate",
            "ambiguity",
            "transient_external",
            "permanent_external",
            "rate_limit",
            "data_integrity",
            "not_found",
            "unsupported",
            "internal"
        }

    def test_valid_input_envelope(self):
        envelope = {
            "contract_version": "1.0",
            "correlation_id": str(uuid.uuid4()),
            "user_id": str(uuid.uuid4()),
            "ingestion_id": str(uuid.uuid4()),
            "source_channel": "telegram",
            "request_id": "req-12345",
            "captured_at": datetime.now().isoformat(),
            "timezone": "America/Argentina/Buenos_Aires",
            "locale": "es-AR",
            "payload": {
                "text": "Comprar café"
            }
        }
        
        self.assertEqual(envelope["contract_version"], "1.0")
        self.assertTrue(uuid.UUID(envelope["correlation_id"]))
        self.assertTrue(uuid.UUID(envelope["user_id"]))
        self.assertIn(envelope["source_channel"], ["telegram", "google_drive", "chatgpt_mcp", "web", "system", "external"])

    def test_valid_output_envelope_success(self):
        output = {
            "ok": True,
            "status": "completed",
            "correlation_id": str(uuid.uuid4()),
            "data": {
                "task_id": str(uuid.uuid4())
            },
            "warnings": []
        }
        self.assertTrue(output["ok"])
        self.assertEqual(output["status"], "completed")
        self.assertIsInstance(output["data"], dict)
        self.assertIsInstance(output["warnings"], list)

    def test_controlled_error_envelope(self):
        error_output = {
            "ok": False,
            "status": "needs_clarification",
            "correlation_id": str(uuid.uuid4()),
            "error": {
                "category": "ambiguity",
                "code": "PERSON_AMBIGUOUS",
                "message_safe": "Hay más de una persona posible."
            }
        }
        self.assertFalse(error_output["ok"])
        self.assertIn(error_output["error"]["category"], self.valid_categories)
        self.assertNotIn("token", error_output["error"]["message_safe"].lower())
        self.assertNotIn("password", error_output["error"]["message_safe"].lower())

if __name__ == "__main__":
    unittest.main()
