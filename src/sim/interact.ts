/**
 * Interactables + work tasks (docs/DESIGN-world.md resource map).
 * Generated deterministically from the same scatter the world uses.
 * Work: press E near a target → timed task; dexterity debuff slows it.
 */
import { CONFIG } from './config';
import { valueNoise2 } from './noise';
import { streamX } from './terrain';
import type { Prop } from './scatter';
import type { ItemId } from './items';

export type InteractKind =
  | 'deadfall' // standing dead spruce → deadfall wood
  | 'boughs' // green spruce → boughs
  | 'bark' // birch → bark strips
  | 'rock' // boulder → hand rocks
  | 'snow' // ground → packed snow (needs container)
  | 'water' // stream → raw water (needs container)
  | 'wreck'; // crash site → one-time loot

export interface Interactable {
  id: number;
  kind: InteractKind;
  x: number;
  z: number;
  uses: number; // finite; wreck = 1
}

export interface WorkTask {
  targetId: number;
  remaining: number; // game-hours of work left
  total: number;
}

export const INTERACT_LABEL: Record<InteractKind, string> = {
  deadfall: 'Break deadfall wood',
  boughs: 'Snap spruce boughs',
  bark: 'Peel birch bark',
  rock: 'Collect hand rocks',
  snow: 'Pack snow (container)',
  water: 'Scoop stream water (container)',
  wreck: 'Scavenge the wreck',
};

/** base work duration in GAME HOURS */
export const WORK_HOURS: Record<InteractKind, number> = {
  deadfall: 0.35,
  boughs: 0.2,
  bark: 0.3,
  rock: 0.25,
  snow: 0.1,
  water: 0.1,
  wreck: 0.5,
};

export const YIELDS: Partial<Record<InteractKind, { item: ItemId; n: number }[]>> = {
  deadfall: [{ item: 'deadfall', n: 2 }],
  boughs: [{ item: 'boughs', n: 3 }],
  bark: [{ item: 'bark', n: 2 }],
  rock: [{ item: 'rock', n: 1 }],
  snow: [{ item: 'snow', n: 1 }],
  water: [{ item: 'waterRaw', n: 1 }],
};

export const WRECK_LOOT: { item: ItemId; n: number }[] = [
  { item: 'knife', n: 1 },
  { item: 'tinCup', n: 1 },
  { item: 'blanket', n: 1 },
  { item: 'flareGun', n: 1 },
  { item: 'flare', n: 1 },
  { item: 'ductTape', n: 2 },
  { item: 'kindling', n: 2 },
];

export function buildInteractables(seed: number, props: Prop[]): Interactable[] {
  const list: Interactable[] = [];
  let id = 1;
  for (const p of props) {
    const r = valueNoise2(p.x * 0.11, p.z * 0.11, seed + 31);
    if (p.kind === 'spruce') {
      if (r < 0.22) list.push({ id: id++, kind: 'deadfall', x: p.x, z: p.z, uses: 2 });
      else if (r < 0.5) list.push({ id: id++, kind: 'boughs', x: p.x, z: p.z, uses: 3 });
    } else if (p.kind === 'birch' && r < 0.45) {
      list.push({ id: id++, kind: 'bark', x: p.x, z: p.z, uses: 2 });
    } else if (p.kind === 'rock' && r < 0.6) {
      list.push({ id: id++, kind: 'rock', x: p.x, z: p.z, uses: 2 });
    }
  }
  // stream access points every ~45 m
  for (let z = 200; z > -150; z -= 45) {
    list.push({ id: id++, kind: 'water', x: streamX(z), z, uses: 99 });
  }
  // crash site
  list.push({ id: id++, kind: 'wreck', x: 0, z: -140, uses: 1 });
  return list;
}

export const INTERACT_RADIUS_M = 2.6;

/** nearest interactable (or dynamic snow if none close and standing on snow) */
export function findTarget(
  px: number,
  pz: number,
  list: Interactable[],
  allowSnow: boolean,
): Interactable | null {
  let best: Interactable | null = null;
  let bd = INTERACT_RADIUS_M;
  for (const it of list) {
    if (it.uses <= 0) continue;
    const d = Math.hypot(it.x - px, it.z - pz);
    if (d < bd) {
      bd = d;
      best = it;
    }
  }
  if (!best && allowSnow) {
    // dynamic snow target follows the player (ground is snow everywhere)
    return { id: -1, kind: 'snow', x: px, z: pz, uses: 99 };
  }
  return best;
}

export function startTask(target: Interactable): WorkTask {
  const hours = WORK_HOURS[target.kind];
  const secs = hours * CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
  return { targetId: target.id, remaining: secs, total: secs };
}
