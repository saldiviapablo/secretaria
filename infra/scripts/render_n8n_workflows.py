#!/usr/bin/env python3
"""
Deterministic n8n Workflow Renderer for DRIVE-ROOT-001.

Renders Git workflow templates by substituting the non-executable placeholder
`__SVIA_DRIVE_ROOT_FOLDER_ID__` with the deployment-local Google Drive root folder ID.

This script enforces fail-closed validation, template immutability, placeholder isolation,
and zero exposure of process environment variables to n8n runtime expressions.
"""

import os
import sys
import json
import re
import shutil
import hashlib
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
WORKFLOWS_DIR = ROOT_DIR / "n8n" / "workflows"
MANIFEST_FILE = WORKFLOWS_DIR / "manifest.json"
DEFAULT_ENV_FILE = ROOT_DIR / "infra" / "docker" / ".env"
DEFAULT_OUTPUT_DIR = ROOT_DIR / "build" / "rendered_workflows"

PLACEHOLDER = "__SVIA_DRIVE_ROOT_FOLDER_ID__"
AUTHORIZED_PLACEHOLDER_FILES = {
    "ingestion/WF-ING-003_PROCESS_MEDIA.json": 1,
    "ingestion/WF-ING-004_DRIVE_WATCH.json": 2,
    "ingestion/WF-ING-005_DRIVE_RECONCILIATION.json": 1
}
TOTAL_EXPECTED_REPLACEMENTS = 4
DRIVE_ID_PATTERN = re.compile(r"^[a-zA-Z0-9_\-]{10,128}$")


def sha256_file(filepath: Path) -> str:
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def load_drive_root_config(env_file_path: Path = None, explicit_value: str = None) -> str:
    if explicit_value:
        val = explicit_value.strip()
        if not val:
            raise ValueError("DRIVE_ROOT_CONFIG_REQUIRED: Explicit drive root value is empty")
        if not DRIVE_ID_PATTERN.match(val):
            raise ValueError(f"DRIVE_ROOT_CONFIG_INVALID: Value does not match expected pattern")
        return val

    env_path = env_file_path or DEFAULT_ENV_FILE
    if not env_path.exists():
        raise FileNotFoundError(f"DRIVE_ROOT_CONFIG_REQUIRED: Configuration file not found at {env_path}")

    val = None
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                if k.strip() == "SVIA_DRIVE_ROOT_FOLDER_ID_DEV":
                    val = v.strip()
                    break

    if not val:
        raise ValueError("DRIVE_ROOT_CONFIG_REQUIRED: SVIA_DRIVE_ROOT_FOLDER_ID_DEV not defined or empty in config")

    if not DRIVE_ID_PATTERN.match(val):
        raise ValueError("DRIVE_ROOT_CONFIG_INVALID: SVIA_DRIVE_ROOT_FOLDER_ID_DEV format is invalid")

    return val


