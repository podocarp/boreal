# Decision Log (append-only)

- **2026-10-06 — Scenario: Arctic / NWT (user choice).** Over Borneo (my rec), desert, Rockies. Implication: cold is the master pressure; water via melting snow (never a fetch-chore); food = snares/fishing/berries; win = rescue by day ~7. Cold-death timers must be tuned forgiving-but-scary (research digest will set numbers).
- **2026-10-06 — Camera: third-person over-shoulder (user choice).** Over first-person. Implication: character capsule visible; shelter/fire readability better; camera rig + collision in S1.
- **2026-10-06 — Stack: Vite + TypeScript + three.js, sim/render split.** Vitest for pure-sim tests; Playwright+Python+nixpkgs Chromium for headless render/E2E (NixOS host, stock Chrome segfaults).
- **2026-10-06 — Needs philosophy (user requirement):** consequences-based needs, batch management, auto-consume from stock allowed; no timed drinking chores. Full spec in DESIGN-needs.md.
- **2026-10-06 — Repo:** GitHub `podocarp/boreal`, local at `/persist/hermes/projects/boreal`. Commits ↔ sprints, tags `sprint-N`, MVP tag `v0.1-mvp`.
