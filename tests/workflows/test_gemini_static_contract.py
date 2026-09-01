import unittest
import json
import re
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WF_PATH = ROOT / "n8n" / "workflows" / "ai" / "WF-AI-001_TRANSCRIBE.json"
MODELS_PATH = ROOT / "config" / "ai_models.json"

ALLOWED_GEMINI_AUDIO_MIMES = {
    'audio/ogg', 'audio/mp3', 'audio/mpeg', 'audio/wav', 'audio/x-wav',
    'audio/aac', 'audio/flac', 'audio/m4a', 'audio/x-m4a', 'audio/mp4',
    'audio/opus', 'audio/webm'
}


class TestGeminiStaticContract(unittest.TestCase):
    def setUp(self):
        self.assertTrue(WF_PATH.exists(), f"Workflow file not found: {WF_PATH}")
        self.raw_text = WF_PATH.read_text(encoding="utf-8")
        self.wf_data = json.loads(self.raw_text)

    def test_model_name_exact(self):
        self.assertIn("gemini-3.5-transcribe", self.raw_text)

    def test_validate_binary_metadata_node_implementation(self):
        val_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Validate Gemini Binary Metadata"), None)
        self.assertIsNotNone(val_node)
        code = val_node["parameters"]["jsCode"]
        self.assertIn("getBinaryDataBuffer", code)
        self.assertIn("AUDIO_BINARY_REQUIRED", code)
        self.assertIn("AUDIO_BINARY_LENGTH_REQUIRED", code)
        self.assertIn("AUDIO_BINARY_LENGTH_MISMATCH", code)
        self.assertIn("AUDIO_MIME_TYPE_REQUIRED", code)
        self.assertIn("AUDIO_MIME_TYPE_MISMATCH", code)
        self.assertIn("GEMINI_UNSUPPORTED_AUDIO_MIME", code)
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

    def test_files_api_finalize_retry_disabled_and_no_manual_content_length(self):
        finalize_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Gemini Files API Upload Finalize"), None)
        self.assertIsNotNone(finalize_node)
        self.assertFalse(finalize_node.get("retryOnFail", False), "Blind retry must be disabled on Finalize")

        params = finalize_node["parameters"]
        self.assertEqual(params["method"], "POST")
        self.assertEqual(params["contentType"], "binaryData")
        self.assertEqual(params["inputDataFieldName"], "data")

        headers = {p["name"]: p["value"] for p in params.get("headerParameters", {}).get("parameters", [])}
        self.assertEqual(headers.get("X-Goog-Upload-Command"), "upload, finalize")
        self.assertEqual(headers.get("X-Goog-Upload-Offset"), "0")
        self.assertNotIn("Content-Length", headers, "Manual Content-Length must be omitted to let n8n compute it")

    def test_interaction_node_retry_disabled_and_mime_binding(self):
        interact_node = next((n for n in self.wf_data["nodes"] if n["name"] == "Gemini Transcribe Interaction"), None)
        self.assertIsNotNone(interact_node)
        self.assertFalse(interact_node.get("retryOnFail", False), "Blind retry must be disabled on Interaction")

        params = interact_node["parameters"]
        self.assertEqual(params["method"], "POST")
        self.assertEqual(params["url"], "https://generativelanguage.googleapis.com/v1beta/interactions")

        json_body = params.get("jsonBody", "")
        self.assertIn('"model": "gemini-3.5-transcribe"', json_body)
        self.assertIn('"type": "audio"', json_body)
        self.assertIn('"language_codes": ["es-AR"]', json_body)
        self.assertIn('"type": "verbatim"', json_body)
        self.assertIn('"mime_type": $json.mime_type', json_body)

        # Prohibited fallback strings
        self.assertNotIn("|| 'audio/ogg'", self.raw_text)
        self.assertNotIn('|| "audio/ogg"', self.raw_text)

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


