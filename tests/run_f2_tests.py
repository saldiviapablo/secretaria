#!/usr/bin/env python3
"""
F2 targeted runner — Secretaria Virtual con IA.
No fabricated PASS: every subprocess must exit 0.
"""
import subprocess
import sys
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "tests" / "evidence"
EVIDENCE.mkdir(parents=True, exist_ok=True)

def run(name, cmd):
    print("\n" + "=" * 72)
    print(name)
    print("$ " + " ".join(cmd))
    p = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    print(p.stdout)
    if p.stderr:
        print(p.stderr, file=sys.stderr)
    if p.returncode != 0:
        raise SystemExit(f"{name}: FAIL (exit={p.returncode})")
    return p.stdout

def main():
    started = datetime.now(timezone.utc).isoformat()
    wf = run("F2 workflow manifest/graph validation",
             ["node", "tests/workflows/test_workflow_import.js"])
    f2 = run("F2 reminder DB/integration/resilience suite",
             ["node", "tests/integration/test_f2_reminders.js"])
    f1 = run("F1 targeted regression after F2 integration",
             ["node", "tests/integration/test_f1_e2e.js"])

    (EVIDENCE / "f2_workflow_validation.txt").write_text(wf, encoding="utf-8")
    (EVIDENCE / "f2_reminders_runtime.txt").write_text(f2, encoding="utf-8")
    (EVIDENCE / "f2_f1_regression.txt").write_text(f1, encoding="utf-8")

    print("\n" + "=" * 72)
    print("F2 TARGETED RUNNER: PASS")
    print("started_at=" + started)
    print("finished_at=" + datetime.now(timezone.utc).isoformat())
    print("=" * 72)

if __name__ == "__main__":
    main()
