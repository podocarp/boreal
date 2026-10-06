# BOREAL — Sprint Plan & Stopping Point

> Status: v0.1 (2026-10-06). One sprint = one checkpoint commit (+ tag). Each sprint ends with: unit tests green, Playwright smoke green, doc status updated, commit pushed.

## Definition of "MVP done" (the stopping point)
A player can, in a single ~60–90 min session on the hand-authored NWT map:
1. Spawn at the crash site, loot a minimal kit, understand controls + goal from an in-game briefing.
2. Manage **core needs** (warmth, hydration, energy, hunger) under a cold/wetness/wind model without micromanagement chores.
3. Gather resources (deadfall wood, bark/tinder, spruce boughs, rocks) with tool use and fatigue.
4. Build **fire** (real multi-step friction-fire-lite with failure risk) and keep it fed through the night; boil/melt water for stock.
5. Build a **debris shelter** (site choice matters: wind, water, fuel, widowmakers) that materially changes overnight survival odds.
6. Get **food** via at least two methods: snares (small game) + fishing or berries; eat to keep heat-production up.
7. Face **dangers**: a snowstorm night, wolf pressure at night/away from fire, injury→infection if careless.
8. Achieve an **end state**: rescue (signal fire lit during the search window / flare) or death with an explanatory summary screen.
9. Verified: sim unit tests cover needs/thermoregulation/fire/rescue balance; Playwright proves render + a scripted "golden path" run.

Anything beyond this (cooking depth, more wildlife, walking-out route, saves, art) is post-MVP.

## Sprints
- **S0 — Scaffold** ✅ commit `sprint-0`: repo, docs skeleton, Vite+TS+three.js, Vitest, flake.nix, Playwright smoke (blank scene renders), GitHub remote.
- **S1 — Engine core** ✅ commit `sprint-1`: fixed-timestep loop, analytic terrain + zones + collision, third-person over-shoulder camera (Skyrim-style), WASD movement, day/night clock, debug API, stylized scatter world.
- **S2 — Needs & thermoregulation:** core needs model (per DESIGN-needs.md), cold/wetness/windchill, shivering→hypothermia chain, sleep, HUD, death causes. Sim-heavy + tests.
- **S3 — World & interaction:** resource nodes, gathering, inventory, prompts/interaction system, crafting (tools, containers, bough bundles), camp/stockpile concept.
- **S4 — Fire & water:** fire model (fuel, stages, failure, extinguish, warmth radius), friction-lite minigame, boil/melt water, cook water, wetness from snow/rain.
- **S5 — Shelter & sleep:** debris shelter build (multi-step, site scoring), sleep system w/ overnight risk model, storm event night.
- **S6 — Food & dangers:** snare system, fishing hole, berries, wolves (fair AI per bot-fairness rules), injury/infection.
- **S7 — Rescue & game loop:** search window, signal fire/flare logic, end screens + summary, balance pass over full run, golden-path E2E, README/play instructions. → **tag `v0.1-mvp`, STOP.**

## Status log
- 2026-10-06: v0.1 plan agreed internally; awaiting research digests → v0.2. User chose Arctic + third-person.
- 2026-10-06: research digests landed → needs numbers v1 (DESIGN-needs.md), scenario notes (RESEARCH-survivorman.md). User locked stylized low-poly art, no animations; camera = Skyrim/Dinkum over-shoulder.
- 2026-10-06: **S1 done**: analytic terrain (lake/stream/bog/ridge zones) shared sim↔render, deterministic prop scatter + colliders, camera-relative WASD + facing + slide collision, Skyrim-style camera (shoulder pivot, orbit, collision ease, sprint swing, idle recenter), day/night sky (8h light), stylized palette + instanced low-poly trees/rocks, crash site, HUD. 18 unit tests + extended E2E (movement, camera, scene graph, day/night, pixels).
