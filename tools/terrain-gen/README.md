# terrain-gen — reusable seeded terrain bake (v0)

Standalone factory tool: fBm heightmap → hydraulic + thermal erosion → biomes →
Factorio-style starter-patch selection → baked mesh/collision. Nothing here runs
at game runtime; games load the baked artifacts. NOT wired into boreal (its
frozen sim terrain stays analytic).

## Usage

```bash
godot --headless --path tools/terrain-gen --script res://terrain_gen.gd -- \
  --seed 1337 [--size 256] [--octaves 5] [--particles 12000] [--thermal 3] \
  [--cell 2.0] [--out baked/] [--no-mesh]
```

| Flag | Default | Meaning |
|---|---|---|
| `--seed` | 1337 | master seed (height fBm = seed, erosion = seed+1, moisture = seed+7777) |
| `--size` | 256 | grid cells per side |
| `--octaves` | 5 | fBm octaves (persistence 0.3, lacunarity 2.0 — see gen.gd) |
| `--particles` | 12000 | hydraulic erosion droplets |
| `--thermal` | 3 | thermal (talus creep) passes, talus=0.15 m |
| `--cell` | 2.0 | meters per cell |
| `--out` | `baked/` | output dir (relative to the tool project) |
| `--no-mesh` | off | skip .tres mesh/collision output |

Prints per-stage timings, `meta:`, `spawn:`, and a final `BAKE OK <dir>` line;
fails loudly (`BAKE FAIL`, exit 1) if total bake exceeds the 120 s cost guard.

## Output contract (all in `--out`)

| File | Contents |
|---|---|
| `terrain_heights.json` | JSON array of `size*size` float32 heights, row-major (y*size+x) |
| `terrain_biomes.json` | JSON array of biome ids: 0 water, 1 grass, 2 forest, 3 rock, 4 snow |
| `terrain_meta.json` | seed, size, cell_size_m, min/max/mean height, water_level, biome counts/fractions, `height_hash` (FNV-1a over raw f32 bytes) |
| `spawn.json` | `{spawn:{x,z,y,yaw,cell}, candidates:[top-5 with per-criterion scores], diagnostics:{viable_cells, constraint_failures, reason}}` — `spawn` is `null` with an explanatory `reason` when no cell passes hard constraints |
| `terrain_mesh.tres` | ArrayMesh, vertex-colored by biome, flat shading (2 tris/cell) |
| `terrain_collision.tres` | HeightMapShape3D (256² data; scale the StaticBody by `cell` in X/Z) |

## How a game consumes it

Copy the baked dir into the game project. Load the two `.tres` directly:

```gdscript
var mesh: ArrayMesh = load("res://baked/terrain_mesh.tres")
var shape: HeightMapShape3D = load("res://baked/terrain_collision.tres")
# MeshInstance3D.mesh = mesh
# CollisionShape3D.shape = shape; parent StaticBody3D.scale = Vector3(2, 1, 2)
#   (scales the heightmap spacing; heights stay in meters)
```

For sim queries, bilinear-sample `terrain_heights.json` (or re-save the array as
raw `.f32` via `store_buffer` for smaller files). Spawn pose comes from
`spawn.json` — never re-run generation at runtime (FACTORY.md determinism rule;
the baked file is the determinism boundary).

## Determinism

All RNG is mulberry32 (`rng.gd`, boreal bit-exact pattern) and all noise is the
integer-hash value noise (`noise.gd`). Same seed + same flags ⇒ byte-identical
outputs on this host. `height_hash` in meta lets tests assert it cheaply.

## Perf (measured, this host: GPU-less NixOS VM, Godot 4.7.1 headless)

256×256, seed 1337, 12 000 droplets + 3 thermal passes + mesh + write:
**bake 7.4 s | spawn 0.34 s | mesh 0.75 s | write 0.08 s — ~9 s total wall**
(incl. engine startup). Full test suite (`bash scripts/run_tests.sh
tools/terrain-gen`): 4/4 scripts, 13 PASS lines, ~41 s.

## Tuning notes / pitfalls

- fBm persistence is **0.3, not 0.5**: at 0.5 the high-frequency roughness makes
  zero cells pass the 8 m / 0.5 m flatness gate, so no spawn exists on any seed.
- `HeightMapShape3D`: set `map_width`/`map_depth` **before** `map_data`, or the
  setter silently drops the data (Godot 4.7 renamed `map_height` → `map_depth`).
- Spawn scorer uses integral images; a naive per-candidate ring scan is too slow
  at 256².
- Small maps (< ~128²) can legitimately have zero viable cells; the scorer
  reports that as a diagnostic instead of picking garbage.

## Divergences from docs/terrain-gen-design.md (written in parallel)

- 5 biomes (task spec) vs the doc's 6 (no wetland band yet).
- Scorer params follow the task spec (water ≤ 40 m, tree ring 15–40 m, animals
  15–60 m, flatness max-min < 0.5 m) vs the doc's table (60 m water, variance
  gate, resource/buildable/escape gates). The doc's resource-spot, buildable-area,
  escape-route, and view terms are v1 work; the diagnostics shape here already
  supports them.
- Doc's fallback ladder (relax → stride → reseed) is v1; v0 emits the
  no-viable-spawn diagnostic only.
- Doc §2.1 recommends persistence 0.5; we measured that it kills spawn
  viability (see tuning notes) — worth folding back into the doc.
