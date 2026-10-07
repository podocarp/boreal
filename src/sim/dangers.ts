/**
 * Food & dangers (S6): snares, ice-edge fishing, berries, wolves, injury.
 * Design rules: skill over timers; wolves are pressure not horror (fairness:
 * reaction delay, repel-able, they finish the already-dying); injury→infection
 * is a nameable chain, not random.
 */
import { makeRng } from './rng';
import { CRASH, streamX } from './terrain';

// ---------------------------------------------------------------------------
// Snares (snowshoe hare runs)
// ---------------------------------------------------------------------------

export interface Snare {
  id: number;
  x: number;
  z: number;
  set: boolean;
  /** game-hours since set (bait freshness decays) */
  ageH: number;
  /** 0..1 placement quality (near fresh sign / pinch point) */
  quality: number;
  /** game-hours since set (bait freshness decays) */
  pending?: number; // caught game meat waiting to be collected
}

/** Hare runs: deterministic bands along the stream banks + bog edges. */
export function hareSignAt(x: number, z: number, seed: number): number {
  // sign strength 0..1: near stream (±25 m) or bog edge, with noise
  const dStream = Math.abs(x - streamX(z));
  const s = Math.max(0, 1 - dStream / 25);
  const n = makeRng(Math.floor(x * 10) ^ Math.floor(z * 10) ^ seed)();
  return Math.min(1, s * (0.5 + n * 0.5));
}

export function setSnare(list: Snare[], nextId: number, x: number, z: number, seed: number): Snare {
  const s: Snare = { id: nextId, x, z, set: true, ageH: 0, quality: hareSignAt(x, z, seed) };
  list.push(s);
  return s;
}

/**
 * Tick snares (game hours). Catch roll per hour scales with placement quality
 * and freshness; deep snow (storm recency) halves it — caller passes snowMul.
 */
export function tickSnares(
  snares: Snare[],
  dtGameH: number,
  snowMul: number,
  rng: () => number,
): { caught: number; ids: number[] } {
  let caught = 0;
  const ids: number[] = [];
  for (const s of snares) {
    if (!s.set) continue;
    s.ageH += dtGameH;
    const freshness = s.ageH < 24 ? 1 : Math.max(0.25, 1 - (s.ageH - 24) / 48);
    const p = 0.06 * (0.3 + s.quality) * freshness * snowMul; // per game hour
    if (rng() < p * dtGameH) {
      caught++;
      ids.push(s.id);
      s.set = false; // snare destroyed in the struggle (realistic + creates a loop)
    }
  }
  return { caught, ids };
}

// ---------------------------------------------------------------------------
// Fishing (ice-edge holes)
// ---------------------------------------------------------------------------

export interface FishHole {
  id: number;
  x: number;
  z: number;
  usesLeft: number;
}

export function buildFishHoles(seed: number): FishHole[] {
  // a few reliable holes where the stream meets the lake + bends
  const holes: FishHole[] = [];
  let id = 1;
  for (const z of [-150, -120, -60, 20, 90]) {
    holes.push({ id: id++, x: streamX(z), z, usesLeft: 4 });
  }
  void seed;
  return holes;
}

/** Fishing success: dawn/dusk best; needs cordage+hook (caller checks items). */
export function fishRoll(hour: number, rng: () => number): boolean {
  const golden = hour < 10 || hour > 15.5 ? 0.65 : 0.4;
  return rng() < golden;
}

// ---------------------------------------------------------------------------
// Wolves
// ---------------------------------------------------------------------------

export type WolfState = 'prowling' | 'circling' | 'retreating' | 'attacking' | 'fleeing';

export interface Wolf {
  id: number;
  x: number;
  z: number;
  state: WolfState;
  /** seconds since acquiring player as target (reaction delay gate) */
  acquireT: number;
  /** attack cooldown */
  coolT: number;
  /** fear of fire/light; rises when repelled, decays slowly */
  fear: number;
  /** strafe oscillation phase */
  phase: number;
  strafePeriod: number;
}

export const WOLF_SPEED_MPS = 2.6;

export function spawnWolves(seed: number): Wolf[] {
  const rng = makeRng(seed ^ 0x5eed);
  const n = 2 + Math.floor(rng() * 2); // 2-3 wolves
  const wolves: Wolf[] = [];
  for (let i = 0; i < n; i++) {
    const a = rng() * Math.PI * 2;
    wolves.push({
      id: i + 1,
      x: CRASH.x + Math.cos(a) * 90,
      z: CRASH.z + Math.sin(a) * 90,
      state: 'prowling',
      acquireT: 0,
      coolT: 0,
      fear: 0,
      phase: rng() * Math.PI * 2,
      strafePeriod: 1.4 + rng() * 1.2, // ≥1.2 s so movement reads calm, not twitchy
    });
  }
  return wolves;
}

export interface WolfTickResult {
  /** damage dealt to player this tick (raw, before armor) */
  damage: number;
  events: string[];
}

/**
 * Wolf AI tick (dt real seconds). Fairness rules (playable-browser-games):
 * - reaction delay: can't attack until acquireT > 0.8 s after acquiring
 * - fire/light deterrence: wolves won't approach within fire radius; a repelled
 *   attack raises fear → they retreat and may flee for good
 * - they prefer weakened prey: attack only if player is cold/hurt/low needs OR
 *   the player is >25 m from any fire at night
 */
