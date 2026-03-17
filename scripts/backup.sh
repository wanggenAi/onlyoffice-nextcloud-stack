#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ts="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT_VALUE="$(grep -E '^BACKUP_ROOT=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
DATA_ROOT_VALUE="$(grep -E '^DATA_ROOT=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
MYSQL_DATABASE_VALUE="$(grep -E '^MYSQL_DATABASE=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
MYSQL_USER_VALUE="$(grep -E '^MYSQL_USER=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
MYSQL_PASSWORD_VALUE="$(grep -E '^MYSQL_PASSWORD=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
RETENTION_DAYS_VALUE="$(grep -E '^BACKUP_RETENTION_DAYS=' .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"

BACKUP_ROOT_VALUE="${BACKUP_ROOT_VALUE:-./backups}"
DATA_ROOT_VALUE="${DATA_ROOT_VALUE:-./.data}"
RETENTION_DAYS_VALUE="${RETENTION_DAYS_VALUE:-14}"

dest="${BACKUP_ROOT_VALUE}/${ts}"
mkdir -p "${dest}"

echo "[1/4] Dumping MariaDB..."
docker compose exec -T db sh -lc \
  "mysqldump -u\"${MYSQL_USER_VALUE}\" -p\"${MYSQL_PASSWORD_VALUE}\" \"${MYSQL_DATABASE_VALUE}\" --single-transaction --quick --lock-tables=false" \
  > "${dest}/nextcloud.sql"

echo "[2/4] Archiving data root..."
tar -czf "${dest}/data-root.tar.gz" -C "$(dirname "${DATA_ROOT_VALUE}")" "$(basename "${DATA_ROOT_VALUE}")"

echo "[3/4] Saving runtime config snapshot..."
docker compose exec -u www-data nextcloud php occ config:list > "${dest}/nextcloud-config.json"
docker compose exec -u www-data nextcloud php occ app:list > "${dest}/nextcloud-apps.txt"

echo "[4/4] Applying retention policy (${RETENTION_DAYS_VALUE} days)..."
find "${BACKUP_ROOT_VALUE}" -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS_VALUE}" -exec rm -rf {} +

echo "Backup completed: ${dest}"
