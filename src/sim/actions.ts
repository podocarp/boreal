/**
 * Contextual actions — the single source of truth for "what can I do here?".
 * Pure sim module (no DOM): the radial menu (src/ui/menu.ts) renders whatever
 * this returns; unit tests assert availability logic without a browser.
 *
 * Design (playtest feedback: "individual buttons for boil etc is a nightmare"):
 * one primary verb (LMB/E on the nearest thing) + one context wheel (hold RMB)
 * listing only actions that make sense at this spot right now.
 */
import type { WorldState } from './world';
import {
  beginWork, buildShelter, checkSnares, cook, currentTarget, drink, eat,
  feedFire, fireFlare, fish, lightFire, nearestFire, setSnareAction,
  signalSmoke, toggleSleep, treatWound, boilWater,
} from './world';
import { INTERACT_LABEL } from './interact';
import { invHas } from './items';
import { RECIPES, canCraft, craft } from './craft';

export interface ActionOption {
  id: string;
  label: string;
  enabled: boolean;
  /** why it's disabled / what it will consume — shown as the slot hint */
  hint?: string;
  /** execute; returns nothing meaningful (world log tells the story) */
  run: (w: WorldState) => void;
}

export interface ActionCtx {
  dexterity: number; // from computeDebuffs — cold hands fumble fire-lighting
}

function push(list: ActionOption[], a: ActionOption): void {
  list.push(a);
}

/**
 * Actions available to the player right now, priority-ordered.
 * Slot 0 is also the primary verb (LMB/E) when it is a gather/loot target.
 */
export function contextActions(w: WorldState, ctx: ActionCtx): ActionOption[] {
  const list: ActionOption[] = [];
  if (w.dead || w.rescued) return list;

  const fire = nearestFire(w, 3);
  const litFire = fire && fire.lit ? fire : null;

  // sleeping: the only verb is waking up
  if (w.needs.sleeping) {
    list.push({ id: 'wake', label: 'Wake up', enabled: true, run: (x) => void toggleSleep(x) });
    return list;
  }

  // 1) world target under/near the player (gather, loot, snow, water…)
  const tgt = currentTarget(w);
  if (tgt) {
    push(list, {
      id: 'work',
      label: INTERACT_LABEL[tgt.kind],
      enabled: true,
      run: (x) => void beginWork(x),
    });
  }

  // 2) spot-specific verbs (only when the spot is right here)
  const snareHere = w.snares.some((s) => (s.pending ?? 0) > 0 && Math.hypot(s.x - w.player.x, s.z - w.player.z) < 3);
  if (snareHere) {
    push(list, { id: 'collectSnare', label: 'Collect snare game', enabled: true, run: (x) => void checkSnares(x) });
  }
  const holeHere = w.fishHoles.some((h) => h.usesLeft > 0 && Math.hypot(h.x - w.player.x, h.z - w.player.z) < 4);
  if (holeHere) {
    const hasLine = invHas(w.inventory, 'cordage', 1);
    push(list, {
      id: 'fish', label: 'Fish the hole', enabled: hasLine,
      hint: hasLine ? undefined : 'needs cordage',
      run: (x) => void fish(x),
    });
  }

  // 3) fire verbs (only near a fire)
  if (fire) {
    const wood = invHas(w.inventory, 'deadfall', 1) || invHas(w.inventory, 'kindling', 1);
    push(list, {
      id: 'feed', label: 'Feed the fire', enabled: !!litFire && wood,
      hint: litFire ? (wood ? undefined : 'needs deadfall/kindling') : 'fire is out',
      run: (x) => void feedFire(x),
    });
    if (invHas(w.inventory, 'meat', 1)) {
      push(list, {
        id: 'cook', label: 'Cook the meat', enabled: !!litFire,
        hint: litFire ? undefined : 'needs a lit fire',
        run: (x) => void cook(x),
      });
    }
    const cup = invHas(w.inventory, 'tinCup', 1) || invHas(w.inventory, 'barkContainer', 1);
    const snowOrRaw = invHas(w.inventory, 'snow', 1) || invHas(w.inventory, 'waterRaw', 1);
    if (snowOrRaw) {
      push(list, {
        id: 'boil', label: 'Boil / melt snow', enabled: !!litFire && cup,
        hint: !litFire ? 'needs a lit fire' : !cup ? 'needs a container' : undefined,
        run: (x) => void boilWater(x),
      });
    }
    push(list, {
      id: 'signal', label: 'Signal smoke (2 boughs)', enabled: !!litFire && invHas(w.inventory, 'boughs', 2),
      hint: !litFire ? 'needs a lit fire' : !invHas(w.inventory, 'boughs', 2) ? 'needs 2 boughs' : undefined,
      run: (x) => void signalSmoke(x),
    });
    if ((w.injuries?.length ?? 0) > 0) {
      push(list, {
        id: 'treat', label: 'Treat wounds', enabled: !!litFire && invHas(w.inventory, 'ductTape', 1),
        hint: !litFire ? 'needs a lit fire' : !invHas(w.inventory, 'ductTape', 1) ? 'needs duct tape' : undefined,
        run: (x) => void treatWound(x),
      });
    }
  }

  // 4) light a fire (bundle in pack; relaying from a nearby fire never fails)
  if (invHas(w.inventory, 'tinderBundle', 1) && !litFire) {
    push(list, { id: 'light', label: 'Light fire', enabled: true, run: (x) => void lightFire(x, ctx.dexterity) });
  }

  // 5) consume + camp essentials (never truncated by convenience verbs)
  const hasFood = invHas(w.inventory, 'meatCooked', 1) || invHas(w.inventory, 'berries', 1) || invHas(w.inventory, 'meat', 1);
  if (hasFood) push(list, { id: 'eat', label: 'Eat', enabled: true, run: (x) => void eat(x) });
  const hasWater = invHas(w.inventory, 'waterClean', 1) || invHas(w.inventory, 'waterRaw', 1) || invHas(w.inventory, 'snow', 1);
  if (hasWater) push(list, { id: 'drink', label: 'Drink', enabled: true, run: (x) => void drink(x) });
  push(list, { id: 'sleep', label: 'Sleep', enabled: true, run: (x) => void toggleSleep(x) });
  push(list, { id: 'shelter', label: 'Build shelter', enabled: true, run: (x) => void buildShelter(x) });
  if (invHas(w.inventory, 'cordage', 1)) {
    push(list, { id: 'snare', label: 'Set a snare', enabled: true, run: (x) => void setSnareAction(x) });
  }

  // 6) crafting (only recipes you can make right now) — convenience tier
  for (const r of RECIPES) {
    if (!canCraft(w.inventory, r)) continue;
    push(list, {
      id: `craft:${r.id}`, label: r.label, enabled: true,
      run: (x) => {
        if (craft(x.inventory, r)) x.log.push({ t: x.t, day: x.day, msg: `Crafted: ${r.label}` });
      },
    });
  }

  // 7) last resort
  if (invHas(w.inventory, 'flare', 1) && invHas(w.inventory, 'flareGun', 1)) {
    push(list, { id: 'flare', label: 'Fire the flare', enabled: true, run: (x) => void fireFlare(x) });
  }
  return list;
}

/** The primary verb: the top action (usually the gather target). Null if none. */
export function primaryAction(w: WorldState, ctx: ActionCtx): ActionOption | null {
  return contextActions(w, ctx)[0] ?? null;
}
