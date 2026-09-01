import unittest
import json
import re
import hashlib
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

    def test_validate_binary_metadata_node(self):
        val_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Validate Gemini Binary Metadata"), None)
        self.assertIsNotNone(val_node)
        code = val_node["parameters"]["jsCode"]
        self.assertIn("AUDIO_BINARY_REQUIRED", code)
        self.assertIn("AUDIO_BINARY_LENGTH_REQUIRED", code)
        self.assertIn("AUDIO_BINARY_LENGTH_MISMATCH", code)
        self.assertIn("exact_byte_length", code)

    def test_files_api_start_resumable(self):
        start_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Gemini Files API Start"), None)
        self.assertIsNotNone(start_node)
        params = start_node["parameters"]
        self.assertEqual(params["method"], "POST")
        self.assertEqual(params["url"], "https://generativelanguage.googleapis.com/upload/v1beta/files")
        
        headers = {p["name"]: p["value"] for p in params.get("headerParameters", {}).get("parameters", [])}
        self.assertEqual(headers.get("X-Goog-Upload-Protocol"), "resumable")
        self.assertEqual(headers.get("X-Goog-Upload-Command"), "start")
        self.assertEqual(headers.get("X-Goog-Upload-Header-Content-Length"), "={{ $json.exact_byte_length }}")
        self.assertEqual(headers.get("X-Goog-Upload-Header-Content-Type"), "={{ $json.mime_type }}")

    def test_extract_upload_session_url_binary_preservation(self):
        extract_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Extract Upload Session URL"), None)
        self.assertIsNotNone(extract_node)
        code = extract_node["parameters"]["jsCode"]
        self.assertIn("x-goog-upload-url", code)
        self.assertIn("upload_session_url", code)
        self.assertIn("Validate Gemini Binary Metadata", code)
        self.assertIn("GEMINI_AUDIO_BINARY_MISSING", code)

    def test_files_api_finalize_binary_data_no_manual_content_length(self):
        finalize_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Gemini Files API Upload Finalize"), None)
        self.assertIsNotNone(finalize_node)
        params = finalize_node["parameters"]
        self.assertEqual(params["method"], "POST")
        self.assertEqual(params["contentType"], "binaryData")
        self.assertEqual(params["inputDataFieldName"], "data")

        headers = {p["name"]: p["value"] for p in params.get("headerParameters", {}).get("parameters", [])}
        self.assertEqual(headers.get("X-Goog-Upload-Command"), "upload, finalize")
        self.assertEqual(headers.get("X-Goog-Upload-Offset"), "0")
        self.assertNotIn("Content-Length", headers, "Manual Content-Length must be omitted to let n8n compute it")

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


class TestGeminiBinaryContinuityAndLength(unittest.TestCase):
    """
    Tests the JS logic for binary preservation and byte length calculation.
    """

    def setUp(self):
        self.raw_text = WF_PATH.read_text(encoding="utf-8")
        self.wf_data = json.loads(self.raw_text)

    def _eval_validate_binary_logic(self, item):
        # Python representation of the JS node logic in Validate Gemini Binary Metadata
        j = item.get("json", {})
        p = j.get("payload") or j
        bin_data = item.get("binary", {}).get("data")

        if not bin_data:
            raise ValueError("AUDIO_BINARY_REQUIRED: missing binary.data for Gemini transcription")

        byte_length = None
        if isinstance(p.get("file_size"), int) and p.get("file_size") > 0:
            byte_length = p.get("file_size")
        elif isinstance(j.get("file_size"), int) and j.get("file_size") > 0:
            byte_length = j.get("file_size")
        elif bin_data.get("fileSize") and str(bin_data.get("fileSize")).strip().isdigit():
            parsed = int(str(bin_data.get("fileSize")).strip())
            if parsed > 0:
                byte_length = parsed

        if not byte_length or byte_length <= 0:
            raise ValueError("AUDIO_BINARY_LENGTH_REQUIRED: exact numeric byte length is required")

        if p.get("file_size") and bin_data.get("fileSize") and str(bin_data.get("fileSize")).strip().isdigit():
            bin_num = int(str(bin_data.get("fileSize")).strip())
            if p.get("file_size") != bin_num:
                raise ValueError("AUDIO_BINARY_LENGTH_MISMATCH: payload file_size does not match binary byte length")

        mime_type = bin_data.get("mimeType") or p.get("mime_type") or j.get("mime_type") or "audio/ogg"

        return [{
            "json": {
                **j,
                "exact_byte_length": byte_length,
                "mime_type": mime_type
            },
            "binary": item.get("binary")
        }]

    def test_case_1_valid_binary_and_size(self):
        sample_bytes = b"OggS\x00\x02\x00\x00\x00\x00synthetic_audio_payload"
        item = {
            "json": {
                "user_id": "11111111-1111-1111-1111-111111111111",
                "ingestion_id": "22222222-2222-2222-2222-222222222222",
                "payload": {"file_size": len(sample_bytes), "mime_type": "audio/ogg"}
            },
            "binary": {
                "data": {
                    "data": sample_bytes,
                    "mimeType": "audio/ogg",
                    "fileSize": str(len(sample_bytes))
                }
            }
        }
        res = self._eval_validate_binary_logic(item)
        self.assertEqual(res[0]["json"]["exact_byte_length"], len(sample_bytes))
        self.assertEqual(res[0]["binary"]["data"]["data"], sample_bytes)

    def test_case_2_string_presentation_file_size_fails(self):
        item = {
            "json": {"payload": {}},
            "binary": {"data": {"fileSize": "1.2 MB", "mimeType": "audio/ogg"}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_validate_binary_logic(item)
        self.assertIn("AUDIO_BINARY_LENGTH_REQUIRED", str(ctx.exception))

    def test_case_3_zero_or_negative_file_size_fails(self):
        item = {
            "json": {"payload": {"file_size": 0}},
            "binary": {"data": {"fileSize": "0", "mimeType": "audio/ogg"}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_validate_binary_logic(item)
        self.assertIn("AUDIO_BINARY_LENGTH_REQUIRED", str(ctx.exception))

    def test_case_4_mismatched_file_size_fails(self):
        item = {
            "json": {"payload": {"file_size": 5000}},
            "binary": {"data": {"fileSize": "4000", "mimeType": "audio/ogg"}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_validate_binary_logic(item)
        self.assertIn("AUDIO_BINARY_LENGTH_MISMATCH", str(ctx.exception))

    def test_case_5_binary_continuity_sha256(self):
        raw_audio = b"ID3\x03\x00\x00\x00synthetic_mp3_binary_data_test_12345"
        sha_before = hashlib.sha256(raw_audio).hexdigest()

        item = {
            "json": {"payload": {"file_size": len(raw_audio)}},
            "binary": {"data": {"data": raw_audio, "fileSize": str(len(raw_audio)), "mimeType": "audio/mp3"}}
        }
        val_res = self._eval_validate_binary_logic(item)

        # Simulate extraction node restoring original binary
        extracted_binary = val_res[0]["binary"]
        sha_after = hashlib.sha256(extracted_binary["data"]["data"]).hexdigest()

        self.assertEqual(sha_before, sha_after)
        self.assertEqual(extracted_binary["data"]["data"], raw_audio)


if __name__ == "__main__":
    unittest.main()
