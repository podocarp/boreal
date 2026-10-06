/**
 * Day/night sky & light cycle. Late-autumn subarctic: ~8h of grey light.
 * Pure-ish: reads world.hourOfDay, writes three.js light/scene props.
 */
import * as THREE from 'three';
import type { WorldState } from '../sim/world';
import { PALETTE as P } from './palette';
import { clamp, smoothstep } from '../sim/noise';

const DAWN = 9.0; // sun rises ~9, sets ~17 — short days
const DUSK = 17.0;

export function updateSky(
  w: WorldState,
  scene: THREE.Scene,
  sun: THREE.DirectionalLight,
  hemi: THREE.HemisphereLight,
  fog: THREE.Fog,
): void {
  const h = w.hourOfDay;
  // daylight 0..1 with soft edges
  const day = smoothstep(DAWN - 1, DAWN + 1, h) * (1 - smoothstep(DUSK - 1, DUSK + 1, h));
  const golden = clamp(1 - Math.abs(h - DAWN) / 2.2, 0, 1) + clamp(1 - Math.abs(h - DUSK) / 2.2, 0, 1);
  // Sun stays in the SOUTH (+z) all day — at ~60°N the winter sun never
  // crosses north of east-west. Rises SE ~09:00, peaks due south ~13:00,
  // sets SW ~17:00, on a low arc.
  const t = ((13 - h) / 4) * 1.2; // +1.2 morning (east) → -1.2 evening (west)
  const el = Math.max(0.06, 0.5 - Math.abs(13 - h) * 0.055);
  sun.position.set(Math.sin(t) * 140, el * 140, Math.cos(t) * 140);

  sun.intensity = 0.15 + day * 1.25;
  sun.color.setHex(P.SUN_DAY).lerp(new THREE.Color(P.SUN_DUSK), clamp(golden, 0, 1) * 0.8);
  hemi.intensity = 0.18 + day * 0.7;
  hemi.color.setHex(P.MOON_NIGHT).lerp(new THREE.Color(0xbfd4e8), day);

  const sky = new THREE.Color(P.SKY_NIGHT)
    .lerp(new THREE.Color(P.SKY_DAY), day)
    .lerp(new THREE.Color(P.SKY_DUSK), clamp(golden, 0, 1) * 0.5 * day);
  (scene.background as THREE.Color).copy(sky);
  fog.color.copy(new THREE.Color(P.FOG_NIGHT).lerp(new THREE.Color(P.FOG_DAY), day));
  fog.near = 60 + day * 40;
  fog.far = 320 + day * 220;
}
