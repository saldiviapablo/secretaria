# AUDITORÍA INTEGRAL DE DATAFLOW Y FIELD-LINEAGE F3

**Base:** main @ 86fad8b  
**Runtime:** n8n 2.35.4 (Node.js runtime, binary filesystem mode)  
**PostgreSQL:** 127.0.0.1:54322 (Supabase CLI, 25 tablas V1)

---

## 1. RASTREO EXTREMO A EXTREMO DE CAMPOS CANÓNICOS

| Campo | Origen de Autoridad | Preservación a través de Transformaciones | Destino de Persistencia |
| :--- | :--- | :--- | :--- |
| `contract_version` | Ingestion trigger ('1.0') | Preservado en JSON context de cada nodo Code | Metadata RPC / JSONB |
| `correlation_id` | Channel entry checkpoint (`corr_*`) | Inmutable en todo el flujo | `ingestions.correlation_id`, `audit_events` |
| `user_id` | Auth context / `user_settings` | Inmutable | Clave foránea en todas las tablas |
| `ingestion_id` | `register_ingestion` RPC (UUID) | Preservado explícitamente post-registro | Primary key en `ingestions` |
| `source_channel` | Gateway / Trigger ('telegram', 'google_drive') | Validado sin defaults inventados | `ingestions.source_channel`, `asset_locations` |
| `idempotency_key` | Channel unique event key | Preservado sin mutaciones | `ingestions.idempotency_key`, `asset_locations` |
| `captured_at` | Metadata del evento | Timestamptz auditado | `ingestions.captured_at` |
| `timezone` | `user_settings.timezone` / Profile | Preservado | Configuración de usuario |
| `locale` | Configuración de usuario | Preservado | `es-AR` |
| `payload` | Metadata del mensaje/archivo | Objeto normalizado | `ingestions.raw_payload` |
| `media_kind` | MIME / Channel detection ('audio', 'image', 'document') | Validado en `Validate / Gate Media` | `assets.media_kind` |
| `mime_type` | Encabezado binario / Channel metadata | Strict whitelist, sin fallback inventado | `assets.mime_type` |
| `file_size` | Longitud real del buffer (`buffer.length`) | Número exacto de bytes | `assets.file_size_bytes` |
| `binary.data` | Downloaded stream | Preservado intacto vía `getBinaryDataBuffer` | Stream transitorio hacia almacenamiento/IA |
| `sha256` | Hash crypto de `buffer` (hex 64 chars) | Calculado en nodo Code preservando binario | `assets.sha256` |
| `asset_id` | `upsert_asset_with_location` RPC | UUID retornado y adherido al payload | `assets.id`, `source_texts.asset_id` |
| `location_id` | `upsert_asset_with_location` RPC | UUID de ubicación primaria | `asset_locations.id` |
| `source_text_id` | `create_source_text_variant` RPC | UUID retornado por subworkflow child | `source_texts.id` |
| `provider` | Model registry (`config/ai_models.json`) | Validado en gate | `source_texts.provider`, `ai_usage_events` |
| `model` | Model registry (`config/ai_models.json`) | Validado en gate | `source_texts.model`, `ai_usage_events` |

---

## 2. AUDITORÍA NODO POR NODO DE LOS 6 WORKFLOWS F3

### 2.1 WF-ING-003_PROCESS_MEDIA
1. `Execute Workflow Trigger`: Recibe envelope canónico y opcionalmente binary.data.
2. `Validate / Gate Media`: Clasifica `media_gate` ('download', 'awaiting_external_file', 'quarantine') y `media_route` ('transcribe', 'visual', 'document', 'unsupported').
3. `Persist Processing / Fallback Status`: Invoca `public.set_ingestion_media_status`.
4. `Gate and Source Router`: Bifurca según gate y source ('telegram' vs 'google_drive').
5. `Telegram Get File`: Descarga el archivo de Telegram.
6. `Restore Telegram Media Context`: Reconstruye el envelope canónico vinculando metadatos y binario descargado.
7. `Compute SHA-256 Preserving Binary`: Calcula hash SHA-256 usando `getBinaryDataBuffer(0, 'data')` sin perder el stream binario.
8. `Branch Source for Archive`:
   - Si origen es Telegram: Ejecuta `Archive Telegram Original in Drive` -> `Upsert Telegram Location` -> `Upsert Drive Location` (1 asset, 2 locations).
   - Si origen es Google Drive: No re-sube el archivo a Drive -> `Upsert Drive Location` (1 asset, 1 location).
9. `Media Type Router`:
   - `transcribe` -> `WF-AI-001 TRANSCRIBE`
   - `visual` -> `WF-AI-003 ANALYZE_VISUAL`
   - `document` -> `WF-ING-006 DOCUMENT_EXTRACT`
   - `unsupported` -> `Persist Unsupported Media Terminal Status` (error sanitizado 'UNSUPPORTED_MEDIA_TYPE').
