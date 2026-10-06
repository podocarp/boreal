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
- **S2 — Needs & thermoregulation** ✅ commit `sprint-2`: heat-budget model (windchill, diurnal temp, wetness, fire/shelter insulation, food=fuel), auto-sip, critical bands with ramped drain + named death causes, event log, HUD bars/warnings. 32 unit tests incl. tuning-target tests.
- **S3 — World & interaction** ✅ commit `sprint-3`: resource nodes, gathering, inventory, prompts/interaction system, crafting (tools, containers, bough bundles), camp/stockpile concept.
- **S4 — Fire & water** ✅ commit `sprint-4`: staged fire (fuel burn/wind/collapse/warmth radius + point-light visuals), friction-light roll (dexterity/wetness/core-temp/wood), feed/boil/drink/eat, snow-as-water tradeoff, raw-water gut risk. 52 unit tests.
- **S5 — Shelter & sleep** ✅ commit `sprint-5`: 6-step debris shelter w/ site scoring (wind/water/fuel/widowmakers), insulation feeds thermoregulation, sleep gamble (restore scaled by warmth/food), storms days 2+4 (wind, wetness, drying by fire). 61 unit tests.
- **S6 — Food & dangers** ✅ commit `sprint-6`: snares (cordage, hare-sign quality, freshness decay, destroyed on catch, collect at site), ice-edge fishing (dawn/dusk), berries, cook meat, wolves (nights day 2+, prefer weakened, fire+shout deter, reaction-delay fairness), injury→infection→sepsis, duct-tape first aid. 70 unit tests.
- **S7 — Rescue & game loop** ✅ commit `sprint-7`: search passes (days 7–10, dawn+dusk, storms scrub), detection model (signal smoke 0.92 open / 0.52 canopy, flare 0.95, position/shelter/tracks modifiers), signal-smoke + flare actions, day-10 collapse end, end screen w/ run summary + Enter restart, golden-path E2E (loot→fire→smoke→day-7 rescue). 77 unit tests. → **tag `v0.1-mvp`, STOP.**

## Status log
- 2026-10-06: v0.1 plan agreed internally; awaiting research digests → v0.2. User chose Arctic + third-person.
- 2026-10-06: research digests landed → needs numbers v1 (DESIGN-needs.md), scenario notes (RESEARCH-survivorman.md). User locked stylized low-poly art, no animations; camera = Skyrim/Dinkum over-shoulder.
- 2026-10-06: **S1 done**: analytic terrain (lake/stream/bog/ridge zones) shared sim↔render, deterministic prop scatter + colliders, camera-relative WASD + facing + slide collision, Skyrim-style camera (shoulder pivot, orbit, collision ease, sprint swing, idle recenter), day/night sky (8h light), stylized palette + instanced low-poly trees/rocks, crash site, HUD. 18 unit tests + extended E2E (movement, camera, scene graph, day/night, pixels).
- 2026-10-06: **S2 done**: needs+thermoregulation per DESIGN-needs.md. Key tuning (tests enforce): walking at feels −25 °C ≈ thermally neutral; idle at feels −20 → hypothermia band in ~5 game-h; fire (2.6 °C/h) beats worst windchill; soaked clothing = 40% insulation; death at 0 hydration ≈ 10 h. Fixed: game-hour conversion (dt is real seconds!), windchill above freezing, diurnal phase, sip unit bug.
- 2026-10-06: **S3 done**: items/inventory (carry limit in invAdd choke point), interactables from scatter, timed work (dexterity-scaled, move-cancels), recipes atomic, E/Tab keys, HUD prompt/inventory/log.
- 2026-10-06: **S4 done**: fire stages/burn/warmth, friction roll (wet+cold+green ≈ 5%), boil/melt, drink (clean/raw/snow tradeoffs), eat berries; fire meshes+lights; keys F/R/Q/1/2. Note: friction roll seeds from sim time — E2E retries with time advance.
- 2026-10-06: **S5 done**: shelter steps site→frame→ribs→insulation→mulch→bedding (costs boughs/deadfall), site quality from wind+water+fuel+widowmaker noise; sleep restores 10/h warm (35% cold), wakes rested or ≥2h at dawn; storms 22:00 day 2 + 19:00 day 4 (severe). Fixed: double energy restore (needs vs world.step), sleep "warm" now shelter/fire-aware not just core temp.
- 2026-10-06: **S6 done**: snares/fishing/berries/cooking + wolves + injury chain. Fixed: lightFire/drink reused same roll when sim time frozen (now world rngN stream), sepsis (6/h) applied after regen (2/h) so untreated infection is lethal, wolf fire-distance used player z not fire z. Keys: C set snare, X check, V fish, B cook, T treat, Space shout. E2E: fire+shouting repels pack with zero injuries.
- 2026-10-06: **S7 done — MVP STOP**: rescue passes days 7–10 (dawn 09:00 / dusk 16:30), storm-scrubbed passes, detection = signal smoke (big lever, per Survivorman) > flare (one shot) > campfire/position/tracks; day-10 collapse; end screen w/ last-10-events summary; Enter restarts. Tuned open-ground smoke to 0.92 after a deterministic 0.87-vs-0.90 near-miss in tests. Keys: H flare, J signal smoke. Golden-path E2E proves the full loop. **Tagged v0.1-mvp.**
