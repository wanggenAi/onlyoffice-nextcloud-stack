# onlyoffice-nextcloud-stack

Self-hosted collaboration stack using Docker Compose:
- Nextcloud (file storage, sharing)
- ONLYOFFICE Docs Community Edition (online document editing)

One unified deployment path: `./scripts/up.sh`

## Project Structure

```text
.
├── docker-compose.yml
├── .env.example
├── README.md
├── deploy
│   └── caddy
│       └── Caddyfile
├── scripts
│   ├── configure-onlyoffice.sh
│   ├── configure-nextcloud-proxy.sh
│   ├── configure-ldap.sh
│   ├── init-storage.sh
│   ├── up.sh
│   ├── down.sh
│   ├── check-ready.sh
│   ├── backup.sh
│   ├── restore.sh
│   ├── purge.sh
│   ├── trust-local-ca.sh
│   ├── trust-local-ca-macos.sh
│   ├── trust-local-ca-linux.sh
│   └── trust-local-ca-windows.ps1
└── docs
    ├── architecture.md
    ├── runbook.md
    ├── setup-guide.md
    └── troubleshooting.md
```

## Quick Start (Ubuntu)

1. Install Docker Engine + Compose plugin.
2. Clone repo and create env file:
   ```bash
   git clone <your-repo-url> onlyoffice-nextcloud-stack
   cd onlyoffice-nextcloud-stack
   cp .env.example .env
   ```
3. Edit `.env` using one complete mode block in `.env.example`:
   - Mode A (default): HTTP over IP (`http://SERVER_IP:8080` and `http://SERVER_IP:8090`)
   - Mode B (optional): HTTPS with domain + Caddy
   - `ENABLE_CADDY=false` for HTTP mode, `ENABLE_CADDY=true` for HTTPS/proxy mode
   - set `ENABLE_LDAP=true` only when LDAP is ready and reachable
   - set strong secrets (`NEXTCLOUD_ADMIN_PASSWORD`, DB passwords, `ONLYOFFICE_JWT_SECRET`)
4. Start stack:
   ```bash
   ./scripts/up.sh
   ```
5. If using HTTPS local certs, trust local CA (run once per client machine):
   ```bash
   ./scripts/trust-local-ca.sh
   ```
6. Open:
   - HTTP mode: `http://<SERVER_IP>:8080` and `http://<SERVER_IP>:8090/healthcheck`
   - HTTPS mode: `https://<NEXTCLOUD_FQDN>` and `https://<ONLYOFFICE_FQDN>/healthcheck`
7. Run readiness check anytime:
   ```bash
   ./scripts/check-ready.sh
   ```

JWT secret generation:
```bash
openssl rand -hex 32
```
Set it in `.env`:
```text
ONLYOFFICE_JWT_SECRET=<generated-value>
```

LDAP note:
- If `ENABLE_LDAP=true`, `./scripts/up.sh` will auto-run LDAP configuration using values in `.env`.
- Do not commit real LDAP bind passwords into git.

See full steps in [docs/setup-guide.md](/Users/seker./onlyoffice-nextcloud-stack/docs/setup-guide.md).
Operations runbook: [docs/runbook.md](/Users/seker./onlyoffice-nextcloud-stack/docs/runbook.md)

## Access Paths (Important)

This stack can be reached in two ways:

1. Direct container ports (recommended for HTTP/IP demo):
   - Nextcloud: `http://<SERVER_IP>:<NEXTCLOUD_PORT>`
   - ONLYOFFICE: `http://<SERVER_IP>:<ONLYOFFICE_PORT>`
2. Through Caddy reverse proxy:
   - Caddy listens on `HTTP_PORT` and `HTTPS_PORT`
   - Caddy routes by host/domain (Host header), not by path only

What this means in practice:
- In HTTP demo mode, use direct ports `8080/8090` to avoid host-header confusion.
- Caddy is disabled by default in HTTP mode (`ENABLE_CADDY=false`).
- Enable Caddy only when needed (`ENABLE_CADDY=true`) for domain/proxy/HTTPS mode.
- If host `80/443` are already used by another service, change `HTTP_PORT` / `HTTPS_PORT` in `.env`.
- `APP_BIND_ADDRESS=0.0.0.0` allows LAN access; `127.0.0.1` allows local-only access.

## Scripts Reference

All scripts are in `scripts/` and support both HTTP (IP+ports) and HTTPS (domain+TLS).

### `./scripts/up.sh`

Purpose:
- End-to-end stack bootstrap and configuration.

What it does:
- prepares storage directories (`DATA_ROOT`)
- pulls images and starts containers
- applies ONLYOFFICE integration config in Nextcloud
- applies Nextcloud reverse-proxy settings
- restarts app services to load new runtime settings

