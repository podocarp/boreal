/**
 * Shelter (docs/DESIGN-world.md "Shelter system") + sleep + storms.
 * Debris shelter: multi-step build; SITE QUALITY matters (wind, water, fuel,
 * widowmakers). shelterInsul feeds thermoregulation; sleeping warm+sheltered
 * is the recovery loop; sleeping cold is the death gamble.
 */
import { CONFIG } from './config';
import { zoneAt } from './terrain';
import { valueNoise2 } from './noise';

export type ShelterStep = 'site' | 'frame' | 'ribs' | 'insulation' | 'mulch' | 'bedding';
export const SHELTER_STEPS: ShelterStep[] = ['site', 'frame', 'ribs', 'insulation', 'mulch', 'bedding'];

export interface Shelter {
  id: number;
  x: number;
  z: number;
  /** index into SHELTER_STEPS: how far the build has progressed */
  step: number;
  /** 0..1 site quality (computed at 'site' step, frozen thereafter) */
  siteQuality: number;
  /** true once bedding platform laid (final step) */
  complete: boolean;
}

export interface SiteScore {
  total: number; // 0..1
  parts: Record<string, number>;
  warnings: string[];
}

/**
 * Site scoring (qualitative hints, not raw numbers, in the HUD).
 * Good: forest shelter from wind, near water (<60m) and fuel, no widowmakers
 * (dead standing trees — modeled as dense scatter), not on the lake ice.
 */
export function scoreSite(x: number, z: number, seed: number): SiteScore {
  const zone = zoneAt(x, z);
  const parts: Record<string, number> = {};
  const warnings: string[] = [];

  parts.wind = zone === 'forest' ? 1 : zone === 'bog' ? 0.6 : zone === 'ridge' || zone === 'lake' ? 0.15 : 0.5;
  if (parts.wind < 0.4) warnings.push('Exposed to the wind here.');

  // water within 60 m?
  const nearWater = z < -60 ? Math.hypot(x, z + 150) < 170 : true; // lake south / stream north
  parts.water = nearWater ? 1 : 0.3;
  if (!nearWater) warnings.push('Water is a long carry.');

  // fuel: forest density proxy
  const density = valueNoise2(x * 0.02, z * 0.02, seed + 55);
  parts.fuel = zone === 'forest' ? 0.6 + density * 0.4 : zone === 'bog' ? 0.5 : 0.2;
  if (parts.fuel < 0.4) warnings.push('Standing dead fuel is scarce.');

  // widowmakers: dense dead standing trees overhead — ridge edge + random pockets
  const widow = valueNoise2(x * 0.08, z * 0.08, seed + 71);
  parts.widowmaker = widow > 0.8 ? 0.2 : 1;
  if (parts.widowmaker < 1) warnings.push('Dead standing trees overhead — widowmakers!');

  // bog floor = wet
  parts.dry = zone === 'bog' ? 0.3 : 1;
  if (parts.dry < 1) warnings.push('Ground stays wet here.');

  const total =
    parts.wind * 0.3 + parts.water * 0.2 + parts.fuel * 0.2 + parts.widowmaker * 0.15 + parts.dry * 0.15;
  return { total, parts, warnings };
}

/** Insulation 0..1 from build progress × site quality. */
export function shelterInsul(s: Shelter | null): number {
  if (!s) return 0;
  const progress = s.step / SHELTER_STEPS.length; // 0..1
  return progress * (0.45 + 0.55 * s.siteQuality);
}

/** Warmth bonus at a shelter point (player must be within 2.5 m). */
export function shelterWarmthAt(shelters: Shelter[], px: number, pz: number): number {
  let best = 0;
  for (const s of shelters) {
    if (Math.hypot(s.x - px, s.z - pz) < 2.5) best = Math.max(best, shelterInsul(s));
  }
  return best;
}

// ---------------------------------------------------------------------------
// Sleep
// ---------------------------------------------------------------------------

export interface SleepState {
  active: boolean;
  /** hours slept this session */
  hours: number;
}

export function createSleep(): SleepState {
  return { active: false, hours: 0 };
}

/** Can the player sleep here? (needs to be idle; shelter/fire improve quality) */
export function canSleep(): boolean {
  return true; // sleeping anywhere is possible — that's the gamble
}

/**
 * Energy restore per game-hour while sleeping. "Warm" = core temp OK OR
 * decent shelter/fire warmth (design: full restore when warm + sheltered + fed).
 */
export function sleepRestorePerH(warm: boolean, fed: boolean): number {
  return CONFIG.NEEDS.SLEEP_RESTORE_PER_H * (warm ? 1 : 0.35) * (fed ? 1 : 0.6);
}

export function shouldWake(sleep: SleepState, energy: number, hourOfDay: number): string | null {
  if (energy >= 100) return 'You wake rested.';
  if (hourOfDay >= 8 && hourOfDay < 12 && sleep.hours > 2) return 'Dawn. You wake stiff and cold.';
  return null;
}

// ---------------------------------------------------------------------------
// Storms (scripted weather events)
// ---------------------------------------------------------------------------

export interface Storm {
  day: number;
  startHour: number;
  durationH: number;
  severity: number; // 0..1
}

/** Storm schedule: day 2 light, day 4 heavy (deterministic per run). */
export function stormSchedule(): Storm[] {
  return [
    { day: 2, startHour: 20, durationH: 6, severity: 0.45 },
    { day: 4, startHour: 18, durationH: 9, severity: 0.85 },
  ];
}

export function activeStorm(day: number, hour: number): Storm | null {
  for (const s of stormSchedule()) {
    if (day === s.day && hour >= s.startHour && hour <= s.startHour + s.durationH) return s;
  }
  return null;
}

/** Storm effects on environment: wind multiplier + wetness gain per hour. */
export function stormWindMul(s: Storm | null): number {
  return s ? 1 + s.severity * 1.6 : 1;
}

export function stormWetnessPerH(s: Storm | null): number {
  return s ? 0.12 * s.severity : 0;
}
