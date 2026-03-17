# Operations Runbook

This runbook is for the unified stack in `docker-compose.yml`.

## 1. First Deployment

```bash
cp .env.example .env
# edit .env (Mode A HTTP default or Mode B HTTPS, strong secrets, limits)
./scripts/up.sh
./scripts/check-ready.sh
```

Manual validation:
- HTTP mode: `http://<PUBLIC_SERVER_IP>:<NEXTCLOUD_PORT>`
- HTTP mode: `http://<PUBLIC_SERVER_IP>:<ONLYOFFICE_PORT>/healthcheck` returns `true`
- HTTPS mode: `https://<NEXTCLOUD_FQDN>`
- HTTPS mode: `https://<ONLYOFFICE_FQDN>/healthcheck` returns `true`
- Upload/open/edit `.docx` in Nextcloud

## 2. Operational Commands

Start:
```bash
./scripts/up.sh
```

Stop:
```bash
./scripts/down.sh
```

Status:
```bash
docker compose ps
```

Logs:
```bash
docker compose logs -f nextcloud onlyoffice-documentserver
# if ENABLE_CADDY=true:
docker compose --profile proxy logs -f caddy
```

Re-apply LDAP config (when LDAP values changed):
```bash
./scripts/configure-ldap.sh
```

## 3. Backup

Run backup:
```bash
./scripts/backup.sh
```

Output:
- `${BACKUP_ROOT}/<timestamp>/nextcloud.sql`
- `${BACKUP_ROOT}/<timestamp>/data-root.tar.gz`
- config snapshots

Retention:
- controlled by `BACKUP_RETENTION_DAYS` in `.env`

## 4. Restore (Disaster Recovery)

```bash
./scripts/restore.sh <backup-folder-path>
```

Notes:
- destructive operation
- requires confirmation (`YES`)
- restores both DB and data root

## 4.1 Full Uninstall (Destructive)

```bash
./scripts/purge.sh
```

Non-interactive:
```bash
./scripts/purge.sh --yes
```

Also remove `.env`:
```bash
./scripts/purge.sh --yes --remove-env
```

## 5. Rolling Update

```bash
docker compose pull
./scripts/up.sh
```

Alternative manual path:
```bash
docker compose pull
docker compose up -d
# if ENABLE_CADDY=true:
docker compose --profile proxy up -d
./scripts/configure-onlyoffice.sh
./scripts/configure-nextcloud-proxy.sh
./scripts/check-ready.sh
```

## 6. Quick Incident Playbook

### A) ONLYOFFICE cannot be reached
1. `./scripts/check-ready.sh`
2. Verify `DocumentServerUrl` matches your mode:
   - HTTP mode -> `http://<PUBLIC_SERVER_IP>:<ONLYOFFICE_PORT>/`
   - HTTPS mode -> `https://<ONLYOFFICE_FQDN>/`
3. Verify internal URLs stay container hostnames:
   - `DocumentServerInternalUrl=http://onlyoffice-documentserver/`
   - `StorageUrl=http://nextcloud-app/`
4. Check JWT secret consistency
5. Re-apply config:
   ```bash
   ./scripts/configure-onlyoffice.sh
   ./scripts/configure-nextcloud-proxy.sh
   ```
6. Restart app services:
   ```bash
   docker compose restart nextcloud onlyoffice-documentserver
   # if ENABLE_CADDY=true:
   docker compose --profile proxy restart caddy
   ```

### B) TLS issuance fails
Applies only when `ENABLE_CADDY=true` and `CADDY_SITE_SCHEME=https`.

1. Verify DNS A records point to server
2. Ensure ports `80/443` are reachable from internet
3. Check Caddy logs:
   ```bash
   docker compose --profile proxy logs caddy --tail=200
   ```

### C) Disk pressure
1. `df -h`
2. Confirm log rotation values (`LOG_MAX_SIZE`, `LOG_MAX_FILE`)
3. Trigger backup cleanup or increase disk

### D) LDAP login/import issues
1. Ensure LDAP server is reachable from Nextcloud container:
   ```bash
   docker compose exec nextcloud sh -lc "apt-get update >/dev/null 2>&1 || true; apt-get install -y ldap-utils >/dev/null 2>&1 || true; nc -zv <LDAP_HOST> <LDAP_PORT>"
   ```
2. Re-apply LDAP config:
   ```bash
   ./scripts/configure-ldap.sh
   ```
3. Test config id (default `s01`):
   ```bash
   docker compose exec -u www-data nextcloud php occ ldap:test-config s01
   ```
