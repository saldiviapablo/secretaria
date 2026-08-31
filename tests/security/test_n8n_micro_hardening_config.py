#!/usr/bin/env python3
from pathlib import Path
import json, sys

ROOT = Path(__file__).resolve().parents[2]
errors = []
def must(cond, msg):
    if not cond:
        errors.append(msg)

compose = (ROOT/"infra/docker/compose.dev.yml").read_text(encoding="utf-8")
envex = (ROOT/"infra/docker/.env.example").read_text(encoding="utf-8")
readme = (ROOT/"infra/docker/README.md").read_text(encoding="utf-8")
deployment = (ROOT/"10_DEPLOYMENT.md").read_text(encoding="utf-8")
wf = json.loads((ROOT/"n8n/workflows/manifest.json").read_text(encoding="utf-8"))

for x in [
    "N8N_PUBLIC_API_DISABLED=${N8N_PUBLIC_API_DISABLED:-true}",
    "N8N_PUBLIC_API_SWAGGERUI_DISABLED=${N8N_PUBLIC_API_SWAGGERUI_DISABLED:-true}",
    "N8N_COMMUNITY_PACKAGES_ENABLED=${N8N_COMMUNITY_PACKAGES_ENABLED:-false}",
]:
    must(x in compose, f"compose missing {x}")

for x in [
    "N8N_PUBLIC_API_DISABLED=true",
    "N8N_PUBLIC_API_SWAGGERUI_DISABLED=true",
    "N8N_COMMUNITY_PACKAGES_ENABLED=false",
]:
    must(x in envex, f".env.example missing {x}")
    must(x in readme, f"README missing {x}")
    must(x in deployment, f"10_DEPLOYMENT missing {x}")

must("docker.n8n.io/n8nio/n8n:2.33.4" in compose, "n8n pin drift")
must("no-new-privileges:true" in compose, "no-new-privileges missing")
must("/var/run/docker.sock" not in compose, "docker.sock mounted")
must("privileged:" not in compose, "privileged mode enabled")
must(wf.get("phase") == "F2", "phase drift")
must(wf.get("total_workflows_implemented") == 17, "workflow count drift")
must(all(w.get("phase") in {"F0","F1","F2"} for w in wf.get("workflows", [])), "F3+ detected")

if errors:
    print("N8N MICRO-HARDENING STATIC TEST: FAIL")
    for e in errors:
        print(" -", e)
    sys.exit(1)

print("N8N MICRO-HARDENING STATIC TEST: PASS")
print("n8n_pin=2.33.4")
print("public_api_disabled=true")
print("swagger_ui_disabled=true")
print("community_packages_enabled=false")
print("workflow_count=17")
print("phase=F2")
print("f3_started=false")
