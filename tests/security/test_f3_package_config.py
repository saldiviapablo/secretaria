from pathlib import Path
import json,re,sys

ROOT=Path(__file__).resolve().parents[2]
assert (ROOT/"supabase/migrations/20260831000013_f3_media_drive_runtime.sql").exists()
sql=(ROOT/"supabase/migrations/20260831000013_f3_media_drive_runtime.sql").read_text(encoding="utf-8")
assert not re.search(r"\bcreate\s+table\b",sql,re.I), "F3 migration must not create product tables"
for fn in ["set_ingestion_media_status","upsert_asset_with_location","create_source_text_variant","record_media_ai_usage"]:
    assert f"FUNCTION public.{fn}" in sql
assert "SET search_path = ''" in sql
assert "TO service_role" in sql
assert "FROM PUBLIC, anon, authenticated" in sql
assert "ON CONFLICT (user_id,location_type,external_id)" in sql
assert "versioned external_id" in sql
assert "source_texts" in sql

wfroot=ROOT/"n8n/workflows"
m=json.loads((wfroot/"manifest.json").read_text(encoding="utf-8"))
assert m["phase"]=="F3" and m["total_workflows_implemented"]==23
expected={"WF-ING-003","WF-ING-004","WF-ING-005","WF-AI-001","WF-ING-006","WF-AI-003"}
assert {x["workflow_id"] for x in m["workflows"] if x["phase"]=="F3"}==expected

tg=json.loads((wfroot/"telegram/WF-TG-001_TELEGRAM_INBOUND.json").read_text(encoding="utf-8"))
tgtext=json.dumps(tg)
assert "Date.now() % 1000000000" not in tgtext
assert "TELEGRAM_UPDATE_ID_REQUIRED" in tgtext
assert "telegram_chat_id" in tgtext and "telegram_user_id" in tgtext
assert "process_media" in tgtext

alltxt="\n".join((wfroot/e["file"]).read_text(encoding="utf-8") for e in m["workflows"] if e["phase"]=="F3")
assert "__SVIA_DRIVE_ROOT_FOLDER_ID__" in alltxt
assert "$env.SVIA_DRIVE_ROOT_FOLDER_ID_DEV" not in alltxt
assert "SVIA_DRIVE_ROOT_FOLDER_ID_DEV__REQUIRED_BINDING" not in alltxt
assert "gemini-3.5-transcribe" in alltxt
assert "gpt-transcribe" in alltxt
assert "gpt-5.6-luna" in alltxt or "gemini-3.7-flash" in alltxt
assert "GEMINI_3_5_TRANSCRIBE_RUNTIME_ADAPTER_BINDING_REQUIRED" not in alltxt
assert "VISION_RUNTIME_PROVIDER_ADAPTER_BINDING_REQUIRED" not in alltxt

models=json.loads((ROOT/"config/ai_models.json").read_text(encoding="utf-8"))
assert models["routing"]["transcription_primary"] is None
assert [x["model"] for x in models["routing"]["transcription_candidates"]]==["gpt-transcribe","gemini-3.5-transcribe"]

for forbidden in ["OPENAI_API_KEY=", "GEMINI_API_KEY=", "TELEGRAM_BOT_TOKEN=", "SUPABASE_SERVICE_ROLE_KEY=", "N8N_ENCRYPTION_KEY="]:
    assert forbidden not in alltxt and forbidden not in sql

print("F3 PACKAGE CONFIG/SECURITY: PASS")
