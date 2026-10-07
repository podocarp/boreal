#!/usr/bin/env bash
# Headless WebGL smoke: serve dist/, run Playwright smoke in nixpkgs Chromium.
set -euo pipefail
cd "$(dirname "$0")/../.."
npx vite build >/dev/null 2>&1
echo BUILD_OK
nix develop --extra-experimental-features 'nix-command flakes' . -c bash ./tests/e2e/run_smoke_inner.sh
