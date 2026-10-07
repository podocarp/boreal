/**
 * BOREAL — hand-authored analytic terrain (meters, y-up).
 * heightAt/zoneAt are pure functions used by BOTH sim (collision, zones) and
 * render (mesh), so visuals and gameplay can never disagree.
 * Zones per docs/DESIGN-world.md: lake (center-south), stream (ridge→lake),
 * bog (north), ridge (west), forest (default).
 */
import { fbm2, smoothstep } from './noise';

export type Zone = 'lake' | 'stream' | 'bog' | 'ridge' | 'forest';

export const LAKE = { cx: 0, cz: -150, rx: 150, rz: 90 };

/** Crash site: on the lake ice at the south shore, stream mouth ~15 m west,
 *  guaranteed spruce grove 14-45 m behind camp (see scatter). */
export const CRASH = { x: -20, z: -62 };

/** Stream meanders x = f(z) from the ridge (north-west) down to the lake,
 *  reaching the south shore right beside the crash site (CRASH). */
export function streamX(z: number): number {
  return -35 + 0.15 * (z + 150) + 14 * Math.sin(z * 0.02 + 0.4);
}

export function lakeT(x: number, z: number): number {
  const dx = (x - LAKE.cx) / LAKE.rx;
  const dz = (z - LAKE.cz) / LAKE.rz;
  return Math.sqrt(dx * dx + dz * dz); // <1 inside lake ellipse
}

export function zoneAt(x: number, z: number): Zone {
  if (lakeT(x, z) < 1.0) return 'lake';
  if (Math.abs(x - streamX(z)) < 5 && z > -160) return 'stream';
  if (z > 110 && fbm2(x * 0.01, z * 0.01, 77, 2) > 0.35) return 'bog';
  if (x < -140) return 'ridge';
  return 'forest';
}

/** Terrain height in meters. Lake ice surface sits at y=0. */
export function heightAt(x: number, z: number): number {
  // rolling boreal base
  let h = fbm2(x * 0.004, z * 0.004, 11, 4) * 30 - 8;
  h += fbm2(x * 0.02, z * 0.02, 12, 3) * 3;

  // western ridge rises
  h += smoothstep(-120, -260, x) * 45;

  // bog flattens toward y≈1 with hummocks
  const bogMix = smoothstep(100, 160, z) * 0.8;
  h = h * (1 - bogMix) + (1 + fbm2(x * 0.05, z * 0.05, 21, 2) * 2.5) * bogMix;

  // stream channel carved down to lake level
  const chW = Math.abs(x - streamX(z));
  if (z > -160 && chW < 14) {
    const carve = 1 - smoothstep(5, 14, chW);
    const floor = Math.max(-1.5, heightAtLakeApproach(z));
    h = h * (1 - carve) + floor * carve;
  }

  // lake basin: flatten to ice at y=0
  const lt = lakeT(x, z);
  const lakeMix = 1 - smoothstep(0.85, 1.15, lt);
  h = h * (1 - lakeMix) + 0 * lakeMix;

  return h;
}

/** Stream bed falls gently from the ridge to the lake surface. */
function heightAtLakeApproach(z: number): number {
  return -0.5 + smoothstep(-160, 200, z) * 2.5; // -0.5 near lake → 2 up north
}

/** Movement speed multiplier by zone (bog soaks you). */
export function speedMulAt(zone: Zone): number {
  switch (zone) {
    case 'bog':
      return 0.55;
    case 'ridge':
      return 0.85;
    case 'stream':
      return 0.7;
    default:
      return 1;
  }
}
