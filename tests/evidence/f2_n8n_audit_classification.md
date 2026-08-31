# Clasificación y Análisis de Seguridad de n8n Audit — Fase F2

**Proyecto:** Secretaria Virtual con IA  
**Baseline:** `SVIA-DOCSET-V1-RC1` (Conforme a `08_SECURITY.md` y `09_TEST_PLAN.md` - `SEC-TEST-026`)  
**Fecha:** 2026-08-30  
**Target:** Contenedor DEV `secretaria-n8n-dev` (n8n `2.33.3`)  
**Estado:** `AUDIT_CLASSIFIED_ACCEPTABLE` (0 vulnerabilidades P0/P1)

---

## 1. Resumen Ejecutivo de la Auditoría

El comando `n8n audit` ejecutado sobre la instancia DEV con los 17 workflows importados reportó advertencias en tres categorías estándar del linter de n8n:
1. **Database Risk Report:** Nodos PostgreSQL marcados por ausencia del campo UI `"Query Parameters"`.
2. **Nodes Risk Report:** Nodos oficiales de tipo Code marcados como potencialmente riesgosos por capacidad general de ejecución JavaScript.
3. **Instance Risk Report:** Advertencia informativa de actualización disponible respecto al pin `2.33.3`.

Conforme al criterio de `09_TEST_PLAN.md` (`SEC-TEST-026`), ningún hallazgo representa una vulnerabilidad crítica o bloqueante (P0/P1), y todos los patrones utilizados cuentan con mitigaciones activas y demostrables.

---

## 2. Matriz de Clasificación de Hallazgos

| Hallazgo | Componente / Workflows | Riesgo Teórico | Input No Confiable | Mitigación / Evidencia Técnica | Severidad | Blocking | Justificación |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Unused "Query Parameters" fields in SQL nodes** | `WF-REM-001`<br>`WF-REM-002`<br>`WF-REM-003`<br>`WF-REM-004`<br>+ Workflows F0/F1 | Inyección SQL por concatenación de strings | No | **Parametrización Posicional Segura:** Todos los nodos SQL utilizan `options.queryReplacement` con parámetros posicionales `$1`, `$2`, etc. pasados directamente al driver `pg` como prepared statements. No existe interpolación de strings (`${...}`) en las consultas SQL. El linter advierte únicamente porque el campo visual UI `queryParameters` de versiones posteriores no está configurado. | **P2** (Aceptado) | **No** | Mitigación nativa a nivel driver SQL. 0 riesgo de SQL Injection. |
| **Official risky nodes (Code Nodes)** | 23 nodos Code en los 17 workflows | Ejecución de código arbitrario (RCE) | Sí (mensajes/textos de entrada) | **Transformación Pura y Aislamiento de Entorno:** Ningún nodo Code utiliza `eval()`, `Function()` ni ejecución dinámica. Las cadenas de entrada se tratan estrictamente como datos de texto/JSON. Además, el contenedor Docker excluye nodos de ejecución de sistema (`nodesExclude: executeCommand, localFileTrigger`) y opera con `no-new-privileges:true`. | **P2** (Aceptado) | **No** | Código estático auditado. No hay ejecución de comandos del sistema ni evaluación de código dinámico. |
| **Outdated Instance (n8n 2.33.3)** | Contenedor n8n | Vulnerabilidades sin parchear en versiones anteriores | No | **Pin Aprobado en Baseline:** La versión `2.33.3` es el pin formalmente establecido y auditado en `00_ESPECIFICACION_MAESTRA.md` y `10_DEPLOYMENT.md`. La instancia está aislada en LAN local (`127.0.0.1:5678`) sin exposición pública directa ni credenciales por defecto. | **P3** (Informativo) | **No** | Hallazgo operativo de versión. Aprobado para DEV en baseline SVIA-DOCSET-V1-RC1. |

---

## 3. Auditoría Detallada de Nodos Postgres F2

### A. WF-REM-001_PLAN_REMINDERS
- **Nodo `rem001-plan`:** `SELECT public.plan_task_reminders($1::uuid, $2::uuid, $3::jsonb) AS res;`
  - Parámetros: `[$json.user_id, $json.task_id, $json.additional_reminders_json]` vía `queryReplacement`.
  - Evaluación: Parámetros tipados estrictamente en PostgreSQL (`uuid`, `jsonb`). Cero concatenación.

### B. WF-REM-002_DISPATCH_DUE
- **Nodo `rem002-claim`:** `SELECT * FROM public.claim_due_reminders();` (Sin parámetros externos).
- **Nodo `rem002-policy`:** `SELECT public.evaluate_reminder_delivery_policy($1::uuid, $2::uuid) AS policy;` vía `[$json.id, $json.lease_token]`.
- **Nodo `rem002-hold`:** `SELECT public.apply_reminder_dispatch_decision($1::uuid, $2::uuid, $3::text, $4::timestamptz, $5::text) AS res;` vía `[$json.id, $json.lease_token, $json.policy.action, $json.policy.suppressed_until, $json.policy.reason]`.
- **Nodo `rem002-attempt`:** `SELECT public.record_notification_result($1::uuid, $2::uuid, 'telegram', $3::integer, $4::text, 'attempting', ...)` vía `[$json.reminder_id, $json.user_id, $json.attempt_number, $json.delivery_key, $json.lease_token]`.
- **Nodo `rem002-final`:** `SELECT public.record_notification_result(...)` vía `[$json.reminder_id, $json.user_id, $json.attempt_number, $json.delivery_key, $json.final_status, $json.provider_message_id, $json.error_code, $json.error_message, metadata, $json.lease_token]`.
  - Evaluación: Todas las mutaciones pasan por RPCs con tipos explícitos y lease token obligatorios. Cero interpolación insegura.

### C. WF-REM-003_REMINDER_WATCHDOG
- **Nodo `rem003-recover`:** `SELECT public.release_expired_reminder_leases() AS recovery;` (Sin parámetros externos).
- **Nodo `rem003-snapshot`:** `SELECT public.reminder_watchdog_snapshot() AS snapshot;` (Sin parámetros externos).
  - Evaluación: Consultas estáticas deterministas de monitoreo y recuperación.

### D. WF-REM-004_FOLLOWUP_PLANNER
- **Nodo `rem004-candidates`:** `SELECT * FROM public.list_followup_candidates();` (Sin parámetros externos).
- **Nodo `rem004-plan`:** `SELECT public.plan_task_reminders($1::uuid, $2::uuid, $3::jsonb) AS res;` vía `[$json.user_id, $json.task_id, $json.additional_json]`.
  - Evaluación: Invocación parametrizada de RPC segura.

---

## 4. Conclusión y Veredicto de Seguridad

- **Total Defectos P0 (Críticos Bloqueantes):** 0
- **Total Defectos P1 (Altos Bloqueantes):** 0
- **Total Defectos P2 (Medios Aceptados / Mitigados):** 2 (Parametrización vía `queryReplacement` y Code Nodes de transformación)
- **Total Defectos P3 (Bajos / Informativos):** 1 (Versión pin n8n 2.33.3)
- **Veredicto SEC-TEST-026:** `PASS`
