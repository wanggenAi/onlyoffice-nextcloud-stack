#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CERT_PATH="${DATA_ROOT:-./.data}/caddy/data/caddy/pki/authorities/local/root.crt"

if [ ! -f "${CERT_PATH}" ]; then
  echo "Local Caddy CA certificate not found at:"
  echo "  ${CERT_PATH}"
  echo "Run ./scripts/up.sh first so Caddy can generate it."
  exit 1
fi

if command -v update-ca-certificates >/dev/null 2>&1; then
  TARGET="/usr/local/share/ca-certificates/caddy-local.crt"
  echo "Installing local Caddy CA into Linux trust store (${TARGET})..."
  sudo cp "${CERT_PATH}" "${TARGET}"
  sudo update-ca-certificates
elif command -v update-ca-trust >/dev/null 2>&1; then
  TARGET="/etc/pki/ca-trust/source/anchors/caddy-local.crt"
  echo "Installing local Caddy CA into Linux trust store (${TARGET})..."
  sudo cp "${CERT_PATH}" "${TARGET}"
  sudo update-ca-trust extract
else
  echo "Could not detect trust-store tool."
  echo "Import this cert manually into your system/browser trust store:"
  echo "  ${CERT_PATH}"
  exit 1
fi

echo "Done. Restart your browser and test:"
echo "  https://cloud.localhost"
echo "  https://docs.localhost/healthcheck"
