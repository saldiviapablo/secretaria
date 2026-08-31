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

must("docker.n8n.io/n8nio/n8n:2.35.4" in compose, "compose does not pin 2.35.4")
must("docker.n8n.io/n8nio/n8n:2.33.4" not in compose, "compose still pins 2.33.4")
must("N8N_IMAGE=docker.n8n.io/n8nio/n8n:2.35.4" in envex, ".env.example does not pin 2.35.4")
must("2.35.4" in readme, "infra README does not document 2.35.4")
must("## 1.3 Segunda supersesión de seguridad aprobada — 2026-08-31" in deployment,
     "10_DEPLOYMENT missing 1.3 controlled supersession")
must('"n8n_image": "docker.n8n.io/n8nio/n8n:2.35.4"' in deployment,
     "deployment manifest example not updated")
must("el pin vigente candidato queda en `2.35.4`" in deployment,
     "DEP-DEC-002 not updated to candidate pin 2.35.4")
must("- [ ] n8n 2.35.4 pinneado;" in deployment,
     "deployment checklist not updated")
must("GHSA-9x83-43r8-5hwc" in deployment,
     "security advisory traceability missing")
must("fresh advisory gate" in deployment.lower(),
     "fresh advisory gate missing")

for hardening in [
    "N8N_PUBLIC_API_DISABLED=${N8N_PUBLIC_API_DISABLED:-true}",
    "N8N_PUBLIC_API_SWAGGERUI_DISABLED=${N8N_PUBLIC_API_SWAGGERUI_DISABLED:-true}",
    "N8N_COMMUNITY_PACKAGES_ENABLED=${N8N_COMMUNITY_PACKAGES_ENABLED:-false}",
]:
    must(hardening in compose, f"hardening lost: {hardening}")

must("no-new-privileges:true" in compose, "no-new-privileges lost")
must("/var/run/docker.sock" not in compose, "docker.sock must not be mounted")
must(wf.get("phase") in {"F2", "F3"}, "workflow phase changed")
must(wf.get("total_workflows_implemented") in {17, 23}, "workflow count changed")
must(all(w.get("phase") in {"F0","F1","F2","F3"} for w in wf.get("workflows", [])),
     "F4+ workflow detected")

if errors:
    print("N8N 2.35.4 SECURITY PATCH STATIC TEST: FAIL")
    for e in errors:
        print(" -", e)
    sys.exit(1)

print("N8N 2.35.4 SECURITY PATCH STATIC TEST: PASS")
print("target_pin=2.35.4")
print(f"workflow_count={wf.get('total_workflows_implemented')}")
print(f"phase={wf.get('phase')}")
print("hardening_preserved=true")
print("f3_started=false")