def render_workflows(drive_root_id: str, output_dir: Path = None, workflows_source_dir: Path = None) -> dict:
    if not drive_root_id or not DRIVE_ID_PATTERN.match(drive_root_id):
        raise ValueError("DRIVE_ROOT_CONFIG_REQUIRED: Valid drive_root_id is required for rendering")

    src_dir = workflows_source_dir or WORKFLOWS_DIR
    out_dir = output_dir or DEFAULT_OUTPUT_DIR

    if not (src_dir / "manifest.json").exists():
        raise FileNotFoundError(f"Manifest not found in source directory {src_dir}")

    manifest_data = json.loads((src_dir / "manifest.json").read_text(encoding="utf-8"))
    workflow_entries = manifest_data.get("workflows", [])
    if len(workflow_entries) != 23:
        raise ValueError(f"Expected exactly 23 workflows in manifest, found {len(workflow_entries)}")

    # Pre-render snapshot of source hashes to verify immutability
    source_hashes_before = {}
    for entry in workflow_entries:
        rel_path = entry["file"]
        src_file = src_dir / rel_path
        if not src_file.exists():
            raise FileNotFoundError(f"Source workflow file missing: {src_file}")
        source_hashes_before[rel_path] = sha256_file(src_file)

    # Clean / prepare output directory
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rendered_hashes = {}
    total_replacements_done = 0

    for entry in workflow_entries:
        rel_path = entry["file"]
        src_file = src_dir / rel_path
        dest_file = out_dir / rel_path
        dest_file.parent.mkdir(parents=True, exist_ok=True)

        raw_text = src_file.read_text(encoding="utf-8")

        # Validation: Verify valid JSON in source
        try:
            json.loads(raw_text)
        except json.JSONDecodeError as err:
            raise ValueError(f"Invalid JSON in source template {rel_path}: {err}")

        # Check for forbidden $env references
        if "$env.SVIA_DRIVE_ROOT_FOLDER_ID_DEV" in raw_text:
            raise ValueError(f"FORBIDDEN_ENV_ACCESS: Template {rel_path} contains $env.SVIA_DRIVE_ROOT_FOLDER_ID_DEV")

        count_in_file = raw_text.count(PLACEHOLDER)
        expected_in_file = AUTHORIZED_PLACEHOLDER_FILES.get(rel_path, 0)

        if count_in_file != expected_in_file:
            raise ValueError(
                f"UNAUTHORIZED_PLACEHOLDER_COUNT in {rel_path}: expected {expected_in_file}, found {count_in_file}"
            )

        # Perform deterministic substitution
        if count_in_file > 0:
            rendered_text = raw_text.replace(PLACEHOLDER, drive_root_id)
            total_replacements_done += count_in_file
        else:
            rendered_text = raw_text

        # Validation: Post-render checks
        if PLACEHOLDER in rendered_text:
            raise ValueError(f"RESIDUAL_PLACEHOLDER: Output file {rel_path} still contains {PLACEHOLDER}")

        if "$env.SVIA_DRIVE_ROOT_FOLDER_ID_DEV" in rendered_text:
            raise ValueError(f"FORBIDDEN_ENV_ACCESS in rendered {rel_path}")

        try:
            json.loads(rendered_text)
        except json.JSONDecodeError as err:
            raise ValueError(f"Invalid JSON produced in rendered output {rel_path}: {err}")

        dest_file.write_text(rendered_text, encoding="utf-8")
        rendered_hashes[rel_path] = sha256_file(dest_file)

    # Copy manifest to output dir
    shutil.copy2(src_dir / "manifest.json", out_dir / "manifest.json")

    # Assert total replacements exactly matches expected
    if total_replacements_done != TOTAL_EXPECTED_REPLACEMENTS:
        raise ValueError(
            f"TOTAL_REPLACEMENT_MISMATCH: expected {TOTAL_EXPECTED_REPLACEMENTS}, performed {total_replacements_done}"
        )

    # Verify source templates were NOT modified during render
    for rel_path, hash_before in source_hashes_before.items():
        current_hash = sha256_file(src_dir / rel_path)
        if current_hash != hash_before:
            raise RuntimeError(f"SOURCE_MODIFIED_DURING_RENDER: {rel_path} hash changed during execution")

    return {
        "status": "PASS",
        "total_workflows_rendered": len(workflow_entries),
        "total_replacements_performed": total_replacements_done,
        "output_directory": str(out_dir),
        "source_hashes": source_hashes_before,
        "rendered_hashes": rendered_hashes
    }


def main():
    try:
        drive_id = load_drive_root_config()
        result = render_workflows(drive_id)
        print(f"RENDER WORKFLOWS: PASS (Rendered {result['total_workflows_rendered']} workflows, {result['total_replacements_performed']} placeholder substitutions)")
        return 0
    except Exception as err:
        print(f"RENDER WORKFLOWS: FAIL ({err})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
