# DATABASE SCHEMA — Secretaria Virtual con IA

**Proyecto:** Secretaria Virtual con IA  
**Repositorio previsto:** `saldiviapablo/secretaria`  
**Documento:** `04_DATABASE_SCHEMA.md`  
**Versión:** 1.0-candidate — AUDITADA  
**Fecha:** 2026-08-29  
**Estado:** Construido, auditado y validado contra `01_PRD.md`, `02_SRS.md` y `03_ARQUITECTURA.md`  
**Motor:** Supabase / PostgreSQL  
**Documentos fuente:** `01_PRD.md`, `02_SRS.md`, `03_ARQUITECTURA.md`

---

# 0. Resultado de construcción y auditoría

Este documento fue construido y auditado antes de su entrega.

La auditoría verificó específicamente:

- presencia de las 22 entidades lógicas obligatorias del SRS;
- soporte para identidad e historial de nombres;
- soporte para relaciones múltiples entre tareas y personas/proyectos;
- medición de consumo/costo de IA;
- memoria permanente y correcciones no destructivas;
- trazabilidad `original → texto/transcripción → interpretación → acción`;
- versionado de mensajes editados y transcripciones A/B;
- deduplicación por idempotencia y SHA-256;
- fechas sin inventar horas;
- hechos con vigencia temporal;
- recordatorios persistentes y reintentos seguros;
- bloqueo de `DELETE` físico sobre memoria histórica;
- búsqueda textual, fuzzy y semántica;
- embeddings desacoplados del contenido;
- RLS preparada para multiusuario;
- funciones/RPC controladas;
- auditoría append-only;
- recuperación del original y verificación de integridad;
- reportes trazables y documentos generados como assets;
- separación de datos estructurados y JSONB;
- compatibilidad con las decisiones congeladas de arquitectura;
- ausencia de una dimensión de embeddings elegida prematuramente.

## 0.1 Tablas obligatorias preservadas

Las 22 tablas lógicas exigidas por el SRS se mantienen:

1. `profiles`
2. `user_settings`
3. `ingestions`
4. `memory_items`
5. `memory_relations`
6. `assets`
7. `asset_locations`
8. `memory_asset_links`
9. `source_texts`
10. `memory_chunks`
11. `embeddings`
12. `interpretations`
13. `entities`
14. `entity_aliases`
15. `memory_entity_links`
16. `facts`
17. `tasks`
18. `reminders`
19. `notification_deliveries`
20. `pending_clarifications`
21. `reports`
22. `audit_log`

## 0.2 Tablas auxiliares justificadas

Se agregan tres tablas auxiliares porque resuelven requisitos que no deberían esconderse en JSONB ni depender solamente de logs:

23. `assistant_name_history`  
    Historial consultable del nombre de la secretaria.

24. `task_entity_links`  
    Relación N:N entre tareas y personas/proyectos/organizaciones.

25. `ai_usage_events`  
    Telemetría de proveedor, modelo, unidades de uso y costo estimado.

Por lo tanto, **DATABASE_SCHEMA_V1 contiene 25 tablas de producto**.

Esto es compatible con `DB-012`, que permite tablas auxiliares justificadas sin eliminar las responsabilidades de las 22 entidades obligatorias.

---

# 1. Principios de diseño

## DB-DESIGN-001 — Supabase es la fuente de verdad

El estado del producto vive en PostgreSQL/Supabase.

n8n orquesta, pero no será el repositorio permanente.

## DB-DESIGN-002 — Original ≠ interpretación ≠ acción

La base debe permitir reconstruir:

```text
ingestion
   ↓
asset / source_text
   ↓
interpretation
   ↓
memory_item
   ↓
fact / task / reminder
```

Ninguna capa deberá sobrescribir silenciosamente a la anterior.

## DB-DESIGN-003 — Sin borrado histórico normal

Telegram, MCP y workflows operativos no deberán borrar físicamente memoria histórica.

Se utilizarán estados como:

```text
active
historical
superseded
invalid
archived
cancelled
```

## DB-DESIGN-004 — UUID

Las entidades de producto utilizarán:

```sql
uuid default gen_random_uuid()
```

como identificador principal, salvo que una estructura técnica requiera otra cosa.

## DB-DESIGN-005 — Tiempo

Los instantes absolutos se almacenarán como:

```sql
timestamptz
```

Las fechas sin hora se almacenarán como:

```sql
date
```

Las horas conocidas sin fecha se almacenarán como:

```sql
time
```

Nunca se utilizará `00:00` para representar “hora desconocida”.

## DB-DESIGN-006 — user_id

Toda tabla que contenga datos del usuario deberá incluir `user_id`.

## DB-DESIGN-007 — JSONB limitado

JSONB se utilizará solo para:

- metadata variable de proveedores;
- salidas crudas/estructuradas de IA;
- contexto flexible de clarificaciones;
- filtros de reportes;
- snapshots de auditoría;
- respuestas técnicas de canales.

No se utilizará JSONB para reemplazar tareas, fechas, estados, entidades, relaciones o hechos que necesitan consultas e integridad.

## DB-DESIGN-008 — Datos derivados regenerables

Embeddings y otros artefactos puramente derivados podrán regenerarse.

Los originales, textos fuente, hechos históricos y auditoría no se consideran caches.

## DB-DESIGN-009 — Restrict antes que Cascade

Las relaciones de memoria utilizarán por defecto:

```sql
ON DELETE RESTRICT
```

La arquitectura no dependerá de cascadas destructivas.

## DB-DESIGN-010 — Migraciones

Todo cambio de esquema deberá existir como migración versionada en GitHub.

No se considerará válido un cambio realizado solo manualmente en el Dashboard.

---

# 2. Schemas PostgreSQL

Se utilizarán al menos:

```text
auth
public
private
```

## `auth`

Administrado por Supabase Auth.

## `public`

Contendrá las tablas y las RPC que deban estar disponibles a través de la capa de datos de Supabase.

Todas las tablas de usuario expuestas deberán tener RLS.

## `private`

No deberá exponerse mediante la Data API.

Contendrá funciones internas como:

- auditoría;
- normalización;
- protección contra DELETE;
- sincronización de timestamps;
- helpers internos;
- funciones administrativas.

---

# 3. Extensiones

Migración inicial recomendada:

```sql
create extension if not exists pgcrypto;
create extension if not exists vector;
create extension if not exists pg_trgm;
create extension if not exists unaccent;
```

## Razón

### `pgcrypto`

Permite `gen_random_uuid()` y funciones criptográficas útiles.

### `vector`

Implementa `pgvector` para embeddings.

### `pg_trgm`

Permite búsquedas aproximadas útiles para:

- nombres;
- alias;
- errores ortográficos;
- transcripciones imperfectas.

### `unaccent`

Ayuda a normalizar búsquedas:

```text
Pérez
Perez
```

sin convertir ambos nombres en la misma entidad automáticamente.

La normalización mejora búsqueda; **no elimina la regla de ambigüedad**.

---

# 4. Convenciones

## 4.1 Nombres

- tablas: plural `snake_case`;
- columnas: `snake_case`;
- PK: `id`;
- FK: `<entidad>_id`;
- timestamps: sufijo `_at`;
- fechas sin hora: sufijo `_date`;
- valores booleanos: prefijo `is_`, `has_`, `can_` o nombre descriptivo.

## 4.2 Columnas comunes

Cuando corresponda:

```text
id          uuid
user_id     uuid
created_at  timestamptz
updated_at  timestamptz
```

## 4.3 Estados

Para V1 se prefieren columnas `text` con `CHECK` en lugar de PostgreSQL ENUM.

Razón:

- los estados todavía pueden evolucionar;
- agregar/modificar valores es más simple mediante migraciones;
- evita acoplar demasiado temprano el esquema a enums difíciles de retirar.

---

# 5. Diagrama lógico resumido

```text
auth.users
    │
    ▼
profiles ─────────── user_settings
    │                    │
    │                    └── assistant_name_history
    │
    ├── ingestions ─────────────┐
    │       │                   │
    │       ├── assets          │
    │       │    └── asset_locations
    │       │
    │       ├── source_texts
    │       │      └── memory_chunks ─── embeddings
    │       │
    │       └── interpretations
    │
    ├── memory_items
    │      ├── memory_relations
    │      ├── memory_asset_links ── assets
    │      ├── memory_entity_links ─ entities
    │      ├── facts
    │      └── reports
    │
    ├── entities
    │      └── entity_aliases
    │
    ├── tasks
    │      ├── task_entity_links ── entities
    │      └── reminders
    │             └── notification_deliveries
    │
    ├── pending_clarifications
    ├── ai_usage_events
    └── audit_log
```

---

# 6. Tabla `profiles`

## Propósito

Representa al propietario lógico de los datos.

V1 tendrá un usuario operativo, pero esta tabla prepara el aislamiento multiusuario.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK y FK a `auth.users(id)` |
| `display_name` | `text` | SÍ | Nombre descriptivo del usuario |
| `language` | `text` | NO | Default `es` |
| `locale` | `text` | NO | Default `es-AR` |
| `timezone` | `text` | NO | Default inicial `America/Argentina/Buenos_Aires` |
| `status` | `text` | NO | `active`, `disabled` |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | mantenido por trigger |

## Constraints

```sql
primary key (id)

foreign key (id)
references auth.users(id)
on delete restrict

check (status in ('active', 'disabled'))
```

La zona horaria deberá validarse contra una zona IANA válida antes de guardarse.

---

# 7. Tabla `user_settings`

## Propósito

Configuración vigente de la secretaria.