10. `Verify Child Persistence`: Valida que el child retornó `ok: true`, `status: 'completed'`, `source_text_id`, `asset_id`, `ingestion_id`.
11. `Persist Completed Media Status`: Marca `ingestions.status = 'completed'` únicamente tras persistencia confirmada.

### 2.2 WF-ING-004_DRIVE_WATCH
1. `Drive Trigger — Created / Updated`: Recibe evento de Google Drive.
2. `Normalize Drive Metadata`: Extrae `id`, `modifiedTime`, `mimeType`, `size`.
3. `Resolve V1 Owner`: Consulta `user_settings` (valida usuario único V1).
4. `Merge Context and Enforce Single Owner`: Construye envelope canónico.
5. `Register Drive Ingestion`: Invoca `public.register_ingestion`.
6. `Check Ingestion Duplicate`: Evalúa `is_duplicate`.
7. `Branch Duplicate vs New`:
   - Si `is_duplicate`: Rama terminal no-op (0 descargas adicionales, 0 side effects).
   - Si `new`: Descarga archivo -> Invoca `WF-ING-003_PROCESS_MEDIA`.

### 2.3 WF-ING-005_DRIVE_RECONCILIATION
1. `Schedule 15 Minutes`: Disparo recurrente.
2. `Validate Single V1 Owner`: Valida usuario configurado.
3. `List Root Files`: Lista archivos en la carpeta raíz.
4. `Query Existing Asset Locations`: Consulta `asset_locations` para comparar claves `drive:<id>:<version>`.
5. `Filter Unindexed or Modified Files`: Produce lista de candidatos no indexados.
6. `Register Reconciled Ingestion`: Registra ingesta en Postgres por candidato.
7. `Restore Reconciled Candidate Context`: Mapea la respuesta Postgres con el contexto del candidato correspondiente sin cruces entre ítems (`.first()` eliminado).
8. `Branch Reconciled Duplicate vs New`: Descarga e invoca `WF-ING-003` únicamente para candidatos nuevos.

### 2.4 WF-ING-006_DOCUMENT_EXTRACT
1. `Document Safety Gate`: Cuarentena estricta para ejecutables y documentos con macros (`.docm`, `.xlsm`, etc.).
2. `Document Format Router`: Rutea a la operación nativa de `ExtractFromFile` 1.1 (`pdf`, `text`, `csv`, `json`, `xml`, `html`, `ods`, `xls`, `xlsx`, `rtf`).
   - Para `.docx`: Se preserva el archivo original y se registra `CONTROLLED_REVIEW_REQUIRED_DOCX_EXTRACTION`.
3. `Normalize Extracted Text`: Extrae texto no vacío; rechaza extracciones fallidas sin convertirlas en éxitos vacíos.
4. `Persist Literal Extraction`: Invoca `public.create_source_text_variant` con `UNTRUSTED_CONTENT`.

### 2.5 WF-AI-001_TRANSCRIBE
1. `Validate Transcription Contract`: Valida provider y modelo permitido (`gpt-transcribe`, `gemini-3.5-transcribe`).
2. `Provider Router`:
   - OpenAI: `OpenAI GPT-Transcribe` (multipart/form-data con stream binario real).
   - Gemini:
     a. `Validate Gemini Binary Metadata`: Acceso a buffer real (`getBinaryDataBuffer`), validación estricta de MIME en whitelist oficial de Gemini, longitud numérica exacta.
     b. `Gemini Files API Start`: Inicia sesión resumable (`X-Goog-Upload-Protocol: resumable`).
     c. `Extract Upload Session URL`: Restaura binario original desde el checkpoint previo.
     d. `Gemini Files API Upload Finalize`: Envía stream binario puro (`contentType: binaryData`, `retryOnFail: false`).
     e. `Gemini Transcribe Interaction`: Envía `interactions` con `language_codes: []` (autodetección) y `mode: { type: "verbatim" }` (`retryOnFail: false`).
3. `Normalize Transcription Output`: Captura idioma real detectado o `NULL` (sin hardcodear 'es-AR').
4. `Persist Literal Transcription` & `Record Transcription AI Usage`.
5. `Format Final Transcription`: Retorna envelope con `source_text_id`, `asset_id`, `ingestion_id`.

### 2.6 WF-AI-003_ANALYZE_VISUAL
1. `Validate Visual Contract + Untrusted Boundary`: Define instrucción segura.
2. `Validate and Prepare Visual Binary`: Accede a `getBinaryDataBuffer`, valida MIME de imagen (`image/jpeg`, `image/png`, `image/webp`, `image/heic`, `image/gif`), prepara base64 transitorio para inference.
3. `Vision Provider Router`: OpenAI (`gpt-5.6-luna`) / Gemini (`gemini-3.7-flash`).
4. `Normalize Vision Output`: Normaliza texto e idioma (`NULL` si no hay texto/idioma específico).
5. `Persist Visual Source Text` & `Record Visual AI Usage`.
6. `Format Visual Output`: Retorna envelope con `source_text_id`.
