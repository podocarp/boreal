#!/usr/bin/env bash
# Inner half: runs INSIDE the nix dev shell (chromium available).
# Usage: run_shot_inner.sh <out.png> [day|camp|night]
set -uo pipefail
cd "$(dirname "$0")/../../dist"
python3 -m http.server 4173 >/dev/null 2>&1 &
SRV=$!
sleep 1
BOREAL_URL=http://localhost:4173/ CHROMIUM="$(which chromium)" python3 ../tests/e2e/screenshot.py "$@"
rc=$?
kill "$SRV" 2>/dev/null
exit $rc
