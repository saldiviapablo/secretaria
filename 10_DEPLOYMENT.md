# DEPLOYMENT — Secretaria Virtual con IA

**Proyecto:** Secretaria Virtual con IA  
**Repositorio previsto:** `saldiviapablo/secretaria`  
**Documento:** `10_DEPLOYMENT.md`  
**Versión:** 1.0-candidate — AUDITADA  
**Fecha:** 2026-08-29  
**Estado:** Construido, auditado y validado antes de entrega  
**Plataforma principal:** NAS UGREEN NASync DXP2800 + Docker  
**Orquestador:** n8n self-hosted  
**Base de producto:** Supabase/PostgreSQL  
**Documentos fuente:** `01_PRD.md` a `09_TEST_PLAN.md`

---

# 0. Resultado de construcción y auditoría

Este documento define cómo desplegar, operar, actualizar, respaldar y recuperar la V1.

Antes de entregarlo se auditó contra los documentos 01–09 y contra documentación vigente de n8n, Supabase, Telegram y OpenAI.

Se verificó especialmente:

- instalación reproducible con Docker Compose;
- n8n separado de su PostgreSQL interno;
- Supabase separado de la base interna de n8n;
- ausencia de Redis/queue mode en V1;
- versión estable de n8n fijada y no `latest`;
- exposición pública limitada a webhooks/MCP necesarios;
- panel administrativo no publicado por necesidad de webhook;
- HTTPS;
- Telegram webhook con `secret_token`;
- Drive OAuth;
- Supabase DEV/PROD;
- región de Supabase;
- variables de entorno;
- almacenamiento de binarios temporal;
- pruning de ejecuciones;
- timezone;
- backups externos a n8n;
- backup de `N8N_ENCRYPTION_KEY`;
- RPO/RTO iniciales;
- restore drill;
- schedulers concretos;
- health checks;
- despliegue por fases;
- rollback;
- upgrade rehearsal;
- security audit;
- gates de `09_TEST_PLAN.md`;
- MCP como capability gate independiente;
- no exposición de secretos en Git;
- no uso de backups de DB como sustituto de los originales de Drive.

---

# 1. Snapshot tecnológico aprobado

A fecha 2026-08-29:

```text
NAS:
UGREEN NASync DXP2800
Intel N100
8 GB DDR5

n8n:
2.33.3 stable

n8n topology:
single instance

n8n internal DB:
PostgreSQL

Product DB:
Supabase PostgreSQL

Originals:
Google Drive

AI:
OpenAI + Gemini APIs

Control:
Telegram
+
MCP cuando el cliente/plan lo soporte
```

## 1.1 Pin inicial de n8n

La versión inicial de producción será:

```text
n8nio/n8n:2.33.3
```

o la referencia equivalente del registry oficial de n8n.

Motivo:

- es la versión `stable` verificada al cerrar este documento;
- 2.34.0 figura como pre-release en el mismo snapshot;
- producción no utilizará `latest`.

Si antes de la instalación real aparece una versión estable posterior:

```text
NO se cambia automáticamente.
```

Proceso:

```text
2.33.3
→ DEV
→ suite 09
→ security audit
→ decisión explícita
→ nueva versión pinneada
```

## 1.2 Supersesión de seguridad aprobada — 2026-08-30

El pin inicial `2.33.3` se conserva como hecho histórico del snapshot del 2026-08-29.

Una revisión de seguridad posterior identificó el advisory oficial:

```text
GHSA-c9c6-rq46-h25v
Sandbox Escape in JavaScript Code Node via Prototype Pollution
```

Rango relevante:

```text
2.x afectado: < 2.33.4
patch:        >= 2.33.4
```

Decisión controlada aprobada:

```text
2.33.3
→ 2.33.4
```

La actualización es un patch mínimo dentro de la misma rama `2.33` y no autoriza saltos automáticos a `2.34+`.

Antes de considerar vigente el nuevo pin en el proyecto:

```text
backup n8n DB + key/config
→ export workflows
→ DEV rehearsal 2.33.4
→ importar los mismos workflows
→ regresión F0/F1/F2
→ security suite
→ n8n audit
→ evidence
→ commit/push
```

Si cualquiera de esos gates falla, el cambio queda `NOT DONE`/`BLOCKED` y no se inicia F3.

Referencias oficiales verificadas al aprobar la revisión:

```text
https://github.com/n8n-io/n8n/security/advisories/GHSA-c9c6-rq46-h25v
https://github.com/n8n-io/n8n/releases/tag/n8n@2.33.4
```


## 1.3 Segunda supersesión de seguridad aprobada — 2026-08-31

La revisión posterior al cierre del micro-hardening detectó advisories oficiales publicados el 19 de agosto de 2026 que afectan la versión `2.33.4`.

Entre los advisories relevantes:

```text
GHSA-9x83-43r8-5hwc  Expression sandbox escape / host RCE
GHSA-fg85-4wv2-p98j  Expression sandbox mutation bypass
GHSA-mwp5-2m32-r54h  Git Node RCE
GHSA-4r56-g65c-fm83  Credential exfiltration via inline sub-workflow
GHSA-95ph-833c-4wrp  Local file read / SSRF
GHSA-wxwj-8wv6-vpw2  Query injection
GHSA-xwx6-jjhv-84p8  Prototype pollution / instance-wide DoS
```

Los advisories oficiales relevantes identifican como líneas corregidas:

```text
>= 2.35.4
o
>= 2.36.2
```

Se adopta el cambio mínimo:

```text
2.33.4
→ 2.35.4
```

Motivo:

- `2.35.4` es el piso de seguridad explícitamente parcheado por los advisories;
- evita un salto innecesario a ramas posteriores;
- producción no usa `latest`;
- el cambio sigue sujeto a backup + rehearsal DEV + regresión + audit.

Antes de certificar `2.35.4`, debe realizarse un **fresh advisory gate**:

```text
revisar advisories oficiales n8n vigentes
→ si 2.35.4 sigue fuera de todos los rangos afectados críticos/altos aplicables
   continuar
→ si un advisory posterior afecta 2.35.4 y exige >2.35.4
   BLOCKED_BY_NEWER_ADVISORY
```

La certificación requiere:

```text
backup DB n8n + key/config
→ export 17 workflows
→ DEV rehearsal 2.35.4
→ verify 17 workflows
→ F1/F2 regression
→ security suite
→ n8n audit
→ restart/recovery
→ evidence
→ commit/push
```

No se inicia F3 durante esta revisión.

Referencias oficiales:

```text
https://github.com/n8n-io/n8n/releases/tag/n8n@2.35.4
https://github.com/n8n-io/n8n/security/advisories/GHSA-9x83-43r8-5hwc
https://github.com/n8n-io/n8n/security/advisories/GHSA-fg85-4wv2-p98j
https://github.com/n8n-io/n8n/security/advisories/GHSA-mwp5-2m32-r54h
https://github.com/n8n-io/n8n/security/advisories/GHSA-4r56-g65c-fm83
https://github.com/n8n-io/n8n/security/advisories/GHSA-95ph-833c-4wrp
https://github.com/n8n-io/n8n/security/advisories/GHSA-wxwj-8wv6-vpw2
https://github.com/n8n-io/n8n/security/advisories/GHSA-xwx6-jjhv-84p8
```

