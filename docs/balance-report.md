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
