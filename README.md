# BOREAL

A realistic 3D wilderness survival game set in the Canadian subarctic (Northwest Territories), inspired by Les Stroud's *Survivorman* Arctic episode. Crash-landed with a knife, a tin cup, and an emergency blanket, you have ~6 days until a search plane passes over: stay warm, stay hydrated, eat, and get spotted.

**Stack:** TypeScript + three.js + Vite. Pure deterministic simulation core (headless-tested with Vitest) + three.js greybox renderer (third-person over-shoulder). Headless render/E2E via Playwright + nixpkgs Chromium (`flake.nix`).

**Status:** Sprint 0 (scaffold). Design docs in [`docs/`](docs/) — start with [VISION.md](docs/VISION.md), sprint plan & MVP stopping point in [PLAN.md](docs/PLAN.md).

## Dev

```bash
npm install
npm run dev        # http://localhost:5173
npm test           # vitest — pure sim tests
npm run build      # typecheck + static build to dist/
```

Headless render smoke test (NixOS flake shell with Chromium + Playwright):

```bash
nix develop --extra-experimental-features 'nix-command flakes' . -c bash -lc \
  'npm run build && (npx vite preview --port 4173 &>/dev/null &) && sleep 2 && python3 tests/e2e/smoke_render.py'
```

## Controls (contextual — one verb + one wheel)

| Input | Action |
|---|---|
| Click canvas | Capture mouse (pointer lock); Esc releases |
| WASD | Move (camera-relative; player faces movement) |
| Shift | Sprint |
| Mouse | Orbit camera (over-shoulder; mouse-only, never auto-swings) |
| **LMB / E** | Primary verb on the nearest thing: gather, loot wreck, pack snow, scoop water, wake up |
| **Hold RMB** | Radial action wheel — everything possible *here, now* (feed fire, cook, boil, craft, eat, drink, snare, shelter, sleep, signal, flare…). Aim with the mouse, release to do it, Esc cancels |
| Space | Shout "hoo-hoo!" (repels wolves while held) |
| Enter | Restart after death / rescue |

Disabled wheel options stay visible but greyed with a reason ("needs cordage",
"fire is out") — you always learn what you're missing without a wiki.

## How to play (the 60–90 min run)

You crashed a bush plane on the shore of a subarctic lake, ~60°N, late autumn. Search passes fly days 7–10 at dawn and dusk — **be ready before day 7**.

1. **Loot the wreck** (E at the orange wreckage): knife, tin cup, blanket, flare gun + 1 flare, duct tape, kindling.
2. **Fire** (F with a tinder bundle — craft from bark; R to feed). Boil/melt water (Q) and stock it; auto-sip handles the sipping.
3. **Shelter** (G, six steps, needs boughs + deadfall). Site matters: forest edge near the lake beats the windy ridge; don't build under dead standing trees.
4. **Food**: cordage (Tab craft from bark) → snares by the stream (C, check with X) or fish the pickerel holes (V, dawn/dusk). Cook it (B). Berries are a stopgap.
5. **Survive the nights**: storms hit days 2 and 4; wolves come nights from day 2 — stay by the fire, shout (Space) if they circle. Treat bites (T) before they infect.
6. **Signal before the planes come**: throw green boughs on a big fire (J) and sleep near it on the open shore, or save the flare (H) for a pass you can hear. Sleeping in the open all night is a gamble you may lose.

Death ends the run with a summary of how and when. Rescue ends it with the same, warmer.

World: crash site on the lake shore (orange wreck), spruce/birch forest, stream to the west ridge, muskeg bog to the north (slows you), rocks on the ridge, berry scrub, hare sign along the stream banks, pickerel holes where the stream meets the lake. Day ≈ 12 real minutes; sun rises ~09:00, sets ~17:00. Storms on days 2 and 4; wolves prowl the nights from day 2 — fire and shouting keep them honest.

## License
TBD (not yet chosen; assume all rights reserved for now).