Hay una fila por usuario.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `user_id` | `uuid` | NO | PK + FK `profiles` |
| `assistant_name` | `text` | SÍ | Null antes del onboarding |
| `assistant_name_source_ingestion_id` | `uuid` | SÍ | Entrada que originó el último cambio de nombre |
| `authorized_telegram_user_id` | `bigint` | SÍ | Usuario Telegram permitido |
| `authorized_telegram_chat_id` | `bigint` | SÍ | Chat Telegram permitido |
| `morning_brief_enabled` | `boolean` | NO | default `true` |
| `morning_brief_time` | `time` | SÍ | Hora configurable |
| `evening_brief_enabled` | `boolean` | NO | default `false` |
| `evening_brief_time` | `time` | SÍ | Hora configurable |
| `quiet_hours_enabled` | `boolean` | NO | default `false` |
| `quiet_start_time` | `time` | SÍ | Inicio silencio |
| `quiet_end_time` | `time` | SÍ | Fin silencio |
| `rest_mode_enabled` | `boolean` | NO | default `false` |
| `rest_started_at` | `timestamptz` | SÍ | Inicio temporal |
| `rest_until` | `timestamptz` | SÍ | Fin temporal |
| `default_reminder_minutes_before` | `integer` | NO | default `180` |
| `critical_can_break_silence` | `boolean` | NO | default `false` |
| `notification_preferences` | `jsonb` | NO | default `{}` |
| `monthly_ai_budget_usd` | `numeric(12,2)` | SÍ | futuro límite/alerta |
| `monthly_ai_alert_pct` | `numeric(5,2)` | SÍ | 0–100 |
| `last_modified_source` | `text` | SÍ | `telegram`, `mcp`, `system`, etc. |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | trigger |

## Constraints

```sql
primary key (user_id)

foreign key (user_id)
references public.profiles(id)
on delete restrict

check (default_reminder_minutes_before >= 0)

check (
  monthly_ai_alert_pct is null
  or (monthly_ai_alert_pct >= 0 and monthly_ai_alert_pct <= 100)
)

check (
  monthly_ai_budget_usd is null
  or monthly_ai_budget_usd >= 0
)
```

## Índices únicos parciales

```sql
create unique index ...
on public.user_settings (authorized_telegram_user_id)
where authorized_telegram_user_id is not null;

create unique index ...
on public.user_settings (authorized_telegram_chat_id)
where authorized_telegram_chat_id is not null;
```

Esto evita asociar accidentalmente la misma identidad autorizada de Telegram a dos perfiles.

---

# 8. Tabla `assistant_name_history`

## Propósito

Mantiene el historial consultable de nombres de la secretaria.

No dependeremos solo de `audit_log` para responder:

> “¿Cómo se llamaba antes?”

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK `profiles` |
| `assistant_name` | `text` | NO | Nombre utilizado |
| `valid_from` | `timestamptz` | NO | Inicio de vigencia |
| `valid_to` | `timestamptz` | SÍ | Null = actual |
| `change_source` | `text` | NO | onboarding/telegram/mcp/settings/system |
| `source_ingestion_id` | `uuid` | SÍ | Entrada que produjo cambio |
| `created_at` | `timestamptz` | NO | `now()` |

## Regla crítica

Solo puede existir un nombre vigente por usuario:

```sql
create unique index assistant_name_history_one_current
on public.assistant_name_history (user_id)
where valid_to is null;
```

## Constraint temporal

```sql
check (valid_to is null or valid_to >= valid_from)
```

---

# 9. Tabla `ingestions`

## Propósito

Registra cada evento de entrada y el estado de su procesamiento.

Es la base para:

- recuperación;
- reintentos;
- idempotencia;
- trazabilidad;
- fallback de archivos grandes.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK `profiles` |
| `source_channel` | `text` | NO | telegram, google_drive, chatgpt_mcp, web, external |
| `source_kind` | `text` | NO | text, audio, file, image, edit, etc. |
| `source_event_key` | `text` | SÍ | identificador externo normalizado |
| `telegram_update_id` | `bigint` | SÍ | update de Telegram |
| `telegram_message_id` | `bigint` | SÍ | mensaje de Telegram |
| `telegram_chat_id` | `bigint` | SÍ | chat de Telegram |
| `telegram_user_id` | `bigint` | SÍ | emisor Telegram |
| `telegram_file_id` | `text` | SÍ | archivo Telegram si existe |
| `drive_file_id` | `text` | SÍ | archivo de Google Drive si existe |
| `source_url` | `text` | SÍ | URL fuente si existe |
| `idempotency_key` | `text` | NO | clave única por usuario |
| `parent_ingestion_id` | `uuid` | SÍ | edición/fallback/continuación |
| `duplicate_of_ingestion_id` | `uuid` | SÍ | si es duplicado |
| `captured_at` | `timestamptz` | NO | fecha/hora real de la fuente |
| `received_at` | `timestamptz` | NO | default `now()` |
| `status` | `text` | NO | estado de pipeline |
| `retry_count` | `integer` | NO | default `0` |
| `next_retry_at` | `timestamptz` | SÍ | si corresponde |
| `processing_started_at` | `timestamptz` | SÍ | inicio |
| `completed_at` | `timestamptz` | SÍ | fin |
| `last_error_code` | `text` | SÍ | diagnóstico |
| `last_error_message` | `text` | SÍ | diagnóstico sin secretos |
| `source_metadata` | `jsonb` | NO | metadata filtrada, default `{}` |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | trigger |

## Estados

```text
received
processing
waiting_clarification
awaiting_external_file
completed
error
duplicate
```

## Constraints

```sql
unique (user_id, idempotency_key)

check (retry_count >= 0)

check (
  status <> 'duplicate'
  or duplicate_of_ingestion_id is not null
)

check (status in (
  'received',
  'processing',
  'waiting_clarification',
  'awaiting_external_file',
  'completed',
  'error',
  'duplicate'
))
```

`source_metadata` no deberá utilizarse como una copia indiscriminada del payload completo si contiene datos innecesarios.

---

# 10. Tabla `memory_items`

## Propósito

Unidad lógica de memoria interpretada.

Un `memory_item` no es necesariamente una tarea ni un archivo; representa un recuerdo consultable.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `ingestion_id` | `uuid` | SÍ | origen principal |
| `memory_type` | `text` | NO | tipo lógico |
| `title` | `text` | SÍ | título breve |
| `normalized_content` | `text` | SÍ | interpretación resumida/canónica |
| `status` | `text` | NO | active/superseded/invalid/archived |
| `importance` | `smallint` | SÍ | 0–100 |
| `event_date` | `date` | SÍ | fecha si se conoce |
| `event_time` | `time` | SÍ | hora si se conoce |
| `event_timezone` | `text` | SÍ | IANA |
| `event_at` | `timestamptz` | SÍ | instante absoluto si existe |
| `event_time_known` | `boolean` | NO | default `false` |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | trigger |

## Tipos iniciales

```text
note
conversation
event
decision
idea
document
image
web_capture
activity
task_context
fact_context
report
other
```

## Constraints

```sql
check (status in ('active', 'superseded', 'invalid', 'archived'))

check (importance is null or (importance >= 0 and importance <= 100))

check (
  (event_time_known = false and event_time is null and event_at is null)
  or
  (event_time_known = true and event_date is not null and event_time is not null)
)
```

`event_at` se calcula/valida usando `event_date + event_time + event_timezone`.

---

# 11. Tabla `memory_relations`

## Propósito

Relaciona memoria con memoria.

Ejemplos:

```text
continues
related_to
based_on
supersedes
contradicts
derived_from
same_project
report_uses
```

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `from_memory_id` | `uuid` | NO | FK |
| `to_memory_id` | `uuid` | NO | FK |
| `relation_type` | `text` | NO | relación |
| `confidence` | `numeric(5,4)` | SÍ | 0–1 |
| `created_by` | `text` | NO | user/ai/system |
| `interpretation_id` | `uuid` | SÍ | interpretación origen |
| `created_at` | `timestamptz` | NO | `now()` |

## Constraints

```sql
check (from_memory_id <> to_memory_id)

check (
  confidence is null
  or (confidence >= 0 and confidence <= 1)
)

unique (
  user_id,
  from_memory_id,
  to_memory_id,
  relation_type
)
```

---

# 12. Tabla `assets`

## Propósito

Representa un archivo lógico único.

Un mismo asset puede aparecer:

- en Telegram;
- en Drive;
- en un backup;
- como documento generado.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `first_ingestion_id` | `uuid` | SÍ | primera aparición |
| `sha256` | `text` | SÍ | hexadecimal 64 |
| `original_filename` | `text` | SÍ | nombre original |
| `mime_type` | `text` | SÍ | MIME |
| `media_kind` | `text` | NO | audio/image/pdf/document/spreadsheet/etc |
| `size_bytes` | `bigint` | SÍ | >= 0 |
| `duration_ms` | `bigint` | SÍ | audio/video |
| `integrity_status` | `text` | NO | unverified/verified/mismatch |
| `storage_status` | `text` | NO | available/missing/quarantined |
| `first_seen_at` | `timestamptz` | NO | `now()` |
| `created_at` | `timestamptz` | NO | `now()` |

## Constraints

```sql
check (
  sha256 is null
  or sha256 ~ '^[0-9a-f]{64}$'
)

check (size_bytes is null or size_bytes >= 0)

check (duration_ms is null or duration_ms >= 0)

check (integrity_status in ('unverified', 'verified', 'mismatch'))

check (storage_status in ('available', 'missing', 'quarantined'))
```

## Deduplicación

```sql
create unique index assets_user_sha256_unique
on public.assets (user_id, sha256)
where sha256 is not null;
```

Si el archivo cambia, cambia el hash y debe registrarse una nueva versión lógica/asset.

---

# 13. Tabla `asset_locations`

## Propósito

Registra dónde puede encontrarse un asset.

