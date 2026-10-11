# BOREAL balance report — GDScript Monte-Carlo harness

Harness: `games/boreal/tools/balance.gd` (port of `boreal-src/tests/sim/balance.ts`).
Run: `godot --headless --path games/boreal --script res://tools/balance.gd -- [seedsPerPolicy]` (default 20).
Pure sim, no render; deterministic per seed (world `roll()` stream + per-bot
xorshift-ish stream; no wall-clock, no `randf()`).

## Run output (20 seeds/policy, 2026-10-11, commit c463039 + this harness)

```
# boreal balance: 20 seeds/policy, 67.7s (GDScript harness)
idle       n=20  rescued   0% (avg day —)  died 100%  days-survived median 2.0
  causes:      hypothermia=20
  death days:  d2=20
  rescue days: none
naive      n=20  rescued   0% (avg day —)  died 100%  days-survived median 3.0
  causes:      hypothermia=12, starvation=8
  death days:  d2=6, d3=6, d4=6, d5=2
  rescue days: none
competent  n=20  rescued   0% (avg day —)  died 100%  days-survived median 3.0
  causes:      hypothermia=11, starvation=8, dehydration=1
  death days:  d2=10, d4=2, d5=6, d6=2
  rescue days: none
```

Policies: `idle` = do-nothing floor (new; the TS harness has no idle bot).
`naive` = TS NaiveBot (loot, fire at the exposed wreck, no shelter/food/signal).
`competent` = TS OptimalBot (scouted forest camp, fire loop, shelter, snares,
dawn fishing, wound care, signal smoke + open shore before day 7), minus the
wolf-repel line (wolves are cut from the MVP per owner directive 2026-10-10).

## Sanity gate: FAILED — and the cause is upstream, not a port bug

Gate: idle must die (PASS — 100% hypothermia d2) and competent must reach the
day 7–10 rescue window on most seeds (FAIL — 0% rescued).

Investigation per the card: the **reference TypeScript harness itself rescues
0%** on this machine. Running the frozen `boreal-src` sim directly
(`node tests/sim/balance_main.ts 10`, Node 26 native type-stripping):

```
naive    n=10  rescued 0%  died 100%  causes: wolf attack=6, exposure=3, hypothermia=1  (all d2)
average  n=10  rescued 0%  died 100%  causes: exposure=7, hypothermia=3                  (all d2)
optimal  n=10  rescued 0%  died 100%  causes: hypothermia=5, starvation=3, dehydration=1, exposure=1  (d2=5, d5=4, d6=1)
```

This is a known open item in `boreal-src/AGENTS.md`: *"Sprint-8 open: harness
bot policies regressed after the crash-site move (bots die d2–5; naive mostly
wolves) — camp scouting rewritten around CRASH, needs re-tuning toward the
rescue band (naive ~60% die, optimal ~5%)."* The target band in the card is
the tuning GOAL, not the current state of the frozen sim.

Port-fidelity evidence (no sim port bug found):

- Core-sim numerics: a no-action idle run (seeds 1, 7, 100 sampled ticks over
  11 days) is **byte-identical** between the TS sim and the GDScript port
  (hydration/hunger/energy/health/coreTemp/wetness to 6 decimals).
- Competent death profile matches TS optimal's non-wolf deaths: same causes
  (hypothermia d1–2 cluster, starvation d5, dehydration d6) and same
  death-day shape (d2=5, d5=4, d6=1 on TS seeds 1–10 vs d2/d5/d6 clusters here).
- Naive differs from TS naive only in cause mix: TS naive deaths are mostly
  `wolf attack` (6/10); wolves are deliberately unported, so those runs die of
  hypothermia/starvation instead. Expected divergence, not a bug.
- The existing golden suite (rng/terrain/needs/world/dangers/craft goldens
  extracted from the real TS sim) is green, so dt conversion and the roll
  stream are pinned.