## 1.4 Decisión controlada DRIVE-ROOT-001 — Configuración Determinista Pre-Import del Google Drive Root

El usuario aprobó explícitamente la decisión `DRIVE-ROOT-001` para el aprovisionamiento de la carpeta raíz de Google Drive (`/SECRETARIA_VIRTUAL`):

1. **Configuración Local del Deployment:** El ID de la carpeta raíz de Google Drive es una configuración específica del entorno de deployment (`SVIA_DRIVE_ROOT_FOLDER_ID_DEV` en `infra/docker/.env`).
2. **Plantillas Git con Placeholder No Ejecutable:** Los archivos de workflow versionados en Git utilizan exclusivamente el placeholder no ejecutable `__SVIA_DRIVE_ROOT_FOLDER_ID__` en los 3 workflows de ingestión autorizados (`WF-ING-003`, `WF-ING-004`, `WF-ING-005`).
3. **Renderizado Determinista Pre-Import:** El script versionado `infra/scripts/render_n8n_workflows.py` genera los workflows renderizados en un directorio temporal/build antes de su importación a n8n.
4. **Aislamiento de Secretos y Hardening:** El ID real de la carpeta permanece fuera de Git y **NO se inyecta como variable de entorno al contenedor n8n**. La protección `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` permanece estrictamente habilitada para evitar exponer secretos del proceso (`N8N_ENCRYPTION_KEY`, credenciales DB) a los Code nodes y expresiones.
5. **Paridad Runtime == Git Renderizado:** La paridad técnica se certifica verificando que la lógica exportada de la instancia n8n coincide determinísticamente con el resultado de `deterministic_render(template + config)`.
6. **Comportamiento Fail-Closed:** La ausencia, vacío o formato inválido de `SVIA_DRIVE_ROOT_FOLDER_ID_DEV` detiene de inmediato el proceso de deployment con error `DRIVE_ROOT_CONFIG_REQUIRED`.

---

# 2. PostgreSQL interno de n8n

V1 utilizará PostgreSQL separado de Supabase.

## 2.1 Candidato inicial

```text
PostgreSQL 16
```

Imagen de desarrollo/configuración:

```text
postgres:16-alpine
```

En producción Antigravity deberá fijar además una versión/digest concreto después de verificar compatibilidad con el pin de n8n.

No utilizar:

```text
postgres:latest
```

## 2.2 Qué guarda

PostgreSQL interno de n8n guarda información operativa de la instancia:

- workflows;
- usuarios n8n;
- credenciales cifradas;
- executions según política;
- configuración interna.

No guarda la memoria de producto como fuente de verdad.

---

# 3. Topología física

```text
                        INTERNET
                           │
             ┌─────────────┴─────────────┐
             │                           │
       Telegram API                MCP cliente
             │                           │
             ▼                           ▼
      HTTPS/Tunnel                 Secure MCP path
             │                           │
             └─────────────┬─────────────┘
                           ▼
                 ┌──────────────────┐
                 │ NAS DXP2800      │
                 │                  │
                 │ Docker           │
                 │ ┌──────────────┐ │
                 │ │ n8n          │ │
                 │ └──────┬───────┘ │
                 │        │         │
                 │ ┌──────▼───────┐ │
                 │ │ PostgreSQL   │ │
                 │ │ n8n interno  │ │
                 │ └──────────────┘ │
                 └────────┬─────────┘
                          │ outbound
             ┌────────────┼─────────────┐
             ▼            ▼             ▼
         Supabase      Google Drive   OpenAI/Gemini
```

## Regla

Desde el router doméstico:

```text
NO port-forward de 5678
NO port-forward de PostgreSQL
```

---

# 4. Servicios Docker V1

Servicios mínimos:

```text
n8n
postgres_n8n
cloudflared     # si se adopta Cloudflare Tunnel para webhooks
```

No:

```text
Redis
n8n workers
queue mode
local LLM
vector DB aparte
```

Supabase es cloud y no forma parte del Compose de producción.

---

# 5. Recursos del NAS

El DXP2800 tiene 8 GB de RAM.

La V1 no deberá fijar límites tan agresivos que maten un procesamiento válido, pero sí deberá observar consumo.

Baseline inicial:

```text
n8n:
objetivo normal < 2.5 GB RAM

PostgreSQL n8n:
objetivo normal < 1 GB RAM

túnel/proxy:
< 300 MB RAM

margen:
reservar suficiente para UGOS, Docker y cache de filesystem
```

## Alarmas

Alertar/revisar si:

```text
RAM host > 85% sostenida
swap crece sostenidamente
disco > 80%
n8n OOM/restart
Postgres storage crece anormalmente
```

Los valores de sizing se ajustarán después de `PERF-TEST-004` y `PERF-TEST-007`.

---

# 6. Directorios del repositorio

Antigravity creará:

```text
infra/
├── docker/
│   ├── compose.prod.yml
│   ├── compose.dev.yml
│   ├── .env.example
│   └── README.md
├── tunnel/
│   └── README.md
├── scripts/
│   ├── backup_supabase.sh
│   ├── backup_n8n_db.sh
│   ├── backup_manifest.sh
│   ├── verify_backup.sh
│   ├── restore_n8n_test.sh
│   └── restore_supabase_test.sh
└── runbooks/
    ├── DEPLOY.md
    ├── ROLLBACK.md
    ├── RESTORE.md
    ├── ROTATE_SECRETS.md
    └── INCIDENT.md
```

Los scripts no contendrán secretos hardcodeados.

---

# 7. Directorio persistente en el NAS

No se asume un path específico de UGOS antes de ver el volumen real.

Se definirá:

```text
SVIA_HOST_ROOT=<VOLUMEN_REAL>/secretaria
```

Debajo:

```text
${SVIA_HOST_ROOT}/
├── n8n/
├── postgres/
├── backups/
│   ├── supabase/
│   ├── n8n/
│   └── manifests/
├── temp/
└── logs/
```

## Permisos

- directorio de secretos/config local: solo usuario administrativo;
- `.env`: modo equivalente a `0600`;
- backups: no world-readable;
- no compartir estos paths por SMB públicamente.

---

# 8. Docker Compose de producción — plantilla canónica

La siguiente es la **plantilla lógica** que Antigravity deberá convertir en `infra/docker/compose.prod.yml`.

