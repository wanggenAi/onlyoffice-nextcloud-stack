#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "${1:-}" = "" ]; then
  echo "Usage: ./scripts/restore.sh <backup-folder-path>"
  exit 1
fi

BACKUP_PATH="$1"
if [ ! -d "${BACKUP_PATH}" ]; then
  echo "Backup folder not found: ${BACKUP_PATH}"
  exit 1
fi

if [ ! -f "${BACKUP_PATH}/nextcloud.sql" ] || [ ! -f "${BACKUP_PATH}/data-root.tar.gz" ]; then
  echo "Invalid backup folder, required files missing (nextcloud.sql, data-root.tar.gz)"
  exit 1
fi

DATA_ROOT_VALUE="$(grep -E '^DATA_ROOT=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
MYSQL_DATABASE_VALUE="$(grep -E '^MYSQL_DATABASE=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
MYSQL_USER_VALUE="$(grep -E '^MYSQL_USER=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
MYSQL_PASSWORD_VALUE="$(grep -E '^MYSQL_PASSWORD=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"

DATA_ROOT_VALUE="${DATA_ROOT_VALUE:-./.data}"

echo "WARNING: restore is destructive and will overwrite current data."
echo "Target DATA_ROOT: ${DATA_ROOT_VALUE}"
read -r -p "Type YES to continue: " confirm
if [ "${confirm}" != "YES" ]; then
  echo "Restore cancelled."
  exit 1
fi

echo "[1/5] Stopping app services..."
docker compose stop nextcloud onlyoffice-documentserver redis

echo "[2/5] Restoring data root archive..."
rm -rf "${DATA_ROOT_VALUE}"
mkdir -p "$(dirname "${DATA_ROOT_VALUE}")"
tar -xzf "${BACKUP_PATH}/data-root.tar.gz" -C "$(dirname "${DATA_ROOT_VALUE}")"

echo "[3/5] Starting database service..."
docker compose up -d db
sleep 10

echo "[4/5] Restoring database dump..."
docker compose exec -T db sh -lc \
  "mariadb -u\"${MYSQL_USER_VALUE}\" -p\"${MYSQL_PASSWORD_VALUE}\" \"${MYSQL_DATABASE_VALUE}\"" \
  < "${BACKUP_PATH}/nextcloud.sql"

echo "[5/5] Starting full stack..."
docker compose up -d

echo "Restore completed from: ${BACKUP_PATH}"
