#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIRMED=false
REMOVE_ENV=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/purge.sh [--yes] [--remove-env]

Danger:
  This script removes the stack completely:
  - containers, project network, anonymous volumes
  - images used by this compose project
  - DATA_ROOT directory from .env (default: ./.data)
  - BACKUP_ROOT directory from .env (default: ./backups)

Options:
  --yes         Skip interactive confirmation
  --remove-env  Also remove .env file
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)
      CONFIRMED=true
      shift
      ;;
    --remove-env)
      REMOVE_ENV=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

DATA_ROOT_VALUE="./.data"
BACKUP_ROOT_VALUE="./backups"

if [ -f .env ]; then
  ENV_DATA_ROOT="$(grep -E '^DATA_ROOT=' .env | tail -n1 | cut -d= -f2- || true)"
  ENV_BACKUP_ROOT="$(grep -E '^BACKUP_ROOT=' .env | tail -n1 | cut -d= -f2- || true)"
  if [ -n "${ENV_DATA_ROOT}" ]; then DATA_ROOT_VALUE="${ENV_DATA_ROOT}"; fi
  if [ -n "${ENV_BACKUP_ROOT}" ]; then BACKUP_ROOT_VALUE="${ENV_BACKUP_ROOT}"; fi
fi

if [ "${DATA_ROOT_VALUE}" = "/" ] || [ "${BACKUP_ROOT_VALUE}" = "/" ]; then
  echo "Refusing to run: DATA_ROOT/BACKUP_ROOT resolves to '/'."
  exit 1
fi

echo "This will permanently delete:"
echo "  - docker compose resources for this project"
echo "  - DATA_ROOT:   ${DATA_ROOT_VALUE}"
echo "  - BACKUP_ROOT: ${BACKUP_ROOT_VALUE}"
if [ "${REMOVE_ENV}" = "true" ]; then
  echo "  - .env"
fi

if [ "${CONFIRMED}" != "true" ]; then
  echo
  read -r -p "Type PURGE to continue: " confirm_text
  if [ "${confirm_text}" != "PURGE" ]; then
    echo "Cancelled."
    exit 1
  fi
fi

echo "[1/5] Stopping and removing compose resources..."
docker compose down --remove-orphans --volumes --rmi all || true
docker compose --profile proxy down --remove-orphans --volumes --rmi all || true

echo "[2/5] Removing DATA_ROOT..."
rm -rf "${DATA_ROOT_VALUE}"

echo "[3/5] Removing BACKUP_ROOT..."
rm -rf "${BACKUP_ROOT_VALUE}"

echo "[4/5] Removing .env (optional)..."
if [ "${REMOVE_ENV}" = "true" ] && [ -f .env ]; then
  rm -f .env
fi

echo "[5/5] Done."
echo "Stack has been purged from this host."
