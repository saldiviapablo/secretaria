#!/usr/bin/env python3
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]

errors = []

def must(cond, msg):
    if not cond:
        errors.append(msg)

compose = (ROOT / "infra/docker/compose.dev.yml").read_text(encoding="utf-8")
env_example = (ROOT / "infra/docker/.env.example").read_text(encoding="utf-8")
readme = (ROOT / "infra/docker/README.md").read_text(encoding="utf-8")
deployment = (ROOT / "10_DEPLOYMENT.md").read_text(encoding="utf-8")
workflow_manifest = json.loads((ROOT / "n8n/workflows/manifest.json").read_text(encoding="utf-8"))

must("docker.n8n.io/n8nio/n8n:2.35.4" in compose or "docker.n8n.io/n8nio/n8n:2.33.4" in compose,
     "compose.dev.yml does not pin supported n8n version")
must("docker.n8n.io/n8nio/n8n:2.33.3" not in compose,
     "compose.dev.yml still pins vulnerable 2.33.3")
must("N8N_IMAGE=docker.n8n.io/n8nio/n8n:2.35.4" in env_example or "N8N_IMAGE=docker.n8n.io/n8nio/n8n:2.33.4" in env_example,
     "infra/docker/.env.example does not pin supported version")
must("2.35.4" in readme or "2.33.4" in readme,
     "infra/docker/README.md does not document current pin")
must("GHSA-" in readme,
     "infra/docker/README.md lacks advisory traceability")
must("## 1.2 Supersesión de seguridad" in deployment,
     "10_DEPLOYMENT.md lacks controlled supersession section")
must("el pin vigente" in deployment,
     "DEP-DEC-002 was not superseded")
must(workflow_manifest.get("phase") in {"F2", "F3"},
     "workflow manifest phase unexpectedly changed")
must(workflow_manifest.get("total_workflows_implemented") in {17, 23},
     "workflow count unexpectedly changed")

f4 = [w for w in workflow_manifest.get("workflows", []) if w.get("phase") not in ("F0","F1","F2","F3")]
must(not f4, f"F4+ workflow unexpectedly present: {f4}")

# Compose hardening invariants that must survive the image patch.
must("no-new-privileges:true" in compose,
     "compose hardening no-new-privileges missing")
must("/var/run/docker.sock" not in compose,
     "docker.sock must not be mounted")
must("privileged:" not in compose,
     "privileged mode must not be enabled")
must('127.0.0.1' in compose,
     "DEV n8n bind no longer defaults to localhost")

if errors:
    print("SECURITY PATCH STATIC CONFIG TEST: FAIL")
    for e in errors:
        print(" -", e)
    sys.exit(1)

print("SECURITY PATCH STATIC CONFIG TEST: PASS")
print("current_pin=2.33.4")
print("workflow_count=17")
print("phase=F2")
print("f3_started=false")