Separar asset de ubicación evita duplicar un archivo lógico que llegó por dos canales.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `asset_id` | `uuid` | NO | FK `assets` |
| `location_type` | `text` | NO | drive/telegram/nas_backup/generated/external |
| `external_id` | `text` | SÍ | ID normalizado |
| `drive_file_id` | `text` | SÍ | cuando aplica |
| `telegram_file_id` | `text` | SÍ | cuando aplica |
| `telegram_chat_id` | `bigint` | SÍ | cuando aplica |
| `telegram_message_id` | `bigint` | SÍ | cuando aplica |
| `path_hint` | `text` | SÍ | path descriptivo, no secreto |
| `is_primary` | `boolean` | NO | default `false` |
| `is_available` | `boolean` | NO | default `true` |
| `first_seen_at` | `timestamptz` | NO | `now()` |
| `last_verified_at` | `timestamptz` | SÍ | verificación |
| `metadata` | `jsonb` | NO | default `{}` |
| `updated_at` | `timestamptz` | NO | trigger |

## Constraints

```sql
check (location_type in (
  'drive',
  'telegram',
  'nas_backup',
  'generated',
  'external'
))
```

## Unicidad

```sql
create unique index asset_location_external_unique
on public.asset_locations (user_id, location_type, external_id)
where external_id is not null;
```

No se almacenarán URLs firmadas temporales como si fueran ubicaciones permanentes.

---

# 14. Tabla `memory_asset_links`

## Propósito

Relación N:N entre memoria y archivos.

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `memory_id` | `uuid` | NO |
| `asset_id` | `uuid` | NO |
| `role` | `text` | NO |
| `created_at` | `timestamptz` | NO |

## Roles iniciales

```text
original
attachment
evidence
generated_report
related
```

## Constraint

```sql
unique (user_id, memory_id, asset_id, role)
```

---

# 15. Tabla `source_texts`

## Propósito

Conserva texto literal extraído o recibido.

Ejemplos:

- mensaje de Telegram;
- edición de mensaje;
- transcripción A;
- transcripción B;
- OCR;
- extracción de PDF;
- texto de página web.

La columna literal no deberá sobrescribirse.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `ingestion_id` | `uuid` | SÍ | evento origen |
| `asset_id` | `uuid` | SÍ | archivo origen |
| `memory_id` | `uuid` | SÍ | memoria asociada |
| `source_type` | `text` | NO | tipo de texto |
| `source_key` | `text` | NO | agrupa versiones |
| `version_no` | `integer` | NO | >= 1 |
| `text_content` | `text` | NO | contenido literal |
| `language` | `text` | SÍ | idioma detectado |
| `provider` | `text` | SÍ | transcripción/OCR |
| `model` | `text` | SÍ | modelo |
| `prompt_version` | `text` | SÍ | si aplica |
| `is_preferred` | `boolean` | NO | default `false` |
| `supersedes_source_text_id` | `uuid` | SÍ | versión anterior |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | solo metadata/selección |

## Constraints

```sql
check (version_no >= 1)

check (
  ingestion_id is not null
  or asset_id is not null
  or memory_id is not null
)

unique (user_id, source_key, version_no)
```

## Una versión preferida por fuente lógica

```sql
create unique index source_text_one_preferred
on public.source_texts (user_id, source_key)
where is_preferred = true;
```

## Inmutabilidad

Un trigger deberá impedir cambiar:

```text
text_content
source_key
version_no
provider
model
```

después de la inserción.

Cambiar `is_preferred` sí estará permitido.

---

# 16. Tabla `memory_chunks`

## Propósito

Fragmentos citables/buscables de un texto fuente.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `memory_id` | `uuid` | NO | FK |
| `source_text_id` | `uuid` | NO | FK |
| `chunk_index` | `integer` | NO | >= 0 |
| `chunking_version` | `text` | NO | versión de estrategia |
| `text_content` | `text` | NO | fragmento |
| `char_start` | `integer` | SÍ | >= 0 |
| `char_end` | `integer` | SÍ | >= start |
| `start_ms` | `bigint` | SÍ | audio |
| `end_ms` | `bigint` | SÍ | audio |
| `token_count` | `integer` | SÍ | aproximado/real |
| `is_active` | `boolean` | NO | default `true` |
| `fts` | `tsvector` | NO | columna generada |
| `created_at` | `timestamptz` | NO | `now()` |

## Full Text Search

```sql
fts tsvector generated always as (
  to_tsvector('simple', coalesce(text_content, ''))
) stored
```

## Constraints

```sql
check (chunk_index >= 0)

check (char_start is null or char_start >= 0)

check (char_end is null or char_end >= char_start)

check (start_ms is null or start_ms >= 0)

check (end_ms is null or end_ms >= start_ms)

check (token_count is null or token_count >= 0)

unique (source_text_id, chunking_version, chunk_index)
```

## Índice

```sql
create index memory_chunks_fts_idx
on public.memory_chunks
using gin (fts);
```

Se utiliza la configuración `simple` para no fijar el esquema a un único idioma. La relevancia en español se complementará con búsqueda semántica/fuzzy y podrá añadirse una estrategia FTS específica por idioma si las pruebas lo justifican.

Si cambia la estrategia de chunking, se creará una nueva `chunking_version`; no se reescribirá silenciosamente la anterior.

---

# 17. Tabla `embeddings`

## Propósito

Almacena vectores derivados de `memory_chunks`.

Los embeddings están deliberadamente separados del chunk.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `chunk_id` | `uuid` | NO | FK |
| `provider` | `text` | NO | proveedor |
| `model` | `text` | NO | modelo |
| `model_version` | `text` | SÍ | versión |
| `dimensions` | `integer` | NO | > 0 |
| `distance_metric` | `text` | NO | inicialmente cosine |
| `embedding` | `vector` | NO | dimensión no fijada aún |
| `is_active` | `boolean` | NO | default `true` |
| `created_at` | `timestamptz` | NO | `now()` |

## Constraint

```sql
check (dimensions > 0)

check (distance_metric in ('cosine', 'l2', 'inner_product'))

unique (
  chunk_id,
  provider,
  model,
  coalesce(model_version, '')
)
```

La restricción de unicidad anterior se implementará mediante índice de expresión porque `coalesce()` no puede escribirse directamente como `UNIQUE` de tabla.

## Decisión importante: dimensión NO congelada

La columna será conceptualmente:

```sql
embedding vector
```

sin fijar `vector(1536)`, `vector(3072)` u otra dimensión hasta completar el benchmark de modelos.

Esto es intencional.

Una vez elegido el modelo en `06_AI_MODELS_AND_PROMPTS.md`, se creará un índice parcial específico para ese modelo/dimensión.

Ejemplo conceptual futuro:

```sql
create index embeddings_model_x_hnsw
on public.embeddings
using hnsw ((embedding::vector(<DIMENSION>)) vector_cosine_ops)
where provider = '<PROVIDER>'
  and model = '<MODEL>'
  and is_active = true;
```

No se reemplazará `<DIMENSION>` antes de decidir el modelo real.

Supabase/pgvector recomienda HNSW en general para datos que cambian con el tiempo; la decisión final del índice se validará con el volumen real.

---

# 18. Tabla `interpretations`

## Propósito

Registra cada interpretación de IA y permite reprocesar sin destruir resultados anteriores.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `ingestion_id` | `uuid` | SÍ | origen |
| `source_text_id` | `uuid` | SÍ | texto interpretado |
| `asset_id` | `uuid` | SÍ | asset visual/etc |
| `memory_id` | `uuid` | SÍ | memoria resultante/asociada |
| `purpose` | `text` | NO | task_extract/fact_extract/etc |
| `provider` | `text` | NO | proveedor |
| `model` | `text` | NO | modelo |
| `prompt_version` | `text` | NO | versión del prompt |
| `run_key` | `text` | SÍ | idempotencia de ejecución |
| `output_json` | `jsonb` | SÍ | salida estructurada |
| `output_text` | `text` | SÍ | salida textual |
| `confidence` | `numeric(5,4)` | SÍ | 0–1 |
| `status` | `text` | NO | proposed/validated/rejected/superseded/error |
| `validated_by` | `text` | SÍ | n8n/system/user |
| `validation_note` | `text` | SÍ | razón |
| `validated_at` | `timestamptz` | SÍ | fecha |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | trigger |

## Constraints

```sql
check (
  confidence is null
  or (confidence >= 0 and confidence <= 1)
)

check (status in (
  'proposed',
  'validated',
  'rejected',
  'superseded',
  'error'
))

check (
  ingestion_id is not null
  or source_text_id is not null
  or asset_id is not null
  or memory_id is not null
)
```

## Índice de idempotencia opcional

```sql
create unique index interpretations_run_key_unique
on public.interpretations (user_id, run_key)
where run_key is not null;
```

---

# 19. Tabla `entities`

## Propósito

Representa entidades reconocidas.

Tipos iniciales:

```text
person
organization
project
place
topic
other
```

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `entity_type` | `text` | NO | tipo |
| `canonical_name` | `text` | NO | nombre |
| `normalized_name` | `text` | NO | búsqueda |
| `description` | `text` | SÍ | descripción breve |
| `status` | `text` | NO | active/historical/merged/invalid |
| `merged_into_entity_id` | `uuid` | SÍ | entidad canónica |
| `source_memory_id` | `uuid` | SÍ | primera fuente |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | trigger |

## Regla crítica: nombres NO únicos

No habrá:

```sql
unique (user_id, normalized_name)
```

porque pueden existir dos personas llamadas Juan Pérez.

Esto preserva la regla de seguridad:

```text
dos candidatos reales
→ preguntar
```

## Constraints

