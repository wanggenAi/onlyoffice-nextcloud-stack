#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo ".env not found. Create it from .env.example first."
  exit 1
fi

read_env() {
  local key="$1"
  grep -E "^${key}=" .env 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

bool_norm() {
  local v
  v="$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    1|true|yes|on) echo "true" ;;
    *) echo "false" ;;
  esac
}

occ() {
  docker compose exec -u www-data nextcloud php occ "$@"
}

ENABLE_LDAP_VALUE="$(bool_norm "$(read_env ENABLE_LDAP)")"
LDAP_HOST_VALUE="$(read_env LDAP_HOST)"
LDAP_PORT_VALUE="$(read_env LDAP_PORT)"
LDAP_USE_SSL_VALUE="$(bool_norm "$(read_env LDAP_USE_SSL)")"
LDAP_START_TLS_VALUE="$(bool_norm "$(read_env LDAP_START_TLS)")"
LDAP_TLS_SKIP_VERIFY_VALUE="$(bool_norm "$(read_env LDAP_TLS_SKIP_VERIFY)")"
LDAP_BIND_USER_VALUE="$(read_env LDAP_BIND_USER)"
LDAP_BIND_PASSWORD_VALUE="$(read_env LDAP_BIND_PASSWORD)"
LDAP_BASE_DN_VALUE="$(read_env LDAP_BASE_DN)"
LDAP_USER_BASE_DN_VALUE="$(read_env LDAP_USER_BASE_DN)"
LDAP_GROUP_BASE_DN_VALUE="$(read_env LDAP_GROUP_BASE_DN)"
LDAP_CONFIG_ID_VALUE="$(read_env LDAP_CONFIG_ID)"
LDAP_USER_FILTER_VALUE="$(read_env LDAP_USER_FILTER)"
LDAP_GROUP_FILTER_VALUE="$(read_env LDAP_GROUP_FILTER)"
LDAP_LOGIN_FILTER_VALUE="$(read_env LDAP_LOGIN_FILTER)"
LDAP_GROUP_MEMBER_ASSOC_ATTR_VALUE="$(read_env LDAP_GROUP_MEMBER_ASSOC_ATTR)"
LDAP_ATTRIBUTES_FOR_GROUP_SEARCH_VALUE="$(read_env LDAP_ATTRIBUTES_FOR_GROUP_SEARCH)"
LDAP_NESTED_GROUPS_VALUE="$(bool_norm "$(read_env LDAP_NESTED_GROUPS)")"

if [ -z "${LDAP_PORT_VALUE}" ]; then
  if [ "${LDAP_USE_SSL_VALUE}" = "true" ]; then
    LDAP_PORT_VALUE="636"
  else
    LDAP_PORT_VALUE="389"
  fi
fi
LDAP_CONFIG_ID_VALUE="${LDAP_CONFIG_ID_VALUE:-s01}"
LDAP_USER_BASE_DN_VALUE="${LDAP_USER_BASE_DN_VALUE:-${LDAP_BASE_DN_VALUE}}"
LDAP_GROUP_BASE_DN_VALUE="${LDAP_GROUP_BASE_DN_VALUE:-${LDAP_BASE_DN_VALUE}}"
LDAP_USER_FILTER_VALUE="${LDAP_USER_FILTER_VALUE:-(&(objectClass=user)(sAMAccountName=*))}"
LDAP_GROUP_FILTER_VALUE="${LDAP_GROUP_FILTER_VALUE:-(objectClass=group)}"
LDAP_LOGIN_FILTER_VALUE="${LDAP_LOGIN_FILTER_VALUE:-(&(objectClass=user)(|(sAMAccountName=%uid)(userPrincipalName=%uid)))}"
LDAP_GROUP_MEMBER_ASSOC_ATTR_VALUE="${LDAP_GROUP_MEMBER_ASSOC_ATTR_VALUE:-member}"
LDAP_ATTRIBUTES_FOR_GROUP_SEARCH_VALUE="${LDAP_ATTRIBUTES_FOR_GROUP_SEARCH_VALUE:-cn}"

if [ "${ENABLE_LDAP_VALUE}" != "true" ]; then
  echo "ENABLE_LDAP is not true. Skipping LDAP configuration."
  exit 0
fi

if [ -z "${LDAP_HOST_VALUE}" ] || [ -z "${LDAP_BIND_USER_VALUE}" ] || [ -z "${LDAP_BIND_PASSWORD_VALUE}" ] || [ -z "${LDAP_BASE_DN_VALUE}" ]; then
  echo "Missing required LDAP values. Please set in .env:"
  echo "  LDAP_HOST, LDAP_BIND_USER, LDAP_BIND_PASSWORD, LDAP_BASE_DN"
  exit 1
fi