```yaml
name: svia

services:
  postgres_n8n:
    image: ${POSTGRES_IMAGE}
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${N8N_DB_NAME}
      POSTGRES_USER: ${N8N_DB_USER}
      POSTGRES_PASSWORD: ${N8N_DB_PASSWORD}
      TZ: ${TZ}
    volumes:
      - postgres_n8n_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${N8N_DB_USER} -d ${N8N_DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
      - svia_internal

  n8n:
    image: ${N8N_IMAGE}
    restart: unless-stopped
    depends_on:
      postgres_n8n:
        condition: service_healthy
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres_n8n
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${N8N_DB_NAME}
      DB_POSTGRESDB_USER: ${N8N_DB_USER}
      DB_POSTGRESDB_PASSWORD: ${N8N_DB_PASSWORD}

      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}

      TZ: ${TZ}
      GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}

      WEBHOOK_URL: ${N8N_WEBHOOK_URL}
      N8N_EDITOR_BASE_URL: ${N8N_EDITOR_BASE_URL}
      N8N_PROXY_HOPS: ${N8N_PROXY_HOPS}

      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: "168"

      N8N_DEFAULT_BINARY_DATA_MODE: filesystem

    volumes:
      - n8n_data:/home/node/.n8n
    ports:
      - "${N8N_LAN_BIND}:5678:5678"
    networks:
      - svia_internal
      - svia_ingress

  cloudflared:
    image: ${CLOUDFLARED_IMAGE}
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    depends_on:
      - n8n
    networks:
      - svia_ingress
    profiles:
      - tunnel

volumes:
  postgres_n8n_data:
  n8n_data:

networks:
  svia_internal:
    internal: true
  svia_ingress:
```

## 8.1 Nota importante

`postgres_n8n` solo pertenece a:

```text
svia_internal
```

y no publica puerto al host.

`n8n` puede salir a Internet y ser alcanzado por el túnel, pero PostgreSQL no.

## 8.2 Bind del editor

`N8N_LAN_BIND` deberá ser una dirección accesible únicamente desde LAN/VPN.

No:

```text
0.0.0.0
```

si el firewall/router deja ese puerto accesible desde WAN.

Si UGOS/Docker obliga a bind amplio, el firewall será obligatorio.

---

# 9. `.env.example`

Repositorio:

```text
infra/docker/.env.example
```

Contenido sin valores secretos:

```dotenv
# Images
N8N_IMAGE=docker.n8n.io/n8nio/n8n:2.35.4
POSTGRES_IMAGE=postgres:16-alpine
CLOUDFLARED_IMAGE=cloudflare/cloudflared:<PINNED_VERSION_OR_DIGEST>

# Locale
TZ=America/Argentina/Buenos_Aires
GENERIC_TIMEZONE=America/Argentina/Buenos_Aires

# Internal n8n database
N8N_DB_NAME=n8n
N8N_DB_USER=n8n
N8N_DB_PASSWORD=

# n8n
N8N_ENCRYPTION_KEY=
N8N_LAN_BIND=<NAS_LAN_IP>
N8N_WEBHOOK_URL=https://hooks.<DOMAIN>/
N8N_EDITOR_BASE_URL=https://<PRIVATE_ADMIN_HOST>/
N8N_PROXY_HOPS=1

# Tunnel
CLOUDFLARE_TUNNEL_TOKEN=
```

No incluir:

- OpenAI key;
- Gemini key;
- Telegram Bot Token;
- Google OAuth secret;
- Supabase secret key;

en este `.env` salvo que técnicamente sea inevitable.

Esas credenciales se cargan dentro del credential store cifrado de n8n.

---

# 10. Hardening de variables n8n

Además de la plantilla base, Antigravity deberá revisar contra **la documentación exacta de n8n 2.35.4** qué variables de hardening están disponibles.

Se preferirá activar, cuando sean compatibles:

- bloqueo de acceso a variables de entorno desde nodos de usuario;
- restricción de filesystem;
- task runners aislados;
- deshabilitar telemetry/diagnostics no necesarios;
- deshabilitar templates no necesarios;
- deshabilitar Public API de n8n si no se usa;
- redacción/minimización de execution data.

## Regla

No se copiarán variables de una guía vieja sin comprobar que existan en 2.35.4.

Cada variable adicional deberá quedar documentada en:

```text
infra/docker/README.md
```

con:

- nombre;
- valor;
- motivo;
- link/documentación de la versión.


## 10.1 Hardening verificado en n8n 2.33.4 y preservado en 2.35.4

El `n8n audit` posterior al upgrade a `2.33.4` reportó:

```text
communityPackagesEnabled = true
publicApiEnabled = true
```

Para F0/F1/F2 esas capacidades no son necesarias.

Se adopta en DEV, sujeto a certificación runtime:

```dotenv
N8N_PUBLIC_API_DISABLED=true
N8N_PUBLIC_API_SWAGGERUI_DISABLED=true
N8N_COMMUNITY_PACKAGES_ENABLED=false
```

Este hardening no modifica workflows, Supabase, contratos ni fases.

Una futura necesidad de Public API o community nodes requiere revisión controlada, mínimo privilegio, tests y CHANGELOG.

Referencias oficiales:

```text
https://docs.n8n.io/deploy/host-n8n/configure-n8n/security/disable-the-public-api/
https://docs.n8n.io/integrations/community-nodes/risks/
```

---

# 11. Execution data

Baseline V1:

```text
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168
```

Es decir, retención aproximada máxima inicial de 7 días para execution data sujeta a pruning.

## Política de persistencia

Preferencia:

```text
errores:
guardar suficiente para diagnóstico

success:
guardar el mínimo necesario

manual/dev:
solo fixtures controlados
```

Antigravity deberá verificar las variables exactas de `SAVE_ON_SUCCESS`, `SAVE_ON_ERROR` y manual executions para el pin elegido antes de fijarlas.

---

# 12. Binary data de n8n

V1 Community/self-hosted utilizará:

```text
filesystem
```

para binarios temporales de ejecución.

No:

```text
PostgreSQL como archivo de binarios
```

Los originales permanentes van a Drive.

## Limpieza

Después de persistir original/metadata:

```text
execution pruning
→ limpia copia temporal
```

No se usará S3 external storage de n8n como requisito V1, ya que esa capacidad está ligada a planes Enterprise en la documentación actual.

---

# 13. Timezone

Host/n8n:

```text
America/Argentina/Buenos_Aires
```

Perfil de producto:

```text
profiles.timezone
```

continúa siendo la autoridad del usuario.

Si en el futuro el usuario cambia timezone:

- no es necesario cambiar el timezone del host;
- los workflows de negocio calculan con `profiles.timezone`.

---

# 14. Acceso administrativo a n8n

El editor/admin de n8n no se publica en el mismo hostname de webhooks como interfaz abierta.

## V1

Acceso:

```text
LAN
o
VPN privada
```

## Recomendación práctica

Tailscale/WireGuard o VPN equivalente es preferible a port-forward.

La tecnología concreta puede elegirse según lo que permita UGOS, sin cambiar la arquitectura.

## Obligatorio

- 2FA n8n;
- password único;
- no URL pública de admin abierta;
- no compartir cuenta owner.

---

# 15. Ingress público para Telegram

Ruta preferida:

```text
Telegram
→ Cloudflare Tunnel
→ hooks.<DOMAIN>
→ n8n
```

No requiere abrir 80/443 desde el router hacia el NAS.

## Motivo

- reduce superficie;
- el NAS no recibe port-forward directo;
- TLS termina en infraestructura controlada;
- se puede limitar hostname/path.

## Regla Cloudflare

El hostname público de webhook deberá permitir solo paths necesarios de producción.

Bloquear por defecto rutas administrativas como:

```text
/
signin
home
rest
api
settings
```

cuando el diseño del túnel/WAF permita expresarlo.

---

# 16. `WEBHOOK_URL`

Producción:

```text
WEBHOOK_URL=https://hooks.<DOMAIN>/
```

