#!/usr/bin/env bash
# Bundle then launch Vani.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${ROOT}/scripts/bundle.sh" "${1:-debug}"
open "${ROOT}/Vani.app"
echo "Launched. Look for the mic icon in the menu bar (top-right)."
