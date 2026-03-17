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

echo "Installing local Caddy CA into macOS System keychain..."
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "${CERT_PATH}"

echo "Done. Restart your browser and test:"
echo "  https://cloud.localhost"
echo "  https://docs.localhost/healthcheck"
