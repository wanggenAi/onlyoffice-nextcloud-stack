#!/usr/bin/env bash
set -euo pipefail

# Transparent, repeatable ONLYOFFICE integration config for this stack.
# This script writes Nextcloud app/system config via occ (as www-data).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ONLYOFFICE_PUBLIC_URL_VALUE=""
CADDY_SITE_SCHEME_VALUE="https"
ONLYOFFICE_FQDN_VALUE=""
PUBLIC_SERVER_IP_VALUE=""
ONLYOFFICE_PORT_VALUE=""
if [ -f .env ]; then
  ENV_CADDY_SITE_SCHEME="$(grep -E '^CADDY_SITE_SCHEME=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_ONLYOFFICE_FQDN="$(grep -E '^ONLYOFFICE_FQDN=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_PUBLIC_URL="$(grep -E '^ONLYOFFICE_PUBLIC_URL=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_PUBLIC_SERVER_IP="$(grep -E '^PUBLIC_SERVER_IP=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_ONLYOFFICE_PORT="$(grep -E '^ONLYOFFICE_PORT=' .env | tail -n1 | cut -d= -f2- || true)"
  if [ -n "${ENV_CADDY_SITE_SCHEME}" ]; then CADDY_SITE_SCHEME_VALUE="${ENV_CADDY_SITE_SCHEME}"; fi
  if [ -n "${ENV_ONLYOFFICE_FQDN}" ]; then ONLYOFFICE_FQDN_VALUE="${ENV_ONLYOFFICE_FQDN}"; fi
  if [ -n "${ENV_PUBLIC_URL}" ]; then ONLYOFFICE_PUBLIC_URL_VALUE="${ENV_PUBLIC_URL}"; fi
  if [ -n "${ENV_PUBLIC_SERVER_IP}" ]; then PUBLIC_SERVER_IP_VALUE="${ENV_PUBLIC_SERVER_IP}"; fi
  if [ -n "${ENV_ONLYOFFICE_PORT}" ]; then ONLYOFFICE_PORT_VALUE="${ENV_ONLYOFFICE_PORT}"; fi
fi
if [ -z "${ONLYOFFICE_PORT_VALUE}" ]; then
  ONLYOFFICE_PORT_VALUE="8090"
fi

if [ -n "${ONLYOFFICE_PUBLIC_URL_VALUE}" ]; then
  PUBLIC_DOCS_URL="${ONLYOFFICE_PUBLIC_URL_VALUE%/}/"
elif [ -n "${PUBLIC_SERVER_IP_VALUE}" ] && [ "${CADDY_SITE_SCHEME_VALUE}" = "http" ]; then
  PUBLIC_DOCS_URL="http://${PUBLIC_SERVER_IP_VALUE}:${ONLYOFFICE_PORT_VALUE}/"
  echo "ONLYOFFICE_PUBLIC_URL not set, using derived HTTP URL: ${PUBLIC_DOCS_URL}"
else
  if [ -z "${ONLYOFFICE_FQDN_VALUE}" ]; then
    echo "Missing ONLYOFFICE_PUBLIC_URL. Set ONLYOFFICE_PUBLIC_URL, or set ONLYOFFICE_FQDN (and optionally PUBLIC_SERVER_IP for HTTP mode)."
    exit 1
  fi
  PUBLIC_DOCS_URL="${CADDY_SITE_SCHEME_VALUE}://${ONLYOFFICE_FQDN_VALUE}/"
  echo "ONLYOFFICE_PUBLIC_URL not set, using derived FQDN URL: ${PUBLIC_DOCS_URL}"
fi
ONLYOFFICE_JWT_SECRET_VALUE=""
if [ -f .env ]; then
  ONLYOFFICE_JWT_SECRET_VALUE="$(grep -E '^ONLYOFFICE_JWT_SECRET=' .env | tail -n1 | cut -d= -f2- || true)"
fi

echo "[1/7] Checking containers..."
docker compose ps

echo "[2/7] Ensuring ONLYOFFICE app is enabled in Nextcloud..."
if ! docker compose exec -u www-data nextcloud php occ app:list | grep -qE '^  - onlyoffice: enabled'; then
  if docker compose exec -u www-data nextcloud php occ app:list | grep -qE '^  - onlyoffice:'; then
    docker compose exec -u www-data nextcloud php occ app:enable onlyoffice
  else
    docker compose exec -u www-data nextcloud php occ app:install onlyoffice
    docker compose exec -u www-data nextcloud php occ app:enable onlyoffice
  fi
fi

echo "[3/7] Configuring ONLYOFFICE app URLs..."
docker compose exec -u www-data nextcloud php occ config:app:set onlyoffice DocumentServerUrl --value="${PUBLIC_DOCS_URL}"
docker compose exec -u www-data nextcloud php occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://onlyoffice-documentserver/"
docker compose exec -u www-data nextcloud php occ config:app:set onlyoffice StorageUrl --value="http://nextcloud-app/"
docker compose exec -u www-data nextcloud php occ config:app:set onlyoffice jwt_header --value="AuthorizationJwt"
docker compose exec -u www-data nextcloud php occ config:app:set onlyoffice verify_peer_off --value=true

if [ -n "${ONLYOFFICE_JWT_SECRET_VALUE}" ]; then
  echo "[4/7] Syncing JWT secret from .env into Nextcloud app config..."
  docker compose exec -u www-data nextcloud php occ config:app:set onlyoffice jwt_secret --value="${ONLYOFFICE_JWT_SECRET_VALUE}"
else
  echo "[4/7] WARNING: ONLYOFFICE_JWT_SECRET not found in .env, skipping jwt_secret sync."
fi

echo "[5/7] Allowing local remote servers (required for container-internal URLs)..."
docker compose exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --value=true --type=bool

echo "[6/7] Adding internal service name to trusted domains..."
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 3 --value=nextcloud-app
docker compose exec -u www-data nextcloud php occ config:app:delete onlyoffice settings_error || true

echo "[7/7] Current effective values:"
docker compose exec -u www-data nextcloud php occ config:app:get onlyoffice DocumentServerUrl
docker compose exec -u www-data nextcloud php occ config:app:get onlyoffice DocumentServerInternalUrl
docker compose exec -u www-data nextcloud php occ config:app:get onlyoffice StorageUrl
docker compose exec -u www-data nextcloud php occ config:app:get onlyoffice jwt_header
docker compose exec -u www-data nextcloud php occ config:app:get onlyoffice verify_peer_off
docker compose exec -u www-data nextcloud php occ config:system:get allow_local_remote_servers
docker compose exec -u www-data nextcloud php occ config:system:get trusted_domains

cat <<'EOF'

Done.
If this is your first run, open Nextcloud and verify:
1) ONLYOFFICE app settings page shows no error
2) Upload and open a .docx file

EOF
