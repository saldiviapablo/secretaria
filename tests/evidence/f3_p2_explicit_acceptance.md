# ACEPTACIÓN FORMAL Y EXPLÍCITA DE HALLAZGOS P2 — FASE F3

---

## 1. Declaración de Aceptación y Alcance (Scope)

- **Fecha de Decisión:** 2026-09-01
- **Aprobado por:** Usuario (Decisión explícita documentada)
- **Estado de Gobernanza:** `P2_PREVIOUSLY_AUDITED = EXPLICITLY_ACCEPTED`
- **User Explicit Acceptance:** `true`
- **Alcance:** Exclusivamente los dos hallazgos P2 identificados y auditados en la fase F3 para la versión de n8n 2.35.4 y el esquema Supabase V1.

---

## 2. Categorías P2 Aceptadas

### Categoría P2-A: `Unused "Query Parameters" fields in SQL nodes` (Database Risk)
- **Descripción:** n8n audit señala el uso de `options.queryReplacement: "={{ [...] }}"` en nodos `n8n-nodes-base.postgres` en lugar del campo declarativo `queryParameters`.
- **Riesgo Residual:** **Nulo / Despreciable.**
  - Todas las consultas SQL en los 23 workflows utilizan sentencias parametrizadas de la forma `SELECT public.rpc_function($1::uuid, $2::uuid, ...) AS res;`.
  - Cero concatenación de cadenas o interpolación dinámica de variables en el texto SQL.
  - Todas las funciones invocadas son funciones almacenadas `SECURITY DEFINER` con `search_path = ''` que validan internamente la autorización del usuario (`user_id`).
- **Controles Compensatorios:**
  1. Parametrización estricta a través de bindings posicionales `$1, $2, ...` en el driver Postgres de n8n (`pg-pool`).
  2. Aislamiento RLS en todas las 25 tablas de Supabase.
  3. Verificación automatizada de contratos de datos en test suites.

### Categoría P2-B: `Official risky nodes` (Nodes Risk)
- **Descripción:** n8n audit cataloga genéricamente a los nodos `n8n-nodes-base.code` y `n8n-nodes-base.httpRequest` como nodos de riesgo por ejecutar JavaScript o emitir peticiones HTTP salientes.
- **Riesgo Residual:** **Bajo / Mitigado.**
  - Los Code nodes son indispensables para la computación criptográfica de hashes SHA-256 (`getBinaryDataBuffer`), parseo de payloads y validación defensiva de esquemas.
  - Los HTTP Request nodes están estrictamente acotados a APIs oficiales seguras (OpenAI, Google Gemini, Telegram Bot API, sidecar local de DOCX).
- **Controles Compensatorios:**
  1. Variable de entorno `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` activa en n8n, impidiendo acceso a variables de proceso o secretos desde código JavaScript.
  2. `N8N_COMMUNITY_PACKAGES_ENABLED=false` y `N8N_PUBLIC_API_DISABLED=true`.
  3. Contenedores Docker ejecutados con `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]` (en sidecar) y sin montaje del Docker socket (`/var/run/docker.sock`).
  4. Red interna aislada `svia_doc_internal` (`internal: true`) para el sidecar DOCX sin salida a Internet.

---

## 3. Condiciones que Invalidan la Aceptación

La presente aceptación quedará automáticamente revocada y requerirá nueva auditoría si se introduce cualquiera de los siguientes cambios:
1. Cualquier concatenación de strings o construcción dinámica de texto SQL en nodos de base de datos.
2. Inclusión de nuevos Code nodes con invocación a shell del host, subprocesos o acceso a filesystem arbitrario.
3. Instalación de community nodes o paquetes no verificados.
4. Peticiones HTTP salientes a destinos dinámicos no controlados por el pipeline o definidos por contenido no confiable de usuarios.
5. Acceso a variables de entorno o credenciales desde nodos Code.
6. Montaje del Docker socket o privilegios elevados de contenedor.
7. Cualquier nuevo hallazgo P2 de una categoría diferente a P2-A o P2-B.

---

## 4. Dictamen de Seguridad

```text
P0 Vulnerabilities: 0
P1 Vulnerabilities: 0
Accepted P2 Findings: 2 (P2-A, P2-B bajo controles compensatorios)
Unaccepted P2 Findings: 0
Status: APPROVED_AND_ACCEPTED
```