```sql
check (entity_type in (
  'person',
  'organization',
  'project',
  'place',
  'topic',
  'other'
))

check (status in (
  'active',
  'historical',
  'merged',
  'invalid'
))

check (
  status <> 'merged'
  or merged_into_entity_id is not null
)
```

## Índices

```sql
create index entities_user_type_idx
on public.entities (user_id, entity_type);

create index entities_normalized_trgm_idx
on public.entities
using gin (normalized_name gin_trgm_ops);
```

---

# 20. Tabla `entity_aliases`

## Propósito

Nombres alternativos de una entidad.

Ejemplos:

```text
Juan Pérez
Juancito
JP
Empresa ABC
ABC
```

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `entity_id` | `uuid` | NO |
| `alias` | `text` | NO |
| `normalized_alias` | `text` | NO |
| `alias_type` | `text` | NO |
| `confidence` | `numeric(5,4)` | SÍ |
| `source_memory_id` | `uuid` | SÍ |
| `is_active` | `boolean` | NO |
| `created_at` | `timestamptz` | NO |

## Unicidad

```sql
unique (user_id, entity_id, normalized_alias)
```

**No** se hará único `normalized_alias` por usuario, porque el mismo alias puede corresponder a dos personas y requerir aclaración.

## Índice fuzzy

```sql
create index entity_aliases_trgm_idx
on public.entity_aliases
using gin (normalized_alias gin_trgm_ops);
```

---

# 21. Tabla `memory_entity_links`

## Propósito

Relaciona una memoria con entidades.

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `memory_id` | `uuid` | NO |
| `entity_id` | `uuid` | NO |
| `link_type` | `text` | NO |
| `confidence` | `numeric(5,4)` | SÍ |
| `interpretation_id` | `uuid` | SÍ |
| `created_at` | `timestamptz` | NO |

## Tipos iniciales

```text
mentions
about
person
project
organization
place
topic
related
```

## Constraint

```sql
unique (user_id, memory_id, entity_id, link_type)
```

---

# 22. Tabla `facts`

## Propósito

Representa conocimiento factual estructurado y temporal.

Ejemplo:

```text
subject: Juan Pérez
predicate: works_at
object: Empresa ABC
valid_from: 2024
valid_to: 2026
```

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `subject_entity_id` | `uuid` | SÍ | sujeto entidad |
| `subject_text` | `text` | SÍ | sujeto textual excepcional |
| `predicate` | `text` | NO | relación normalizada |
| `object_entity_id` | `uuid` | SÍ | objeto entidad |
| `object_text` | `text` | SÍ | objeto textual |
| `object_value` | `jsonb` | SÍ | valor estructurado excepcional |
| `polarity` | `text` | NO | positive/negative |
| `status` | `text` | NO | current/historical/superseded/invalid |
| `valid_from_date` | `date` | SÍ | vigencia |
| `valid_to_date` | `date` | SÍ | vigencia |
| `valid_from_at` | `timestamptz` | SÍ | precisión datetime |
| `valid_to_at` | `timestamptz` | SÍ | precisión datetime |
| `temporal_granularity` | `text` | NO | unknown/date/datetime |
| `recorded_at` | `timestamptz` | NO | cuándo se aprendió |
| `source_memory_id` | `uuid` | NO | fuente |
| `source_interpretation_id` | `uuid` | SÍ | interpretación |
| `supersedes_fact_id` | `uuid` | SÍ | dato anterior |
| `confidence` | `numeric(5,4)` | SÍ | 0–1 |
| `created_at` | `timestamptz` | NO | `now()` |

## Constraints

```sql
check (
  subject_entity_id is not null
  or subject_text is not null
)

check (
  object_entity_id is not null
  or object_text is not null
  or object_value is not null
)

check (polarity in ('positive', 'negative'))

check (status in (
  'current',
  'historical',
  'superseded',
  'invalid'
))

check (temporal_granularity in (
  'unknown',
  'date',
  'datetime'
))

check (
  valid_to_date is null
  or valid_from_date is null
  or valid_to_date >= valid_from_date
)

check (
  valid_to_at is null
  or valid_from_at is null
  or valid_to_at >= valid_from_at
)

check (
  confidence is null
  or (confidence >= 0 and confidence <= 1)
)
```

## Regla “desconocido no es falso”

Si no existe evidencia sobre un hecho, no se inserta automáticamente una fila negativa.

Una negación solo existe si hay evidencia explícita:

```text
polarity = negative
```

---

# 23. Tabla `tasks`

## Propósito

Estado estructurado de tareas y actividades.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `title` | `text` | NO | descripción breve |
| `description` | `text` | SÍ | detalle |
| `status` | `text` | NO | estado |
| `priority` | `text` | NO | urgent/high/normal/low |
| `priority_source` | `text` | NO | user/ai/default |
| `due_date` | `date` | SÍ | fecha |
| `due_time` | `time` | SÍ | hora opcional |
| `due_timezone` | `text` | SÍ | zona IANA |
| `due_at` | `timestamptz` | SÍ | solo cuando hora conocida |
| `time_known` | `boolean` | NO | default `false` |
| `raw_date_expression` | `text` | SÍ | “el miércoles...” |
| `captured_at` | `timestamptz` | SÍ | referencia temporal |
| `source_memory_id` | `uuid` | SÍ | fuente |
| `source_interpretation_id` | `uuid` | SÍ | interpretación |
| `idempotency_key` | `text` | SÍ | creación segura |
| `completion_note` | `text` | SÍ | detalle de cierre |
| `started_at` | `timestamptz` | SÍ | inicio |
| `completed_at` | `timestamptz` | SÍ | cierre |
| `postponed_at` | `timestamptz` | SÍ | posposición |
| `cancelled_at` | `timestamptz` | SÍ | cancelación |
| `last_modified_source` | `text` | SÍ | telegram/mcp/system |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | trigger |

## Estados

```text
pending
in_progress
waiting_confirmation
completed
postponed
cancelled
```

`waiting_confirmation` evita convertir “no sé si lo hice” en `completed`.

## Prioridades

```text
urgent
high
normal
low
```

## Constraints temporales

```sql
check (
  time_known = false
  or (
    due_date is not null
    and due_time is not null
    and due_timezone is not null
    and due_at is not null
  )
)

check (
  time_known = true
  or (
    due_time is null
    and due_at is null
  )
)
```

## Idempotencia

```sql
create unique index tasks_idempotency_unique
on public.tasks (user_id, idempotency_key)
where idempotency_key is not null;
```

## Regla de cierre

Si:

```text
status = completed
```

entonces `completed_at` deberá ser no null.

La función de transición de estado se encargará de esta consistencia.

---

# 24. Tabla `task_entity_links`

## Propósito

Permite que una tarea se relacione con varias personas, un proyecto, organizaciones u otras entidades.

No se guardarán listas de IDs dentro de JSONB.

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `task_id` | `uuid` | NO |
| `entity_id` | `uuid` | NO |
| `role` | `text` | NO |
| `created_at` | `timestamptz` | NO |

## Roles iniciales

```text
primary_person
related_person
project
organization
related
```

## Constraint

```sql
unique (user_id, task_id, entity_id, role)
```

La aplicación deberá comprobar que:

```text
role = project
```

se vincule normalmente con una entidad `entity_type = project`.

---

# 25. Tabla `reminders`

## Propósito

Fuente de verdad de los recordatorios.

n8n los ejecuta; no los “posee”.

## Columnas

| Columna | Tipo | Null | Regla |
|---|---|---:|---|
| `id` | `uuid` | NO | PK |
| `user_id` | `uuid` | NO | FK |
| `task_id` | `uuid` | NO | FK |
| `reminder_kind` | `text` | NO | base/ai/followup/manual |
| `planned_at` | `timestamptz` | NO | objetivo |
| `original_planned_at` | `timestamptz` | SÍ | antes de reprogramar |
| `status` | `text` | NO | pending/sending/sent/retry/cancelled |
| `can_break_silence` | `boolean` | NO | default `false` |
| `suppressed_until` | `timestamptz` | SÍ | retención temporal por silencio/descanso |
| `suppression_reason` | `text` | SÍ | motivo de retención |
| `reason` | `text` | SÍ | explicación |
| `idempotency_key` | `text` | NO | único |
| `retry_count` | `integer` | NO | default `0` |
| `next_retry_at` | `timestamptz` | SÍ | reintento |
| `lease_token` | `uuid` | SÍ | claim |
| `lease_expires_at` | `timestamptz` | SÍ | recuperación |
| `last_error_code` | `text` | SÍ | error |
| `last_error_message` | `text` | SÍ | error |
| `sent_at` | `timestamptz` | SÍ | confirmación |
| `cancelled_at` | `timestamptz` | SÍ | cancelación |
| `created_at` | `timestamptz` | NO | `now()` |
| `updated_at` | `timestamptz` | NO | trigger |

## Constraints

```sql
unique (user_id, idempotency_key)

check (retry_count >= 0)

check (status in (
  'pending',
  'sending',
  'sent',
  'retry',
  'cancelled'
))
```

## Índice del watchdog

```sql
create index reminders_due_idx
on public.reminders (planned_at)
where status in ('pending', 'retry');

El claimant deberá ignorar temporalmente filas con:

```text
suppressed_until > now()
```
```

## Lease

El lease evita que dos ejecuciones reclamen el mismo recordatorio.

Si n8n se cae después de reclamar:

```text
lease_expires_at < now()
```

permite que el watchdog lo recupere.

---

# 26. Tabla `notification_deliveries`

## Propósito

Registra los intentos reales de entrega.

Un reminder es el plan.

