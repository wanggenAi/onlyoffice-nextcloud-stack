#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NEXTCLOUD_FQDN_VALUE="$(grep -E '^NEXTCLOUD_FQDN=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
ONLYOFFICE_FQDN_VALUE="$(grep -E '^ONLYOFFICE_FQDN=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
CADDY_SITE_SCHEME_VALUE="$(grep -E '^CADDY_SITE_SCHEME=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
CADDY_SITE_SCHEME_VALUE="${CADDY_SITE_SCHEME_VALUE:-https}"
NEXTCLOUD_PUBLIC_URL_VALUE="$(grep -E '^NEXTCLOUD_PUBLIC_URL=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
ONLYOFFICE_PUBLIC_URL_VALUE="$(grep -E '^ONLYOFFICE_PUBLIC_URL=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
PUBLIC_SERVER_IP_VALUE="$(grep -E '^PUBLIC_SERVER_IP=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
NEXTCLOUD_PORT_VALUE="$(grep -E '^NEXTCLOUD_PORT=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
ONLYOFFICE_PORT_VALUE="$(grep -E '^ONLYOFFICE_PORT=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
NEXTCLOUD_PORT_VALUE="${NEXTCLOUD_PORT_VALUE:-8080}"
ONLYOFFICE_PORT_VALUE="${ONLYOFFICE_PORT_VALUE:-8090}"
ENABLE_LDAP_VALUE="$(grep -E '^ENABLE_LDAP=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
ENABLE_LDAP_VALUE="$(printf "%s" "${ENABLE_LDAP_VALUE:-false}" | tr '[:upper:]' '[:lower:]')"

if [ -z "${NEXTCLOUD_PUBLIC_URL_VALUE}" ]; then
  if [ -n "${PUBLIC_SERVER_IP_VALUE}" ] && [ "${CADDY_SITE_SCHEME_VALUE}" = "http" ]; then
    NEXTCLOUD_PUBLIC_URL_VALUE="http://${PUBLIC_SERVER_IP_VALUE}:${NEXTCLOUD_PORT_VALUE}"
  else
    if [ -z "${NEXTCLOUD_FQDN_VALUE}" ]; then
      echo "Missing NEXTCLOUD_PUBLIC_URL and NEXTCLOUD_FQDN in .env"
      exit 1
    fi
    NEXTCLOUD_PUBLIC_URL_VALUE="${CADDY_SITE_SCHEME_VALUE}://${NEXTCLOUD_FQDN_VALUE}"
  fi
fi

if [ -z "${ONLYOFFICE_PUBLIC_URL_VALUE}" ]; then
  if [ -n "${PUBLIC_SERVER_IP_VALUE}" ] && [ "${CADDY_SITE_SCHEME_VALUE}" = "http" ]; then
    ONLYOFFICE_PUBLIC_URL_VALUE="http://${PUBLIC_SERVER_IP_VALUE}:${ONLYOFFICE_PORT_VALUE}"
  else
    if [ -z "${ONLYOFFICE_FQDN_VALUE}" ]; then
      echo "Missing ONLYOFFICE_PUBLIC_URL and ONLYOFFICE_FQDN in .env"
      exit 1
    fi
    ONLYOFFICE_PUBLIC_URL_VALUE="${CADDY_SITE_SCHEME_VALUE}://${ONLYOFFICE_FQDN_VALUE}"
  fi
fi

echo "[1/4] Container status"
docker compose ps

echo "[2/4] Edge checks"
curl -fsS "${ONLYOFFICE_PUBLIC_URL_VALUE%/}/healthcheck"
echo
curl -fsS "${NEXTCLOUD_PUBLIC_URL_VALUE%/}/status.php" >/dev/null
echo "Nextcloud status endpoint reachable: ok"

echo "[3/4] Internal checks"
docker compose exec nextcloud sh -lc "curl -fsS http://onlyoffice-documentserver/healthcheck"
echo
docker compose exec onlyoffice-documentserver bash -lc "curl -fsS http://nextcloud-app/status.php" >/dev/null
echo "nextcloud-app reachable from ONLYOFFICE: ok"

echo "[4/5] ONLYOFFICE app config snapshot"
docker compose exec -u www-data nextcloud php occ config:list onlyoffice | sed -n '1,120p'

echo "[5/5] LDAP status"
if [ "${ENABLE_LDAP_VALUE}" = "true" ]; then
  docker compose exec -u www-data nextcloud php occ app:list | grep -E '^  - user_ldap:' || true
  LDAP_CONFIG_ID_VALUE="$(grep -E '^LDAP_CONFIG_ID=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  LDAP_CONFIG_ID_VALUE="${LDAP_CONFIG_ID_VALUE:-s01}"
  docker compose exec -u www-data nextcloud php occ ldap:show-config "${LDAP_CONFIG_ID_VALUE}" | sed -n '1,120p' || true
else
  echo "LDAP disabled (ENABLE_LDAP=false)."
fi

echo
echo "Readiness check passed."
