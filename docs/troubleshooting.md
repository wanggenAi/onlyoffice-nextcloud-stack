# Troubleshooting Checklist

Use this checklist when the stack does not work as expected.

## 0. Fast pre-check (recommended first)

```bash
./scripts/check-ready.sh
```

If this fails, then continue with the sections below.

## 1. Containers not running

```bash
docker compose ps
docker compose logs --tail=200
```

If one container exits repeatedly:
- Check env values in `.env`
- Confirm ports are free
- Check VM RAM/CPU (ONLYOFFICE can fail on small VMs)

If you are in HTTP mode, `caddy` may be absent by design (`ENABLE_CADDY=false`).

## 2. Port conflict

Symptom:
- `bind: address already in use`

Check:
```bash
sudo ss -tulpn | rg ':8080|:8090|:80|:443'
```

Fix:
- Change `NEXTCLOUD_PORT` or `ONLYOFFICE_PORT` in `.env` (direct HTTP access)
- If using Caddy, also adjust `HTTP_PORT` / `HTTPS_PORT`
- Restart stack: `docker compose up -d`

## 2.1 Disk usage grows too fast (logs)

Check container log size:
```bash
docker ps --format '{{.Names}}' | xargs -I{} sh -c 'echo "### {}"; docker inspect {} --format "{{.LogPath}}" | xargs ls -lh'
```

Fix:
- Lower `.env` values:
  - `LOG_MAX_SIZE` (example: `5m`)
  - `LOG_MAX_FILE` (example: `3`)
- Recreate containers:
  ```bash
  docker compose up -d --force-recreate
  ```

## 2.2 VM runs out of RAM/CPU

Fix:
- Reduce service limits in `.env`:
  - `NEXTCLOUD_CPUS`, `NEXTCLOUD_MEM_LIMIT`
  - `ONLYOFFICE_CPUS`, `ONLYOFFICE_MEM_LIMIT`
  - `DB_CPUS`, `DB_MEM_LIMIT`
  - `REDIS_CPUS`, `REDIS_MEM_LIMIT`
- Restart:
  ```bash
  docker compose up -d --force-recreate
  ```

## 3. Nextcloud says “Access through untrusted domain”

Cause:
- Access host/IP not in Nextcloud trusted domains

Fix:
1. Update `.env`:
   - HTTP mode: `NEXTCLOUD_TRUSTED_DOMAINS=<PUBLIC_SERVER_IP>`
   - HTTPS mode: `NEXTCLOUD_TRUSTED_DOMAINS=<NEXTCLOUD_FQDN>`
2. Apply proxy/URL config again:
   ```bash
   ./scripts/configure-nextcloud-proxy.sh
   ```
3. Recreate Nextcloud container (if needed):
   ```bash
   docker compose up -d --force-recreate nextcloud
   ```

## 4. ONLYOFFICE healthcheck fails

Check:
```bash
curl -sS http://127.0.0.1:${ONLYOFFICE_PORT}/healthcheck
docker compose logs onlyoffice-documentserver --tail=200
```

Possible causes:
- Container still starting
- Low memory
- Port mapping wrong

## 5. Nextcloud cannot connect to ONLYOFFICE

Symptoms:
- Error while saving ONLYOFFICE settings
- `.docx` does not open in editor

Checks:
```bash
docker compose exec nextcloud sh -lc "curl -I http://onlyoffice-documentserver/"
docker compose logs nextcloud --tail=200
docker compose logs onlyoffice-documentserver --tail=200
```

Common fixes:
- Use internal URL exactly: `http://onlyoffice-documentserver/`
- Ensure external/public URL matches current mode:
  - HTTP mode: `http://<PUBLIC_SERVER_IP>:<ONLYOFFICE_PORT>/`
  - HTTPS mode: `https://<ONLYOFFICE_FQDN>/`
- Ensure JWT secret is identical on both sides
- Re-save ONLYOFFICE app settings in Nextcloud

If Nextcloud blocks local/private addresses, set:
```bash
docker compose exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --value=true --type=bool
```

## 6. JWT-related document open errors

Symptoms:
- `Download failed` / token / signature errors

Fix:
1. Set a strong `ONLYOFFICE_JWT_SECRET` in `.env`
2. `docker compose up -d --force-recreate onlyoffice-documentserver`
3. In Nextcloud ONLYOFFICE settings, paste the same secret
4. Retry opening `.docx`

## 7. Networking debug inside Docker network

Inspect network:
```bash
docker network ls
docker network inspect onlyoffice-nextcloud-stack_collaboration
```

Validate DNS resolution:
```bash
docker compose exec nextcloud getent hosts onlyoffice-documentserver
```

If DNS fails:
- Ensure both services are in same Compose network
- Recreate stack:
  ```bash
  docker compose down
  docker compose up -d
  ```

## 8. Data reset (development only, destructive)

```bash
docker compose down -v
docker compose up -d
```

Warning:
- This removes DB/files/cache volumes.
- Do not run on production data.

## 9. TLS / domain issues

This section only applies when `ENABLE_CADDY=true`.

Check Caddy logs:
```bash
docker compose --profile proxy logs caddy --tail=200
```

Common causes:
- DNS does not point to this host
- Ports `80/443` blocked by firewall/cloud security group
- Invalid `NEXTCLOUD_FQDN` / `ONLYOFFICE_FQDN` values in `.env`

## 10. LDAP / AD login not working

Symptoms:
- LDAP users cannot log in to Nextcloud
- `occ ldap:test-config s01` fails

Checks:
```bash
docker compose exec -u www-data nextcloud php occ app:list | grep user_ldap
docker compose exec -u www-data nextcloud php occ ldap:show-config s01
docker compose exec -u www-data nextcloud php occ ldap:test-config s01
```

Common fixes:
- Confirm `.env` values: `LDAP_HOST`, `LDAP_PORT`, `LDAP_BIND_USER`, `LDAP_BIND_PASSWORD`, `LDAP_BASE_DN`
- If using LDAPS with self-signed cert in lab, set `LDAP_TLS_SKIP_VERIFY=true`
- Do not set both `LDAP_USE_SSL=true` and `LDAP_START_TLS=true`
- If users appear but groups are empty, verify:
  - `LDAP_GROUP_MEMBER_ASSOC_ATTR=member`
  - `LDAP_ATTRIBUTES_FOR_GROUP_SEARCH=cn`
- Re-apply config:
  ```bash
  ./scripts/configure-ldap.sh
  ```
- Ensure network reachability from container to LDAP server/port