Este hostname es exclusivamente para callbacks/webhooks de producción.

DEV:

```text
https://hooks-dev.<DOMAIN>/
```

o URL temporal controlada.

No mezclar DEV/PROD.

---

# 17. Proxy hops

Con un único proxy/túnel que inserte forwarded headers:

```text
N8N_PROXY_HOPS=1
```

es el candidato inicial.

Si la cadena real es:

```text
Cloudflare
→ reverse proxy local
→ n8n
```

el número deberá ajustarse al número real de proxies confiables.

No se fija incorrectamente “por costumbre”.

---

# 18. Telegram webhook — procedimiento

Una vez activo `WF-TG-001`:

1. obtener URL de producción real del Telegram Trigger;
2. generar un `secret_token` aleatorio;
3. llamar `setWebhook`;
4. limitar `allowed_updates`;
5. verificar `getWebhookInfo`;
6. enviar mensaje de prueba;
7. comprobar `SEC-TEST-001/002/003`.

Plantilla conceptual:

```bash
curl -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -d "url=${TELEGRAM_PRODUCTION_WEBHOOK}" \
  -d "secret_token=${TELEGRAM_WEBHOOK_SECRET}" \
  -d 'allowed_updates=["message","edited_message","callback_query"]'
```

## Regla

`drop_pending_updates`:

```text
false / omitido
```

en operación normal.

Solo usar `true` durante un incidente/procedimiento que acepte perder pendientes.

---

# 19. Telegram secret token

El secreto del webhook:

- distinto del Bot Token;
- aleatorio;
- guardado en credential/config segura;
- no Git;
- no logs;
- rotación documentada.

La validación deberá ocurrir en el borde/receptor siempre que el mecanismo de n8n/túnel permita validar el header.

Igualmente se valida user/chat.

---

# 20. Google Drive — cuenta y carpeta

V1 utilizará una carpeta raíz única:

```text
SECRETARIA_VIRTUAL/
```

Subestructura sugerida:

```text
SECRETARIA_VIRTUAL/
├── 01_ORIGINALES/
│   ├── telegram/
│   ├── drive/
│   ├── web/
│   └── generated/
├── 02_REPORTES_GENERADOS/
└── 99_SYSTEM/
```

La estructura exacta podrá evolucionar sin cambiar IDs de Supabase.

## Cuenta

Preferencia de seguridad:

```text
cuenta Google dedicada al sistema
```

si es operativamente viable.

Si se usa una cuenta existente:

- folder raíz exclusiva;
- OAuth mínimo;
- no operar sobre todo Drive por defecto.

---

# 21. Google OAuth

Credential n8n:

```text
SVIA_DRIVE_PROD
```

DEV:

```text
SVIA_DRIVE_DEV
```

OAuth secrets no se exportan con workflows.

## Redirect URL

Debe corresponder al editor/admin URL seguro utilizado durante autorización.

El callback debe probarse antes de activar `DRIVE_WATCH`.

---

# 22. Drive ingestion

Dos mecanismos:

```text
DRIVE_WATCH
+
DRIVE_RECONCILIATION
```

## Scheduler concreto

Inicialmente:

```text
WF-ING-005 DRIVE_RECONCILIATION
cada 15 minutos
```

Puede aumentarse a 30/60 min si el costo/volumen demuestra que 15 es innecesario.

---

# 23. Supabase producción

## 23.1 Proyecto

Crear un proyecto dedicado:

```text
secretaria-prod
```

No reutilizar un proyecto de otra aplicación.

## 23.2 Región

Primera preferencia:

```text
sa-east-1 — São Paulo
```

si está disponible para el proyecto al momento de creación.

Motivo:

- región sudamericana;
- menor latencia esperable desde Argentina que regiones norteamericanas.

Si no está disponible:

```text
usar recomendación Americas
```

y registrar la región real.

## 23.3 Plan

V1 puede comenzar en:

```text
Free
```

si capacidad/uso real lo permiten.

Pero:

```text
Free NO se toma como fuente de backups automáticos.
```

Se ejecutan dumps propios.

---

# 24. Supabase DEV

Preferencia:

```text
Supabase local mediante CLI/Docker
```

en la máquina de desarrollo/Antigravity.

Ventajas:

- sin datos reales;
- migraciones reproducibles;
- reset;
- tests RLS;
- no consume segundo proyecto cloud.

Si alguna integración requiere callback cloud real:

se puede crear temporalmente un proyecto DEV separado.

---

# 25. Migrations

Fuente de verdad:

```text
supabase/migrations/
```

Flujo:

```text
Antigravity genera migration
→ supabase local reset
→ DB tests
→ RLS tests
→ Git
→ backup PROD
→ apply PROD
→ smoke
```

## Prohibido

Cambiar producción desde Dashboard y olvidarse de generar migración.

Si por emergencia se modifica manualmente:

- capturar diff;
- convertir a migration;
- documentar incidente.

---

# 26. Acceso n8n → Supabase

Ruta preferida de negocio:

```text
HTTPS
→ Supabase REST/RPC
```

con RPC específicas.

Ventajas:

- menos superficie que conexión SQL libre;
- contratos claros;
- fácil auditar.

## Credencial

Server-side secret/service key solo en n8n.

Nunca:

- ChatGPT/MCP;
- Telegram;
- prompts;
- Git.

## Conexión Postgres directa

Reservada para:

- migraciones;
- backups;
- tareas administrativas controladas;

no para un “execute arbitrary SQL” de workflows.

---

# 27. OpenAI/Gemini credentials

En n8n Credentials:

```text
SVIA_OPENAI_PROD
SVIA_GEMINI_PROD
```

DEV separados.

## Billing

Activar límites/alertas disponibles del proveedor.

## Data policy

Mantener:

- data sharing voluntario desactivado;
- storage externo minimizado;
- `store=false` cuando corresponda;
- Gemini Paid Services para memoria privada de producción.

---

# 28. MCP deployment gate

El servidor:

```text
WF-MCP-001
```

se puede implementar y probar en DEV.

## Producción

Inicialmente:

```text
MCP_WRITE_ENABLED=false
```

hasta verificar que el cliente ChatGPT usado en producción permita las capacidades aprobadas.

La documentación de OpenAI verificada al cerrar este documento indica que full MCP con write/modify está disponible para Business y Enterprise/Edu; Pro puede tener custom MCP read/fetch en developer mode.

## Regla

Telegram sigue siendo interfaz completa aunque MCP write esté deshabilitado.

---

# 29. Exposición MCP

Preferencia:

```text
Secure MCP Tunnel
```

cuando el producto OpenAI/cliente elegido sea compatible.

Si no:

```text
mcp.<DOMAIN>
→ HTTPS tunnel
→ path MCP exacto
→ Bearer/Header Auth
```

No exponer:

```text
n8n admin
otros webhooks
REST interno
```

por el hostname MCP.

---

# 30. MCP secrets

Credential:

```text
SVIA_MCP_PROD
```

Rotación:

- kill switch MCP;
- cambiar secret;
- test;
- reactivar.

No reutilizar:

```text
Telegram token
OpenAI key
Supabase key
```

---

# 31. Scheduler matrix V1