Una delivery es lo que ocurrió.

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `reminder_id` | `uuid` | NO |
| `channel` | `text` | NO |
| `attempt_number` | `integer` | NO |
| `idempotency_key` | `text` | NO |
| `status` | `text` | NO |
| `attempted_at` | `timestamptz` | NO |
| `sent_at` | `timestamptz` | SÍ |
| `provider_message_id` | `text` | SÍ |
| `error_code` | `text` | SÍ |
| `error_message` | `text` | SÍ |
| `response_metadata` | `jsonb` | NO |
| `created_at` | `timestamptz` | NO |

## Constraints

```sql
check (attempt_number >= 1)

check (status in ('attempting', 'sent', 'failed', 'unknown'))

unique (reminder_id, attempt_number)

unique (user_id, idempotency_key)
```

Una delivery exitosa debe impedir un reenvío posterior del mismo reminder salvo una nueva acción explícita.

Si el proveedor pudo haber recibido el mensaje pero n8n perdió la respuesta antes de persistirla, la delivery deberá poder quedar `unknown`. En ese caso el watchdog no deberá asumir automáticamente que el mensaje falló y reenviarlo de inmediato; deberá aplicar una política conservadora de reconciliación/reintento definida en `05_N8N_WORKFLOWS.md`. La base reconoce que la entrega externa exactamente-una-vez no puede garantizarse solo con una transacción PostgreSQL.

---

# 27. Tabla `pending_clarifications`

## Propósito

Mantiene preguntas conversacionales que necesitan respuesta posterior.

Ejemplo:

```text
“¿Juan Pérez o Juan Gómez?”
```

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `related_ingestion_id` | `uuid` | SÍ |
| `related_memory_id` | `uuid` | SÍ |
| `related_task_id` | `uuid` | SÍ |
| `question_type` | `text` | NO |
| `question_text` | `text` | NO |
| `channel` | `text` | NO |
| `channel_context_key` | `text` | SÍ |
| `context_json` | `jsonb` | NO |
| `status` | `text` | NO |
| `expires_at` | `timestamptz` | SÍ |
| `resolved_at` | `timestamptz` | SÍ |
| `answer_text` | `text` | SÍ |
| `answer_ingestion_id` | `uuid` | SÍ |
| `created_at` | `timestamptz` | NO |
| `updated_at` | `timestamptz` | NO |

## Estados

```text
pending
resolved
expired
cancelled
```

`context_json` puede contener candidatos temporales porque la clarificación es un objeto conversacional flexible. La relación definitiva deberá terminar en tablas estructuradas.

---

# 28. Tabla `reports`

## Propósito

Registra una consulta de reporte y su resultado.

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `source_ingestion_id` | `uuid` | SÍ |
| `requested_channel` | `text` | NO |
| `query_text` | `text` | NO |
| `date_from` | `date` | SÍ |
| `date_to` | `date` | SÍ |
| `filters` | `jsonb` | NO |
| `status` | `text` | NO |
| `result_text` | `text` | SÍ |
| `result_memory_id` | `uuid` | SÍ |
| `created_at` | `timestamptz` | NO |
| `completed_at` | `timestamptz` | SÍ |
| `updated_at` | `timestamptz` | NO |

## Estados

```text
requested
generating
completed
error
```

## Trazabilidad

El resultado del reporte deberá tener un `memory_item` de tipo `report`.

Las memorias usadas se relacionarán mediante:

```text
memory_relations
relation_type = report_uses
```

Los PDF/Excel generados se almacenarán como `assets` y se relacionarán mediante:

```text
memory_asset_links
role = generated_report
```

Así no se necesita una tabla adicional `report_assets`.

---

# 29. Tabla `ai_usage_events`

## Propósito

Permite conocer cuánto se utiliza cada proveedor/modelo y estimar gasto.

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `operation_type` | `text` | NO |
| `provider` | `text` | NO |
| `model` | `text` | NO |
| `model_version` | `text` | SÍ |
| `provider_request_id` | `text` | SÍ |
| `input_tokens` | `bigint` | SÍ |
| `output_tokens` | `bigint` | SÍ |
| `cached_input_tokens` | `bigint` | SÍ |
| `audio_seconds` | `numeric(12,3)` | SÍ |
| `image_count` | `integer` | SÍ |
| `estimated_cost_usd` | `numeric(14,6)` | SÍ |
| `pricing_version` | `text` | SÍ |
| `ingestion_id` | `uuid` | SÍ |
| `interpretation_id` | `uuid` | SÍ |
| `embedding_id` | `uuid` | SÍ |
| `report_id` | `uuid` | SÍ |
| `asset_id` | `uuid` | SÍ |
| `metadata` | `jsonb` | NO |
| `created_at` | `timestamptz` | NO |

## Constraints

Los valores de uso no podrán ser negativos.

```sql
check (input_tokens is null or input_tokens >= 0)
check (output_tokens is null or output_tokens >= 0)
check (cached_input_tokens is null or cached_input_tokens >= 0)
check (audio_seconds is null or audio_seconds >= 0)
check (image_count is null or image_count >= 0)
check (estimated_cost_usd is null or estimated_cost_usd >= 0)
```

El costo será una **estimación histórica según la tabla de precios conocida al momento de la ejecución**, no una factura contable oficial.

---

# 30. Tabla `audit_log`

## Propósito

Auditoría append-only de cambios relevantes.

## Columnas

| Columna | Tipo | Null |
|---|---|---:|
| `id` | `uuid` | NO |
| `user_id` | `uuid` | NO |
| `table_name` | `text` | NO |
| `record_id` | `uuid` | SÍ |
| `action` | `text` | NO |
| `actor_type` | `text` | NO |
| `actor_id` | `text` | SÍ |
| `source_channel` | `text` | SÍ |
| `ingestion_id` | `uuid` | SÍ |
| `correlation_id` | `uuid` | SÍ |
| `before_data` | `jsonb` | SÍ |
| `after_data` | `jsonb` | SÍ |
| `changed_fields` | `text[]` | SÍ |
| `db_role` | `text` | SÍ |
| `occurred_at` | `timestamptz` | NO |

## Acciones iniciales

```text
insert
update
state_transition
correction
supersede
configuration_change
delete_blocked
```

## Regla append-only

Roles operativos:

```text
SELECT   permitido según política
INSERT   solo mediante trigger/función interna
UPDATE   prohibido
DELETE   prohibido
```

El `audit_log` no deberá disparar auditoría sobre sí mismo.

## Minimización

No se copiarán indiscriminadamente audios/binarios ni secretos al audit log.

Para tablas con texto pesado, la auditoría deberá preferir:

- IDs;
- estados;
- hashes;
- campos modificados;

en lugar de duplicar megabytes de contenido.

---

# 31. Foreign Keys

Todas las FK de producto utilizarán por defecto:

```sql
on delete restrict
```

## 31.1 Integridad entre usuarios

No alcanza con que una fila tenga `user_id`.

La base también deberá impedir que una fila del usuario A apunte accidentalmente a un registro del usuario B.

Por lo tanto, para relaciones entre tablas de producto se preferirán foreign keys compuestas:

```text
(user_id, foreign_id)
        ↓
(target.user_id, target.id)
```

Las tablas padre necesarias deberán disponer de:

```sql
unique (user_id, id)
```

además de su PK global `id`.

Ejemplo conceptual:

```sql
foreign key (user_id, task_id)
references public.tasks(user_id, id)
on delete restrict
```

Esto añade integridad multiusuario incluso si una operación backend utiliza una credencial que omite RLS.

`profiles` es la excepción natural: su propio `id` representa al usuario y referencia `auth.users(id)`.

## 31.2 Relaciones principales

Principales relaciones:

```text
profiles.id
  ← user_settings.user_id
  ← assistant_name_history.user_id
  ← ingestions.user_id
  ← memory_items.user_id
  ← assets.user_id
  ← entities.user_id
  ← tasks.user_id
  ← ...

ingestions.id
  ← assets.first_ingestion_id
  ← source_texts.ingestion_id
  ← interpretations.ingestion_id
  ← memory_items.ingestion_id
  ← pending_clarifications.related_ingestion_id

memory_items.id
  ← memory_relations.from_memory_id
  ← memory_relations.to_memory_id
  ← memory_asset_links.memory_id
  ← source_texts.memory_id
  ← memory_chunks.memory_id
  ← memory_entity_links.memory_id
  ← facts.source_memory_id
  ← tasks.source_memory_id
  ← reports.result_memory_id

assets.id
  ← asset_locations.asset_id
  ← memory_asset_links.asset_id
  ← source_texts.asset_id
  ← interpretations.asset_id
  ← ai_usage_events.asset_id

source_texts.id
  ← memory_chunks.source_text_id
  ← interpretations.source_text_id
  ← source_texts.supersedes_source_text_id

memory_chunks.id
  ← embeddings.chunk_id

interpretations.id
  ← memory_relations.interpretation_id
  ← memory_entity_links.interpretation_id
  ← facts.source_interpretation_id
  ← tasks.source_interpretation_id
  ← ai_usage_events.interpretation_id

entities.id
  ← entity_aliases.entity_id
  ← memory_entity_links.entity_id
  ← facts.subject_entity_id
  ← facts.object_entity_id
  ← task_entity_links.entity_id

tasks.id
  ← task_entity_links.task_id
  ← reminders.task_id
  ← pending_clarifications.related_task_id

reminders.id
  ← notification_deliveries.reminder_id
```

---

# 32. Índices obligatorios de V1

No se indexará todo indiscriminadamente.

## Identidad / RLS

En tablas con alto volumen:

```sql
create index <table>_user_id_idx
on public.<table> (user_id);
```

`user_id` deberá estar indexado porque aparece en RLS y filtros frecuentes.

## Ingestas

```sql
(user_id, status)
(user_id, received_at desc)
(user_id, source_event_key)
(user_id, telegram_chat_id, telegram_message_id)
(user_id, drive_file_id)
```

