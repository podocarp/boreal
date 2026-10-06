/**
 * BOREAL — needs & thermoregulation (docs/DESIGN-needs.md "Numbers v1").
 * Pure sim: no DOM/three. All tunables in CONFIG.NEEDS / CONFIG.THERMO.
 *
 * Design invariants (user-locked):
 * - consequences, not chores: debuffs before death, slow critical bands
 * - auto-sip hydration when idle + carrying treated water (toggleable)
 * - food = fuel for heat (hunger starves heat production)
 *
 * Thermal tuning targets (verified by tests/sim balance):
 * - feels-like −20 °C, dry, active, clothed ≈ thermally stable
 * - same, idle at night, no fire/shelter → hypothermia band in ~4–5 game h
 * - soaked clothing at −12 °C is lethal within a night unless dried/fire
 */
import { CONFIG } from './config';
import { clamp } from './noise';

export type Difficulty = 'ranger' | 'bushman' | 'survivorman';

export interface NeedsState {
  hydration: number; // 0..100
  hunger: number; // 0..100
  energy: number; // 0..100
  health: number; // 0..100
  /** core body temp °C, 37 nominal */
  coreTemp: number;
  /** 0..1 clothing/boot wetness — the big cold multiplier */
  wetness: number;
  sleeping: boolean;
  autoSip: boolean;
  /** liters of treated water carried */
  carriedWaterL: number;
}

export interface EnvState {
  airTempC: number;
  windKmh: number;
  /** fire proximity warmth 0..1 (S4 drives this) */
  fireWarmth: number;
  /** shelter+bedding insulation 0..1 (S5 drives this; 0 = exposed) */
  shelterInsul: number;
}

export interface Debuffs {
  steadiness: number; // 0..1 (1 = steady)
  dexterity: number; // 0..1 work/interaction multiplier
  strength: number; // 0..1
  focus: number; // 0..1
  shivering: boolean;
  confusion: number; // hypothermic control drift 0..1
  drowsiness: number; // 0..1
}

export function createNeeds(): NeedsState {
  return {
    hydration: 85,
    hunger: 80,
    energy: 90,
    health: 100,
    coreTemp: 37.0,
    wetness: 0.1,
    sleeping: false,
    autoSip: true,
    carriedWaterL: 0,
  };
}

export function createEnv(): EnvState {
  return {
    airTempC: CONFIG.WORLD.TEMP_BASE_C,
    windKmh: CONFIG.WORLD.WIND_BASE_KMH,
    fireWarmth: 0,
    shelterInsul: 0,
  };
}

export function difficultyMul(d: Difficulty): number {
  const D = CONFIG.NEEDS.DIFF;
  return d === 'bushman' ? D.bushman : d === 'survivorman' ? D.survivorman : 1;
}

/** Environment Canada windchill index; only meaningful below freezing —
 * above 0 °C we return the air temp (model uses max(0,-feels) as cold load). */
export function windchill(tempC: number, windKmh: number): number {
  if (tempC >= 0) return tempC;
  const v = Math.max(4.8, windKmh);
  const vv = Math.pow(v, 0.16);
  return 13.12 + 0.6215 * tempC - 11.37 * vv + 0.3965 * tempC * vv;
}

/** Diurnal air temp: cosine peaking at 14:00, coldest ~02:00. */
export function airTempAt(hour: number, base: number, swing: number): number {
  const t = ((hour - 14 + 24) % 24) / 24;
  return base + swing * Math.cos(t * Math.PI * 2);
}

