# DESIGN — Needs & Metabolism System

> Status: DRAFT v0.1 — numbers pending `docs/RESEARCH-needs.md` digest (in progress).
> This is the most delicate system in the game; the user's hard constraint:
> **consequences without chores** — no "click the bottle every 5 minutes."

## Design stance (agreed)
- Needs are **slow-burning pressures**, not reflex mini-games. A need should move enough in an hour of play that the player *notices the trend*, but never force an action mid-task.
- **Batch management:** the player drinks/eats at camp or on the move from stock, ideally in deliberate "maintenance windows" (breaking camp, after a chore). Auto-consume from equipped stock is allowed for hydration (see below) so a prepared player never dies of thirst while working.
- **Consequences are layered:** need depletion → performance debuffs (vision, strength, decision errors) → health damage only at the extremes. Death from a single need at zero should be *slow* (hours of game time) and always signposted by earlier debuffs.
- **Food = fuel for cold.** Hunger multiplies heat loss / shivering cost. This makes eating matter through the cold system rather than a separate death timer.

## Needs set (candidate — 4, not 6)
1. **Core temperature** (the master stat; not a "need bar" but the central physical model — see thermoregulation section)
2. **Hydration** — auto-sip from carried water when above a floor threshold; drinking snow/meltwater untreated has consequences (see water)
3. **Energy (sleep)** — pressure builds with activity + cold; sleep only safe-ish in shelter by fire; sleep in the cold drains core temp (real risk/reward)
4. **Hunger (calories)** — slow decay; feeds heat production; starvation is a long, visible slide, not a cliff

Dropped for MVP: thirst-as-timer, boredom, morale/depression, micronutrients, thirst-quenching granularity.

## Thermoregulation model (sketch)
- Player has **core temp** (37 °C nominal) and **skin/clothing warmth state**.
- Heat gain: fire proximity, shelter interior, sleeping bag/bedding, food digestion (small), exertion (while active).
- Heat loss: f(air temp, wind speed, wetness, clothing insulation, exposure). Wet clothing is a massive multiplier — drying takes time by fire. This is the game's core "oh no" vector.
- Bands: comfortable → cold (shivering, aim/steadiness debuff) → very cold (dexterity loss: fumbling interactions, slower work) → hypothermic (confusion: inverted controls drift, drowsiness pull, health drain) → death.
- Windchill modeled simply (standard windchill chart approximation), displayed on HUD as "feels like."

## Numbers
> To be filled from research digest + tuning sims in S2. Placeholders only:
- Hydration: full→thirsty ≈ 1.5 game days idle; auto-sip engages below 60%.
- Energy: 16h awake → heavy drowsiness; sleep restores in ~6-7h (compressed).
- Hunger: full→starving ≈ 3 game days; debuffs start at ~35%.
- Core temp: −20 °C, dry, active, decent clothing ≈ stable; same conditions idle at night without shelter/fire → hypothermia band in ~4-5 game hours.

## Death & failure chains (must be nameable by the player)
- "Went to sleep without bedding in −18 °C" → hypothermia.
- "Slept next to the fire, got soaked in the night storm, dried clothes but not the sleeping bag" → hypothermia two nights later.
- "Skipped meals while building the shelter" → shivering worse → fire-building failed from fumbling → cold chain.
Each death screen shows the chain (timeline of contributing events).
