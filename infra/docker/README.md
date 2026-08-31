# Infraestructura DEV — Secretaria Virtual con IA

Este directorio contiene la configuración de Docker Compose para el entorno de desarrollo (DEV) de la Secretaria Virtual con IA, conforme a `10_DEPLOYMENT.md` y `08_SECURITY.md`.

## Servicios

1. **n8n (`secretaria-n8n-dev`)**:
   - Imagen fijada vigente: `docker.n8n.io/n8nio/n8n:2.33.4`.
   - `2.33.4` supersede el pin inicial `2.33.3` por revisión controlada de seguridad posterior a F2.
   - Motivo: parche oficial para `GHSA-c9c6-rq46-h25v` (sandbox escape en JavaScript Code Node por prototype pollution), que afecta `< 2.33.4`.
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
- Los upgrades de n8n son manuales: backup + rehearsal DEV + tests + `n8n audit`.
- No se hará downgrade ciego: si n8n migra su DB interna, rollback exige DB compatible + imagen previa + `N8N_ENCRYPTION_KEY`.

## Levantamiento en DEV

1. Copiar `.env.example` a `.env` local (no versionado), si aún no existe:
   ```bash
   cp .env.example .env
   ```
2. Si ya existe `.env`, actualizar **solo** `N8N_IMAGE` a:
   ```text
   docker.n8n.io/n8nio/n8n:2.33.4
   ```
   No imprimir ni publicar el resto del archivo porque puede contener secretos.
3. Iniciar contenedores:
   ```bash
   docker compose -f compose.dev.yml up -d
   ```
4. Verificar estado:
   ```bash
   docker compose -f compose.dev.yml ps
   ```
5. Verificar versión:
   ```bash
   docker exec secretaria-n8n-dev n8n --version
   ```
   Debe devolver `2.33.4`.
6. Detener entorno DEV sin borrar volúmenes:
   ```bash
   docker compose -f compose.dev.yml stop
   ```

## Referencias oficiales

- Advisory: `https://github.com/n8n-io/n8n/security/advisories/GHSA-c9c6-rq46-h25v`
- Release: `https://github.com/n8n-io/n8n/releases/tag/n8n@2.33.4`