Frecuencias iniciales:

| Workflow | Frecuencia inicial |
|---|---|
| `WF-REM-002_DISPATCH_DUE` | cada 1 minuto |
| `WF-REM-003_REMINDER_WATCHDOG` | cada 5 minutos |
| `WF-REM-004_FOLLOWUP_PLANNER` | cada 30 minutos |
| `WF-REM-005_BRIEFING_DISPATCHER` | cada 5 minutos |
| `WF-REM-006_SILENCE_RELEASE` | cada 5 minutos |
| `WF-ING-005_DRIVE_RECONCILIATION` | cada 15 minutos |
| `WF-SYS-002_INGESTION_WATCHDOG` | cada 10 minutos |
| `WF-SYS-003_HEALTHCHECK` | cada 5 minutos |
| `WF-SYS-004_AI_COST_MONITOR` | cada 6 horas |
| `WF-SYS-005_BACKUP_HEALTH` | cada 6 horas |

## Regla

Los horarios de buenos días/cierre no viven en cron fijo.

El dispatcher periódico compara:

```text
hora actual local
+
settings
+
idempotency
```

---

# 32. Reminder precision

Con dispatcher de 1 minuto:

```text
error de polling teórico ≈ 0–60 s
```

más latencia externa.

Esto es suficiente para reminders de minutos/horas.

No se promete precisión de reloj en milisegundos.

---

# 33. Healthcheck policy

Cada 5 min:

- Supabase basic connectivity;
- Telegram basic connectivity;
- Drive credential/health razonable;
- último estado de ingesta;
- último reminder dispatcher.

## IA

No gastar tokens cada 5 min.

AI health:

- inferido de llamadas reales recientes;
- ping activo solo si no hubo actividad o ante diagnóstico.

---

# 34. Backup jobs no viven en n8n

Regla crítica:

```text
n8n NO se hace backup a sí mismo.
```

Los jobs reales de backup se ejecutan desde:

- scheduler del NAS;
- script/container independiente;
- job del host.

`WF-SYS-005` solo verifica:

- timestamp;
- manifest;
- estado.

---

# 35. RPO/RTO V1

Objetivos iniciales:

## Core product data

```text
RPO <= 6 horas
RTO <= 4 horas
```

Incluye:

- Supabase;
- tasks;
- memory;
- facts;
- reminders.

## Originals/complete recovery

```text
RPO <= 24 horas para copia independiente
RTO <= 8 horas para recuperación completa
```

Google Drive sigue siendo copia primaria online de originales.

## n8n control plane

```text
RPO <= 24 horas DB n8n
RTO <= 4 horas
```

Workflows además están en Git por cambio.

Estos objetivos se revisarán después de experiencia real.

---

# 36. Backup Supabase

En Free:

```text
cada 6 horas
```

job externo al proyecto.

Comandos base oficiales:

```bash
supabase db dump --db-url "$SUPABASE_DB_URL" \
  -f roles.sql --role-only

supabase db dump --db-url "$SUPABASE_DB_URL" \
  -f schema.sql

supabase db dump --db-url "$SUPABASE_DB_URL" \
  -f data.sql --use-copy --data-only
```

Antigravity adaptará exclusiones oficiales necesarias para schemas administrados por Supabase.

## Packaging

Cada ejecución produce:

```text
timestamp/
├── roles.sql
├── schema.sql
├── data.sql
├── manifest.json
└── SHA256SUMS
```

---

# 37. Retención Supabase

Baseline:

```text
snapshots 6h:
48 horas

daily:
30 días

weekly:
12 semanas
```

La rotación deberá mantener al menos una copia anterior a un error tardíamente detectado.

## Offsite

Una copia cifrada de backup de Supabase deberá salir del mismo proveedor.

V1 recomendado:

```text
NAS
+
copia cifrada en ubicación cloud distinta de Supabase
```

No se sube al repositorio Git.

---

# 38. Backup n8n PostgreSQL

Frecuencia:

```text
diaria — 03:30 local
```

Formato recomendado:

```text
pg_dump custom format
```

Contenido adicional del mismo backup set:

- `N8N_ENCRYPTION_KEY` referencia/secret package;
- Compose version;
- `.env` cifrado o inventario de variables sin secretos;
- n8n image tag/digest;
- workflow manifest.

## Regla

`N8N_ENCRYPTION_KEY` no se almacena en texto plano dentro del mismo directorio world-readable.

---

# 39. Retención n8n backup

```text
daily:
14 días

weekly:
8 semanas
```

Workflows viven además en Git, pero eso no reemplaza credentials/database.

---

# 40. Backup de Drive

Frecuencia de copia independiente:

```text
diaria — 04:00 local
```

Origen:

```text
SECRETARIA_VIRTUAL/01_ORIGINALES
```

Destino:

```text
NAS backup area
```

## Política

No borrar automáticamente del backup un archivo porque desapareció de Drive en la siguiente sincronización.

Usar:

```text
versioned/snapshot behavior
```

o papelera/retención.

---

# 41. Backup manifests

Cada backup real genera:

```json
{
  "backup_id": "uuid",
  "source": "supabase|n8n|drive",
  "started_at": "ISO",
  "finished_at": "ISO",
  "status": "ok|failed",
  "size_bytes": 0,
  "sha256_manifest": "...",
  "tool_version": "...",
  "host": "nas",
  "notes": ""
}
```

`WF-SYS-005` lee solo este manifest/status, no los secretos del backup.

---

# 42. Restore drills

## Frecuencia

```text
antes del primer release estable
+
trimestral
+
después de cambios importantes de backup
```

## Restore n8n

1. crear stack aislado;
2. restaurar dump PostgreSQL;
3. usar la misma `N8N_ENCRYPTION_KEY`;
4. arrancar n8n pinneado;
5. abrir credential de prueba;
6. ejecutar workflow DEV;
7. comprobar que descifra.

## Restore Supabase

1. proyecto/local DB aislado;
2. restaurar schema/data;
3. ejecutar tests;
4. comprobar RLS/constraints;
5. consultar memoria fixture.

No se considera PASS si solo “el dump importa”.

---

# 43. Backup health

`WF-SYS-005` cada 6h.

Alerta si:

```text
Supabase backup > 8h
n8n backup > 30h
Drive independent backup > 30h
último restore drill fuera de política
```

Estos thresholds dejan margen sobre la frecuencia planificada.

---

# 44. Git deployment model

El repositorio privado será la fuente versionada.

Flujo:

```text
Antigravity local
→ tests
→ commit
→ push GitHub
→ revisión
→ deploy
```

## n8n source control

No se depende de la feature comercial de environments/source control de n8n.

Los workflows se versionarán como JSON en Git.

La exportación concreta seguirá el manifest definido en `05_N8N_WORKFLOWS.md`.

La documentación actual de n8n reserva su source-control environments integrado para planes Business/Enterprise; nuestra estrategia funciona independientemente de eso.

---

# 45. Branch model

V1 personal:

```text
main
```

puede seguir siendo la rama aprobada.

Antes de producción estable:

```text
feature/<...>
→ pull request
→ main
```

recomendado para cambios sensibles.

No se requiere mantener una rama `production` distinta mientras el deploy sea manual/controlado y se registre el commit desplegado.

