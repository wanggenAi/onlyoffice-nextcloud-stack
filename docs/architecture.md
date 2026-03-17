# Architecture (v1)

## Goal

A minimal, working collaboration stack:
- Nextcloud for files/users/sharing
- ONLYOFFICE Docs CE for browser-based document editing

## Components

1. `nextcloud` (`nextcloud:29-apache`)
2. `onlyoffice-documentserver` (`onlyoffice/documentserver:latest`)
3. `db` (`mariadb:11`) for Nextcloud metadata
4. `redis` (`redis:7-alpine`) for cache/locking
5. `caddy` (`caddy:2.9`) for optional reverse proxy/TLS (`ENABLE_CADDY=true`)

All containers run in one Docker Compose project on one host.

## Runtime Modes

### Mode A (default): HTTP over IP + ports

- `ENABLE_CADDY=false`
- Browser -> `http://<PUBLIC_SERVER_IP>:<NEXTCLOUD_PORT>` -> Nextcloud
- Browser -> `http://<PUBLIC_SERVER_IP>:<ONLYOFFICE_PORT>` -> ONLYOFFICE Docs

### Mode B (optional): HTTPS/domain via Caddy

- `ENABLE_CADDY=true`
- Browser -> `https://<NEXTCLOUD_FQDN>` -> Caddy -> Nextcloud
- Browser -> `https://<ONLYOFFICE_FQDN>` -> Caddy -> ONLYOFFICE Docs

### Internal service traffic (both modes)

- Nextcloud -> `http://onlyoffice-documentserver/` (Docker internal DNS)
- ONLYOFFICE -> `http://nextcloud-app/` (callback/storage)
- Nextcloud -> MariaDB (`db:3306`)
- Nextcloud -> Redis (`redis:6379`)

## Key Decisions

- Simple enough for first deployment and learning
- HTTP/IP mode works without DNS/certificates
- Keep Caddy in project for future HTTPS cutover without redesign
- Single compose file with health checks and scripted configuration

## Known Limits (Intentional in v1)

- Single-host deployment only
- No multi-node failover
- No HA database
- No external object storage in v1

## Resource Guidance

ONLYOFFICE Docs is heavier than Nextcloud. For smoother v1:
- CPU: 2+ vCPU
- RAM: 4+ GB recommended
- Disk: 20+ GB free

If the VM is small, prioritize stability over load tests.
