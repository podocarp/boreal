#!/usr/bin/env bash
# Inner half of run_smoke.sh — runs INSIDE the nix dev shell (chromium available).
set -uo pipefail
cd "$(dirname "$0")/../../dist"
python3 -m http.server 4173 >/dev/null 2>&1 &
SRV=$!
sleep 1
BOREAL_URL=http://localhost:4173/ CHROMIUM="$(which chromium)" python3 ../tests/e2e/smoke_render.py
rc=$?
kill "$SRV" 2>/dev/null
exit $rc
