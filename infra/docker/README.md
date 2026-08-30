# Infraestructura DEV — Secretaria Virtual con IA

Este directorio contiene la configuración de Docker Compose para el entorno de desarrollo (DEV) de la Secretaria Virtual con IA, conforme a `10_DEPLOYMENT.md` y `08_SECURITY.md`.

## Servicios

1. **n8n (`secretaria-n8n-dev`)**:
   - Imagen fijada: `docker.n8n.io/n8nio/n8n:2.33.3`
   - Single-instance (sin Redis, sin queue mode, sin workers distribuidos).
   - Acceso web confinado a localhost (`127.0.0.1:5678`). No expuesto a WAN.
   - Modo de datos binarios: `filesystem`.
   - Pruning automático: habilitado cada 168 horas (`EXECUTIONS_DATA_PRUNE=true`, `EXECUTIONS_DATA_MAX_AGE=168`).
   - Timezone: `America/Argentina/Buenos_Aires`.

2. **PostgreSQL interno de n8n (`secretaria-n8n-postgres-dev`)**:
   - Imagen: `postgres:16-alpine`.
   - Servidor exclusivo para el estado y orquestación de n8n.
   - Totalmente aislado en la red interna de Docker (`n8n_internal_network`).
   - **No publica puertos hacia el host ni hacia WAN.**

## Seguridad y Hardening

- **Sin `privileged: true`** y con `no-new-privileges:true`.
- **Sin montaje de `/var/run/docker.sock`**.
- **Sin secrets en etiquetas ni commits.**
- **Supabase** es la fuente de verdad del producto y corre de forma desacoplada de la base interna de n8n.

## Levantamiento en DEV

1. Copiar `.env.example` a `.env` local (no versionado):
   ```bash
   cp .env.example .env
   ```
2. Iniciar contenedores:
   ```bash
   docker compose -f compose.dev.yml up -d
   ```
3. Verificar estado de los contenedores:
   ```bash
   docker compose -f compose.dev.yml ps
   ```
4. Detener entorno DEV:
   ```bash
   docker compose -f compose.dev.yml down
   ```
