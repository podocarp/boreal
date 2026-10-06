# BOREAL — Tech Stack & Architecture

> Status: v0.1 (2026-10-06). Chosen for convenience on the dev host (NixOS, headless verification) and for testability.

## Stack
- **Language:** TypeScript (strict), ES2022 modules.
- **Renderer:** three.js (vendored via npm; placeholder geometry/materials only for MVP).
- **Build/dev:** Vite (`npm run dev`), `npm run build` → static `dist/`.
- **Unit tests:** Vitest — targets the **pure simulation core** (no DOM, no WebGL). This is where most testing happens.
- **E2E / render tests:** Playwright (Python) driving **nixpkgs Chromium** (stock puppeteer Chrome segfaults on this NixOS host). See skill `nixos-headless-webgl-verification`; flake.nix in repo root provides the dev shell:
  `nix develop --extra-experimental-features 'nix-command flakes' . -c bash -lc '<cmd>'`
- **Lint/format:** ESLint + Prettier (light config, don't over-invest).
- **Repo:** GitHub `podocarp/boreal` (token via `gh`/git-creds from Hermes secrets). Commits map 1:1 to sprints; tags `sprint-N`.

## Architecture: sim/render split (the one rule that matters)
```
src/sim/    ← pure TS: world state, needs, thermoregulation, fire, AI, inventory,
              time, rescue logic. Fixed timestep: step(dt) with dt = 0.25s sim tick.
              NO imports of three, DOM, or Date.now(). Deterministic given seed.
src/render/ ← three.js scene: reads sim state, builds/updates greybox meshes,
              third-person over-shoulder camera, placeholder materials.
src/ui/     ← HUD (DOM overlay): needs, temp, clock, inventory, prompts, log.
src/input/  ← keyboard/mouse → intent events consumed by sim.
src/main.ts ← boot: wires sim+render+ui+input, rAF loop (accumulator → sim.step).
```
Consequences:
- Sim is headless-testable in Vitest without a browser (thousands of ticks/sec).
- E2E harness drives the game through a `window.__boreal` debug API (getters for reassigned state!) and asserts on sim state + framebuffer pixels (preserveDrawingBuffer + readPixels).
- Save/load = serialize sim state to JSON (later sprint, cheap because sim is pure data).

## Conventions
- All tunables in `src/sim/config.ts` (single source of balance truth; design docs reference constant names).
- Determinism: seeded RNG (`mulberry32`), no wall-clock in sim.
- Every sprint: `npm test` green + Playwright smoke green before tagging.
- Log notable choices in `docs/DECISIONS.md` (one paragraph each).

## Host pitfalls (learned; don't re-learn)
- NixOS store is ephemeral — rely on `flake.nix` + `package-lock.json`, never global installs.
- Playwright must use nixpkgs chromium via `executable_path` + args `--no-sandbox --disable-gpu --use-gl=swiftshader --enable-unsafe-swiftshader`.
- Screenshots under SwiftShader are slow: explicit long timeouts.
- `window.__boreal` must use **getters** for reassigned bindings (classic stale-reference bug).
