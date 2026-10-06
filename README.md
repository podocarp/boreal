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

## Controls (as implemented — updated per sprint)

| Key | Action |
|---|---|
| Click canvas | Capture mouse (pointer lock); Esc releases |
| WASD | Move (camera-relative; player faces movement) |
| Shift | Sprint |
| Mouse | Orbit camera (over-shoulder) |
| E | Work nearest target (gather / loot wreck / snow / water / berries) |
| Tab | Craft first available recipe |
| F | Light fire (needs tinder bundle; friction roll) |
| R | Feed nearest fire (deadfall/kindling) |
| Q | Melt snow / boil water (at lit fire, needs container) |
| G | Build next shelter step at position |
| Z | Sleep / wake |
| C | Set snare (needs cordage; near hare sign by the stream) |
| X | Check snares in reach |
| V | Fish at an ice-edge hole (needs cordage; dawn/dusk bite better) |
| B | Cook meat at fire |
| T | Treat wound (duct tape, at fire) |
| 1 / 2 | Drink / eat |
| Space | Shout "hoo-hoo!" (repels wolves while held) |

World: crash site on the lake shore (orange wreck), spruce/birch forest, stream to the west ridge, muskeg bog to the north (slows you), rocks on the ridge, berry scrub, hare sign along the stream banks, pickerel holes where the stream meets the lake. Day ≈ 12 real minutes; sun rises ~09:00, sets ~17:00. Storms on days 2 and 4; wolves prowl the nights from day 2 — fire and shouting keep them honest.

## License
TBD (not yet chosen; assume all rights reserved for now).
