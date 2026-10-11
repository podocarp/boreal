#!/usr/bin/env bash
# Build the itch-ready web export for boreal.
#   bash tools/export.sh            # -> dist/boreal-web-<ver>.zip (+ dist/web/ loose build)
#   VER=0.2.0 bash tools/export.sh  # override version stamp
# Requires: godot on PATH (export PATH=$HOME/.local/bin:$PATH) and the Web
# export templates for the engine version installed under
# ~/.local/share/godot/export_templates/<ver>.stable/ (see README "Web export").
#
# The preset exports WITHOUT threads (variant/thread_support=false): itch.io
# serves plain files without COOP/COEP cross-origin headers, which threaded
# Godot web builds require. No-threads is the itch-compatible choice.
set -euo pipefail
cd "$(dirname "$0")/.."   # games/boreal
PROJ="$PWD"
VER="${VER:-0.1.0}"
GODOT="${GODOT:-godot}"

command -v "$GODOT" >/dev/null || { echo "godot not on PATH (export PATH=\$HOME/.local/bin:\$PATH)"; exit 1; }

# Import pass so freshly added resources are in the .godot/ cache the exporter reads.
"$GODOT" --headless --path "$PROJ" --import --quit >/dev/null 2>&1 || true

rm -rf dist/web
mkdir -p dist/web
"$GODOT" --headless --path "$PROJ" --export-release "Web" "dist/web/index.html"

# Godot prints "one or more files were not exported" style warnings as
# non-fatal; fail loudly if the core artifacts are missing.
for f in index.html index.js index.wasm index.pck; do
  [[ -s "dist/web/$f" ]] || { echo "export missing dist/web/$f"; exit 1; }
done

python3 tools/mkzip.py "dist/boreal-web-${VER}.zip" dist/web
echo "OK: dist/boreal-web-${VER}.zip (index.html at zip root — upload this to itch.io)"
