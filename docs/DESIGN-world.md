# DESIGN — World, Resources, Dangers, Rescue

> Status: DRAFT v0.1 — scenario facts pending `docs/RESEARCH-survivorman.md` digest (in progress).
> Setting: NWT-style boreal forest / muskeg edge, late autumn. Hand-authored map ~400 m half-size.

## Map zones (greybox layout)
1. **Crash site** (lake shore, map center-south): the wreck — lootable once (grab bag: knife, tin cup, emergency blanket, flare gun + 1 flare, duct tape). Open, windy, exposed — bad camp, good signal spot.
2. **Spruce forest** (everywhere): deadfall standing & downed wood (fuel, construction), spruce boughs (bedding/shelter insulation), bark (tinder), evergreen tips (tea/vit C flavor), berry patches (low yield).
3. **Birch stand** (rocky ridge side): bark strips = best tinder (burns wet), sap (waterproofing/adhesive, later).
4. **Stream** (forest → lake): running water (safe-ish if boiled; moving water still treatable), fishing holes under ice edges, beaver-sign snare runs along banks.
5. **Muskeg bog** (north): open water leads, cranberry hummocks, dangerous footing (slow movement, soaked boots → wetness mechanic), leech-free but cold-water hazard.
6. **Rocky ridge / outcrop** (west): wind-exposed, visibility point (spotting planes), dry fuel scarce. Good signal-fire site, bad camp site.
7. **Old trapper's cache** (far NE, optional discovery): a stash that rewards exploration (tin can, wire for snares, matches — a game-changer if found early).

## Resource → use map (MVP)
| Resource | Gets you |
|---|---|
| Deadfall wood (sizes: punk/twig/kindling/log) | fire stages, shelter frame, platform |
| Spruce boughs | bedding (sleep warmth), shelter insulation |
| Birch bark | tinder (burns wet), containers (bark dish/basket), torch |
| Green boughs + debris | debris shelter walls/roof |
| Rock (hand-carriable) | fire reflector wall, cooking "boil-and-drop" stones |
| Wire sinew / paracarp (cache, wreck) | snares |
| Ice/snow | water (must melt — eating snow lowers core temp, real mechanic) |

## Fire system (S4)
- Stages: ember → tinder nest → kindling → stick fire → log fire. Each stage has a maintenance window; neglect = collapse back a stage. Fuel consumption curve per stage.
- Friction fire (bow drill, hand drill): multi-step (hearth+spindle from specific dry deadwood, tinder bundle prep, ember catch, blow-to-flame). High failure risk when cold/hands-damp/inexperienced — the player should *dread* needing fire at night with wet hands. Matches (cache) shortcut it → makes exploration meaningful.
- Fire uses: warmth radius, drying (clothing/bag/boots), melting/boiling water, cooking, signal smoke (green boughs on fire = white smoke column — key for rescue), morale/sleep quality, wolf deterrence.

## Shelter system (S5)
- **Debris shelter** build steps: site prep → ridgepole frame → ribbing → bough insulation (thickness matters) → debris leaf mulch (depth matters) → bedding platform (critical: ground steal, not air).
- **Site scoring** (shown as qualitative hints, not numbers): wind exposure, distance to water & fuel, "widowmaker" dead standing trees overhead (real hazard: falling limbs kill — a scripted event if you camp under one), snow-load/sun.
- A good shelter + dry bedding should roughly *double* overnight warmth margin. A bad site should visibly punish (wind flushing, wet snowmelt drip).

## Food (S6)
- **Snares** (snowshoe hare sign): placement skill (runs, pinch points, fresh sign), checking rounds, set/trigger mini-interaction, weather (snow buries sets). 2-4 snares max — a maintenance loop, not a farm.
- **Fishing**: ice-edge hole or open stream pool; needs cordage/hook improvisation (bone hook, snare wire); time-of-day matters.
- **Berries/cranberries**: calorie floor, not a main — foraging is a stopgap.
- Eating raw vs cooked: cookable items safer/tastier; raw small game has small infection risk.

## Dangers (S6)
- **Wolves**: pressure, not horror. They stalk/circle, test camp edges on windless nights, avoid fire/light and active noise. Fairness rules: reaction delays, no instant kills — attacks are repel-able if prepared; they finish the already-dying. First MVP predator.
- **Storms**: scripted weather events (1-2 per run): wind (tears poorly-built shelter, blows out fire), wet snow (soaks everything, kills firewood dryness), whiteout (navigation loss).
- **Injury → infection**: chopping/climbing/widowmaker mishaps; untreated → sepsis slide; first-aid from wreck is finite.
- **Cold water immersion**: bog leads / river crossing — fast core-temp hit, urgent dry-out need.

## Rescue & win condition (S7)
- Search window opens **day 7** (two passes: dawn and dusk, weather permitting).
- Detection score at pass time = f(signal fire lit & smoky, being in the open/ridge, flare used (1 shot), shelter visible from altitude, movement).
- Weather can scrub a pass → tension: day 7 might not be your day.
- Loss states: death (any chain), or day 10 without rescue → exposure-collapse end (game over with summary).