## Memoria

```sql
(user_id, created_at desc)
(user_id, memory_type, status)
(user_id, event_date)
```

## Assets

```sql
(user_id, sha256) unique partial
(user_id, first_seen_at desc)
```

## Chunks

```sql
GIN (fts)
(user_id, memory_id)
(source_text_id, chunking_version, chunk_index)
```

## Entidades

```sql
(user_id, entity_type)
GIN (normalized_name gin_trgm_ops)
GIN (normalized_alias gin_trgm_ops)
```

## Facts

```sql
(user_id, subject_entity_id, predicate)
(user_id, status)
(user_id, recorded_at desc)
```

## Tasks

```sql
(user_id, status, due_date)
(user_id, priority, status)
(user_id, due_at)
```

## Reminders

```sql
planned_at WHERE status IN ('pending','retry')
(user_id, task_id)
(user_id, status)
```

## Deliveries

```sql
(reminder_id, status)
(user_id, created_at desc)
```

## Clarifications

```sql
(user_id, status, created_at desc)
```

## IA usage

```sql
(user_id, created_at desc)
(user_id, provider, model, created_at desc)
```

## Auditoría

```sql
(user_id, occurred_at desc)
(table_name, record_id, occurred_at desc)
```

---

# 33. Normalización de nombres

Se creará una función interna:

```text
private.normalize_search_text(text)
```

Objetivo conceptual:

```text
"  JUAN   PÉREZ "
→ "juan perez"
```

Aplicará:

- trim;
- espacios repetidos;
- minúsculas;
- unaccent.

Se usará para:

```text
entities.normalized_name
entity_aliases.normalized_alias
```

La normalización **no fusionará entidades**.

Dos registros pueden seguir normalizándose a:

```text
juan perez
juan perez
```

y eso obliga a aclaración si ambos son candidatos.

---

# 34. Fechas de tareas

La autoridad temporal no será el modelo.

Se implementará un trigger/helper:

```text
private.sync_task_due_at()
```

Regla:

```text
si time_known = false:
    due_time = null
    due_at = null

si time_known = true:
    requiere due_date
    requiere due_time
    requiere due_timezone
    calcula due_at
```

Conceptualmente:

```sql
(due_date + due_time) at time zone due_timezone
```

La zona deberá validarse previamente.

Siempre se conserva:

```text
raw_date_expression
captured_at
```

para reconstruir cómo se resolvió.

---

# 35. Historial de nombres

El cambio de:

```text
Clara → Victoria
```

tendrá **un único mecanismo canónico** para evitar duplicar historial:

```text
set_assistant_name(...)
      ↓
actualiza user_settings.assistant_name
+ assistant_name_source_ingestion_id
+ last_modified_source
      ↓
trigger AFTER UPDATE OF assistant_name
      ↓
1. cierra assistant_name_history actual
2. inserta el nuevo nombre vigente
3. registra audit_log
```

La función `set_assistant_name()` no insertará manualmente una segunda fila de historial; el trigger será la autoridad de historial.

La sincronización con `setMyName` de Telegram ocurre fuera de PostgreSQL mediante n8n.

Si Telegram falla:

```text
Supabase conserva Victoria como nombre deseado
Telegram sync queda pendiente/reintentable
```

No se revertirá la historia solo porque Telegram tarde en reflejar el cambio.

---

# 36. Mensajes editados de Telegram

Un mensaje editado no reemplaza el texto anterior.

Ejemplo:

```text
source_key:
telegram:12345:789
```

Versión original:

```text
version_no = 1
is_preferred = false
```

Versión editada:

```text
version_no = 2
is_preferred = true
supersedes_source_text_id = <v1>
```

La nueva ingesta podrá apuntar a la original mediante:

```text
parent_ingestion_id
```

Si la edición cambia una tarea/facto, se creará una nueva interpretación y se corregirá el estado de forma auditada.

---

# 37. A/B de transcripción

Un único audio:

```text
asset_id = X
```

puede producir:

```text
source_text A
provider = openai
model = ...
version = 1

source_text B
provider = gemini
model = ...
version = 2
```

Ambas se preservan.

Una sola puede ser:

```text
is_preferred = true
```

La elección de preferida no borra la otra.

---

# 38. Integridad de originales

La integridad se basa en:

```text
assets.sha256
```

Cuando se recupere un archivo para verificación:

```text
recalcular SHA-256
       ↓
comparar
       ↓
igual → integrity_status = verified
distinto → integrity_status = mismatch
```

No se deberá presentar un asset con `mismatch` como idéntico al original sin advertencia.

---

# 39. Búsqueda híbrida

La recuperación combinará tres familias.

## 39.1 Full Text Search

`memory_chunks.fts`

Útil para:

- términos;
- frases;
- palabras concretas.

## 39.2 Fuzzy search

`pg_trgm`

Útil para:

- nombres;
- errores;
- alias;
- transcripciones aproximadas.

## 39.3 Vector search

`embeddings.embedding`

Útil para significado semántico.

## 39.4 Filtros estructurados

Antes/después de la recuperación podrán aplicarse:

- `user_id`;
- fechas;
- personas;
- proyectos;
- tipo de memoria;
- estado;
- tarea;
- fuente.

## 39.5 Función híbrida

Se prevé una RPC:

```text
search_memory_hybrid(...)
```

La implementación final de pesos y dimensión vectorial se realizará después del benchmark.

Este documento **no inventa esos valores**.

---

# 40. Row Level Security

RLS deberá habilitarse en todas las tablas públicas de usuario.

Ejemplo:

```sql
alter table public.tasks enable row level security;
```

## 40.1 Política base de SELECT

Para tablas dependientes con `user_id`, conceptualmente:

```sql
create policy "select own rows"
on public.tasks
for select
to authenticated
using (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
);
```

Para `profiles`, la comparación será:

```text
auth.uid() = id
```

porque `profiles.id` es el identificador del usuario.

## 40.2 INSERT

```sql
with check (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
)
```

## 40.3 UPDATE

```sql
using (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
)
with check (
  (select auth.uid()) is not null
  and (select auth.uid()) = user_id
)
```

## 40.4 DELETE

No se creará una política de DELETE para roles de usuario normales en las tablas históricas.

Además, las tablas permanentes tendrán trigger de bloqueo de DELETE para proteger también contra errores de un backend con privilegios altos.

## 40.5 Índices RLS

`user_id` deberá indexarse en tablas grandes.

Esto reduce el costo de políticas basadas en:

```text
auth.uid() = user_id
```

## 40.6 RLS no reemplaza filtros

Las consultas seguirán filtrando explícitamente por `user_id` cuando corresponda.

RLS es seguridad, no la lógica principal de filtrado.

---

# 41. Acceso de n8n a Supabase

## 41.1 Principio

La IA nunca recibe una credencial de Supabase.

## 41.2 Producción V1

n8n mantendrá las credenciales únicamente en su almacén seguro.

Cuando exista una RPC específica, se preferirá:

```text
n8n → RPC controlada
```

sobre:

```text
n8n → operación administrativa arbitraria
```

## 41.3 Service role

Si alguna integración requiere `service_role`:

- solo existirá en n8n/servidor;
- nunca en GitHub;
- nunca en Telegram;
- nunca en prompts;
- nunca en MCP;
- nunca en un cliente público.

Las protecciones de no borrado mediante triggers seguirán existiendo porque `service_role` puede omitir RLS.

## 41.4 Evolución

Si durante Deployment resulta práctico crear un rol PostgreSQL runtime más restringido, podrá hacerse sin modificar el modelo de datos.

---

# 42. Protección contra DELETE

Se creará una función:

```text
private.prevent_historical_delete()
```

que lance una excepción.

Se aplicará como `BEFORE DELETE` a las tablas históricas/permanentes.

Como mínimo:

```text
assistant_name_history
ingestions
memory_items
memory_relations
assets
asset_locations
memory_asset_links
source_texts
memory_chunks
interpretations
entities
entity_aliases
memory_entity_links
facts
tasks
task_entity_links
reminders
notification_deliveries
pending_clarifications
reports
ai_usage_events
audit_log
```

## Excepción: embeddings

`embeddings` es dato derivado regenerable.

Podrá existir una operación de mantenimiento para eliminar embeddings de un modelo retirado y regenerarlos.

Eso no elimina:

- memoria;
- texto fuente;
- original;
- historial.

## Eliminación extraordinaria futura

Si alguna obligación legal o administrativa exige borrado físico, no se habilitará desde Telegram/MCP.

Requerirá un procedimiento administrativo/migración explícita y auditada.

---

# 43. Auditoría automática

Se creará:

```text
private.audit_row_change()
```

para tablas críticas.

Como mínimo auditar:

```text
user_settings
memory_items
entities
facts
tasks
reminders
pending_clarifications
reports
```

Y eventos especiales:

```text
assistant_name change
task state transition
fact supersede
configuration change
blocked delete
```

## Seguridad de funciones

Por defecto se preferirá:

```text
SECURITY INVOKER
```

Si una función necesita:

```text
SECURITY DEFINER
```

deberá utilizar:

```sql
security definer
set search_path = ''
```

y referenciar las tablas con schema explícito.

También deberá restringirse `EXECUTE`.

---

# 44. Funciones/RPC previstas

Las migraciones deberán implementar funciones pequeñas y específicas.

## 44.1 `set_assistant_name`

Entrada:

```text
user_id
new_name
change_source
source_ingestion_id
```

Operación:

- validar nombre;
- actualizar `user_settings.assistant_name`;
- guardar `assistant_name_source_ingestion_id`;
- guardar `last_modified_source`.

El trigger `trg_capture_assistant_name_history` realizará de forma atómica el cierre/inserción del historial y la auditoría.

