# AGENT.md — BOREAL (project state & agent handbook)

Read-me-first for any agent (fresh subagent or resumed-after-compaction). This file is the compact state-of-project; deep detail lives in the other `docs/` files. (If the repo root ever gets an `AGENTS.md`, it should just point here.)

## What this is
3D browser wilderness-survival game (stylized low-poly, no animations, Skyrim/Dinkum over-shoulder camera). Scenario: bush-plane crash, NWT subarctic ~60°N, late autumn, inspired by Les Stroud's Survivorman. One 60–90 min run: survive to the day 7–10 search window, signal, get rescued — or die with a summary.

**Status: MVP COMPLETE.** Tags `sprint-0`…`sprint-7` + `v0.1-mvp` pushed to https://github.com/podocarp/boreal (branch `main`). 77 unit tests green, tsc clean, headless E2E golden path (loot→fire→signal→day-7 rescue) green.

## Commands
- Dev: `npm run dev` → http://localhost:5173
- Typecheck: `npx tsc --noEmit` · Unit tests: `npx vitest run`
- Build: `npx vite build` → `dist/`
- E2E (headless WebGL, NixOS host): `nix develop --extra-experimental-features 'nix-command flakes' . -c bash -lc '(cd dist && python3 -m http.server 4173 &) ; sleep 1; BOREAL_URL=http://localhost:4173/ CHROMIUM=$(which chromium) python3 tests/e2e/smoke_render.py'` — must use nixpkgs chromium (stock puppeteer chromium segfaults on this host).
- Screenshot: `tests/e2e/screenshot.py <out.png> [day|night]` (same nix env). Inspect visually — the driving model has vision.

## Architecture (respect these boundaries)
- `src/sim/*` — **pure sim core**: no three.js, no DOM, no wall clock, deterministic. Fixed timestep `CONFIG.SIM_DT` (0.25 s real). All tunables in `src/sim/config.ts`.
- `src/render/*`, `src/ui/*`, `src/input/*` — presentation only; reads world state, never mutates needs/economy.
- `src/main.ts` — wiring + `window.__boreal` debug/E2E API (reset/step/move/orbitCam/actions). E2E scripts drive the game exclusively through this API.
- Modules: `world` (state+step+actions), `needs` (thermoregulation), `fire`, `shelter` (build/sleep/storms), `dangers` (snares/fishing/wolves/injury), `rescue` (search passes/detection), `interact` (targets/work tasks), `items`, `craft`, `terrain` (analytic height/zone — shared sim↔render), `scatter`, `noise`, `rng`.

## Hard conventions (learned the expensive way)
- **Time**: `dt` everywhere is REAL seconds; 1 game-hour = `CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR` (30 s). Convert before any per-game-hour math.
- **Randomness**: never `Math.random` in sim. World has a serializable `rngN` stream via `roll(w)` — do NOT seed rolls from `w.t` (frozen time ⇒ identical rolls; that was a real bug).
- Sleep energy restore lives in `world.step`, not `tickNeeds` — don't double-apply.
- Sepsis damage applies AFTER regen (untreated infection must be lethal).
- Camera: yaw 0 looks −z; pitch>0 looks down; mouse-up looks up.
- WebGL `readPixels` origin is bottom-left (ground checks use `y < h*0.25`).
- Subarctic sun stays due south (rises SE ~09:00, sets SW ~17:00).
- Git: commit per sprint, tag `sprint-N`; NEVER force-push/re-point tags. Commit identity podocarp-hermes.
- Host is NixOS with an ephemeral nix store overlay — use `nix develop` per command; don't assume installed packages persist.

## Docs map
- `docs/VISION.md` pillars/scenario/non-goals · `docs/TECH.md` stack+camera spec · `docs/PLAN.md` sprint plan + dated status log (append entries) · `docs/DECISIONS.md` append-only ADRs
- `docs/DESIGN-needs.md` + `docs/RESEARCH-needs.md` needs model & tuning targets · `docs/RESEARCH-needs-full.md` full per-game needs research (PZ/TLD/Green Hell/Raft/Valheim numbers + pitfalls) · `docs/RESEARCH-survivorman.md` scenario facts (corrected episode list — Borneo/Fiji/Yucatan don't exist) · `docs/DESIGN-world.md` zones/resources/fire/shelter/food/rescue design · `docs/RESEARCH-survivorman.md` scenario facts
- `README.md` controls + "How to play" run guide.

## Game-design principles (user-agreed)
Consequences not chores: slow need decay, auto-sip from carried stock, no click-the-bottle timers. Stylized art, basic interactions, no animations. Fair dangers: reaction delays, repel-able wolves, nameable death chains (injury→infection). Rescue is the goal; signal smoke > flare > hiding.

## Post-MVP backlog (not started)
Trapper's cache discovery · widowmaker scripted hazard · tea/morale · save/load · balance Monte-Carlo (naive vs smart play) · art polish · license choice (currently TBD).
Needs-research deltas not yet built (see RESEARCH-needs-full.md §3): hidden fat-reserve pool buffering hunger · auto-EAT toggle (we only auto-sip) · Raft-style craving curve (food more effective when hungrier) · 3-match economy as a hard mode.

## Workflow expectations (from user)
Sprint = dev → eval → test loop ending in: unit green, E2E green, docs updated (PLAN.md log + this file if state changed), commit + tag, push. Delegate exploration/simple parallelizable work to subagents to protect context; point them at this file. Keep replies to the user short and factual.