Per the card ("fix ONLY with a golden-test justification, or report findings
in the summary instead of hacking policies"): **no tuning constants were
touched and no policies were hacked.** The rescue band is unreachable in the
frozen sim itself; closing it is a rebalance of `Config.gd`/`config.ts`
(Sprint-8 work), out of scope here.

## Gotchas for the next worker

- GDScript lambdas capture locals **by value** — the TS per-bot RNG closure
  mutates its captured `seed`; the port uses a method with member state
  (`BaseBot.bot_rng`), and rounds through float64 to reproduce JS
  `seed * 1103515245 + 12345` precision loss bit-for-bit.
- Nested GDScript classes cannot see script-level functions; bot helpers
  (`dist`/`nearest_kind`/`craft_first`/`is_night`) are statics on `BaseBot`.
- `tests/test_balance.gd` asserts the idle floor + per-seed determinism only;
  it deliberately does NOT assert competent-rescued (would fail on the frozen
  sim, same as TS). Re-enable that gate when the Sprint-8 rebalance lands.
- TS harness without node_modules: copy `src/` + `tests/sim/balance*.ts` to a
  scratch dir, append `.ts` to relative imports, `{"type":"module"}` package
  json, run with Node ≥ 22 (`node tests/sim/balance_main.ts N`).

---

# Rebalance 2026-10-11 (card t_664e2ca0): soft energy + auto-sip everywhere

Owner directives landed this card (the second supersedes the first):

1. Energy/stamina must be PURE performance (work speed, walk speed, sprint
   lockout) and must never cause collapse or death.
2. REMOVE the collapse/pass-out mechanic entirely — "passing out simply means
   death in a survival situation". No forced sleep, no blackout, no
   forced-unconsciousness state anywhere in the sim. The old TS
   forced-sleep-on-exhaustion path is deliberately NOT ported.

## Sim changes (DIVERGENCE from TS, marked in config.gd)

- `ENERGY_DECAY_PER_H` 4.0 -> 2.5.
- Stamina ladder: `SPRINT_LOCKOUT_ENERGY` 15.0 (sprint refused below it, HUD
  toast "Too exhausted to sprint." once per episode), `WALK_SLOW_AT_ZERO` 0.3
  (linear move-speed penalty below `DEBUFF_FROM`, max -30% at energy 0),
  `HUNGRY_DEX_PENALTY` 0.15 (starving adds a dexterity contribution; movement
  stays possible).
- Auto-sip fires on ALL movement (idle/walk/run), suppressed only while
  `preoccupied` (a task/action is in progress) or asleep. Sip = half a bottle
  (0.5 L = 25 pts), clamped to carried amount; `AUTO_SIP_BELOW` 50 makes it
  self-limiting.
- NO collapse/pass-out: `Needs.tick()` no longer returns `collapsed`, the
  world's forced-sleep-on-collapse block and the "Your legs give out..." log
  line are deleted, and tests assert energy 0 NEVER forces sleep and never
  produces an exhaustion death cause. Death stays owned by the cold/thirst/
  starvation health drains. (`RescueSim.check_collapse` is the pre-existing
  day-10 rescue deadline, unrelated to energy — kept.)

## Harness after sim changes (20 seeds/policy)

Before (frozen sim, this file's first table): competent median 2.0 d, 100%
dead (hypothermia 11 / starvation 8 / dehydration 1).

After sim changes + bot policy fixes (below):

```
idle       n=20  rescued 0%  died 100%  median 2.0  hypothermia=20 (d2=20)
naive      n=20  rescued 0%  died 100%  median 2.0  hypothermia=20 (d2=20)
competent  n=20  rescued 0%  died 100%  median 4.0  hypothermia=19 starvation=1
  death days: d3=4, d4=7, d5=6, d6=2, d7=1
```

Iteration log (each step re-ran the 20-seed harness):

1. Fire-fetch threshold 50 -> 70: the burn cascade (10/18/30 %/h by stage)
   empties a fuel-50 fire in ~2.5 h; the bot was stoking embers at 21:00.
2. Night tinder emergency: no fire at camp after dark now allows tinder-chain
   gathering (the old night-gate deadlocked: build-fire needs a bundle,
   crafting needs bark, bark-gather was night-gated).
3. Fish branch daylight-gated (bot ping-ponged fish<->curfew at 03:00).
4. Berry eat + forage added; forage moved BEFORE the critical/camp-loop check
   (hunger<30 routed into the camp loop which never forages — a starvation
   trap next to berry bushes).
5. Home-range gathering: prefer targets within 60 m of camp; distant targets
   allowed in daylight only (night errands were the #1 freeze-mid-walk death).
   A strict 60 m cap deadlocked sparse-resource camps into idle-freezing, so
   the fallback is distance-permissive by day.
6. Pack-full dump-wood (a full pack of deadfall must never deadlock the
   tinder chain); snare target search capped to 60 m of camp.
7. Fire-first priority: camp fire < 70 routes into the camp loop (fetch/stoke)
   and outranks snares/shelter/forage; fire < 40 = "sinking" -> immediate
   stoke/return. Side chores only run with a topped-up fire.
8. Snare collect runs only when a line has actually sprung (walking to an
   empty line every tick starved the fire loop).

## Band status — NOT met, and why (honest)

Target band: competent rescued >=50%. Current: 0% rescued, median 4.0 d
(was 2.0). The energy-economy root cause the card diagnosed is real and is
now fixed — deaths moved off the d2 cluster — but the residual killer is the
hunger->health-drain model itself: `CRITICAL_HUNGER_HP_PER_H` makes hunger-at-
0 a slow death sentence no policy-realistic foraging bot can out-work in
winter, and hypothermia still dominates because a sinking fire at -20 °C kills
faster than any chore list. The frozen TS reference harness rescues 0% for
the same reasons (see first section). The structural fix is the weight-based
calorie model (card t_da550b46, child of this card): hunger-at-0 burns mass
instead of health, malnutrition is a day-8-11 tail risk, hypothermia stays
#1. Re-measure the band there; `tests/test_balance.gd` still deliberately
does not assert competent-rescued until that lands.

## Gotchas

- The competent bot's `sleep()` "exhaustion-nap" is VOLUNTARY policy (a human
  choice), not a sim mechanic — the sim itself never forces sleep.
- `fire_sinking`/`lit_at_camp`/`camp_fuel_now` are computed once at the top of
  `CompetentBot.tick` and shared by the forage/snare/critical gates — don't
  re-declare them lower (GDScript shadowing error).

## Weight-based calorie model (card t_da550b46, owner directive 2026-10-11 v2)

Sim changes (all DIVERGENCE-commented in config.gd / needs.gd / items.gd /
actions.gd): hunger-at-0 burns MASS (weightKg, start 80 kg; STARVE_KG_PER_DAY
3.2 game-scale, shiver/sprint multipliers stacked) instead of draining
health; cutoffs 74/68/60 kg add the performance ladder (walk/dexterity/
strength + WEAK_ENERGY_MUL 1.3); <60 kg drains health (STARVATION_HP_PER_H
1.5) and kills nameably ("starvation (malnutrition, 58 kg)"). Surplus kcal
(Items.KCAL, eaten above a full stomach) bank into calorieBank and refill
mass at FILL_KG_PER_DAY 0.4. Sleep is a requirement: energy restores ONLY
while sleeping; waking streaks > 30 h grow the drowsiness debuff to full at
42 h (DROWSY_AFTER_H/DROWSY_FULL_H). CRITICAL_HUNGER_HP_PER_H deleted.
weightKg/calorieBank/awakeH are hashed in the determinism test.

Harness before (parent card, frozen hunger-drain sim):
competent 0% rescued, median 4.0 d, hypothermia=19 starvation=1.

Harness after (20 seeds/policy):

```
idle       n=20  rescued   0%  died 100%  median 2.0  hypothermia=20 (d2=20)
naive      n=20  rescued  35% (avg d8.1) died  65%  median 7.0  hypothermia=7 dehydration=6
competent  n=20  rescued  50% (avg d7.3) died  50%  median 7.0  hypothermia=8 dehydration=2
  rescue days: d7=8, d8=1, d9=1
```

Band: idle ~100% hypothermia d2 ✓ (floor holds), naive 65% die ✓ (40-90%),
competent 50% rescued ✓ (>=50%). TARGET BAND MET. Hypothermia still the #1
death cause for both dying policies; starvation deaths are gone from the
harness entirely (the weight tail only bites a never-eats player around
day 8-11, past the harness deaths).

Iteration log (each step re-ran the 20-seed harness or a per-hour trace):

1. Weight model landed; competent median 4.0 -> 5.0, starvation deaths 1 -> 0.
   Residual killer: fire-out-at-night freeze (unchanged from parent card).
2. Friction-light RETRY COOLDOWN (bot): the old bot spammed light_fire 40×/s
   on failed rolls (cold hands -> p~0.05), burning its whole tinder reserve,
   then froze beside a pack of bundles. Now one strike per ~1 game-hour.
3. Night tinder errand un-gated (bot): gather()'s night gate now exempts
   urgent_wood (fire OUT at night is the one errand a real player makes in
   the dark); the stock-branch reachability pre-check that deadlocked
   build-fire with an empty chain is gone.
4. Signal-run vitals gate (bot): the day-6 shore march now requires
   hydration>55 / hunger>45 / energy>25 — it used to walk the bot to shore
   starving and dehydrated (d6 'water ran out' mid-march). Same light_fire
   cooldown applied to the shore branch.
5. FLARE FROM CAMP (bot): the flare line lived inside the vitals-gated shore
   move, so camp-bound bots reached day 10 with a full flare gun and died of
   "the search gave up". A competent player fires at the day-7 dawn pass
   from wherever they stand (0.95 detection). This alone took competent
   20% -> 50%.
6. emergency-snow deadlock (bot): begin_work grabs the nearest PROP within
   reach, and a prop whose yield doesn't fit the pack completes with no
   yield forever — the bot re-scooped one bark prop for 10 h and died of
   thirst next to a lit fire. Snow tasks now start directly (id -1), and
   camp_fire stands still while any task runs (tick_work cancels tasks on
   movement — the old fetch-fuel branch cancelled its own thirst task every
   tick).
7. Cold-sleep guard (bot): exhaustion-naps require core > 35.5 °C, and
   forage/snare side chores require core > COLD_C — a freezing player stays
   by the fire instead of napping into hypothermia at 34 °C.

test_balance re-pins (DIVERGENCE): naive death assertion moved seed 2 -> 5
(seed 2 now legitimately gets spotted by its wreck fire at the d7 pass), and
the competent-rescued gate is RE-ENABLED on seed 3 (stable d7 flare rescue)
— the old 0%-rescue premise is dead.

Gotchas:
- Naive rescues (35%) are honest: NaiveBot keeps a fire at the exposed
  shore, and detection_chance gives anyFire+openGround 0.32/pass over 8
  passes. If the owner wants naive strictly <40% die-survival, nerf
  open-ground anyFire detection, not the bots.
- The harness runtime doubled (~100 s -> ~240 s / 20 seeds) because bots
  now survive to the rescue window instead of dying at d2-4.