## 44.2 `transition_task_status`

Entrada:

```text
task_id
target_status
source
completion_note
```

Responsabilidad:

- validar transición;
- completar timestamps;
- auditar;
- no adivinar identidad.

## 44.3 `correct_fact`

Responsabilidad:

- marcar hecho anterior historical/superseded;
- insertar hecho nuevo;
- conservar fuentes;
- auditar.

## 44.4 `claim_due_reminders`

Responsabilidad:

- seleccionar reminders vencidos;
- excluir temporalmente `suppressed_until > now()`;
- bloquear filas;
- usar `FOR UPDATE SKIP LOCKED`;
- asignar `lease_token`;
- asignar `lease_expires_at`;
- cambiar a `sending`;
- devolver lote.

Esto hace robusto el sistema incluso si en el futuro existen varios workers.

## 44.5 `release_expired_reminder_leases`

Recupera reminders:

```text
status = sending
lease_expires_at < now()
```

y los pasa a reintento.

## 44.6 `record_notification_result`

Registra delivery y actualiza reminder de forma atómica.

## 44.7 `resolve_clarification`

Marca la aclaración resuelta y relaciona la respuesta.

No ejecuta automáticamente una acción ambigua: la acción posterior debe utilizar los candidatos ya validados.

## 44.8 `search_memory_text`

Búsqueda textual con ranking.

## 44.9 `search_entities_fuzzy`

Devuelve candidatos; no selecciona uno automáticamente si hay más de uno plausible.

## 44.10 `search_memory_hybrid`

Se implementará completamente después de fijar modelo/dimensión/pesos.

---

# 45. Triggers previstos

## `trg_set_updated_at`

Tablas mutables:

```text
profiles
user_settings
ingestions
memory_items
asset_locations
source_texts
interpretations
entities
tasks
reminders
pending_clarifications
reports
```

## `trg_normalize_entity_name`

Antes de INSERT/UPDATE de `entities`.

## `trg_normalize_entity_alias`

Antes de INSERT/UPDATE de `entity_aliases`.

## `trg_sync_task_due_at`

Antes de INSERT/UPDATE de fechas de `tasks`.

## `trg_capture_assistant_name_history`

Mecanismo canónico de historial.

Se ejecutará `AFTER INSERT/UPDATE OF assistant_name` cuando el valor cambie y:

- cerrará la fila vigente anterior;
- insertará la nueva;
- copiará `assistant_name_source_ingestion_id`;
- registrará el origen;
- evitará duplicar historial.

`set_assistant_name()` será la vía preferida para cambiar el nombre porque valida los argumentos y deja los metadatos necesarios para el trigger.

## `trg_audit_*`

Sobre tablas críticas.

## `trg_prevent_delete_*`

Sobre tablas históricas.

## `trg_source_text_immutable`

Impide alterar el texto literal/versionado.

---

# 46. Transacciones críticas

Estas operaciones deberán ejecutarse atómicamente.

## Crear tarea

```text
crear/actualizar memory
+
crear task
+
task_entity_links
+
reminders
+
audit
```

## Corregir hecho

```text
cerrar hecho anterior
+
insertar hecho nuevo
+
relacionar fuentes
+
audit
```

## Cambiar nombre

```text
cerrar historial
+
insertar nuevo nombre
+
actualizar setting
+
audit
```

## Marcar recordatorio enviado

```text
insert delivery
+
update reminder
```

No deberá existir un estado donde se confirme éxito al usuario pero la operación esencial no haya sido persistida.

---

# 47. Estrategia de idempotencia

## Telegram

Ejemplo:

```text
telegram:<bot>:<update_id>
```

## Mensaje lógico

```text
telegram-message:<chat_id>:<message_id>
```

## Drive

Ejemplo:

```text
drive:<file_id>:<version-or-modifiedTime>
```

## Tarea derivada

Ejemplo conceptual:

```text
task:<ingestion_id>:<service-or-index>
```

## Reminder

```text
reminder:<task_id>:<kind>:<planned_at>
```

## Delivery

```text
delivery:<reminder_id>:<attempt_number>
```

Las claves exactas se definirán en `05_N8N_WORKFLOWS.md`, pero la base ya contiene los campos/índices necesarios.

---

# 48. Manejo de duplicados

## Mismo evento

`ingestions`:

```text
unique (user_id, idempotency_key)
```

## Mismo archivo

`assets`:

```text
unique (user_id, sha256)
where sha256 is not null
```

## Mismo archivo en Telegram + Drive

Resultado:

```text
1 asset
2 asset_locations
```

No:

```text
2 assets
```

## Archivo Drive modificado

Si:

```text
same drive_file_id
new sha256
```

entonces:

```text
nuevo asset
+
nueva ubicación/versión
+
relación histórica
```

No se sobrescribe el asset anterior.

---

# 49. Recuperación de evidencia

Una respuesta histórica deberá poder recorrer:

```text
fact/task
   ↓
source_memory_id
   ↓
memory_item
   ↓
memory_asset_links / source_texts
   ↓
memory_chunks
   ↓
asset
   ↓
asset_locations
```

Esto permite responder:

```text
“Lo dijiste en este audio.”
“Fue el 14 de agosto.”
“Este es el fragmento literal.”
“El rango era 01:32–01:48.”
“Te envío el original.”
```

---

# 50. Reportes y documentos generados

Un reporte textual:

```text
reports
   ↓
result_memory_id
   ↓
memory_item(type=report)
```

Fuentes utilizadas:

```text
memory_relations
relation_type = report_uses
```

PDF/Excel:

```text
assets
+
asset_locations(location_type=drive/generated)
+
memory_asset_links(role=generated_report)
```

Así podrá consultarse posteriormente:

> “Buscame el PDF que hicimos sobre agosto.”

---

# 51. No exposición de secretos

No habrá columnas para:

```text
OPENAI_API_KEY
GEMINI_API_KEY
TELEGRAM_BOT_TOKEN
GOOGLE_CLIENT_SECRET
SUPABASE_SERVICE_ROLE_KEY
N8N_ENCRYPTION_KEY
MCP_AUTH_SECRET
```

Esos secretos no pertenecen a esta base de producto.

Se almacenarán fuera de Git y mediante gestores de credenciales/secretos.

---

# 52. Datos sensibles en logs

La auditoría y telemetría deberán evitar duplicar contenido completo cuando no sea necesario.

Ejemplo correcto:

```json
{
  "table": "tasks",
  "record_id": "...",
  "changed_fields": ["status", "completed_at"]
}
```

En vez de copiar una transcripción completa de 40 páginas dentro de `audit_log`.

---

# 53. Migraciones propuestas

Estructura recomendada:

```text
supabase/
└── migrations/
    ├── 0001_extensions_and_schemas.sql
    ├── 0002_profiles_and_settings.sql
    ├── 0003_ingestions_and_assets.sql
    ├── 0004_memory_and_source_texts.sql
    ├── 0005_entities_and_facts.sql
    ├── 0006_tasks_and_reminders.sql
    ├── 0007_reports_ai_usage_audit.sql
    ├── 0008_indexes.sql
    ├── 0009_rls_and_grants.sql
    ├── 0010_functions_and_triggers.sql
    └── 0011_embedding_index_<model>.sql   # solo después del benchmark
```

El nombre real generado por Supabase CLI podrá usar timestamps.

Lo importante es el orden lógico.

---

# 54. Política para Antigravity

Antigravity deberá:

1. leer este documento antes de crear migraciones;
2. no eliminar ninguna de las 22 tablas obligatorias;
3. conservar las 3 auxiliares aprobadas;
4. no convertir datos estructurados críticos en un único JSONB;
5. no agregar cascadas destructivas de borrado a memoria histórica;
6. no agregar una dimensión vectorial hasta que esté aprobada;
7. crear las FK/constraints/índices especificados;
8. activar RLS;
9. implementar bloqueo de DELETE;
10. implementar auditoría;
11. probar migraciones en desarrollo;
12. generar rollback/procedimiento de recuperación cuando corresponda;
13. no modificar producción directamente sin migración;
14. documentar cualquier cambio que altere el significado del modelo.

---

# 55. Casos de prueba de esquema

## DB-TEST-001 — Dos Juan

Crear:

```text
Juan Pérez A
Juan Pérez B
```

Debe ser permitido.

La búsqueda debe devolver ambos candidatos.

## DB-TEST-002 — Alias duplicado entre personas

Dos entidades pueden tener alias normalizado `juan`.

Debe ser permitido.

## DB-TEST-003 — Archivo duplicado

Insertar mismo SHA-256 dos veces para mismo user.

La segunda creación de asset debe fallar/conflictuar y reutilizar el existente.

## DB-TEST-004 — Archivo en dos fuentes

Un asset debe soportar ubicación Telegram y Drive.

## DB-TEST-005 — Mensaje editado

Debe conservar versión 1 y versión 2.

## DB-TEST-006 — Transcripción A/B

Debe conservar dos transcripciones y permitir seleccionar una preferida.

## DB-TEST-007 — Fecha sin hora

Debe permitir:

```text
due_date = 2026-09-01
time_known = false
due_time = null
due_at = null
```

## DB-TEST-008 — Hora falsa

Debe rechazarse:

```text
time_known = false
due_time = 00:00
```

## DB-TEST-009 — Tarea completada

`status=completed` debe terminar con `completed_at`.

## DB-TEST-010 — Historial factual

Hecho anterior y nuevo deben coexistir.

## DB-TEST-011 — Nombre secretaria

Solo un nombre puede tener `valid_to is null`.

## DB-TEST-012 — DELETE memoria

DELETE operativo de una memoria/tarea/fact debe fallar.

## DB-TEST-013 — DELETE embedding