export function computeDebuffs(n: NeedsState): Debuffs {
  const N = CONFIG.NEEDS;
  const T = CONFIG.THERMO;
  const cold = n.coreTemp < T.COLD_C;
  const veryCold = n.coreTemp < T.VERY_COLD_C;
  const hypo = n.coreTemp < T.HYPOTHERMIA_C;
  const thirsty = n.hydration < N.DEBUFF_FROM;
  const hungry = n.hunger < N.DEBUFF_FROM;
  const sleepy = n.energy < N.DEBUFF_FROM;
  const shivering = cold && !n.sleeping;
  return {
    steadiness: clamp(1 - (shivering ? 0.35 : 0) - (hypo ? 0.3 : 0), 0.2, 1),
    dexterity: clamp(1 - (veryCold ? 0.4 : 0) - (hypo ? 0.3 : 0) - (sleepy ? 0.15 : 0), 0.15, 1),
    strength: clamp(1 - (hungry ? 0.3 : 0) - (hypo ? 0.25 : 0), 0.2, 1),
    focus: clamp(1 - (thirsty ? 0.2 : 0) - (sleepy ? 0.25 : 0) - (hypo ? 0.35 : 0), 0.15, 1),
    shivering,
    confusion: hypo ? clamp((T.HYPOTHERMIA_C - n.coreTemp) / 4, 0.2, 1) : 0,
    drowsiness: clamp((N.DEBUFF_FROM - n.energy) / N.DEBUFF_FROM, 0, 1),
  };
}

/** Effective insulation: clothing base + shelter bonus, gutted by wetness. */
export function insulationOf(n: NeedsState, env: EnvState): number {
  const T = CONFIG.THERMO;
  return clamp(
    (T.BASE_INSULATION + env.shelterInsul * T.SHELTER_INSUL_BONUS) *
      (1 - n.wetness * T.WETNESS_INSUL_PENALTY),
    0.15,
    2.5,
  );
}

/** Heat budget °C/h: positive = warming. Exposed for tests/tuning. */
export function heatBudget(
  n: NeedsState,
  env: EnvState,
  feelsLikeC: number,
  moving: boolean,
  sprinting: boolean,
): number {
  const T = CONFIG.THERMO;
  const coldLoad = Math.max(0, -feelsLikeC); // how far below freezing
  const heatFuel = n.hunger > 25 ? 1 : 0.6 + (n.hunger / 25) * 0.4; // food = fuel
  const insul = insulationOf(n, env);
  const loss = (T.LOSS_K * coldLoad) / insul;
  const exertion = sprinting ? T.EXERTION_HEAT * 2 : moving ? T.EXERTION_HEAT : 0;
  const gain = env.fireWarmth * T.FIRE_HEAT_GAIN + exertion + T.METABOLIC_HEAT * heatFuel;
  return gain - loss;
}

export interface NeedsTickResult {
  died?: { cause: string; detail: string };
  events: string[]; // notable transitions for the death-chain narrative
}

/** 0 at the critical band edge, 1 at zero. */
function CRITICAL_DEPTH_MUL(v: number): number {
  return (CONFIG.NEEDS.CRITICAL_BAND - Math.max(0, v)) / CONFIG.NEEDS.CRITICAL_BAND;
}

