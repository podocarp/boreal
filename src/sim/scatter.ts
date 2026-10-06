/**
 * Deterministic resource scatter — shared by sim (colliders) and render (meshes).
 * Rules per docs/DESIGN-world.md: spruce on forest/bog hummocks, birch near
 * stream/ridge, rocks on ridge & shore, none on lake ice or in the stream.
 */
import { valueNoise2 } from './noise';
import { heightAt, lakeT, streamX, zoneAt } from './terrain';

export interface Prop {
  kind: 'spruce' | 'birch' | 'rock';
  x: number;
  z: number;
  scale: number;
  rot: number;
}

export function scatter(seed: number): Prop[] {
  const props: Prop[] = [];
  const N = 1400;
  const R = 380;
  for (let i = 0; i < N; i++) {
    // deterministic jittered grid-ish placement
    const gx = ((i * 977) % 53) / 53;
    const gz = ((i * 1699) % 71) / 71;
    const x = (valueNoise2(i * 0.71, 3.3, seed) * 2 - 1) * R + gx * 7;
    const z = (valueNoise2(5.1, i * 0.53, seed) * 2 - 1) * R + gz * 7;
    const zone = zoneAt(x, z);
    if (zone === 'lake' || zone === 'stream') continue;
    if (lakeT(x, z) < 1.12) continue; // keep shore clear-ish
    if (Math.abs(x - streamX(z)) < 8) continue;

    const r = valueNoise2(x * 0.05, z * 0.05, seed + 5);
    let kind: Prop['kind'] | null = null;
    if (zone === 'ridge') kind = r < 0.62 ? 'rock' : r < 0.72 ? 'birch' : null;
    else if (zone === 'bog') kind = r < 0.3 ? 'spruce' : r > 0.92 ? 'rock' : null;
    else kind = r < 0.55 ? 'spruce' : r < 0.64 ? 'birch' : r > 0.97 ? 'rock' : null;
    if (!kind) continue;

    const scale =
      kind === 'spruce'
        ? 0.7 + valueNoise2(x, z, seed + 9) * 1.1
        : kind === 'birch'
          ? 0.6 + valueNoise2(x, z, seed + 13) * 0.7
          : 0.5 + valueNoise2(x, z, seed + 17) * 1.4;
    const rot = valueNoise2(x + 40, z - 40, seed + 23) * Math.PI * 2;
    props.push({ kind, x, z, scale, rot });
  }
  // sanity: nothing embedded below terrain
  return props.filter((p) => heightAt(p.x, p.z) > 0.2 || p.kind === 'rock');
}

export interface Collider {
  x: number;
  z: number;
  r: number;
}

/** Sim colliders (trunk/rock circles) derived from the same scatter. */
export function collidersFrom(props: Prop[]): Collider[] {
  return props
    .filter((p) => p.kind !== 'birch' || p.scale > 0.9) // thin birches are push-through
    .map((p) => ({
      x: p.x,
      z: p.z,
      r: p.kind === 'rock' ? 0.5 + p.scale * 0.7 : 0.35 + p.scale * 0.25,
    }));
}
