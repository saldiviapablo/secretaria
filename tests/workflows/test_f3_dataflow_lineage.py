import unittest
import json
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WF3_PATH = ROOT / "n8n" / "workflows" / "ingestion" / "WF-ING-003_PROCESS_MEDIA.json"
WF4_PATH = ROOT / "n8n" / "workflows" / "ingestion" / "WF-ING-004_DRIVE_WATCH.json"
WF5_PATH = ROOT / "n8n" / "workflows" / "ingestion" / "WF-ING-005_DRIVE_RECONCILIATION.json"
WF6_PATH = ROOT / "n8n" / "workflows" / "ingestion" / "WF-ING-006_DOCUMENT_EXTRACT.json"
AI1_PATH = ROOT / "n8n" / "workflows" / "ai" / "WF-AI-001_TRANSCRIBE.json"
AI3_PATH = ROOT / "n8n" / "workflows" / "ai" / "WF-AI-003_ANALYZE_VISUAL.json"


class TestF3DataflowLineage(unittest.TestCase):
    def setUp(self):
        self.wf3 = json.loads(WF3_PATH.read_text(encoding="utf-8"))
        self.wf4 = json.loads(WF4_PATH.read_text(encoding="utf-8"))
        self.wf5 = json.loads(WF5_PATH.read_text(encoding="utf-8"))
        self.wf6 = json.loads(WF6_PATH.read_text(encoding="utf-8"))
        self.ai1 = json.loads(AI1_PATH.read_text(encoding="utf-8"))
        self.ai3 = json.loads(AI3_PATH.read_text(encoding="utf-8"))

    def test_prelive_001_sha256_preserves_binary_node(self):
        # Crypto node should NOT be used for binary in WF-ING-003
        crypto_nodes = [n for n in self.wf3["nodes"] if n.get("type") == "n8n-nodes-base.crypto"]
        self.assertEqual(len(crypto_nodes), 0, "Crypto v1 must be replaced with Code node preserving binary")

        sha_node = next((n for n in self.wf3["nodes"] if n["name"] == "Compute SHA-256 Preserving Binary"), None)
        self.assertIsNotNone(sha_node)
        code = sha_node["parameters"]["jsCode"]
        self.assertIn("getBinaryDataBuffer", code)
        self.assertIn("createHash('sha256')", code)
        self.assertIn("binary: item.binary", code)

    def test_prelive_002_telegram_context_restoration(self):
        tg_restore = next((n for n in self.wf3["nodes"] if n["name"] == "Restore Telegram Media Context"), None)
        self.assertIsNotNone(tg_restore)
        code = tg_restore["parameters"]["jsCode"]
        self.assertIn("Validate / Gate Media", code)
        self.assertIn("telegram_download_meta", code)
        self.assertIn("binary: item.binary", code)

    def test_prelive_003_004_separate_archive_and_dual_locations(self):
        branch_archive = next((n for n in self.wf3["nodes"] if n["name"] == "Branch Source for Archive"), None)
        self.assertIsNotNone(branch_archive)

        upsert_tg = next((n for n in self.wf3["nodes"] if n["name"] == "Upsert Telegram Location RPC"), None)
        upsert_drive = next((n for n in self.wf3["nodes"] if n["name"] == "Upsert Drive Location RPC"), None)
        upsert_drive_only = next((n for n in self.wf3["nodes"] if n["name"] == "Upsert Drive Only Location RPC"), None)

        self.assertIsNotNone(upsert_tg)
        self.assertIsNotNone(upsert_drive)
        self.assertIsNotNone(upsert_drive_only)

        # Drive upload retryOnFail must be false
        drive_upload = next((n for n in self.wf3["nodes"] if n["name"] == "Archive Original in Drive"), None)
        self.assertIsNotNone(drive_upload)
        self.assertFalse(drive_upload.get("retryOnFail", False))

    def test_prelive_005_drive_watch_duplicate_branch(self):
        dup_switch = next((n for n in self.wf4["nodes"] if n["name"] == "Branch on Duplicate vs New"), None)
        self.assertIsNotNone(dup_switch)
        dup_noop = next((n for n in self.wf4["nodes"] if n["name"] == "Drive Duplicate Ignored"), None)
        self.assertIsNotNone(dup_noop)

    def test_prelive_006_007_reconciliation_multi_item_pairing(self):
        restore_cand = next((n for n in self.wf5["nodes"] if n["name"] == "Restore Reconciled Candidate Context"), None)
        self.assertIsNotNone(restore_cand)
        code = restore_cand["parameters"]["jsCode"]
        self.assertIn("results.map((item, idx)", code)
        self.assertIn("candidates[idx]", code)
        self.assertNotIn("$input.first()", code)

    def test_prelive_009_unsupported_media_terminal_handler(self):
        unsupported_node = next((n for n in self.wf3["nodes"] if n["name"] == "Persist Unsupported Media Status"), None)
        self.assertIsNotNone(unsupported_node)
        q = unsupported_node["parameters"]["query"]
        self.assertIn("UNSUPPORTED_MEDIA_TYPE", q)

    def test_prelive_012_vision_binary_buffer_helper(self):
        prep_bin = next((n for n in self.ai3["nodes"] if n["name"] == "Validate and Prepare Visual Binary"), None)
        self.assertIsNotNone(prep_bin)
        code = prep_bin["parameters"]["jsCode"]
        self.assertIn("getBinaryDataBuffer", code)
        self.assertIn("UNSUPPORTED_IMAGE_MIME", code)
        self.assertNotIn("|| 'image/jpeg'", code)
        self.assertNotIn('|| "image/jpeg"', code)

        openai_node = next((n for n in self.ai3["nodes"] if n["name"] == "OpenAI Luna Vision Adapter"), None)
        gemini_node = next((n for n in self.ai3["nodes"] if n["name"] == "Gemini Multimodal Vision Adapter"), None)
        self.assertFalse(openai_node.get("retryOnFail", False))
        self.assertFalse(gemini_node.get("retryOnFail", False))

    def test_prelive_014_document_format_router_and_empty_check(self):
        doc_router = next((n for n in self.wf6["nodes"] if n["name"] == "Document Format Router"), None)
        self.assertIsNotNone(doc_router)

        norm_node = next((n for n in self.wf6["nodes"] if n["name"] == "Normalize Extracted Text"), None)
        self.assertIsNotNone(norm_node)
        code = norm_node["parameters"]["jsCode"]
        self.assertIn("EMPTY_DOCUMENT_EXTRACTION", code)
        self.assertIn("CONTROLLED_REVIEW_REQUIRED_DOCX_EXTRACTION", code)

    def test_prelive_015_child_persistence_gate_in_parent(self):
        verify_child = next((n for n in self.wf3["nodes"] if n["name"] == "Verify Child Persistence Before Completion"), None)
        self.assertIsNotNone(verify_child)
        code = verify_child["parameters"]["jsCode"]
        self.assertIn("CHILD_WORKFLOW_PERSISTENCE_FAILED", code)
        self.assertIn("source_text_id", code)


if __name__ == "__main__":
    unittest.main()
