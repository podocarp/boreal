/**
 * BOREAL — pure simulation core (no three.js, no DOM, no wall clock).
 * Sprint 0 stub: world state + fixed-timestep step(). S1+ adds movement,
 * S2 adds needs/thermoregulation per docs/DESIGN-needs.md.
 */
import { CONFIG } from './config';

export interface WorldState {
  seed: number;
  /** Elapsed sim time in seconds. */
  t: number;
  /** In-game hour of day, 0..24. */
  hourOfDay: number;
  /** In-game day number, 1-based. */
  day: number;
  player: { x: number; z: number; yaw: number };
}

export function createWorld(seed = 1): WorldState {
  return { seed, t: 0, hourOfDay: 8, day: 1, player: { x: 0, z: 0, yaw: 0 } };
}

/** Advance the world by one fixed tick (CONFIG.SIM_DT seconds). Pure w.r.t. args. */
export function step(w: WorldState, dt = CONFIG.SIM_DT): void {
  w.t += dt;
  const hoursPerSec = 1 / CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
  w.hourOfDay += dt * hoursPerSec;
  if (w.hourOfDay >= 24) {
    w.hourOfDay -= 24;
    w.day += 1;
  }
}

/** Deterministic RNG (mulberry32). Sim code must use this, never Math.random. */
export function makeRng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
