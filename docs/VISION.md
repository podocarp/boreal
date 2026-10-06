# BOREAL — Game Vision

> Read-this-first doc for any agent (or human) joining this project with empty context.
> Status: v0.2 (2026-10-06). Decisions marked **[LOCKED]** are agreed with the user; don't change them without asking.

## One-liner
A realistic 3D wilderness survival game: you are alone in the Canadian subarctic (Northwest Territories) after an aircraft incident, in the spirit of Les Stroud's *Survivorman* Arctic episode. Get warm, get water, get food, signal for rescue — survive until the helicopter comes.

## Pillars
1. **Realistic, not simulationist.** Mechanics mirror real subarctic survival skills (firecraft, debris shelter, snaring, hypothermia) but every system must earn its click budget. **[LOCKED]** No "click the bottle every 5 minutes." Needs are managed in batches (drink/eat when at camp from stock), with automation where sensible.
2. **Punishing but fair (Project Zomboid flavor).** Mistakes compound: stay wet near a fire → hypothermia anyway; skip food → shivering worse, sleep worse, mistakes more likely. Death should be traceable to a chain of decisions the player can name.
3. **Skills over timers.** The interesting choices are *how* (feather stick vs. bark, shelter site placement, trap placement, when to push for distance vs. stay), not *when the meter beeps*.
4. **Stylized, not realistic art.** **[LOCKED: user direction]** Low-poly stylized look (flat-shaded, limited palette, simple shapes — think Firewatch-ish readability). No character animations for MVP (capsule/simple mesh slides; interactions are prompts + state changes, not emotes). Good lighting/fog/sky color does the heavy lifting. Graphics polish beyond "pleasant stylized greybox" is out of MVP scope.

## Scenario: subarctic boreal forest / muskeg, NWT-style **[LOCKED: user chose Arctic]**
- **Premise:** bush plane goes down on a remote lake edge; you survive with a minimal grab bag (knife, tin cup, emergency blanket). Rescue is scheduled: a search pattern passes the area around **day 7** — you must survive ~6 in-game days and be found (signal fire / flare / being seen moving) or walk out (later feature, not MVP).
- **Environment:** boreal forest (spruce/fir/pine/birch), muskeg bog with open water leads, a stream flowing to the lake, rocky ridge. Late-autumn/early-winter shoulder season: short days (~8h light), cold (−5…−20 °C band), snow patches, occasional snowstorms and high wind.
- **Why this scenario works:** cold is the master pressure that ties every system together (fire, shelter, clothing, wetness, food = fuel for heat, sleep = recovery). Water is never a chore (melt snow — but eating snow raw is a bad idea, a real decision). Food is skill-based (snares, ice fishing, berries). Dangers: wolves, falling limbs ("widowmakers"), injury → infection, storms. Rescue signal is the win condition, giving a clear arc.

## Session shape (MVP)
- One run = ~6 in-game days ≈ 60–90 real minutes (1 in-game day ≈ 10–15 real min).
- Start: crash site (lootable wreck, flare gun w/ 1 flare, first-aid scraps).
- End states: **RESCUED** (signal seen / spotted during search window), **DEAD** (hypothermia chain, starvation chain, trauma, wolves), **GIVEN UP** (player quits to summary).
- End-of-run summary: days survived, cause of death/rescue, key stats, skill lessons (death screen explains *why*, Survivorman-style).

## Explicit non-goals for MVP
Crafting trees beyond survival kit, base-building beyond shelters, cooking depth beyond "safe/unsafe/raw", clothing tailoring, wildlife beyond wolves + small game + birds, save/load mid-run (nice-to-have), multiplayer, audio polish, controller support, procedural world gen (hand-authored map), localization.

## Where things live
- `docs/VISION.md` — this file (why/what)
- `docs/DESIGN-needs.md` — needs/metabolism system spec (the most delicate design)
- `docs/DESIGN-world.md` — map, resources, dangers, rescue
- `docs/TECH.md` — stack, architecture, testing strategy
- `docs/PLAN.md` — sprints, stopping point, status log
- `docs/RESEARCH-*.md` — research digests feeding the above
- `docs/DECISIONS.md` — decision log (append-only)
