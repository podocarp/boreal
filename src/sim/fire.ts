/**
 * Fire model (docs/DESIGN-world.md "Fire system").
 * Stages driven by fuel level; neglect collapses stages back down; a fire that
 * hits 0 fuel is out (nursing embers is the S4 tension).
 * Warmth feeds needs.env.fireWarmth (0..1).
 */
export interface Fire {
  id: number;
  x: number;
  z: number;
  /** 0..100 — stage is derived from fuel */
  fuel: number;
  /** true while an unlit tinder bundle is being blown into flame (S4-lite: instant) */
  lit: boolean;
}

export const FIRE_STAGE_LABELS = ['out', 'tinder', 'kindling', 'stick', 'log'] as const;

/** stage 0..4 from fuel */
export function fireStage(f: Fire): number {
  if (!f.lit || f.fuel <= 0) return 0;
  if (f.fuel < 15) return 1;
  if (f.fuel < 40) return 2;
  if (f.fuel < 75) return 3;
  return 4;
}

export const FUEL_VALUE = { deadfall: 25, kindling: 8 } as const;

export function addFuel(f: Fire, item: 'deadfall' | 'kindling', n = 1): void {
  f.fuel = Math.min(100, f.fuel + FUEL_VALUE[item] * n);
  f.lit = true;
}

/** Warmth radius in meters by stage. */
export function warmthRadius(stage: number): number {
  return [0, 3, 4.5, 6, 7.5][stage];
}

/** 0..1 warmth at a point from one fire. */
export function fireWarmth(f: Fire, px: number, pz: number): number {
  const stage = fireStage(f);
  if (stage === 0) return 0;
  const r = warmthRadius(stage);
  const d = Math.hypot(f.x - px, f.z - pz);
  if (d > r) return 0;
  return Math.min(1, (1 - d / r) * (stage / 4 + 0.35));
}

export function maxWarmth(fires: Fire[], px: number, pz: number): number {
  let m = 0;
  for (const f of fires) m = Math.max(m, fireWarmth(f, px, pz));
  return m;
}

/**
 * Tick one fire: fuel burns down (faster when small — a tinder fire dies fast).
 * Returns true if it just went out.
 */
export function tickFire(f: Fire, dtGameHours: number, windKmh: number): boolean {
  if (!f.lit || f.fuel <= 0) return false;
  const stage = fireStage(f);
  // burn rate %/h: small fires burn disproportionately fast
  const base = [0, 30, 18, 12, 9][stage];
  const windBurn = 1 + Math.max(0, windKmh - 15) * 0.01;
  const before = stage;
  f.fuel = Math.max(0, f.fuel - base * windBurn * dtGameHours);
  if (f.fuel <= 0) {
    f.lit = false;
    return true;
  }
  void before;
  return false;
}

/**
 * Friction-fire attempt (bow drill, simplified multi-factor roll).
 * Consumes the tinder bundle either way. Returns success.
 */
export function frictionRoll(opts: {
  dexterity: number; // 0..1
  handWetness: number; // 0..1
  coreTemp: number; // °C
  woodDry: boolean;
  rng: () => number;
}): boolean {
  let p = 0.6;
  p += (opts.dexterity - 0.7) * 0.75; // skilled hands help a lot
  p -= opts.handWetness * 0.35; // wet hands are the classic failure
  if (opts.coreTemp < 34.5) p -= 0.2; // very cold = clumsy
  if (!opts.woodDry) p -= 0.3; // green/wet deadwood
  p = Math.max(0.05, Math.min(0.9, p));
  return opts.rng() < p;
}
