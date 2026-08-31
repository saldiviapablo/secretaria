# Infraestructura DEV — Secretaria Virtual con IA

Este directorio contiene la configuración DEV de n8n y su PostgreSQL interno.

## Pin vigente propuesto

```text
docker.n8n.io/n8nio/n8n:2.35.4
```

Historial:

```text
2.33.3
→ 2.33.4
→ 2.35.4
```

`2.35.4` se adopta mediante revisión controlada de seguridad posterior a F2.
No es un upgrade automático ni autoriza `latest`.

## Motivo de seguridad

Advisories oficiales de n8n publicados el 19 de agosto de 2026 indican que varias vulnerabilidades afectan ramas anteriores y están corregidas a partir de `2.35.4` o `2.36.2`.

Entre ellas:

- `GHSA-9x83-43r8-5hwc` — Expression sandbox escape / host RCE.
- `GHSA-fg85-4wv2-p98j` — expression sandbox mutation bypass.
- `GHSA-mwp5-2m32-r54h` — Git Node RCE.
- `GHSA-4r56-g65c-fm83` — credential exfiltration via inline sub-workflow.
- `GHSA-95ph-833c-4wrp` — local file read / SSRF in Gmail/Brevo.
- `GHSA-wxwj-8wv6-vpw2` — query injection in Elasticsearch/Firestore.
- `GHSA-xwx6-jjhv-84p8` — prototype pollution / instance-wide DoS.

Release oficial:
`https://github.com/n8n-io/n8n/releases/tag/n8n@2.35.4`

## Hardening preservado

```text
N8N_PUBLIC_API_DISABLED=true
N8N_PUBLIC_API_SWAGGERUI_DISABLED=true
N8N_COMMUNITY_PACKAGES_ENABLED=false
```

Además:

- bind DEV por defecto en `127.0.0.1`;
- sin Docker socket;
- sin `privileged: true`;
- `no-new-privileges:true`;
- PostgreSQL interno sin port mapping;
- telemetry/templates deshabilitados;
- 17 workflows F0/F1/F2;
- F3 no iniciada.

## Gate de frescura de seguridad

Antes de certificar `2.35.4`, Antigravity debe volver a revisar los advisories oficiales publicados de `n8n-io/n8n`.

Si existe un advisory posterior que:

```text
afecta 2.35.4
+
requiere una versión parcheada > 2.35.4
```

entonces:

```text
SECURITY PATCH BLOCKED_BY_NEWER_ADVISORY
```

No se hace commit y no se inicia F3.

## Upgrade DEV

No imprimir el `.env` local.

Si existe:

```text
infra/docker/.env
```

cambiar únicamente:

```text
N8N_IMAGE=docker.n8n.io/n8nio/n8n:2.35.4
```

preservando todas las demás variables.

El upgrade real requiere:

```text
backup DB interna n8n
→ export workflows
→ pull 2.35.4
→ restart n8n DEV
→ verify version
→ 17 workflows
→ F1/F2 regression
→ n8n audit
→ restart/recovery
→ evidence
```

No usar `docker compose down -v`.