---

# 46. Version manifest de producción

Archivo runtime fuera de secretos:

```text
deployment_manifest.json
```

Ejemplo:

```json
{
  "release": "v1.0.0-rc1",
  "git_commit": "abc123",
  "n8n_image": "docker.n8n.io/n8nio/n8n:2.35.4",
  "postgres_image": "postgres:16-alpine@sha256:...",
  "supabase_migration_head": "20260829...",
  "model_registry_version": "2026-08-29",
  "deployed_at": "ISO-8601"
}
```

Esto permite reproducir un estado.

---

# 47. Secret inventory

Debe existir inventario **sin valores**:

| Secret | Ubicación | Rotable | Backup requerido |
|---|---|---:|---:|
| `N8N_ENCRYPTION_KEY` | host secret + backup seguro | sí, procedimiento especial | sí |
| n8n DB password | local env/secret | sí | sí/inventario |
| Telegram Bot Token | n8n credential | sí | no, regenerable |
| Telegram webhook secret | n8n/edge config | sí | no |
| Google OAuth | n8n credential | sí | sí/reautorizable |
| OpenAI key | n8n credential | sí | no |
| Gemini key | n8n credential | sí | no |
| Supabase server key | n8n credential | sí | no |
| Supabase DB password | backup/migration secret | sí | sí/recoverable |
| MCP bearer/header | n8n credential/config | sí | no |
| Cloudflare tunnel token | local secret | sí | no |

---

# 48. Secret rotation cadence

No rotar por calendario sin necesidad si el proveedor no lo requiere, pero sí:

- inmediatamente ante exposición;
- al retirar un equipo/usuario con acceso;
- al cambiar proveedor;
- si un secret scanner lo detecta;
- según política del proveedor.

## Test

`OPS-TEST-008` debe demostrar rotación en DEV.

---

# 49. Deploy inicial — orden exacto

## Paso 1

Preparar:

- dominio/túnel;
- NAS actualizado;
- Docker;
- directorios;
- secrets.

## Paso 2

Crear Supabase PROD.

## Paso 3

Aplicar migraciones de `04_DATABASE_SCHEMA.md`.

## Paso 4

Ejecutar DB/RLS tests.

## Paso 5

Levantar:

```text
postgres_n8n
n8n
```

sin webhooks públicos todavía.

## Paso 6

Crear owner n8n + 2FA.

## Paso 7

Configurar credentials DEV/PROD necesarias.

## Paso 8

Importar workflows por fases.

## Paso 9

Ejecutar:

```text
n8n audit
```

y resolver hallazgos críticos.

## Paso 10

Configurar Drive OAuth/root.

## Paso 11

Activar túnel webhook.

## Paso 12

Configurar Telegram `setWebhook`.

## Paso 13

Ejecutar E2E core.

## Paso 14

Activar reminder schedulers.

## Paso 15

Activar Drive ingestion.

## Paso 16

Activar IA/embeddings solo después de su benchmark/aprobación correspondiente.

## Paso 17

Activar MCP read/write según deployment gate.

## Paso 18

Ejecutar release gates de `09_TEST_PLAN.md`.

---

# 50. Activación por fases

No activar 41 workflows simultáneamente.

Orden:

```text
F0 infraestructura
F1 Telegram texto/tasks
F2 reminders
F3 audio/Drive
F4 memoria semántica
F5 briefings/rest
F6 reports
F7 MCP
F8 hardening/watchdogs
```

Cada fase:

```text
deploy
→ tests
→ observation
→ siguiente
```

---

# 51. Ventana de observación

Después de habilitar una fase nueva en producción:

```text
mínimo 24 horas
```

antes de cambios grandes posteriores, salvo hotfix urgente.

Observar:

- errores;
- duplicados;
- memoria;
- costo;
- CPU/RAM;
- reminders.

---

# 52. Release gate

Antes de `GO`:

- Gate A–F del Test Plan;
- 0 P0;
- 0 P1;
- security audit;
- backup reciente;
- restore drill cuando corresponda;
- manifest generado.

No:

```text
“parece bien, activalo”
```

---

# 53. Rollback de workflows

Si un workflow nuevo falla:

1. desactivar workflow afectado;
2. conservar ingestas/errores;
3. importar JSON del commit anterior;
4. verificar credentials bindings;
5. ejecutar tests;
6. reactivar;
7. watchdog recupera pendientes.

No borrar ingestas para “limpiar”.

---

# 54. Rollback de n8n

Una versión de n8n puede ejecutar migraciones internas de DB.

Por lo tanto:

```text
NO hacer downgrade ciego de imagen.
```

Rollback seguro:

```text
backup pre-upgrade
+
imagen anterior
+
DB n8n anterior correspondiente
+
N8N_ENCRYPTION_KEY
```

como conjunto.

## Upgrade

Antes de cambiar versión:

1. backup n8n DB;
2. backup key/config;
3. export workflows;
4. DEV rehearsal;
5. suite;
6. production window;
7. smoke.

---

# 55. Rollback Supabase

Las migrations de producto no se asumen reversibles automáticamente.

Preferencia:

```text
forward fix
```

para cambios no destructivos.

Si una migration daña datos:

```text
stop writes
→ evaluar restore a entorno aislado
→ recuperar/corregir
→ migration de reparación
```

No aplicar un `down.sql` destructivo genérico sin evidencia.

---

# 56. Prompt/model rollback

Mucho más simple:

```text
config/ai_models.json
prompts/
schemas/
```

volver al commit probado.

Pero:

- no borrar interpretations anteriores;
- registrar versión usada;
- no reescribir historia.

---

# 57. Maintenance window

Ventana recomendada inicial:

```text
domingo 04:30–06:00
America/Argentina/Buenos_Aires
```

para:

- upgrades;
- restore drills no productivos;
- reindex/maintenance;
- security checks.

Backups diarios no requieren downtime.

---

# 58. Upgrade cadence

## n8n

Revisión:

```text
mensual
```

Security fixes críticas:

```text
evaluación inmediata
```

No upgrade automático.

## PostgreSQL container

Revisar patch releases y seguridad.

Major upgrade:

- proyecto separado;
- backup;
- restore test;
- compatibility.

## Supabase

Gestionado por proveedor; revisar anuncios/migrations.

## AI models

Según `06_AI_MODELS_AND_PROMPTS.md` + evals.

---

# 59. Security audit cadence

```text
antes de producción
mensual
después de upgrade n8n
después de community/custom node
después de cambio importante de seguridad
```

V1 no instalará community nodes por defecto.

---

# 60. Pruning / storage maintenance

Revisar mensualmente:

- execution count;
- n8n Postgres size;
- n8n_data size;
- binary temp;
- backup size;
- NAS disk usage.

Alerta disco:

```text
80%
```

Crítico:

```text
90%
```

No esperar a llenar volumen.

---

# 61. Monitoring V1

Sin agregar una plataforma compleja de observabilidad al inicio.

Fuentes:

- n8n executions;
- `WF-SYS-003`;
- `WF-SYS-005`;
- NAS health;
- Supabase dashboard/status;
- Cloudflare tunnel status;
- Telegram alerts.

## Limitación conocida