Result:
- stack is running with URLs from `.env` (`NEXTCLOUD_PUBLIC_URL`, `ONLYOFFICE_PUBLIC_URL`)

When to run:
- first deployment
- after major `.env` changes

### `./scripts/down.sh`

Purpose:
- stop the whole stack cleanly.

What it does:
- runs `docker compose down --remove-orphans`

Result:
- containers and project network are stopped/removed

When to run:
- maintenance windows
- before host-level changes

### `./scripts/check-ready.sh`

Purpose:
- operational readiness check (quick health gate).

What it validates:
- container status
- external public endpoints are reachable (HTTP or HTTPS)
- internal service-to-service connectivity
- current ONLYOFFICE app config snapshot from Nextcloud

Result:
- pass/fail signal for deployment verification

When to run:
- after `up.sh`
- before demos
- after updates/restarts

### `./scripts/init-storage.sh`

Purpose:
- create all required bind-mount directories under `DATA_ROOT`.

What it creates:
- database, redis, nextcloud, caddy, onlyoffice data/log paths

Result:
- host filesystem layout is ready for Docker bind mounts

When to run:
- manually before first deploy (optional, `up.sh` already calls it)

### `./scripts/configure-onlyoffice.sh`

Purpose:
- configure Nextcloud <-> ONLYOFFICE integration settings.

What it sets:
- ONLYOFFICE public URL used by browser
- internal service URLs for container-to-container traffic
- JWT header and JWT secret sync from `.env`
- `allow_local_remote_servers` and internal trusted domain

Result:
- `.docx` editing path is wired and reproducible

When to run:
- after changing ONLYOFFICE URL/JWT values
- when editor integration breaks

### `./scripts/configure-nextcloud-proxy.sh`

Purpose:
- configure Nextcloud to behave correctly behind reverse proxy/TLS.

What it sets:
- `overwrite.cli.url`
- `overwritehost`
- `overwriteprotocol`
- trusted domains
- trusted proxies

Result:
- correct URL generation, protocol handling, and proxy trust behavior

When to run:
- after changing FQDN/public URL/proxy settings in `.env`

### `./scripts/configure-ldap.sh`

Purpose:
- configure Nextcloud LDAP/AD integration via `occ` (repeatable, no manual UI clicks).

What it sets:
- server, port, protocol (`LDAP_USE_SSL` / `LDAP_START_TLS`)
- bind DN/user + bind password
- base DN / users DN / groups DN
- TLS verify policy (`LDAP_TLS_SKIP_VERIFY`)
- group membership mapping (`LDAP_GROUP_MEMBER_ASSOC_ATTR`, default `member`)
- group searchable attrs (`LDAP_ATTRIBUTES_FOR_GROUP_SEARCH`, default `cn`)
- nested-group switch (`LDAP_NESTED_GROUPS`)
- default AD-oriented user/group/login filters

When it runs:
- automatically during `./scripts/up.sh` when `ENABLE_LDAP=true`
- manually when changing LDAP values:
  ```bash
  ./scripts/configure-ldap.sh
  ```

### `./scripts/backup.sh`

Purpose:
- create a restore-capable backup set.

What it backs up:
- MariaDB logical dump (`nextcloud.sql`)
- full `DATA_ROOT` archive (`data-root.tar.gz`)
- Nextcloud config/app snapshots

Result:
- timestamped backup folder in `BACKUP_ROOT`
- retention cleanup using `BACKUP_RETENTION_DAYS`

When to run:
- before upgrades
- scheduled daily (recommended)

### `./scripts/restore.sh <backup-folder>`

Purpose:
- restore stack data from a previous backup.

What it does:
- stops app services
- restores `DATA_ROOT` archive
- restores MariaDB dump
- starts stack again

Result:
- stack state rolled back to selected backup point

When to run:
- disaster recovery
- rollback after failed upgrade/change

### `./scripts/purge.sh`

Purpose:
- fully remove this stack from the current host.

What it removes:
- compose containers/networks/anonymous volumes/images
- `DATA_ROOT` directory from `.env` (default `./.data`)
- `BACKUP_ROOT` directory from `.env` (default `./backups`)

Safety:
- requires typing `PURGE` unless `--yes` is provided
- refuses to run if `DATA_ROOT` or `BACKUP_ROOT` is `/`

Useful options:
- `--yes` skip interactive confirmation
- `--remove-env` also delete `.env`

When to run:
- clean uninstall
- lab reset before fresh install

### `./scripts/trust-local-ca.sh`

Purpose:
- one command entrypoint for local CA trust setup.

What it does:
- detects OS and dispatches to platform-specific script
- macOS -> `trust-local-ca-macos.sh`
- Linux -> `trust-local-ca-linux.sh`
- Windows -> prints PowerShell command for `trust-local-ca-windows.ps1`

Result:
- local browser/system trusts Caddy local certs for `.localhost` URLs