export function tickWolves(
  wolves: Wolf[],
  dt: number,
  ctx: {
    px: number;
    pz: number;
    night: boolean;
    fireX: number | null; // nearest lit fire position (within warmth radius)
    fireZ: number;
    fireR: number;
    playerWeakened: boolean;
    playerShouting: boolean; // spacebar "hoo-hoo!" — cheap repel
    rng: () => number;
  },
): WolfTickResult {
  const events: string[] = [];
  let damage = 0;
  for (const w of wolves) {
    if (w.state === 'fleeing') continue;
    const d = Math.hypot(w.x - ctx.px, w.z - ctx.pz);
    const toP = { x: (ctx.px - w.x) / (d || 1), z: (ctx.pz - w.z) / (d || 1) };

    // fear decay
    w.fear = Math.max(0, w.fear - 0.02 * dt);
    w.coolT = Math.max(0, w.coolT - dt);
    w.acquireT += dt;

    // deterrence: fire, shouting
    const nearFire = ctx.fireX !== null && Math.hypot(w.x - ctx.fireX!, w.z - ctx.fireZ) < ctx.fireR + 2;
    if (nearFire || ctx.playerShouting) {
      w.fear = Math.min(2, w.fear + (ctx.playerShouting ? 0.6 : 0.35) * dt * 4);
    }
    if (w.fear > 1.4) {
      w.state = 'fleeing';
      events.push('The wolves melt back into the trees.');
      const fx = w.x - toP.x * WOLF_SPEED_MPS * 1.2 * dt;
      const fz = w.z - toP.z * WOLF_SPEED_MPS * 1.2 * dt;
      w.x = fx;
      w.z = fz;
      continue;
    }

    // acquisition: night + (weakened or far from fire)
    const interested = ctx.night && (ctx.playerWeakened || ctx.fireX === null);
    if (!interested) {
      // prowl at distance: keep 25-40 m, circle
      w.state = 'prowling';
      w.acquireT = 0;
      const want = 30;
      const dir = d > want ? 1 : -0.5;
      w.phase += dt;
      const strafe = Math.sin(w.phase / w.strafePeriod) * 0.8;
      w.x += (toP.x * dir - toP.z * strafe) * WOLF_SPEED_MPS * 0.5 * dt;
      w.z += (toP.z * dir + toP.x * strafe) * WOLF_SPEED_MPS * 0.5 * dt;
      continue;
    }

    if (w.state === 'prowling' || w.state === 'circling') {
      if (w.acquireT < 0.8) {
        w.state = 'circling'; // acquiring but can't attack yet (reaction delay)
      } else {
        w.state = 'attacking';
      }
    }

    if (w.state === 'circling') {
      w.phase += dt;
      const strafe = Math.sin(w.phase / w.strafePeriod);
      const close = d > 12 ? 0.6 : 0;
      w.x += (toP.x * close - toP.z * strafe) * WOLF_SPEED_MPS * 0.7 * dt;
      w.z += (toP.z * close + toP.x * strafe) * WOLF_SPEED_MPS * 0.7 * dt;
      if (d < 40 && events.length === 0) events.push('Eyes low in the dark. Wolves.');
      continue;
    }

    if (w.state === 'attacking') {
      if (d > 2.2) {
        w.x += toP.x * WOLF_SPEED_MPS * dt;
        w.z += toP.z * WOLF_SPEED_MPS * dt;
      } else if (w.coolT === 0) {
        // bite: 8-14 raw damage, then back off (cooldown) — repel-able
        damage += 8 + Math.floor(ctx.rng() * 6);
        w.coolT = 4;
        w.fear += 0.15; // each repelled/landed bite is also a scare
        events.push('A wolf lunges — teeth through the parka!');
      }
      // shouting mid-attack repels
      if (ctx.playerShouting) w.state = 'retreating';
      continue;
    }

    if (w.state === 'retreating') {
      w.x -= toP.x * WOLF_SPEED_MPS * dt;
      w.z -= toP.z * WOLF_SPEED_MPS * dt;
      if (d > 25) w.state = 'circling';
    }
  }
  return { damage, events };
}

// ---------------------------------------------------------------------------
// Injury → infection
// ---------------------------------------------------------------------------

export interface Injury {
  /** 0..100 wound severity */
  severity: number;
  infected: boolean;
  /** infection progression 0..100 */
  infection: number;
  label: string;
}

export function addInjury(list: Injury[], label: string, severity: number): void {
  list.push({ severity, infected: false, infection: 0, label });
}

/**
 * Infection progression: untreated wounds + wet/cold raise risk; first aid
 * (finite) cleans and halves severity. Sepsis damages health (caller applies).
 */
export function tickInjuries(list: Injury[], dtGameH: number, rng: () => number): string[] {
  const events: string[] = [];
  for (const inj of list) {
    if (!inj.infected) {
      // ~5% per game hour untreated, scaled by severity
      if (rng() < 0.05 * (inj.severity / 50) * dtGameH) {
        inj.infected = true;
        events.push(`Your ${inj.label} is turning red and hot — infected.`);
      }
    } else {
      inj.infection = Math.min(100, inj.infection + 2.5 * dtGameH);
    }
  }
  return events;
}

export function treatInjury(list: Injury[]): boolean {
  const inj = list.find((i) => i.infected || i.severity > 30);
  if (!inj) return false;
  inj.infected = false;
  inj.infection = 0;
  inj.severity = Math.max(5, inj.severity / 2);
  return true;
}

/** Health drain from sepsis (game hours). Out-heals natural regen: untreated
 * sepsis is a death sentence — that's what makes first aid a real resource. */
export function sepsisDamagePerH(list: Injury[]): number {
  let d = 0;
  for (const inj of list) if (inj.infected && inj.infection > 60) d += 6;
  return d;
}
