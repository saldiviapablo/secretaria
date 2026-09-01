import unittest
import http.server
import threading
import json
import hashlib
import urllib.request
import urllib.parse
from pathlib import Path

# Local mock server to test Gemini Files API start & finalize protocol
class MockGeminiFilesServer(http.server.BaseHTTPRequestHandler):
    recorded_uploads = []

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        if self.path == "/upload/v1beta/files":
            # Files API Start resumable
            proto = self.headers.get("X-Goog-Upload-Protocol")
            cmd = self.headers.get("X-Goog-Upload-Command")
            declared_len = self.headers.get("X-Goog-Upload-Header-Content-Length")
            declared_mime = self.headers.get("X-Goog-Upload-Header-Content-Type")

            self.send_response(200)
            upload_url = f"http://127.0.0.1:{self.server.server_port}/upload_session/mock_session_123"
            self.send_header("x-goog-upload-url", upload_url)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"upload_url": upload_url, "status": "session_created"}).encode("utf-8"))

        elif self.path.startswith("/upload_session/"):
            # Files API Upload Finalize
            offset = self.headers.get("X-Goog-Upload-Offset")
            cmd = self.headers.get("X-Goog-Upload-Command")
            content_type = self.headers.get("Content-Type")

            sha256 = hashlib.sha256(post_data).hexdigest()
            MockGeminiFilesServer.recorded_uploads.append({
                "path": self.path,
                "byte_count": len(post_data),
                "sha256": sha256,
                "offset": offset,
                "command": cmd,
                "content_type": content_type
            })

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "file": {
                    "name": "files/mock_file_id_999",
                    "displayName": "svia-test-audio",
                    "mimeType": "audio/ogg",
                    "sizeBytes": str(len(post_data)),
                    "uri": "https://generativelanguage.googleapis.com/v1beta/files/mock_file_id_999",
                    "sha256Hash": sha256
                }
            }).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Quiet logging in tests


class TestGeminiBinaryRuntimeMock(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.HTTPServer(("127.0.0.1", 0), MockGeminiFilesServer)
        cls.port = cls.server.server_port
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        MockGeminiFilesServer.recorded_uploads.clear()

    def test_mock_resumable_upload_lifecycle(self):
        # 1. Prepare synthetic binary fixture
        audio_fixture = b"OggS\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00synthetic_audio_payload_bytes_for_testing"
        expected_len = len(audio_fixture)
        expected_sha = hashlib.sha256(audio_fixture).hexdigest()
        expected_mime = "audio/ogg"

        # 2. Simulate Start
        start_req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/upload/v1beta/files",
            data=json.dumps({"file": {"display_name": "svia-test"}}).encode("utf-8"),
            headers={
                "X-Goog-Upload-Protocol": "resumable",
                "X-Goog-Upload-Command": "start",
                "X-Goog-Upload-Header-Content-Length": str(expected_len),
                "X-Goog-Upload-Header-Content-Type": expected_mime,
                "Content-Type": "application/json"
            }
        )
        with urllib.request.urlopen(start_req) as resp:
            self.assertEqual(resp.status, 200)
            upload_url = resp.headers.get("x-goog-upload-url")
            self.assertIsNotNone(upload_url)

        # 3. Simulate Finalize with binary stream
        finalize_req = urllib.request.Request(
            upload_url,
            data=audio_fixture,
            headers={
                "X-Goog-Upload-Offset": "0",
                "X-Goog-Upload-Command": "upload, finalize"
            }
        )
        with urllib.request.urlopen(finalize_req) as resp:
            self.assertEqual(resp.status, 200)
            res_body = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(res_body["file"]["uri"], "https://generativelanguage.googleapis.com/v1beta/files/mock_file_id_999")
            self.assertEqual(res_body["file"]["sha256Hash"], expected_sha)

        # 4. Verify recorded mock data matches fixture
        self.assertEqual(len(MockGeminiFilesServer.recorded_uploads), 1)
        rec = MockGeminiFilesServer.recorded_uploads[0]
        self.assertEqual(rec["byte_count"], expected_len)
        self.assertEqual(rec["sha256"], expected_sha)
        self.assertEqual(rec["command"], "upload, finalize")
        self.assertEqual(rec["offset"], "0")


if __name__ == "__main__":
    unittest.main()
