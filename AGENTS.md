# AGENTS.md — BOREAL

Project-state handbook for any agent (fresh subagent or resumed-after-compaction). Start here; deep detail lives in `docs/`.

**Full handbook: [`docs/AGENT.md`](docs/AGENT.md)** — commands, architecture boundaries, hard-won conventions (real-seconds dt, `rngN` RNG stream, tag policy, Nix/NixOS E2E env), docs map, design principles, post-MVP backlog.

## TL;DR status
- **MVP COMPLETE** — tags `sprint-0`…`sprint-7` + `v0.1-mvp` on `main` @ https://github.com/podocarp/boreal.
- 3D browser survival game (TypeScript + three.js + Vite; pure deterministic sim in `src/sim`, render/input/UI never touch economy). Scenario: Survivorman-style Arctic crash run, 60–90 min, rescue window days 7–10.
- Green: `npx tsc --noEmit` · `npx vitest run` (77 tests) · headless Playwright E2E incl. golden path to day-7 rescue (see docs/AGENT.md for the exact nix-Chromium command — stock Chrome segfaults on this host).
- Play: `npm run dev` → http://localhost:5173. README has controls + "How to play".

## Non-negotiables (details/why in docs/AGENT.md)
- Sim core stays pure: no three.js/DOM/wall-clock/`Math.random` in `src/sim`; rolls via `roll(w)` on the world `rngN` stream.
- `dt` is REAL seconds everywhere; convert via `CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR` before per-game-hour math.
- Sprint discipline: unit green → E2E green → docs updated (`docs/PLAN.md` log + this/docs handbook if state changed) → commit + tag `sprint-N` → push. Never force-push or re-point tags.
- Needs design: consequences not chores (slow decay, auto-sip, debuff-first/die-last). Fair dangers (reaction delays, repel-able wolves, nameable death chains).

## Current open items
Post-MVP backlog only (nothing in flight): trapper's cache · widowmaker hazard · tea/morale · save/load · balance Monte-Carlo · art polish · license. Needs-research deltas queued in docs/AGENT.md backlog (fat-reserve pool, auto-eat toggle, craving curve, 3-match hard mode).
