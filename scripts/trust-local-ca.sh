#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OS="$(uname -s || true)"

case "$OS" in
  Darwin)
    ./scripts/trust-local-ca-macos.sh
    ;;
  Linux)
    ./scripts/trust-local-ca-linux.sh
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "Detected Windows shell. Run PowerShell as Administrator:"
    echo "  powershell -ExecutionPolicy Bypass -File .\\scripts\\trust-local-ca-windows.ps1"
    ;;
  *)
    echo "Unsupported OS: ${OS}"
    echo "Use one of:"
    echo "  ./scripts/trust-local-ca-macos.sh"
    echo "  ./scripts/trust-local-ca-linux.sh"
    echo "  powershell -ExecutionPolicy Bypass -File .\\scripts\\trust-local-ca-windows.ps1"
    exit 1
    ;;
esac