if [ "${LDAP_USE_SSL_VALUE}" = "true" ] && [ "${LDAP_START_TLS_VALUE}" = "true" ]; then
  echo "Invalid LDAP config: LDAP_USE_SSL and LDAP_START_TLS cannot both be true."
  echo "Use one transport mode only."
  exit 1
fi

if [ "${LDAP_USE_SSL_VALUE}" = "true" ]; then
  LDAP_HOST_FIELD_VALUE="${LDAP_HOST_VALUE}"
  case "${LDAP_HOST_FIELD_VALUE}" in
    ldaps://*) ;;
    ldap://*) LDAP_HOST_FIELD_VALUE="ldaps://${LDAP_HOST_FIELD_VALUE#ldap://}" ;;
    *) LDAP_HOST_FIELD_VALUE="ldaps://${LDAP_HOST_FIELD_VALUE}" ;;
  esac
else
  LDAP_HOST_FIELD_VALUE="${LDAP_HOST_VALUE}"
  case "${LDAP_HOST_FIELD_VALUE}" in
    ldap://*|ldaps://*) ;;
    *) LDAP_HOST_FIELD_VALUE="ldap://${LDAP_HOST_FIELD_VALUE}" ;;
  esac
fi

echo "[1/7] Enabling Nextcloud LDAP app..."
occ app:enable user_ldap >/dev/null

echo "[2/7] Ensuring LDAP config ID ${LDAP_CONFIG_ID_VALUE} exists..."
if ! occ ldap:show-config "${LDAP_CONFIG_ID_VALUE}" >/dev/null 2>&1; then
  occ ldap:create-empty-config >/dev/null
  if ! occ ldap:show-config "${LDAP_CONFIG_ID_VALUE}" >/dev/null 2>&1; then
    DETECTED_CONFIG_ID="$(occ ldap:show-config 2>/dev/null | grep -oE 's[0-9]{2}' | head -n1 || true)"
    if [ -n "${DETECTED_CONFIG_ID}" ]; then
      LDAP_CONFIG_ID_VALUE="${DETECTED_CONFIG_ID}"
      echo "Using detected LDAP config id: ${LDAP_CONFIG_ID_VALUE}"
    fi
  fi
fi

if ! occ ldap:show-config "${LDAP_CONFIG_ID_VALUE}" >/dev/null 2>&1; then
  echo "Could not find a valid LDAP config id after creation."
  echo "Set LDAP_CONFIG_ID in .env and rerun ./scripts/configure-ldap.sh"
  exit 1
fi

echo "[3/7] Writing LDAP connection settings..."
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapHost "${LDAP_HOST_FIELD_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapPort "${LDAP_PORT_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapAgentName "${LDAP_BIND_USER_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapAgentPassword "${LDAP_BIND_PASSWORD_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapBase "${LDAP_BASE_DN_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapBaseUsers "${LDAP_USER_BASE_DN_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapBaseGroups "${LDAP_GROUP_BASE_DN_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapConfigurationActive "1"

echo "[4/7] Writing LDAP security and protocol settings..."
if [ "${LDAP_START_TLS_VALUE}" = "true" ]; then
  occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapTLS "1"
else
  occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapTLS "0"
fi
if [ "${LDAP_TLS_SKIP_VERIFY_VALUE}" = "true" ]; then
  occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" turnOffCertCheck "1"
else
  occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" turnOffCertCheck "0"
fi

echo "[5/7] Writing LDAP user/group filters..."
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapUserFilter "${LDAP_USER_FILTER_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapGroupFilter "${LDAP_GROUP_FILTER_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapLoginFilter "${LDAP_LOGIN_FILTER_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapGroupMemberAssocAttr "${LDAP_GROUP_MEMBER_ASSOC_ATTR_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapAttributesForGroupSearch "${LDAP_ATTRIBUTES_FOR_GROUP_SEARCH_VALUE}"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapExperiencedAdmin "1"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapGidNumber ""
if [ "${LDAP_NESTED_GROUPS_VALUE}" = "true" ]; then
  occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapNestedGroups "1"
else
  occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapNestedGroups "0"
fi
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" useMemberOfToDetectMembership "1"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapExpertUsernameAttr "sAMAccountName"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapExpertUUIDUserAttr "objectGUID"
occ ldap:set-config "${LDAP_CONFIG_ID_VALUE}" ldapExpertUUIDGroupAttr "objectGUID"

echo "[6/7] Running LDAP config test..."
if occ ldap:test-config "${LDAP_CONFIG_ID_VALUE}"; then
  echo "LDAP test passed."
else
  echo "LDAP test failed. Check credentials, TLS settings, network reachability, and filters."
  exit 1
fi

echo "[7/7] Effective LDAP configuration snapshot:"
occ ldap:show-config "${LDAP_CONFIG_ID_VALUE}" | sed -n '1,220p'

echo
echo "LDAP integration is configured."