Un embedding derivado podrá eliminarse por mantenimiento autorizado.

## DB-TEST-014 — Reminder duplicado

Misma idempotency key debe producir conflicto y no duplicado.

## DB-TEST-015 — Delivery duplicada

Mismo intento/idempotency key no debe duplicarse.

## DB-TEST-016 — Lease expirado

Un reminder `sending` con lease vencido debe poder volver a retry.

## DB-TEST-016B — Resultado de entrega desconocido

Una delivery cuyo resultado externo sea incierto debe poder quedar `unknown` y no provocar un reenvío inmediato ciego.

## DB-TEST-017 — RLS usuario A/B

Usuario A no puede leer/escribir filas de B.

## DB-TEST-017B — FK cross-user

Una fila con `user_id=A` no debe poder relacionar un `task_id`, `memory_id`, `asset_id` o `entity_id` perteneciente a B.

## DB-TEST-018 — Audit append-only

Un rol operativo no puede UPDATE/DELETE `audit_log`.

## DB-TEST-019 — Source text inmutable

No debe poder editarse `text_content` de una transcripción guardada.

## DB-TEST-020 — Embeddings múltiples

Un chunk puede tener embeddings de modelos diferentes.

## DB-TEST-021 — Reporte trazable

Un reporte debe llegar a sus memorias fuente y assets generados.

## DB-TEST-022 — Integridad SHA

Un hash recalculado distinto debe marcar `mismatch`.

---

# 56. Auditoría de normalización

Se revisó específicamente que no se utilicen estas malas prácticas:

### NO

```text
tasks.people = JSON array
```

### SÍ

```text
task_entity_links
```

### NO

```text
facts = gran JSONB de toda la memoria
```

### SÍ

```text
facts + entities + source_memory_id
```

### NO

```text
audio_blob BYTEA permanente en Supabase
```

### SÍ

```text
asset metadata en Supabase
original en Drive
```

### NO

```text
embedding pegado a memory_chunks como única columna fija
```

### SÍ

```text
embeddings como tabla separada
```

### NO

```text
audit_log como reemplazo del historial de nombre
```

### SÍ

```text
assistant_name_history + audit_log
```

---

# 57. Auditoría de consistencia con arquitectura

## Originales

Soportados por:

```text
assets
asset_locations
memory_asset_links
source_texts
```

## Interpretación

Soportada por:

```text
interpretations
memory_items
memory_entity_links
```

## Acción

Soportada por:

```text
tasks
facts
reminders
reports
```

## Idempotencia

Soportada por:

```text
ingestions.idempotency_key
assets.sha256
tasks.idempotency_key
reminders.idempotency_key
notification_deliveries.idempotency_key
interpretations.run_key
```

## Histórico

Soportado por:

```text
status
supersedes_*
assistant_name_history
audit_log
source_texts versions
facts validity
```

## Ambigüedad

Soportada por:

```text
entities no unique por nombre
entity_aliases no unique global
pending_clarifications
```

## Búsqueda híbrida

Soportada por:

```text
memory_chunks.fts
pg_trgm
embeddings
relaciones/filtros
```

---

# 58. Decisiones de base congeladas

### DB-DEC-001
PostgreSQL/Supabase será la fuente de verdad del producto.

### DB-DEC-002
DATABASE_SCHEMA_V1 tendrá 25 tablas: 22 obligatorias + 3 auxiliares justificadas.

### DB-DEC-003
`assistant_name_history` será tabla propia.

### DB-DEC-004
Las relaciones tarea↔entidad serán N:N mediante `task_entity_links`.

### DB-DEC-005
La telemetría de IA se guardará en `ai_usage_events`.

### DB-DEC-006
Las PK de producto serán UUID.

### DB-DEC-007
Las FK históricas utilizarán `ON DELETE RESTRICT`.

### DB-DEC-008
No habrá política normal de DELETE sobre memoria histórica.

### DB-DEC-009
Existirá un trigger adicional de protección contra DELETE en tablas permanentes.

### DB-DEC-010
`embeddings` será la excepción principal por ser dato regenerable.

### DB-DEC-011
Los textos literales se versionarán en `source_texts`.

### DB-DEC-012
Los mensajes editados no reemplazarán la versión anterior.

### DB-DEC-013
No habrá unicidad global de nombre/alias de personas.

### DB-DEC-014
Las tareas con fecha sin hora guardarán `due_time=NULL` y `due_at=NULL`.

### DB-DEC-015
La fecha absoluta de una tarea con hora será derivada/validada usando timezone IANA.

### DB-DEC-016
Los hechos distinguirán `recorded_at` de período de validez.

### DB-DEC-017
Los recordatorios tendrán lease/idempotencia para recuperación segura.

### DB-DEC-018
`notification_deliveries` será independiente de `reminders`.

### DB-DEC-019
Los reportes se representarán también como `memory_items` y usarán relaciones existentes para sus fuentes/assets.

### DB-DEC-020
Los embeddings no fijarán dimensión hasta el benchmark.

### DB-DEC-021
La búsqueda textual usará FTS; nombres/alias usarán trigramas; semántica usará pgvector.

### DB-DEC-022
RLS se preparará desde V1 con aislamiento por `user_id`.

### DB-DEC-023
Las funciones con privilegios elevados usarán `SECURITY DEFINER` solo cuando sea necesario, `search_path` seguro y EXECUTE restringido.

### DB-DEC-024
Los cambios de esquema se harán únicamente mediante migraciones versionadas.

### DB-DEC-025
JSONB no reemplazará entidades operativas estructuradas.

### DB-DEC-026
Las relaciones entre tablas de producto deberán preservar consistencia de `user_id` mediante foreign keys compuestas cuando sea práctico.

### DB-DEC-027
El resultado externo incierto de una notificación se representará explícitamente como `unknown`; no se asumirá automáticamente fracaso ni éxito.

---

# 59. Decisiones que siguen pendientes

No se fijan todavía:

1. proveedor/modelo de embeddings;
2. dimensión vectorial;
3. `vector` versus eventual `halfvec` para un modelo de alta dimensión;
4. parámetros HNSW;
5. tamaño de chunks;
6. versión inicial exacta de chunking;
7. pesos FTS/vector/fuzzy;
8. umbral de similitud de entidades;
9. duración exacta del lease de reminder;
10. política exacta de retry/backoff;
11. límites mensuales de costo;
12. frecuencia de pruning de telemetría no histórica, si se decide aplicar alguna.

Estas decisiones pertenecen principalmente a:

```text
05_N8N_WORKFLOWS.md
06_AI_MODELS_AND_PROMPTS.md
10_DEPLOYMENT.md
```

---

# 60. Referencias técnicas verificadas

Antes de cerrar esta versión se verificaron contra documentación vigente de Supabase/PostgreSQL los siguientes puntos:

- RLS con `auth.uid()` y aislamiento por `user_id`;
- recomendación de indexar columnas utilizadas por RLS;
- Full Text Search con `tsvector`, columnas generadas e índices GIN;
- disponibilidad de `pg_trgm`, `unaccent` y `vector` en Supabase;
- HNSW e IVFFlat en pgvector, manteniendo HNSW como candidato preferente una vez fijado el modelo;
- necesidad de proteger funciones `SECURITY DEFINER` mediante `search_path` y privilegios de ejecución;
- posibilidad de utilizar funciones PostgreSQL/RPC para operaciones de datos intensivas.

La implementación deberá verificar nuevamente versiones/extensiones reales del proyecto Supabase al aplicar las migraciones.

---

# 61. Checklist final de aceptación del schema

Antes de dar por terminada la implementación de estas migraciones deberá verificarse:

- [ ] 25 tablas creadas;
- [ ] 22 tablas obligatorias presentes;
- [ ] 3 auxiliares presentes;
- [ ] todas las tablas dependientes del usuario tienen `user_id` (`profiles` usa `id = auth.users.id`);
- [ ] FK críticas creadas;
- [ ] no hay cascadas destructivas no aprobadas;
- [ ] RLS habilitada;
- [ ] índices `user_id` relevantes creados;
- [ ] no existe DELETE operativo de memoria histórica;
- [ ] trigger de DELETE probado;
- [ ] audit_log append-only probado;
- [ ] SHA-256 único por usuario probado;
- [ ] idempotencia de ingestions probada;
- [ ] idempotencia de tasks/reminders/deliveries probada;
- [ ] mensajes editados versionados;
- [ ] transcripciones A/B versionadas;
- [ ] due_date sin due_time funciona;
- [ ] dos personas con mismo nombre son posibles;
- [ ] clarificación puede mantener candidatos;
- [ ] hechos temporales preservan anterior/nuevo;
- [ ] reminder lease recuperable;
- [ ] FTS funciona;
- [ ] trigram search funciona;
- [ ] embeddings de varios modelos pueden coexistir;
- [ ] ninguna dimensión vectorial se fijó sin benchmark;
- [ ] reportes tienen trazabilidad;
- [ ] nombre de secretaria tiene historial;
- [ ] ai_usage_events registra consumo;
- [ ] migraciones corren en desarrollo desde cero;
- [ ] migraciones son reproducibles;
- [ ] pruebas automáticas del esquema pasan.

---

# 62. Próximo documento

Con este modelo de base definido y auditado, el siguiente documento será:

```text
05_N8N_WORKFLOWS.md
```

Ese documento definirá:

- lista exacta de workflows;
- triggers;
- subworkflows;
- entradas/salidas;
- orden de procesamiento;
- idempotency keys;
- reintentos;
- manejo de errores;
- watchdog;
- Telegram;
- Drive;
- IA;
- Supabase;
- MCP;
- recordatorios;
- reportes.

`05_N8N_WORKFLOWS.md` deberá usar este schema y no inventar una base paralela.