Si Telegram está caído, la alerta Telegram no puede llegar.

V1 deberá conservar el incidente en logs/estado para revisión.

Un canal secundario externo se puede agregar después sin cambiar el core.

---

# 62. Logging retention

Baseline:

```text
n8n execution data:
7 días máximo inicial

host/container logs:
7–14 días rotados

audit_log de producto:
histórico/permanente según diseño

backup manifests:
mínimo 1 año
```

No confundir logs temporales con audit histórico.

---

# 63. Cloudflare Tunnel recovery

Si el túnel falla:

- n8n sigue vivo;
- schedulers internos siguen;
- Drive polling sigue;
- Telegram inbound no llega;
- Telegram outbound puede seguir por API si Internet sale.

Procedimiento:

1. verificar tunnel container;
2. restart;
3. validar DNS/tunnel;
4. `getWebhookInfo`;
5. reconciliar pendientes.

---

# 64. NAS reboot

Compose:

```text
restart: unless-stopped
```

Postgres healthcheck antes de n8n.

Después:

- ingestion watchdog;
- reminder watchdog;
- healthcheck;
- backup health.

`RES-TEST-030`/equivalente E2E de restart debe pasar.

---

# 65. Power failure

Recomendación operativa:

```text
UPS
```

para NAS si el sistema se vuelve de uso diario crítico.

No es requisito de software, pero reduce corrupción/apagados bruscos.

Si no hay UPS:

- PostgreSQL sigue usando durability;
- restore procedure debe existir;
- backups son más importantes.

---

# 66. Resource failure

Si n8n consume memoria excesiva:

1. identificar execution/workflow;
2. desactivar workflow;
3. no aumentar RAM ciegamente;
4. revisar archivo/contexto;
5. limitar lote;
6. reintentar.

El router de IA no debe cargar todo un archivo enorme en memoria si puede procesarlo por partes.

---

# 67. Cost operations

`WF-SYS-004` cada 6h.

Alertas cuando exista budget.

Además revisar mensualmente:

```text
OpenAI billing
Gemini billing
Supabase usage
Cloudflare usage
```

Un contador estimado no reemplaza factura oficial.

---

# 68. Free → paid upgrade triggers

Supabase deberá evaluarse para upgrade si:

- límites de proyecto afectan disponibilidad;
- DB/storage/egress crecen;
- backup automático/PITR se vuelve necesario;
- performance insuficiente;
- el proyecto deja de ser tolerante a pause/limitaciones del Free plan.

n8n Community puede mantenerse mientras no se necesiten capacidades comerciales específicas.

---

# 69. Seguridad de Compose

No usar:

```text
privileged: true
host network
docker.sock
```

para n8n.

No publicar Postgres.

No poner secrets en labels.

No usar `latest`.

---

# 70. `docker compose` commands

## Start

```bash
docker compose --env-file .env -f compose.prod.yml up -d
```

## Status

```bash
docker compose -f compose.prod.yml ps
```

## Logs limitados

```bash
docker compose -f compose.prod.yml logs --tail=200 n8n
```

Antes de copiar logs a un ticket/chat:

```text
redactar secretos/datos privados
```

## Stop controlado

```bash
docker compose -f compose.prod.yml stop
```

No `down -v` en producción.

---

# 71. Comandos peligrosos

Prohibidos como rutina:

```bash
docker compose down -v
docker volume rm ...
docker system prune --volumes
rm -rf <persistent-data>
```

si no existe backup/entendimiento exacto.

Antigravity no ejecutará estos comandos automáticamente en PROD.

---

# 72. Backup pre-change

Antes de:

- n8n upgrade;
- Postgres upgrade;
- migration de DB con riesgo;
- cambio de secrets estructural;
- cambio de storage;

crear snapshot/backup reciente y verificar que terminó.

---

# 73. Telegram recovery procedure

Si webhook no recibe:

1. `getWebhookInfo`;
2. revisar error;
3. validar tunnel;
4. validar secret;
5. validar workflow activo;
6. verificar URL;
7. no usar `drop_pending_updates`;
8. recuperar;
9. ejecutar reconciliation de estado.

---

# 74. Drive recovery procedure

Si OAuth vence/revoca:

1. pausar Drive ingestion;
2. conservar ingestas;
3. reautorizar credential;
4. ejecutar `DRIVE_RECONCILIATION`;
5. no reprocesar mismo hash.

---

# 75. Supabase recovery procedure

Si PROD no responde:

1. no confirmar escrituras;
2. workflows quedan retryable;
3. verificar status del proveedor;
4. no migrar por pánico;
5. al volver:
   - ingestion watchdog;
   - reminders;
   - reconciliation;
6. si pérdida real:
   - restore procedure.

---

# 76. AI provider outage

Si primario falla:

- retry limitado;
- fallback aprobado;
- registrar provider/model;
- no duplicar action.

Si ambos fallan:

```text
ingestion error/retry
```

No fingir procesamiento.

---

# 77. MCP recovery

Si MCP presenta comportamiento anómalo:

```text
kill switch MCP
```

Telegram/Drive siguen activos.

Si solo una tool está afectada:

```text
tool-specific kill switch
```

---

# 78. Deployment DEV

Compose DEV puede usar:

- n8n misma versión;
- PostgreSQL separado DEV;
- webhook DEV;
- Supabase local;
- bot Telegram DEV;
- no credentials PROD.

El objetivo es reproducir producción sin datos reales.

---

# 79. RC build

Una Release Candidate debe congelar:

```text
git commit
n8n image
postgres image/digest
Supabase migration head
workflow manifest
model registry
prompt versions
schema versions
```

Se ejecuta `09_TEST_PLAN.md`.

---

# 80. Production release

Una vez `GO`:

1. backup;
2. deploy commit exacto;
3. migrations;
4. import/activate workflows;
5. smoke;
6. monitor;
7. registrar deployment manifest.

No seguir editando directamente producción después de release sin nuevo cambio versionado.

---

# 81. Post-deploy smoke

Como mínimo:

- Telegram texto simple;
- query task;
- create/cancel smoke task;
- Supabase read/write controlado;
- Drive health;
- reminder corto DEV/controlado;
- healthcheck;
- no secret leak.

MCP smoke solo si está habilitado.

---

# 82. Test Plan integration

Antes de deploy:

```text
OPS-TEST-001..010
security gate
affected DB/WF/E2E
```

Antes de V1 estable:

```text
Gate A–F
restore drill
AI benchmarks requeridos
```

Después de deploy:

```text
safe smoke
```

---

# 83. Files que Antigravity generará

Después de aprobar este documento, Antigravity podrá generar:

```text
infra/docker/compose.prod.yml
infra/docker/compose.dev.yml
infra/docker/.env.example
infra/scripts/*
infra/runbooks/*
```

Este documento define la especificación.

No se deben crear secrets dentro del repo.

---

# 84. Decisiones de deployment congeladas

### DEP-DEC-001
n8n se desplegará self-hosted en el NAS mediante Docker Compose.

### DEP-DEC-002
El pin inicial fue `2.33.3`. Después de las revisiones controladas de seguridad posteriores a F2, el pin vigente candidato queda en `2.35.4`, sujeto a certificación DEV con backup, rehearsal, suites afectadas, revisión de advisories oficiales y `n8n audit` antes de cualquier uso productivo. No se utiliza `latest` ni se autoriza upgrade automático.

