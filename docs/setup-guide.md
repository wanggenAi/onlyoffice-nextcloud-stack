# Setup Guide (Ubuntu + Docker Compose)

This guide targets the first milestone: working Nextcloud + ONLYOFFICE integration.

## 1. Install Docker (Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
newgrp docker
docker --version
docker compose version
```

## 2. Prepare Project

```bash
git clone <your-repo-url> onlyoffice-nextcloud-stack
cd onlyoffice-nextcloud-stack
cp .env.example .env
```

Edit `.env`:
- Choose one full mode block from `.env.example`:
  - Mode A (default): HTTP over IP + ports (`8080`/`8090`)
  - Mode B (optional): HTTPS with domain + Caddy
- Replace all `change-me-*` values with strong secrets
- Set `DATA_ROOT` (persistent data path, e.g. `./.data` or `/opt/onlyoffice-nextcloud/data`)
- Tune resource limits for your VM: `*_CPUS`, `*_MEM_LIMIT`
- Tune log rotation: `LOG_MAX_SIZE`, `LOG_MAX_FILE`

Default demo mode (HTTP over IP) values are:
- `APP_BIND_ADDRESS=0.0.0.0`
- `NEXTCLOUD_PORT=8080`
- `ONLYOFFICE_PORT=8090`
- `PUBLIC_SERVER_IP=<SERVER_IP>`
- `ENABLE_CADDY=false`

In HTTP mode, scripts auto-derive:
- `NEXTCLOUD_PUBLIC_URL=http://<PUBLIC_SERVER_IP>:<NEXTCLOUD_PORT>`
- `ONLYOFFICE_PUBLIC_URL=http://<PUBLIC_SERVER_IP>:<ONLYOFFICE_PORT>`

If using HTTPS local certificates, trust CA on your client machine:
```bash
./scripts/trust-local-ca.sh
```

Future real-domain cutover:
- set real FQDN/public URL values
- set `ENABLE_CADDY=true`
- set `CADDY_GLOBAL_OPTION=` (empty) so Caddy uses ACME public certs

Generate JWT secret:
```bash
openssl rand -hex 32
```
Set result to `.env`:
```text
ONLYOFFICE_JWT_SECRET=<generated-value>
```

## 3. Start Stack

Recommended (repeatable):
```bash
./scripts/up.sh
```

Expected:
- `nextcloud-app` running
- `onlyoffice-documentserver` running
- `nextcloud-db` running
- `nextcloud-redis` running

## 4. Bootstrap Nextcloud

Open in browser:
- HTTP mode: `http://<SERVER_IP>:8080`
- HTTPS mode: `https://<NEXTCLOUD_FQDN>`

If auto-bootstrap env vars worked, admin account is already created.
If you still see install page:
- choose MariaDB
- database host: `db`
- database/user/password from `.env`

## 5. Verify ONLYOFFICE Docs

Open:
- HTTP mode: `http://<SERVER_IP>:8090/healthcheck`
- HTTPS mode: `https://<ONLYOFFICE_FQDN>/healthcheck`

Expected response:
- `true`

## 6. Integrate ONLYOFFICE in Nextcloud

Use:
```bash
./scripts/configure-onlyoffice.sh
```

The script auto-handles:
- Install/enable Nextcloud ONLYOFFICE app
- URL wiring for browser + container-internal communication
- JWT header + secret sync from `.env`
- Local remote server allowance + trusted domain for internal service name

If Nextcloud rejects local/private URL, run:
```bash
docker compose exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --value=true --type=bool
```
Then save ONLYOFFICE settings again.

What this script configures:
- `onlyoffice.DocumentServerUrl=<ONLYOFFICE_PUBLIC_URL>` (browser-reachable)
- `onlyoffice.DocumentServerInternalUrl=http://onlyoffice-documentserver/`
- `onlyoffice.StorageUrl=http://nextcloud-app/`
- `onlyoffice.jwt_header=AuthorizationJwt` (matches DocumentServer container env)
- `allow_local_remote_servers=true`
- `trusted_domains` includes `nextcloud-app`

## 6.1 Readiness Check

Run anytime:
```bash
./scripts/check-ready.sh
```

This validates:
- container status
- `ONLYOFFICE /healthcheck`
- container-to-container reachability
- effective Nextcloud ONLYOFFICE config snapshot

## 7. Milestone Test

1. Upload a `.docx` file into Nextcloud
2. Click file to open
3. ONLYOFFICE editor should load in browser
4. Edit text and save
5. Reopen file to verify persistence

## Optional (Recommended soon, not v1-required)

- Add UFW rules for ports in use
- Add periodic backup script for DB + volumes
- Add reverse proxy + HTTPS for internet exposure

## Runtime Controls

- Volume/data root: `DATA_ROOT`
- CPU limits: `DB_CPUS`, `REDIS_CPUS`, `NEXTCLOUD_CPUS`, `ONLYOFFICE_CPUS`
- Memory limits: `DB_MEM_LIMIT`, `REDIS_MEM_LIMIT`, `NEXTCLOUD_MEM_LIMIT`, `ONLYOFFICE_MEM_LIMIT`
- Container log rotation: `LOG_MAX_SIZE`, `LOG_MAX_FILE`

Daily backup:
```bash
./scripts/backup.sh
```

Disaster restore:
```bash
./scripts/restore.sh <backup-folder-path>
```

Detailed operations:
- see [docs/runbook.md](/Users/seker./onlyoffice-nextcloud-stack/docs/runbook.md)