/** Advance needs + thermoregulation by dt sim-seconds. */
export function tickNeeds(
  n: NeedsState,
  env: EnvState,
  dt: number,
  opts: { moving: boolean; sprinting: boolean; difficulty: Difficulty },
): NeedsTickResult {
  const N = CONFIG.NEEDS;
  const T = CONFIG.THERMO;
  const events: string[] = [];
  // dt is REAL seconds; convert to game hours via the time scale
  const h = dt / CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
  const dm = difficultyMul(opts.difficulty);

  // --- energy ---
  if (n.sleeping) {
    const warm = n.coreTemp > T.COLD_C;
    const fed = n.hunger > 25;
    const restore = N.SLEEP_RESTORE_PER_H * (warm ? 1 : 0.35) * (fed ? 1 : 0.6);
    n.energy = clamp(n.energy + restore * h, 0, 100);
  } else {
    let drain = N.ENERGY_DECAY_PER_H;
    if (opts.sprinting) drain *= 2.2;
    else if (opts.moving) drain *= 1.3;
    n.energy = clamp(n.energy - drain * dm * h, 0, 100);
  }

  // --- hunger (shivering burns more; food = fuel for cold) ---
  const shivering = n.coreTemp < T.COLD_C;
  let hungerDrain = N.HUNGER_DECAY_PER_H * (shivering ? N.SHIVER_HUNGER_MUL : 1);
  if (opts.sprinting) hungerDrain *= 1.6;
  n.hunger = clamp(n.hunger - hungerDrain * dm * h, 0, 100);

  // --- hydration + auto-sip (idle only; never interrupts travel/work) ---
  let thirstDrain = N.HYDRATION_DECAY_PER_H * (opts.sprinting ? 1.8 : opts.moving ? 1.25 : 1);
  n.hydration = clamp(n.hydration - thirstDrain * dm * h, 0, 100);
  if (n.autoSip && !n.sleeping && !opts.moving && n.hydration < N.AUTO_SIP_BELOW && n.carriedWaterL > 0) {
    const points = Math.min(N.AUTO_SIP_POINTS_PER_H * h, 100 - n.hydration);
    const liters = points / N.HYDRATION_PER_LITER; // 1 L = 50 points
    const sip = Math.min(liters, n.carriedWaterL);
    if (sip > 1e-9) {
      n.hydration = clamp(n.hydration + sip * N.HYDRATION_PER_LITER, 0, 100);
      n.carriedWaterL = Math.max(0, n.carriedWaterL - sip);
    }
  }

  // --- thermoregulation ---
  const feels = windchill(env.airTempC, env.windKmh);
  const budget = heatBudget(n, env, feels, opts.moving, opts.sprinting);
  const prev = n.coreTemp;
  const dT = clamp(budget * h, -T.MAX_COOL_PER_H * h, T.MAX_WARM_PER_H * h);
  n.coreTemp = clamp(n.coreTemp + dT, 24, 38.5);

  const crossed = (band: number) => prev > band && n.coreTemp <= band;
  if (crossed(T.COLD_C)) events.push('You start shivering — the cold is getting in.');
  if (crossed(T.VERY_COLD_C)) events.push('Hands clumsy, thoughts slow. Very cold.');
  if (crossed(T.HYPOTHERMIA_C)) events.push('Hypothermia sets in — confusion, drowsiness.');

  // --- health: critical bands only; drain ramps with depth below the band,
  // so 15% is a warning and 0% kills in ~10 h (thirst) / ~20 h (hunger) ---
  const depth = (v: number) => (CRITICAL_DEPTH_MUL(v));
  if (n.hydration < N.CRITICAL_BAND)
    n.health -= N.CRITICAL_THIRST_HP_PER_H * (1 + 5 * depth(n.hydration)) * dm * h;
  if (n.hunger < N.CRITICAL_BAND)
    n.health -= N.CRITICAL_HUNGER_HP_PER_H * (1 + 9 * depth(n.hunger)) * dm * h;
  if (n.coreTemp < T.HYPOTHERMIA_C) {
    const sev = n.coreTemp < 30 ? 3 : 1;
    n.health -= T.HYPO_HP_PER_H * sev * dm * h;
  }
  if (
    n.hydration > 50 &&
    n.hunger > 50 &&
    n.coreTemp > T.COLD_C &&
    n.energy > 20 &&
    n.health < 100
  ) {
    n.health += N.REGEN_HP_PER_H * h;
  }
  n.health = clamp(n.health, 0, 100);

  let died: NeedsTickResult['died'];
  if (n.health <= 0) {
    if (n.coreTemp < T.HYPOTHERMIA_C)
      died = { cause: 'hypothermia', detail: `core temp ${n.coreTemp.toFixed(1)} °C` };
    else if (n.hydration < N.CRITICAL_BAND) died = { cause: 'dehydration', detail: 'water ran out' };
    else if (n.hunger < N.CRITICAL_BAND) died = { cause: 'starvation', detail: 'calories ran out' };
    else died = { cause: 'exposure', detail: 'the north wore you down' };
  }
  return { died, events };
}