When to run:
- once after first `up.sh` on each client machine used for demo/testing (HTTPS mode)

### `./scripts/trust-local-ca-macos.sh`

Purpose:
- trust Caddy local CA certificate in macOS System keychain.

What it does:
- reads local root cert from `DATA_ROOT`
- installs it as trusted root (requires `sudo`)

Result:
- browser trusts `https://cloud.localhost` and `https://docs.localhost`

When to run:
- once after first `up.sh` on macOS

### `./scripts/trust-local-ca-linux.sh`

Purpose:
- trust Caddy local CA certificate in Linux system trust store.

What it does:
- installs root cert into distro trust anchors and refreshes CA store

Result:
- browser/system trusts local HTTPS endpoints

When to run:
- once after first `up.sh` on Linux desktop/laptop clients

### `./scripts/trust-local-ca-windows.ps1`

Purpose:
- trust Caddy local CA certificate in Windows cert store.

What it does:
- imports root cert into `CurrentUser\Root`

Result:
- browser/system trusts local HTTPS endpoints

When to run:
- once after first `up.sh` on Windows clients

Local HTTPS notes:
- Default template uses local certificates (`local_certs`) and local hostnames (`cloud.localhost`, `docs.localhost`).
- Browser may warn on first visit until local CA trust is installed.
- This trust is client-side only and does not lock your server to local cert mode.
- For future real-domain HTTPS, set `CADDY_GLOBAL_OPTION=` (empty) and use real FQDN values in `.env`.

## HTTP Mode (Lab Only)

Default `.env.example` Mode A is already HTTP over IP + ports:

1. Edit `.env`:
   - `CADDY_SITE_SCHEME=http`
   - `CADDY_GLOBAL_OPTION=`
   - `PUBLIC_SERVER_IP=<SERVER_IP>`
   - `NEXTCLOUD_PORT=<YOUR_NEXTCLOUD_PORT>`
   - `ONLYOFFICE_PORT=<YOUR_ONLYOFFICE_PORT>`
   - if host `80/443` are occupied, also change `HTTP_PORT` / `HTTPS_PORT` (for caddy)
2. Recreate stack:
   ```bash
   docker compose down
   ./scripts/up.sh
   ```

Notes:
- HTTP mode is for local/internal lab only.
- Browser security and Nextcloud security checks are weaker in HTTP mode.
- If you only use `IP:8080/8090`, caddy `80/443` can be moved to free ports (for example `18080/18443`).

## Runtime Tuning (Config-Driven)

All are in `.env`:
- Persistent data root: `DATA_ROOT`
- Listener and ports: `APP_BIND_ADDRESS`, `NEXTCLOUD_PORT`, `ONLYOFFICE_PORT`
- HTTP quick host: `PUBLIC_SERVER_IP` (used to auto-build public URLs in HTTP mode)
- CPU limits: `DB_CPUS`, `REDIS_CPUS`, `NEXTCLOUD_CPUS`, `ONLYOFFICE_CPUS`
- Memory limits: `DB_MEM_LIMIT`, `REDIS_MEM_LIMIT`, `NEXTCLOUD_MEM_LIMIT`, `ONLYOFFICE_MEM_LIMIT`
- Container log rotation: `LOG_MAX_SIZE`, `LOG_MAX_FILE`
- Access URLs: `NEXTCLOUD_PUBLIC_URL`, `ONLYOFFICE_PUBLIC_URL`
- HTTPS-only fields: `NEXTCLOUD_FQDN`, `ONLYOFFICE_FQDN`, `ACME_EMAIL`, `CADDY_GLOBAL_OPTION`

## Common Pitfalls (Read Before Deploy)

- Public URL host/port mismatch -> Nextcloud trusted domain and ONLYOFFICE callback errors.
- JWT mismatch between Nextcloud app and ONLYOFFICE -> editor fails to open documents.
- VM has low RAM/CPU -> ONLYOFFICE service may restart or fail.
- Port already in use (`8080`, `8090`) -> change values in `.env`.
- ONLYOFFICE not reachable in browser -> `DocumentServerUrl` must be browser-reachable (host/IP), not container hostname.
- Disk grows unexpectedly -> tune `LOG_MAX_SIZE` and `LOG_MAX_FILE` in `.env`.

## Where Config Is Stored (No Black Box)

- Compose-level settings: repo files (`docker-compose.yml`, `.env`)
- Persistent data location: `${DATA_ROOT}` from `.env` (bind mounts)
- Nextcloud ONLYOFFICE app settings: Nextcloud DB (`oc_appconfig`)
- Nextcloud system settings: `/var/www/html/config/config.php` inside `nextcloud` volume

All runtime changes can be applied/reviewed with:
```bash
./scripts/init-storage.sh
./scripts/configure-onlyoffice.sh
./scripts/check-ready.sh
```
