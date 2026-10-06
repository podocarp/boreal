# RESEARCH DIGEST — Needs/metabolism in survival games → our design rules

> Condensed from a research pass (Oct 2026) over TLD, Project Zomboid, Green Hell, Stranded Deep, Don't Starve, Raft, The Forest, This War of Mine + design writeups.
> Key sources: yamoru.blog (TLD survival systems), zomboid.wiki (Hunger/Thirst/Fatigue/Boredom), survivorgamedesign.com, gameknot.com "Harsh but Fair", survivormanual.com.

## What the good ones do
- **4 needs max** (hunger, thirst, energy, warmth). More = spreadsheet (Green Hell's electrolytes/proteins/fats/carbs is the cautionary tale).
- **Decay to critical ≈ 2–4 real hours**: thirst ~1.5–2 pts/h (full→empty ≈ 2 days), hunger ~1 pt/h (≈ 4 days), energy ~4 pt/h awake (16h awake → critical). Warmth is **event-driven** (zone thresholds), not a drain bar, when dressed.
- **Death at zero is slow**: thirst 6–10h, hunger 12–24h at zero, with a "critical" band (15–20%) before it. TLD: starvation kills in ~2 days at zero.
- **Debuffs start at ~40–50%**, not 70% (PZ: hunger effects start at 50). Debuffs are the teaching mechanism; death is the last resort.
- **Warmth/cold as modifier, not need** (TLD): cold accelerates hunger drain and blocks sleep; food powers cold resistance. This is exactly our "food = fuel for heat" pillar.
- **Auto-consume**: precedents exist (PZ pets/children drink/eat from accessible stock; RimWorld auto-eats from allowed stockpile). Rules that keep it from feeling like a tamagotchi: only for the most chore-y need (thirst), only when idle/standing still, visible log line ("drinking from canteen"), player can toggle.
- **Sleep is a risk/reward decision** (TLD: sleep outside in winter = death; TWoM: sleep location = safety tradeoff). Sleep restores ~full energy in 6–7 compressed hours; drowsiness debuffs before that.
- **Injury/infection gated by difficulty** (PZ), from wound + untreated + dirty water/food combo, not random.
- **Comfort/morale as soft debuff only** (PZ boredom: -1 focus, no death timer) — candidate for us, no death contribution.

## Pitfalls players revolt against (our anti-goals)
1. Chore loops (click-bottle) — the user's explicit veto.
2. Invisible mechanics (TLD's hidden calorie/warmth math → wiki dependency). → We surface numbers on hover + death-screen chains.
3. Sudden death / no recovery window. → All death paths pass through visible critical bands + debuffs first.
4. Punishing exploration (Stranded Deep: leave island = die). → Our far cache must be findable and rewarding.
5. Zero-sum needs (eat→thirst↓→need water→...). → No linked drains except intentional food=heat.
6. Micromanagement creep (PZ's 12+ skills). → MVP crafting is survival-kit depth only.
7. No difficulty options. → 3 presets (see below).

## Our defaults (baked into DESIGN-needs.md numbers)
- 4 needs: Hydration, Hunger, Energy + Core temp (physical model, not a bar).
- Decay: thirst 1.75/h, hunger 1.0/h, energy 4/h awake (×1.5 hard labor, ×0.25 sleep). 1 game day = 12 real min.
- Critical band 15%: health drain thirst 1.5%/h, hunger 0.5%/h. Debuffs from 45%.
- Auto-sip: hydration only, idle/standing, from carried treated water, log line, toggleable.
- Warmth: event-driven bands; wet clothing is the big multiplier; exertion & food add heat.
- Sleep only when warm+sheltered restores fully; sleeping cold = core-temp risk (the game's central night gamble).
- Infection only from untreated wounds + contamination events; first aid finite; difficulty presets:
  - **Ranger** (default): above numbers. **Bushman**: decay ×0.7, no infection, rescue easier. **Survivorman**: decay ×1.3, injuries/infection on, harsher storms, rescue harder.
