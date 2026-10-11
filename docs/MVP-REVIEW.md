# Boreal MVP review — 2026-10-11

Final quality gate before calling the Boreal MVP done. Reviewer: gamedev
(kanban t_45da5c91). Baseline commit reviewed: `c2d26dd` (web ship
toolchain). No features added; verification + doc-truth fixes only.

## 1. Full test suite — GREEN

`bash scripts/run_tests.sh games/boreal` on the working tree:
**16/16 test scripts passed** (matches README "Test status (16/16)").
Every script printed its PASS line (no silent passes).

Note: the README test-list previously enumerated 15 scripts —
`test_water_channel.gd` existed and ran but was undocumented. Fixed in
this review's doc commit.

## 2. CI workflow — steps run locally, all green

`.github/workflows/ci.yml` test job runs `run_tests.sh` over
`template sdk tools/terrain-gen games/boreal`. Local run (host engine
4.7.2.stable.nixpkgs; CI pins the 4.7.1-stable binary — see gaps):

| project          | result |
|------------------|--------|
| template         | 1/1    |
| sdk              | 7/7    |
| tools/terrain-gen| 4/4    |
| games/boreal     | 16/16  |

Render job (weston + lavapipe screenshot, PNG > 1 KiB): equivalent
renders succeed locally (see §5); the local host now prefers the Intel
iGPU ANV ICD with lavapipe fallback (uncommitted `scripts/render_shot.sh`
change by another worker — CI's ubuntu-latest path still selects
`/usr/share/vulkan/icd.d/lvp_icd*.json`, unchanged behavior).

## 3. Fresh-clone check — GREEN

`git clone` of the repo to a temp dir, full suite from the clone:
template 1/1, sdk 7/7, tools/terrain-gen 4/4, games/boreal 16/16.
No uncommitted dependencies; the baked `levels/gen_001/` + assets all
ship in git.

## 4. Export script — end-to-end PASS

`bash tools/export.sh` → `dist/web/` + `dist/boreal-web-0.1.0.zip`
(9 entries, index.html at zip root, 30,894,935 B,
sha256 `bd24c4d85b45d4d2cc70430086f205496f7c624227855ec6f5a1548bd4475029`).

Headless smoke (`tools/smoke_web.py`, nixpkgs playwright-chromium):
`SMOKE: PASS` — index.html/js/wasm/pck all HTTP 200, splash overlay
removed (engine booted), canvas 1280×720 WebGL 2.0, 228 distinct
framebuffer colors (real frames rendered). One known console error
(~15 s after boot): `AudioWorkletNode ... not of type
'BaseAudioContext'` — headless-Chromium no-threads audio init; game
renders and plays; real-browser audio untested on this host (no audio
device). First suspect if itch testers report no sound.

## 5. Screenshots — re-rendered, vision-checked

Re-rendered with `SHOT_FROZEN=1` (deterministic) on the Intel iGPU
backend, then vision-checked for the white-silhouette regression class:

| shot | sha256 (first 12) | verdict |
|------|-------------------|---------|
| `shots/boreal_camp.png`   | `0bc35ea7547e` | PASS — campfire warm light, red/white wreck, green/brown trees, snow; fog band is atmospheric, not a glitch |
| `shots/boreal_stream.png` | `5048577e851f` | rendered OK (backend asserted) |
| `shots/boreal_hud.png`    | `53a288139f0f` | PASS — HYDRATION/HUNGER/ENERGY/HEALTH bars, `80 kg (ok)` weight readout, CORE/FEELS temps, DAY 1 16:30, `[E] Scavenge the wreck` prompt; no garbled text |
| `shots/boreal_menu.png`   | `aa0433192f0c` | rendered OK (title screen; previously vision-checked at ship time) |
| `shots/gen_overview.png`  | `35ed92023d55` | PASS with known caveat — see below |

`gen_overview.png` note: the generated level reads heavily washed-out
(uniform blue-grey ground, distant trees fading to pale silhouettes).
This is the DOCUMENTED fog behavior (`day_night.gd` fog ≈ horizon
color, README handover notes "Fog wash, not a bug"), and the new render
is pixel-comparable to the committed baseline (183,012 B vs 182,668 B,
same composition). The baked terrain mesh carries its vertex-color
material (3 material refs in `terrain_mesh.tres`); no white-mesh
regression. Post-MVP: raise generated-level fog contrast / biome
saturation for readability.

## 6. Doc truth fixes (this commit)

- README title `phase 2b` → `MVP complete` + pointer to this review.
- README test list: added the missing `test_water_channel.gd` entry
  (count line 16/16 was already correct).
- BACKLOG.md asset wishlist: plane wreck and audio marked DONE
  (2026-10-11); wolf marked deliberately CUT (owner directive
  2026-10-10), not an open gap.
- FACTORY.md status: phase 2 checked done (MVP reviewed), CI checked
  done (workflow exists and its steps pass locally), sdk test count
  5/5 → 7/7.

## Known gaps (post-MVP backlog)

1. **CI engine drift**: workflow pins Godot 4.7.1-stable binary; host
   runs 4.7.2.stable.nixpkgs. Tests pass on both, but bump the workflow
   URL (and `flake.nix` comment) when the pin moves.
2. **Web audio**: AudioWorklet console error under headless Chromium
   (§4); real-browser audio never exercised on this host.
3. **Generated-level readability**: fog wash + flat biome palette
   (§5); shoreline stair-stepping from rect water decomposition.
4. **Generated-level sim seam**: zone/wind math still reads analytic
   `Terrain` internally (sim-freeze constraint) — generated zone
   effects are approximate (BACKLOG v1 item).
5. **No level select** in the itch build (`LEVEL=generated` is env-only).
6. **Checkpoint cams** hardcoded offsets from baked spawn.
7. **Crafting UI / action wheel** unported (deliberate MVP scope-out).
8. Character animation clips: 0 on the base-character rig (BACKLOG).
9. `scripts/render_shot.sh` + `tools/terrain-gen/mesh_out.gd` carry
   another worker's uncommitted iGPU/material changes; left unstaged
   per commit discipline. CI's lavapipe path is unaffected by the ICD
   change (falls through when /dev/dri is absent).

## Verdict

**MVP gate: PASS.** Suite 16/16 (repo-wide 28/28), fresh clone green,
export + smoke green, screenshots regression-checked, docs truthful.