### DEP-DEC-003
Producción no utilizará `latest`.

### DEP-DEC-004
V1 utilizará una sola instancia n8n, sin Redis/queue workers.

### DEP-DEC-005
n8n utilizará PostgreSQL interno separado de Supabase.

### DEP-DEC-006
PostgreSQL interno no publicará su puerto.

### DEP-DEC-007
El panel n8n será LAN/VPN, no público por necesidad de webhook.

### DEP-DEC-008
Telegram utilizará hostname de webhook público separado.

### DEP-DEC-009
La ruta preferida de ingress Telegram será un túnel HTTPS sin port-forward del NAS.

### DEP-DEC-010
`WEBHOOK_URL` apuntará al hostname público de webhooks.

### DEP-DEC-011
Timezone base será `America/Argentina/Buenos_Aires`.

### DEP-DEC-012
Execution data tendrá pruning con baseline inicial de 7 días.

### DEP-DEC-013
Binary data temporal de n8n utilizará filesystem.

### DEP-DEC-014
Los backups reales se ejecutarán fuera de n8n.

### DEP-DEC-015
Supabase Free, si se usa, tendrá dumps propios cada 6h.

### DEP-DEC-016
Supabase PROD será un proyecto dedicado.

### DEP-DEC-017
Se preferirá `sa-east-1` si está disponible; si no, región Americas adecuada documentada.

### DEP-DEC-018
Supabase DEV será local por defecto.

### DEP-DEC-019
Drive tendrá root exclusiva `SECRETARIA_VIRTUAL`.

### DEP-DEC-020
Drive tendrá copia independiente diaria al NAS.

### DEP-DEC-021
RPO core inicial será <= 6h.

### DEP-DEC-022
RTO core inicial será <= 4h.

### DEP-DEC-023
RPO de copia independiente de originals será <= 24h.

### DEP-DEC-024
Restore drill será obligatorio antes de V1 estable y trimestral después.

### DEP-DEC-025
Reminder dispatcher correrá inicialmente cada 1 minuto.

### DEP-DEC-026
Drive reconciliation correrá inicialmente cada 15 minutos.

### DEP-DEC-027
MCP write tendrá deployment gate independiente.

### DEP-DEC-028
Se preferirá Secure MCP Tunnel cuando sea compatible.

### DEP-DEC-029
Workflows se versionarán como JSON en Git y no dependerán del source-control comercial de n8n.

### DEP-DEC-030
Los upgrades serán manuales, con backup + DEV rehearsal + tests.

### DEP-DEC-031
Un downgrade n8n requerirá recuperar también su DB compatible; no se hará downgrade ciego.

### DEP-DEC-032
Supabase migrations se probarán localmente antes de PROD.

### DEP-DEC-033
No habrá secretos en Git.

### DEP-DEC-034
No se expondrá Docker socket a n8n.

### DEP-DEC-035
`docker compose down -v` no será un procedimiento normal de producción.

### DEP-DEC-036
Cada release producirá un deployment manifest reproducible.

---

# 85. Pendientes que requieren datos reales de instalación

No son decisiones de producto; se completan al instalar:

1. path exacto del volumen UGOS;
2. IP LAN del NAS;
3. dominio;
4. hostname final de webhook;
5. mecanismo VPN administrativo;
6. versión/digest exacto de `postgres:16-alpine`;
7. versión/digest exacto de `cloudflared`;
8. número real de proxy hops;
9. client ID/secret Google;
10. Telegram webhook URL generada por n8n;
11. Supabase project ref;
12. región final realmente disponible;
13. budget mensual de IA;
14. host secondary alert futuro;
15. valores finales de performance baseline.

Estos valores van en configuración/secret inventory, no requieren reescribir arquitectura.

---

# 86. Referencias técnicas verificadas

Antes de cerrar este documento se comprobó:

## n8n

- release estable `2.33.3` al snapshot de 2026-08-29;
- `2.34.0` como pre-release en el snapshot consultado;
- Docker/self-host;
- PostgreSQL como backend;
- security audit;
- execution pruning/binarios;
- MCP Server Trigger;
- source-control environments como capacidad comercial, por lo que V1 no depende de ella.

## Supabase

- proyectos Free no tienen que asumirse con daily backups automáticos;
- Supabase recomienda `supabase db dump` para export periódico de Free;
- daily backups automáticos aplican a Pro/Team/Enterprise;
- backup DB no incluye objetos externos;
- `sa-east-1` existe como región sudamericana en servicios regionales y debe verificarse disponibilidad al crear proyecto;
- región de proyecto debe elegirse al crear y cambiarla requiere migración.

## Telegram

- HTTPS webhook;
- `secret_token`;
- `allowed_updates`;
- `drop_pending_updates`;
- `getWebhookInfo`.

## OpenAI

- ChatGPT se conecta a MCP remoto;
- Secure MCP Tunnel es la recomendación para servidor privado compatible;
- full MCP write actual está gated por producto/plan.

---

# 87. Checklist de aceptación

- [ ] n8n 2.35.4 pinneado;
- [ ] Postgres pin/digest validado;
- [ ] no `latest`;
- [ ] Compose reproducible;
- [ ] Postgres no expuesto;
- [ ] admin n8n LAN/VPN;
- [ ] 2FA n8n;
- [ ] `N8N_ENCRYPTION_KEY` segura + backup;
- [ ] pruning activo;
- [ ] binary filesystem;
- [ ] timezone correcta;
- [ ] tunnel/webhook HTTPS;
- [ ] proxy hops correcto;
- [ ] Telegram secret token;
- [ ] Telegram allowlist;
- [ ] Drive OAuth PROD;
- [ ] root Drive creada;
- [ ] Drive reconciliation cada 15 min;
- [ ] Supabase PROD dedicado;
- [ ] región documentada;
- [ ] migrations aplicadas desde Git;
- [ ] Supabase RLS tests;
- [ ] backup Supabase 6h;
- [ ] backup n8n diario;
- [ ] backup Drive diario;
- [ ] backup manifests;
- [ ] restore drill;
- [ ] healthcheck 5 min;
- [ ] reminder dispatch 1 min;
- [ ] watchdogs activos;
- [ ] security audit sin crítico;
- [ ] MCP gate aplicado;
- [ ] secretos DEV/PROD separados;
- [ ] deployment manifest;
- [ ] rollback runbook;
- [ ] release Gate A–F;
- [ ] smoke PROD;
- [ ] 0 P0/P1.

---

# 88. Próximo documento

El siguiente y último documento de la serie base será:

```text
11_CHANGELOG.md
```

Ese documento registrará:

- decisiones aprobadas;
- revisiones de schema;
- cambios de arquitectura;
- cambios de modelos;
- cambios de prompts;
- cambios de workflows;
- migrations;
- releases;
- incidentes que modifiquen diseño;
- deprecaciones;
- compatibilidad.

Después de `11_CHANGELOG.md`, la documentación base 01–11 estará completa y se podrá preparar el paquete/instrucciones de ejecución para Antigravity.
