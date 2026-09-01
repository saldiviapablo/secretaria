import unittest
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WF_PATH = ROOT / "n8n" / "workflows" / "ai" / "WF-AI-001_TRANSCRIBE.json"
MODELS_PATH = ROOT / "config" / "ai_models.json"


class TestGeminiStaticContract(unittest.TestCase):
    def setUp(self):
        self.assertTrue(WF_PATH.exists(), f"Workflow file not found: {WF_PATH}")
        self.raw_text = WF_PATH.read_text(encoding="utf-8")
        self.wf_data = json.loads(self.raw_text)

    def test_model_name_exact(self):
        self.assertIn("gemini-3.5-transcribe", self.raw_text)

    def test_files_api_start_resumable(self):
        start_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Gemini Files API Start"), None)
        self.assertIsNotNone(start_node)
        params = start_node["parameters"]
        self.assertEqual(params["method"], "POST")
        self.assertEqual(params["url"], "https://generativelanguage.googleapis.com/upload/v1beta/files")
        
        headers = {p["name"]: p["value"] for p in params.get("headerParameters", {}).get("parameters", [])}
        self.assertEqual(headers.get("X-Goog-Upload-Protocol"), "resumable")
        self.assertEqual(headers.get("X-Goog-Upload-Command"), "start")
        self.assertIn("X-Goog-Upload-Header-Content-Length", headers)
        self.assertIn("X-Goog-Upload-Header-Content-Type", headers)

    def test_extract_upload_session_url(self):
        extract_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Extract Upload Session URL"), None)
        self.assertIsNotNone(extract_node)
        code = extract_node["parameters"]["jsCode"]
        self.assertIn("x-goog-upload-url", code)
        self.assertIn("upload_session_url", code)

    def test_files_api_finalize_binary_data(self):
        finalize_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Gemini Files API Upload Finalize"), None)
        self.assertIsNotNone(finalize_node)
        params = finalize_node["parameters"]
        self.assertEqual(params["method"], "POST")
        self.assertEqual(params["contentType"], "binaryData")
        self.assertEqual(params["inputDataFieldName"], "data")

        headers = {p["name"]: p["value"] for p in params.get("headerParameters", {}).get("parameters", [])}
        self.assertEqual(headers.get("X-Goog-Upload-Command"), "upload, finalize")
        self.assertEqual(headers.get("X-Goog-Upload-Offset"), "0")

    def test_interactions_api_body_and_verbatim_schema(self):
        interact_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Gemini Transcribe Interaction"), None)
        self.assertIsNotNone(interact_node)
        params = interact_node["parameters"]
        self.assertEqual(params["method"], "POST")
        self.assertEqual(params["url"], "https://generativelanguage.googleapis.com/v1beta/interactions")

        json_body = params.get("jsonBody", "")
        self.assertIn('"model": "gemini-3.5-transcribe"', json_body)
        self.assertIn('"type": "audio"', json_body)
        self.assertIn('"language_codes": ["es-AR"]', json_body)
        self.assertIn('"type": "verbatim"', json_body)

        # Prohibited legacy formats
        self.assertNotIn('"language_code": "es-AR"', json_body)
        self.assertNotIn('"mode": "verbatim"', json_body)

    def test_no_forbidden_methods_or_inline_data(self):
        self.assertNotIn("generateContent", self.raw_text)
        self.assertNotIn("inlineData", self.raw_text)

    def test_no_hardcoded_secrets(self):
        forbidden_patterns = [
            r'AIza[0-9A-Za-z\-_]{35}',
            r'key=[a-zA-Z0-9_\-]{20,}',
            r'x-goog-api-key\s*:\s*["\'][a-zA-Z0-9]'
        ]
        for pat in forbidden_patterns:
            self.assertIsNone(re.search(pat, self.raw_text))

    def test_transcription_primary_remains_null(self):
        models_data = json.loads(MODELS_PATH.read_text(encoding="utf-8"))
        self.assertIsNone(models_data["routing"]["transcription_primary"])


if __name__ == "__main__":
    unittest.main()
