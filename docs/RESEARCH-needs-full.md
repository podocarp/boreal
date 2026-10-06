# Survival Needs/Metabolism Systems — Research for a Survivorman-style Browser Survival Game

Compiled 2026-10-06. Sources cited inline. Target design: realistic first-person-ish survival,
1 in-game day ≈ 10–15 real minutes, needs must have real consequences without "click the bottle
every 5 minutes" micromanagement.

---

## 1. Per-game breakdown

### Project Zomboid
- **Needs:** hunger, thirst, fatigue, temperature, pain, panic, stress, unhappiness, boredom,
  discomfort, wetness, sickness (illness/food sickness), plus a separate calories/nutrition
  subsystem (647 food defs with calories, carbs/lipids/proteins, spoilage).
  (https://projectzomboid.com/modding/zombie/characters/CharacterStat.html,
  https://www.bamboogaming.net/project-zomboid/food-water)
- **Pacing:** on Normal, hunger/thirst take roughly a full in-game day to go from fed to hungry;
  fatigue builds within minutes of running/fighting, exhaustion in under an hour of hard labor.
  Hunger is 100→0; below ~30 = "starving," health drains. (https://trendsmask.com/how-fast-the-players-hunger-thirst-and-fatigue-will-decrease-zomboid-1152707.html,
  https://steamcommunity.com/app/108600/discussions/0/4363501716022123805)
- **Gating:** manual eat/drink, but **vanilla has an Auto-Drink toggle** (context menu / sandbox
  option; a whole mod exists just to *disable* it: https://steamcommunity.com/sharedfiles/filedetails?id=3598196432).
  The hugely popular "Auto Eat" / "Automate Series" mods auto-eat when the first negative moodle
  appears, prioritizing perishables, skipping dangerous/rotten/alcohol, eating partially to avoid
  waste (https://steamcommunity.com/sharedfiles/filedetails/?id=2977628726,
  https://steamcommunity.com/sharedfiles/filedetails/?id=3034859905). This is direct market
  evidence that players want auto-consume from stockpiles.
- **At zero:** starving = health loss + no stamina recovery; exhaustion = missed swings, slower
  reading, collapse; dehydration kills before starvation; boredom compounds into stress; stress
  reduces skill gain and triggers panic; pain reduces accuracy and limits actions.
  (https://projectzomboid.wiki/guides/entertainment-moodles, https://projectzomboid.wiki/guides/moodles)
- **UI lesson:** "moodles" are a stacked icon queue; hover = exact penalty. Guides teach reading
  them as a priority queue (bleeding/panic first → thirst/hunger → weather/mood). Reactive
  management = already penalized; proactive = prevent thresholds.
- **Controversy:** boredom is widely called a broken chore ("you gain boredom while cooking and
  crafting; replace with stress"; "I can 100% game this by reading skillbooks outside")
  (https://steamcommunity.com/app/108600/discussions/0/4299250686372151554).

### The Long Dark
- **Needs:** Warmth, Fatigue, Thirst, Hunger → all feed a single **Condition** (health) pool.
  Injuries/afflictions (sprains, infection, food poisoning, hypothermia, frostbite) are separate.
  (https://thelongdark.fandom.com/wiki/Condition)
- **Pacing / at-zero rates (documented, excellent reference):** when a need hits 0, condition
  drains per hour: **Warmth −18.75%/h, Thirst −2.08%/h, Hunger −1.04%/h, Fatigue −1.04%/h.**
  Warmth is the only fast killer; food/water/rest kill slowly. Condition regen is ~1%/h while all
  needs >0; sleeping 10h in a bed restores up to 65% condition if you drink water and have ~600
  calories. (https://thelongdark.fandom.com/wiki/Condition, https://inanage.com/tag/the-long-dark)
- **Calories model:** expenditure is activity-based (walking ~270 cal/h, sleeping 75 cal/h,
  breaking a crate ~62 cal, MRE ~1800). Food = calories, not "hunger points."
  (https://inanage.com/tag/the-long-dark, https://earlyguides.com/the-long-dark)
- **Exploit lesson ("Hibernation meta"):** because zero-hunger only costs ~1%/h condition while
  sleep heals, players starve all day and eat 600 cal before bed, needing ~600 cal/day instead of
  ~3400. The community **Hunger Revamped** mod fixes it by splitting hunger vs *stored calories*
  (body-fat pool, up to 20,000 cal ≈ a week): full hunger stores fat, empty hunger burns fat,
  starvation damage scales 0→5%/h as the fat store empties, and fat gives warmth bonus / leanness
  gives cold penalty. This is the single best reference design for "hunger with long-term
  consequence and no daily nagging." (https://github.com/TLD-Mods/HungerRevamped)
- **Warmth:** "feels-like" temp = ambient + windchill − clothing insulation; wet clothes lose
  insulation; hypothermia blurs vision, slows movement, cuts carry capacity → downward spiral.
  Frostbite is **permanent max-condition loss** (−10% per instance, up to death). Affliction DoTs:
  blood loss −30%/h, infection −5%/h, dysentery −4%/h, food poisoning −3.5%/h but non-lethal
  (floors at 15% condition). (https://thelongdark.fandom.com/wiki/Condition,
  https://playreviewlab.com/blog/the-geometry-of-frost--the-micro-logistics-of-caloric-decay-and-hypothermia-in-the-long-dark)
- **Consumption gating:** fully manual (eat/drink are sit-down actions with time cost); praised as
  tense because scarcity never trivializes (see §2).

### Green Hell
- **Needs:** Health, Hydration, Energy, plus **macroelements (carbs/fats/protein)** and **Sanity**;
  wounds/ailments layer on top (lacerations, infection, fever, parasites, worms, leeches, rashes,
  venom, food poisoning, insomnia). (https://greenhell.fandom.com/wiki/Healing_Guide,
  https://en.wikipedia.org/wiki/Green_Hell_(video_game))
- **Design intent (dev interview):** sanity modeled on Ed Stafford's books — "will to live" is the
  base of the survival pyramid; every mechanic is a trade-off: eating only worms keeps you alive
  but drives you insane; leeches don't damage HP at all, they drain sanity; sitting by a fire
  costs time to regain sanity. Dirty water: drink it and risk parasites, or die of thirst —
  dehydration kills faster than parasites. (https://www.gamedeveloper.com/design/designing-for-survival-in-steam-early-access-hit-i-green-hell-i-,
  https://www.reddit.com/r/GreenHell/comments/1hxo8s5/dying_of_thirst/)
- **Infection design:** any unbandaged wound becomes infected over time → fever (drains energy +
  hydration faster) → death if untreated; treated with maggots on the wound. Body inspection is
  the diagnostic UI. (https://greenhell-archive.fandom.com/wiki/Wound_Infection,
  https://greenhell.fandom.com/wiki/Healing_Guide)
- **Complaint:** opacity — "mechanics that aren't very clear such as insanity and infection
  killing you when you think you won't die" (https://steamcommunity.com/app/815370/discussions/0/5179725348510827241/?l=dutch).

### Stranded Deep
- **Needs:** Health, Hunger, Thirst, **Sunlight/sunstroke** (sunstroke doubles dehydration rate);
  ailments: poison (snake/starfish), broken bones, vomiting/diarrhoea which *dump thirst rapidly*
  — over-drinking coconut water causes diarrhoea, a net hydration loss. Raw food → illness.
  Health regenerates passively only while hunger & thirst stay >80%. Sleeping drains both.
  (https://stranded-deep.fandom.com/wiki/Vitals, https://www.gamespew.com/2021/05/how-to-get-water-in-stranded-deep)
- **Gating:** fully manual; watch UI shows vitals. Water still / crops turn it into logistics.

### Don't Starve
- **Needs:** Hunger (150), Health, Sanity. Day ≈ 8 real minutes (close to our target day length).
- **Pacing:** hunger drains 9.375/min = 75/day → **a full belly lasts exactly 2 in-game days**
  (~16 real min). At 0: −1.25 HP/s (150 HP in 2 real minutes — harsh but fast enough to be
  "you had a warning window"). (https://dontstarve.wiki.gg/wiki/Hunger,
  https://dontstarvetogether.wiki.fextralife.com/Survival_Conditions)
- **Sanity:** drains contextually (−5/min at dusk/night, −50/min in darkness, auras from
  monsters/rain/wet clothes), restored by safe foods, sleep, fire, clothes. Low sanity =
  hallucinations that become *real attackers* below 15% — the mental need manifests as physical
  threat rather than a stat tax. (https://dontstarve.wiki.gg/wiki/Sanity)
- **Food depth:** freshness stages (fresh/stale/spoiled) trade hunger vs health/sanity; cooking
  improves value and resets spoilage; seasonal diets. Eating is manual, one click, stacks.
  (https://dontstarve.wiki.gg/wiki/Food/DST)
- **Design analysis:** pressure is converted into exploration motivation; high death rate +
  trial-and-error is accepted because deaths read as learnable, and all three meters trade
  against each other (sleep restores sanity+health but burns hunger).
  (https://www.atlantis-press.com/article/126021848.pdf, https://annamalecki.medium.com/game-design-analysis-dont-starve-50d06561097d)

### Raft
- **Needs:** Hunger + Thirst only (plus survival stats added later). **Rate: 0.09/s → full bar
  empties in 18:31 on Normal** (30:52 Easy, 12:21 Hard). At low hunger: movement slows; at 0:
  −0.75 HP/s → dead in ~2:13 from full HP. 20s digestion lockout after eating.
  (https://raft.fandom.com/wiki/Hunger)
- **Craving system (key mechanic):** food/drink effectiveness scales with how empty you are
  (curve, ~0→1), so eating when nearly full wastes little — removes "waste anxiety" and
  "top-up spam" simultaneously.
- **Complaint:** "The entire thirst/hunger mechanic needs an overhaul. Got tired very rapidly of
  micromanaging water and food production" (https://steamcommunity.com/app/648800/discussions/0/1694922345929914628/).
  The chore was *production* (freshwater smelties, crop watering), not consumption.

### Valheim (the widely-praised counter-model)
- **No starvation at all.** Food = 3-slot buff loadout: each food grants max HP/stamina + regen
  rates, decaying over ~25 real minutes; no repeats allowed, so variety is the gameplay.
  (https://valheim.fandom.com/wiki/Food)
- Analysis: reframes eating from **loss prevention to gain** (loss aversion; WoW's "rested XP"
  reframe of the fatigue penalty is the canonical precedent). Punitive hunger works only when
  scarcity is the game's point (TLD, Don't Starve, early PZ); grafted onto non-scarcity games
  (Fallout 4 survival) it's pure interruption. And punitive systems that trivialize late-game
  become a "maintenance tax": the bar still ticks even when you own a farm.
  (https://unmappedworlds.com/posts/why-valheims-food-feels-good/)

---

## 2. Harsh-but-fair vs. chore — the patterns

**Harsh-but-fair:**
1. **Death comes from mistakes, not timers.** "A vast majority of players do not tolerate dying
   for any reason other than a direct gameplay mistake they just made… watching hunger hit 0 with
   no time to fix it is the ultimate rage-quit moment." (r/gamedesign:
   https://reddit.com/r/gamedesign/comments/1bvhhae/how_can_we_improve_on_survival_game_systems)
2. **Consistent, learnable rules + persistent consequences** ("harsh but fair" = rules consistency
   + consequence persistence + clear communication). (https://cjgeringer.wordpress.com)
3. **Needs interlock with the core loop** rather than sitting beside it: TLD's warmth→carry
   capacity→calorie spiral; Green Hell's dirty-water risk/reward; Don't Starve's sleep-eats-hunger
   triangle; Stranded Deep's sunstroke→2× dehydration. A need is good when fixing it forces a
   dangerous decision.
4. **Slow lethality, fast debuffs.** TLD: only warmth kills fast (−18.75%/h); food/water/rest kill
   at ~1–2%/h, so neglect costs *capability* for a long time before it costs the run.
5. **Buffers that store past effort:** fat reserves / stored calories (TLD Hunger Revamped,
   Vintage Story community consensus) let a well-fed player skip meals during a crisis — the
   opposite of the every-5-minutes bottle click.
6. **Reward framing beats punishment framing:** Valheim food buffs, "Well Fed" positive moodles
   (TLD Well Fed = +5% condition, +5kg carry; PZ positive food moodle as buffer).
7. **Scarcity that stays real** (TLD) or a designed exit from the mechanic once mastered
   (Minecraft's arc: threat → farm → minor inconvenience). "Either keep the mechanic challenging
   throughout, or accept it becomes redundant and remove the busywork." (r/gamedesign)

**Chore patterns (avoid):**
1. **Chip damage + nagging audio** when a need is low ("nothing annoys me more than hearing chip
   damage from hunger" — Vintage Story forum:
   https://vintagestory.at/?app=core&content_class=forums_Topic&content_commentid=117030&content_id=21910).
2. **Immediate drain after topping up** (ARK's visible number-spin). "After I eat, my meter should
   stay 100% for a good amount of time." (PC Gamer:
   https://www.pcgamer.com/how-survival-games-get-hunger-and-thirst-wrong-and-how-to-fix-it/)
3. **Thirst = second hunger bar** at the same rate. Thirst should be faster/more urgent than
   hunger (realism + it changes route planning around water sources). (PC Gamer, same)
4. **Meters that rise while you're actively doing things** — PZ boredom gaining during
   carpentry/cooking; universally loathed, "game this by reading outside."
5. **Production micromanagement** (Raft water stills, crop watering every N minutes) — the chore
   is usually *maintaining the supply chain*, not the eating itself.
6. **Click-friction consumption** (Starbound non-stacking food: "eating takes at least 3 clicks,
   bandages stack and take 1").
7. **Opaque lethal thresholds** (Green Hell "infection killing you when you think you won't").
8. **Too many parallel bars** where each is a separate timer with the same shape (PZ moodle
   overload; "thirst meter being just a second hunger bar is realism-as-tedium").
9. **Hunger as pure gate on a non-survival loop** (Fallout 4 survival mode) — friction without
   meaning.

---

## 3. Recommended defaults for OUR game

Assume **1 in-game day = 12 real minutes** (1 in-game hour = 30 s). Scale linearly for 10–15 min.
Needs on 0–100.

**Needs (4 primary + derived states — resist more):**
1. **Hydration** — base −4.0/h (≈25 in-game h ≈ 1 day to empty). Multipliers: ×2 in heat/heavy
   labor/sunstroke, ×0.5 at rest in shade. Fastest bar; primary "day planner."
2. **Energy (hunger)** — base −2.5/h awake, −1.25/h asleep (≈40 h ≈ 1.7 days). Activity-scaled
   like TLD (chopping/carrying/paddling add up). **Back it with a hidden Fat Reserve** (0–100,
   ≈1.5 in-game days of buffer): surplus eating stores fat, empty Energy burns fat first.
   Starvation debuffs only start when fat is low — this kills the daily-nag AND the TLD
   hibernation exploit in one move.
3. **Rest (fatigue)** — −5/h awake (≈20 h to exhausted), −8/h while injured/sick; sleep +12/h in
   a bed/shelter, +8 hushed by a fire, +5 rough outdoors. Sleep is a time-skip (see below).
4. **Core temperature** — NOT a draining bar. Body temp moves toward an equilibrium set by
   ambient+windchill vs insulation (layers, dryness, shelter, fire), TLD-style. Display as a
   "feels-like" number + shivering/sweating cues. Freezing → hypothermia (vision blur, −speed,
   −carry, DoT); prolonged cold exposure leaves **permanent frostbite scars** (max-health cap
   reduction) for Survivorman-style long-term cost.

**Derived states (not bars):** Pain (from wounds; −accuracy, −melee damage; fades with healing),
Bleeding (DoT, bandage), **Infection** (untreated wound chance rises with dirt/water quality;
once infected: fever = +50% hydration & energy drain + slow HP DoT; untreated → death in ~2–3
in-game days; treatable with cleaned dressing/antibiotics), **Morale/Morale-adjacent** — do NOT
copy PZ boredom. Use a slow "Isolation/Routine" meter that only drains when doing nothing but
grinding (camp chores with no variety, no camp improvements, rainy days indoors with nothing to
do) and is fixed by *activities the player would choose anyway* (cooking a real meal, crafting at
the bench, radio/trinkets). Low morale → slower skill gain + higher panic chance, never death.

**At zero (tiered, debuff-first, death last):**
- Tier 1 (below 30): warning cues (stomach growl ONCE per threshold, not looping; vignette),
  −10–20% relevant stat.
- Tier 2 (at 0): hard debuff (−40% stamina regen, −carry, aim sway, screen desaturation) + slow
  HP drain: hydration −2%/h, energy −1%/h (only when fat empty), rest −1%/h + forced microsleeps
  (character passes out for 1–2 in-game hours = the real punishment). **Zero never one-shots;
  death from pure neglect takes ≥1.5–2 in-game days (15–25 real min) of total inaction** — long
  enough that any death is "I chose to ignore it" or "I had no water anywhere," i.e., a mistake.
- Death should overwhelmingly come from the world (wolves, falls, infection, freezing storms),
  not from the meter itself.

**Auto-consume (the anti-chore core):**
- Per-category toggles (default ON for drink, OFF or ON for food — test): when a need crosses
  ~25%, the character automatically consumes the best item from inventory/belt with a short
  animation and a one-line log ("drank from canteen"). Interrupted by combat/aggression.
- Selection rules (proven by PZ Auto Eat): perishables before canned; never alcohol, spice,
  medicine, marked/cooking-ingredient items; skip rotten/poisonous unless dying; partial-eat to
  avoid waste; Raft-style craving curve so near-full consumption isn't a total waste.
- **No production chores:** water stills/filters/fires fill passively over in-game time; crops
  grow on day-timers with no watering click. The chore budget goes into the expedition loop,
  not the larder.
- Eating/drinking should still *exist* manually because it's a risk window (you're vulnerable
  while eating; PZ mod "Slow Eat & Drink" exists because that tension is fun) — auto-consume
  only fires at safe thresholds, manual fast-swig in emergencies.

**Sleep design:** sleep only where defensible; time-skip to dawn with a roll: safe shelter+bed =
full restore + condition heal (TLD: needs food+water before bed to heal while sleeping);
exposed spot = partial restore + nightmare (−morale, wake at 60%) + ambush risk. Pushing through
with caffeine gives a short window then a crash (PZ pills lesson). Never force sleep mid-activity
except the Tier-2 microsleep penalty.

**Injury/infection design (Survivorman flavor):** injuries are persistent with a healing timer
(sprain 1–2 days, fracture 5–7 days, deep wound 3–4 days if cared for); they heal only while fed
+ rested (links needs to long-term health); bad first aid (dirty water, no disinfectant) →
infection chain above; frostbite permanent. Show via body-inspection screen (Green Hell) not
floating numbers.

**Pacing sanity check:** with these rates a player engages with food ~1×/in-game day, water
~1–2×/day *from stockpiles automatically*, sleeps once/day as a deliberate camp ritual — i.e.,
2–3 need-driven decisions per 12-minute day, all of them planning decisions (what to carry, where
to get water, where to bed down), not button-mashing. Don't Starve's "full belly = exactly 2
days" is the closest proven benchmark at our day length.

---

## 4. Common pitfalls players complain about (checklist)

- Dying to a ticking meter rather than a mistake (top rage-quit cause).
- Chip damage / nagging sounds from needs; hunger DoT spam.
- Meter visibly draining the second after you fill it (ARK).
- Thirst and hunger draining at identical rates / thirst not mattering more.
- Boredom/stress meters that rise while the player is busy doing survival things (PZ).
- Late-game "maintenance tax": bar still ticks after you've solved food (PZ farms, Fallout 4).
- Production micromanagement (Raft water/crops, Stranded Deep still refills).
- Multi-click consumption, non-stacking food, no auto-consume (PZ players mod it in; whole mod
  series exists).
- Hidden lethal thresholds and unclear ailment chains (Green Hell insanity/infection).
- Exploitable single-variable hunger (TLD hibernation meta: starve all day, eat 600 cal, sleep).
- Punishing good play / arbitrary debuffs (Dark Devotion lesson) — penalties must trace to
  mistakes.
- Needs that don't interact with anything else (redundant bar).
- Too many bars at once (moodle soup) — communicate via a small priority queue, not 12 icons.
- Early-access-style brutal starting rates that chase off new players (PC Gamer: start forgiving,
  tune later; offer a decay-rate slider in singleplayer).

## Key sources
- https://thelongdark.fandom.com/wiki/Condition (need-zero drain table, affliction rates, frostbite)
- https://github.com/TLD-Mods/HungerRevamped (stored-calories design)
- https://inanage.com/tag/the-long-dark (hibernation meta, calorie costs)
- https://projectzomboid.wiki/guides/moodles + /guides/entertainment-moodles (moodle priority, tiers)
- https://steamcommunity.com/sharedfiles/filedetails/?id=2977628726 (Auto Eat mod — auto-consume rules)
- https://steamcommunity.com/sharedfiles/filedetails?id=3598196432 (vanilla auto-drink exists)
- https://dontstarve.wiki.gg/wiki/Hunger (9.375/min, 2-day belly, 1.25 HP/s at 0)
- https://dontstarve.wiki.gg/wiki/Sanity (contextual drains, shadow creatures)
- https://raft.fandom.com/wiki/Hunger (0.09/s, craving curve, 2:13 death)
- https://stranded-deep.fandom.com/wiki/Vitals (sunstroke, fluid loss via illness, >80% regen rule)
- https://greenhell.fandom.com/wiki/Healing_Guide + https://www.gamedeveloper.com/design/designing-for-survival-in-steam-early-access-hit-i-green-hell-i- (ailment chains, sanity-as-will-to-live)
- https://valheim.fandom.com/wiki/Food + https://unmappedworlds.com/posts/why-valheims-food-feels-good/ (buff model, maintenance tax, loss aversion)
- https://www.pcgamer.com/how-survival-games-get-hunger-and-thirst-wrong-and-how-to-fix-it/ (fill-then-leave-alone, thirst>hunger, adjustability)
- https://reddit.com/r/gamedesign/comments/1bvhhae/how_can_we_improve_on_survival_game_systems (buff-vs-debuff, well-fed investment, death-by-mistake)
- https://vintagestory.at/forums topic 22047 (fat reserves, malnourishment-before-death)
- https://steamcommunity.com/app/108600/discussions/0/4299250686372151554 (boredom backlash)
- https://cjgeringer.wordpress.com (rules consistency + consequence persistence = harsh-but-fair)
