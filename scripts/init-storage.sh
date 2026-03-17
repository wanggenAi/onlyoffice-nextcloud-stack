#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DATA_ROOT="./.data"
if [ -f .env ]; then
  ENV_DATA_ROOT="$(grep -E '^DATA_ROOT=' .env | tail -n1 | cut -d= -f2- || true)"
  if [ -n "${ENV_DATA_ROOT}" ]; then DATA_ROOT="${ENV_DATA_ROOT}"; fi
fi

mkdir -p "${DATA_ROOT}/mariadb" \
         "${DATA_ROOT}/redis" \
         "${DATA_ROOT}/nextcloud" \
         "${DATA_ROOT}/caddy/data" \
         "${DATA_ROOT}/caddy/config" \
         "${DATA_ROOT}/onlyoffice/data" \
         "${DATA_ROOT}/onlyoffice/logs"

chmod -R 775 "${DATA_ROOT}" || true

echo "Storage paths ready under: ${DATA_ROOT}"
