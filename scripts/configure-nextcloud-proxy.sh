#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NEXTCLOUD_PUBLIC_URL_VALUE=""
NEXTCLOUD_FQDN_VALUE=""
NEXTCLOUD_TRUSTED_PROXIES_VALUE="172.16.0.0/12"
CADDY_SITE_SCHEME_VALUE="https"
PUBLIC_SERVER_IP_VALUE=""
NEXTCLOUD_PORT_VALUE=""

if [ -f .env ]; then
  NEXTCLOUD_PUBLIC_URL_VALUE="$(grep -E '^NEXTCLOUD_PUBLIC_URL=' .env | tail -n1 | cut -d= -f2- || true)"
  NEXTCLOUD_FQDN_VALUE="$(grep -E '^NEXTCLOUD_FQDN=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_CADDY_SITE_SCHEME="$(grep -E '^CADDY_SITE_SCHEME=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_PUBLIC_SERVER_IP="$(grep -E '^PUBLIC_SERVER_IP=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_NEXTCLOUD_PORT="$(grep -E '^NEXTCLOUD_PORT=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_TRUSTED_PROXIES="$(grep -E '^NEXTCLOUD_TRUSTED_PROXIES=' .env | tail -n1 | cut -d= -f2- || true)"
  if [ -n "${ENV_CADDY_SITE_SCHEME}" ]; then
    CADDY_SITE_SCHEME_VALUE="${ENV_CADDY_SITE_SCHEME}"
  fi
  if [ -n "${ENV_PUBLIC_SERVER_IP}" ]; then
    PUBLIC_SERVER_IP_VALUE="${ENV_PUBLIC_SERVER_IP}"
  fi
  if [ -n "${ENV_NEXTCLOUD_PORT}" ]; then
    NEXTCLOUD_PORT_VALUE="${ENV_NEXTCLOUD_PORT}"
  fi
  if [ -n "${ENV_TRUSTED_PROXIES}" ]; then
    NEXTCLOUD_TRUSTED_PROXIES_VALUE="${ENV_TRUSTED_PROXIES}"
  fi
fi

if [ -z "${NEXTCLOUD_PORT_VALUE}" ]; then
  NEXTCLOUD_PORT_VALUE="8080"
fi

if [ -z "${NEXTCLOUD_PUBLIC_URL_VALUE}" ]; then
  if [ -n "${PUBLIC_SERVER_IP_VALUE}" ] && [ "${CADDY_SITE_SCHEME_VALUE}" = "http" ]; then
    NEXTCLOUD_PUBLIC_URL_VALUE="http://${PUBLIC_SERVER_IP_VALUE}:${NEXTCLOUD_PORT_VALUE}"
    echo "NEXTCLOUD_PUBLIC_URL not set, using derived HTTP URL: ${NEXTCLOUD_PUBLIC_URL_VALUE}"
  else
    if [ -z "${NEXTCLOUD_FQDN_VALUE}" ]; then
      echo "Missing NEXTCLOUD_PUBLIC_URL. Set NEXTCLOUD_PUBLIC_URL, or set NEXTCLOUD_FQDN (and optionally PUBLIC_SERVER_IP for HTTP mode)."
      exit 1
    fi
    NEXTCLOUD_PUBLIC_URL_VALUE="${CADDY_SITE_SCHEME_VALUE}://${NEXTCLOUD_FQDN_VALUE}"
    echo "NEXTCLOUD_PUBLIC_URL not set, using derived FQDN URL: ${NEXTCLOUD_PUBLIC_URL_VALUE}"
  fi
fi

NEXTCLOUD_SCHEME="$(printf "%s" "${NEXTCLOUD_PUBLIC_URL_VALUE}" | awk -F:// '{print $1}')"
NEXTCLOUD_HOSTPORT="$(printf "%s" "${NEXTCLOUD_PUBLIC_URL_VALUE}" | awk -F:// '{print $2}' | cut -d/ -f1)"
if [ -z "${NEXTCLOUD_FQDN_VALUE}" ]; then
  NEXTCLOUD_FQDN_VALUE="$(printf "%s" "${NEXTCLOUD_HOSTPORT}" | cut -d: -f1)"
  echo "NEXTCLOUD_FQDN not set, using host from NEXTCLOUD_PUBLIC_URL: ${NEXTCLOUD_FQDN_VALUE}"
fi

echo "[1/4] Setting overwrite URL options..."
docker compose exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="${NEXTCLOUD_PUBLIC_URL_VALUE}"
docker compose exec -u www-data nextcloud php occ config:system:set overwritehost --value="${NEXTCLOUD_HOSTPORT}"
docker compose exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="${NEXTCLOUD_SCHEME}"

echo "[2/4] Ensuring trusted domain includes configured FQDN..."
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 10 --value="${NEXTCLOUD_FQDN_VALUE}"

echo "[3/4] Setting trusted proxies..."
index=0
for proxy in ${NEXTCLOUD_TRUSTED_PROXIES_VALUE}; do
  docker compose exec -u www-data nextcloud php occ config:system:set trusted_proxies "${index}" --value="${proxy}"
  index=$((index + 1))
done

echo "[4/4] Snapshot:"
docker compose exec -u www-data nextcloud php occ config:system:get overwrite.cli.url
docker compose exec -u www-data nextcloud php occ config:system:get overwritehost
docker compose exec -u www-data nextcloud php occ config:system:get overwriteprotocol
docker compose exec -u www-data nextcloud php occ config:system:get trusted_proxies
docker compose exec -u www-data nextcloud php occ config:system:get trusted_domains

echo "Nextcloud reverse-proxy settings applied."