class TestGeminiBinaryLogicAndValidation(unittest.TestCase):
    """
    Simulates the exact logic implemented in the Validate Gemini Binary Metadata Code Node.
    """

    def _eval_node_logic(self, item, mock_buffer):
        j = item.get("json", {})
        p = j.get("payload") or j
        bin_data = item.get("binary", {}).get("data")

        if not bin_data:
            raise ValueError("AUDIO_BINARY_REQUIRED: missing binary.data for Gemini transcription")

        buffer = mock_buffer
        if not buffer or len(buffer) == 0:
            raise ValueError("AUDIO_BINARY_LENGTH_REQUIRED: binary audio buffer is empty or missing")

        exact_byte_length = len(buffer)
        if exact_byte_length <= 0:
            raise ValueError("AUDIO_BINARY_LENGTH_REQUIRED: exact numeric byte length is invalid")

        if p.get("file_size") is not None:
            if not isinstance(p.get("file_size"), int) or p.get("file_size") <= 0:
                raise ValueError("AUDIO_BINARY_LENGTH_REQUIRED: payload file_size must be a positive integer")
            if p.get("file_size") != exact_byte_length:
                raise ValueError(f"AUDIO_BINARY_LENGTH_MISMATCH: payload file_size ({p.get('file_size')}) does not match binary buffer length ({exact_byte_length})")

        raw_mime = (bin_data.get("mimeType") or p.get("mime_type") or "").strip().lower()
        if not raw_mime:
            raise ValueError("AUDIO_MIME_TYPE_REQUIRED: audio MIME type is missing")

        if p.get("mime_type") and bin_data.get("mimeType"):
            if p.get("mime_type").strip().lower() != bin_data.get("mimeType").strip().lower():
                raise ValueError("AUDIO_MIME_TYPE_MISMATCH: payload mime_type does not match binary mimeType")

        if raw_mime not in ALLOWED_GEMINI_AUDIO_MIMES:
            raise ValueError(f"GEMINI_UNSUPPORTED_AUDIO_MIME: MIME type {raw_mime} is not supported by Gemini API")

        return [{
            "json": {
                **j,
                "exact_byte_length": exact_byte_length,
                "mime_type": raw_mime
            },
            "binary": item.get("binary")
        }]

    def test_byte_length_1_byte_buffer(self):
        buf = b"X"
        item = {
            "json": {"payload": {"file_size": 1, "mime_type": "audio/ogg"}},
            "binary": {"data": {"mimeType": "audio/ogg", "fileSize": "1"}}
        }
        res = self._eval_node_logic(item, buf)
        self.assertEqual(res[0]["json"]["exact_byte_length"], 1)

    def test_byte_length_n_bytes_buffer(self):
        buf = b"OggS\x00\x02\x00\x00\x00\x00synthetic_payload_32_bytes_len!"
        item = {
            "json": {"payload": {"file_size": len(buf), "mime_type": "audio/ogg"}},
            "binary": {"data": {"mimeType": "audio/ogg", "fileSize": str(len(buf))}}
        }
        res = self._eval_node_logic(item, buf)
        self.assertEqual(res[0]["json"]["exact_byte_length"], len(buf))

    def test_byte_length_mismatch_fails_closed(self):
        buf = b"1234567890"
        item = {
            "json": {"payload": {"file_size": 20, "mime_type": "audio/ogg"}},
            "binary": {"data": {"mimeType": "audio/ogg"}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_node_logic(item, buf)
        self.assertIn("AUDIO_BINARY_LENGTH_MISMATCH", str(ctx.exception))

    def test_byte_length_missing_payload_size_uses_buffer_length(self):
        buf = b"audio_sample_bytes_without_payload_size"
        item = {
            "json": {"payload": {"mime_type": "audio/ogg"}},
            "binary": {"data": {"mimeType": "audio/ogg"}}
        }
        res = self._eval_node_logic(item, buf)
        self.assertEqual(res[0]["json"]["exact_byte_length"], len(buf))

    def test_empty_buffer_fails_closed(self):
        buf = b""
        item = {
            "json": {"payload": {"file_size": 0, "mime_type": "audio/ogg"}},
            "binary": {"data": {"mimeType": "audio/ogg"}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_node_logic(item, buf)
        self.assertIn("AUDIO_BINARY_LENGTH_REQUIRED", str(ctx.exception))

    def test_mime_supported_formats(self):
        buf = b"audio_data"
        for mime in ['audio/ogg', 'audio/mp3', 'audio/mpeg', 'audio/wav', 'audio/flac', 'audio/m4a']:
            item = {
                "json": {"payload": {"file_size": len(buf), "mime_type": mime}},
                "binary": {"data": {"mimeType": mime}}
            }
            res = self._eval_node_logic(item, buf)
            self.assertEqual(res[0]["json"]["mime_type"], mime)

    def test_mime_missing_fails_closed(self):
        buf = b"audio_data"
        item = {
            "json": {"payload": {"file_size": len(buf)}},
            "binary": {"data": {"data": buf}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_node_logic(item, buf)
        self.assertIn("AUDIO_MIME_TYPE_REQUIRED", str(ctx.exception))

    def test_mime_mismatch_fails_closed(self):
        buf = b"audio_data"
        item = {
            "json": {"payload": {"file_size": len(buf), "mime_type": "audio/mp3"}},
            "binary": {"data": {"mimeType": "audio/ogg"}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_node_logic(item, buf)
        self.assertIn("AUDIO_MIME_TYPE_MISMATCH", str(ctx.exception))

    def test_unsupported_mime_fails_closed(self):
        buf = b"video_data"
        item = {
            "json": {"payload": {"file_size": len(buf), "mime_type": "video/mp4"}},
            "binary": {"data": {"mimeType": "video/mp4"}}
        }
        with self.assertRaises(ValueError) as ctx:
            self._eval_node_logic(item, buf)
        self.assertIn("GEMINI_UNSUPPORTED_AUDIO_MIME", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
