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
| — | Sprint 0: nothing yet; scene renders and clock ticks |

## License
TBD (not yet chosen; assume all rights reserved for now).
