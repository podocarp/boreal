#!/usr/bin/env bash
# Reproduce levels/gen_001 from tools/terrain-gen (fixed seed —
# the baked files are the determinism boundary; do NOT regenerate casually).
# Run from anywhere; paths are resolved relative to this script.
#
# Seed choice notes (probed 1337/7/42/2024/999):
#   1337: 369 viable cells, water 8 m away, 10 trees in ring, balanced biome
#         mix (20% water, 32% forest) — chosen: moderate trees, water close.
#   7/999: water too dominant near spawn (606/1367 water cells in the 80 m
#         ring); 2024: only 73 viable cells.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)   # repo root (tools -> root)
OUT="$HERE/levels/gen_001/"
godot --headless --path "$HERE/tools/terrain-gen" --script res://terrain_gen.gd -- \
  --seed 1337 --size 256 --octaves 5 --particles 12000 --thermal 3 --cell 2.0 \
  --out "$OUT"
# Expected: "BAKE OK <OUT>" and terrain_meta.json height_hash "ebabe3cf".
