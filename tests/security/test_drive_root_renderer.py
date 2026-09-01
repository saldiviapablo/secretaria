import unittest
import tempfile
import json
import shutil
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "infra" / "scripts"))

from render_n8n_workflows import (
    render_workflows,
    load_drive_root_config,
    PLACEHOLDER,
    AUTHORIZED_PLACEHOLDER_FILES,
    TOTAL_EXPECTED_REPLACEMENTS
)


class TestDriveRootRenderer(unittest.TestCase):
    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp(prefix="test_renderer_"))

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_case_1_missing_config(self):
        non_existent = self.temp_dir / "non_existent.env"
        with self.assertRaises(FileNotFoundError) as ctx:
            load_drive_root_config(env_file_path=non_existent)
        self.assertIn("DRIVE_ROOT_CONFIG_REQUIRED", str(ctx.exception))

    def test_case_2_empty_config(self):
        empty_env = self.temp_dir / "empty.env"
        empty_env.write_text("SVIA_DRIVE_ROOT_FOLDER_ID_DEV=\n", encoding="utf-8")
        with self.assertRaises(ValueError) as ctx:
            load_drive_root_config(env_file_path=empty_env)
        self.assertIn("DRIVE_ROOT_CONFIG_REQUIRED", str(ctx.exception))

    def test_case_3_invalid_config_format(self):
        invalid_env = self.temp_dir / "invalid.env"
        invalid_env.write_text("SVIA_DRIVE_ROOT_FOLDER_ID_DEV=bad!char@id\n", encoding="utf-8")
        with self.assertRaises(ValueError) as ctx:
            load_drive_root_config(env_file_path=invalid_env)
        self.assertIn("DRIVE_ROOT_CONFIG_INVALID", str(ctx.exception))

    def test_case_4_valid_render_and_immutability(self):
        valid_id = "1AbC-xYz_folder_root_test_id_12345"
        out_dir = self.temp_dir / "rendered"
        res = render_workflows(valid_id, output_dir=out_dir)

        self.assertEqual(res["status"], "PASS")
        self.assertEqual(res["total_workflows_rendered"], 23)
        self.assertEqual(res["total_replacements_performed"], TOTAL_EXPECTED_REPLACEMENTS)

        # Check rendered workflows are valid JSON and contain real ID
        for rel_path, count in AUTHORIZED_PLACEHOLDER_FILES.items():
            rendered_file = out_dir / rel_path
            self.assertTrue(rendered_file.exists())
            content = rendered_file.read_text(encoding="utf-8")
            self.assertNotIn(PLACEHOLDER, content)
            self.assertNotIn("$env.SVIA_DRIVE_ROOT_FOLDER_ID_DEV", content)
            self.assertEqual(content.count(valid_id), count)
            data = json.loads(content)
            self.assertIsInstance(data, dict)

    def test_case_5_unauthorized_extra_placeholder_in_source(self):
        # Create a mock source directory with extra placeholder in unauthorized file
        mock_src = self.temp_dir / "mock_workflows"
        shutil.copytree(ROOT / "n8n" / "workflows", mock_src)

        unauth_file = mock_src / "telegram" / "WF-TG-001_TELEGRAM_INBOUND.json"
        txt = unauth_file.read_text(encoding="utf-8")
        unauth_file.write_text(txt.replace('"nodes": [', f'"extra_field": "{PLACEHOLDER}", "nodes": ['), encoding="utf-8")

        out_dir = self.temp_dir / "rendered_fail"
        with self.assertRaises(ValueError) as ctx:
            render_workflows("1AbC-xYz_folder_root_test_id_12345", output_dir=out_dir, workflows_source_dir=mock_src)
        self.assertIn("UNAUTHORIZED_PLACEHOLDER_COUNT", str(ctx.exception))

    def test_case_6_no_env_dependency_in_templates(self):
        src_dir = ROOT / "n8n" / "workflows"
        manifest = json.loads((src_dir / "manifest.json").read_text(encoding="utf-8"))
        for entry in manifest["workflows"]:
            content = (src_dir / entry["file"]).read_text(encoding="utf-8")
            self.assertNotIn("$env.SVIA_DRIVE_ROOT_FOLDER_ID_DEV", content)

    def test_case_7_secret_scan_in_rendered_output(self):
        valid_id = "1AbC-xYz_folder_root_test_id_12345"
        out_dir = self.temp_dir / "rendered_secrets"
        render_workflows(valid_id, output_dir=out_dir)

        forbidden_tokens = ["OPENAI_API_KEY", "GEMINI_API_KEY", "TELEGRAM_BOT_TOKEN", "N8N_ENCRYPTION_KEY", "BEGIN PRIVATE KEY"]
        for f in out_dir.rglob("*.json"):
            content = f.read_text(encoding="utf-8")
            for tok in forbidden_tokens:
                self.assertNotIn(tok, content)


if __name__ == "__main__":
    unittest.main()
