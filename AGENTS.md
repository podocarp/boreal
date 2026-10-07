# AGENTS.md — BOREAL

Project-state handbook for any agent (fresh subagent or resumed-after-compaction). Start here; deep detail lives in `docs/`.

**Full handbook: [`docs/AGENT.md`](docs/AGENT.md)** — commands, architecture boundaries, hard-won conventions (real-seconds dt, `rngN` RNG stream, tag policy, Nix/NixOS E2E env), docs map, design principles, post-MVP backlog.

## TL;DR status
- **MVP COMPLETE** — tags `sprint-0`…`sprint-7` + `v0.1-mvp` on `main` @ https://github.com/podocarp/boreal.
- 3D browser survival game (TypeScript + three.js + Vite; pure deterministic sim in `src/sim`, render/input/UI never touch economy). Scenario: Survivorman-style Arctic crash run, 60–90 min, rescue window days 7–10.
- **Sprint 8 in progress** (uncommitted work is normal): craving curve + Monte-Carlo harness (`npm run balance [seeds]`) + playtest fixes — contextual interactions (LMB/E + hold-RMB radial wheel, `src/sim/actions.ts`), mouse-only camera, crash site moved to shore beside grove/stream (`CRASH` in `terrain.ts`).
- Green: `npx tsc --noEmit` · `npx vitest run` (87 tests) · headless Playwright E2E incl. golden path to day-7 rescue — one command: `./tests/e2e/run_smoke.sh` (nix-Chromium; stock Chrome segfaults on this host).
- Play: `npm run dev` → http://localhost:5173. README has controls + "How to play".

## Non-negotiables (details/why in docs/AGENT.md)
- Sim core stays pure: no three.js/DOM/wall-clock/`Math.random` in `src/sim`; rolls via `roll(w)` on the world `rngN` stream.
- `dt` is REAL seconds everywhere; convert via `CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR` before per-game-hour math.
- Sprint discipline: unit green → E2E green → docs updated (`docs/PLAN.md` log + this/docs handbook if state changed) → commit + tag `sprint-N` → push. Never force-push or re-point tags.
- Needs design: consequences not chores (slow decay, auto-sip, debuff-first/die-last). Fair dangers (reaction delays, repel-able wolves, nameable death chains).

## Current open items
Sprint-8 open: harness bot policies regressed after the crash-site move (bots die d2–5; naive mostly wolves) — camp scouting rewritten around `CRASH`, needs re-tuning toward the rescue band (naive ~60% die, optimal ~5%). Backlog: trapper's cache · widowmaker hazard · tea/morale · save/load · art polish · license. Needs-research deltas queued in docs/AGENT.md backlog (fat-reserve pool, auto-eat toggle).
