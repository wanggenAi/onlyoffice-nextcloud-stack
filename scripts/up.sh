#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo ".env not found. Create it from .env.example first."
  exit 1
fi

DATA_ROOT_VALUE="$(grep -E '^DATA_ROOT=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
DATA_ROOT_VALUE="${DATA_ROOT_VALUE:-./.data}"
ENABLE_CADDY_VALUE="$(grep -E '^ENABLE_CADDY=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
ENABLE_CADDY_VALUE="${ENABLE_CADDY_VALUE:-false}"
CADDY_SITE_SCHEME_VALUE="$(grep -E '^CADDY_SITE_SCHEME=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
CADDY_SITE_SCHEME_VALUE="${CADDY_SITE_SCHEME_VALUE:-http}"

if [ "${CADDY_SITE_SCHEME_VALUE}" = "https" ] && [ "${ENABLE_CADDY_VALUE}" != "true" ]; then
  echo "Invalid config: HTTPS mode requires ENABLE_CADDY=true"
  exit 1
fi

echo "[1/6] Preparing storage directories..."
./scripts/init-storage.sh
mkdir -p "${DATA_ROOT_VALUE}/caddy/data" "${DATA_ROOT_VALUE}/caddy/config"

echo "[2/6] Pulling images..."
docker compose pull

echo "[3/6] Starting stack..."
if [ "${ENABLE_CADDY_VALUE}" = "true" ]; then
  echo "ENABLE_CADDY=true -> starting with proxy profile"
  docker compose --profile proxy up -d
else
  echo "ENABLE_CADDY=false -> starting core services only (no caddy)"
  docker compose up -d
fi

echo "[4/6] Waiting for services to become healthy..."
for i in $(seq 1 90); do
  nc_state="$(docker inspect -f '{{.State.Health.Status}}' nextcloud-app 2>/dev/null || echo starting)"
  oo_state="$(docker inspect -f '{{.State.Health.Status}}' onlyoffice-documentserver 2>/dev/null || echo starting)"
  db_state="$(docker inspect -f '{{.State.Health.Status}}' nextcloud-db 2>/dev/null || echo starting)"
  rd_state="$(docker inspect -f '{{.State.Health.Status}}' nextcloud-redis 2>/dev/null || echo starting)"

  if [ "${nc_state}" = "healthy" ] && [ "${oo_state}" = "healthy" ] && [ "${db_state}" = "healthy" ] && [ "${rd_state}" = "healthy" ]; then
    echo "All core services are healthy."
    break
  fi

  if [ "$i" -eq 90 ]; then
    echo "Timed out waiting for health checks."
    docker compose ps
    docker compose logs --tail=120 nextcloud onlyoffice-documentserver db redis
    exit 1
  fi
  sleep 2
done

echo "[5/6] Configuring Nextcloud + ONLYOFFICE integration..."
./scripts/configure-onlyoffice.sh
./scripts/configure-nextcloud-proxy.sh

echo "[6/6] Restarting app services to apply config..."
if [ "${ENABLE_CADDY_VALUE}" = "true" ]; then
  docker compose restart nextcloud onlyoffice-documentserver caddy
else
  docker compose restart nextcloud onlyoffice-documentserver
fi

echo "[7/7] Final status:"
docker compose ps

cat <<'EOF'

Stack is up.
Verify:
1) <NEXTCLOUD_PUBLIC_URL> (or derived from mode + FQDN)
2) <ONLYOFFICE_PUBLIC_URL>/healthcheck (or derived from mode + FQDN)
3) Open/edit a .docx in Nextcloud

EOF
