/**
 * BOREAL — pure simulation core (no three.js, no DOM, no wall clock).
 * Sprint 0 stub: world state + fixed-timestep step(). S1+ adds movement,
 * S2 adds needs/thermoregulation per docs/DESIGN-needs.md.
 */
import { CONFIG } from './config';
import { collidersFrom, scatter, type Collider } from './scatter';
import type { Zone } from './terrain';
import { airTempAt, createEnv, createNeeds, tickNeeds, windchill, type Difficulty, type EnvState, type NeedsState } from './needs';
import { buildInteractables, findTarget, startTask, WRECK_LOOT, YIELDS, type Interactable, type WorkTask } from './interact';
import { invAdd, invCanAdd, invRemove, invHas, type Inventory } from './items';
import { addFuel, frictionRoll, maxWarmth, tickFire, type Fire } from './fire';

export interface WorldState {
  seed: number;
  /** Elapsed sim time in seconds. */
  t: number;
  /** In-game hour of day, 0..24. */
  hourOfDay: number;
  /** In-game day number, 1-based. */
  day: number;
  player: {
    x: number;
    y: number;
    z: number;
    yaw: number;
    speed: number;
    moving: boolean;
    zone: Zone;
  };
  colliders: Collider[];
  needs: NeedsState;
  env: EnvState;
  difficulty: Difficulty;
  /** rolling event log for the death/rescue narrative */
  log: { t: number; day: number; msg: string }[];
  /** set when the run ends */
  dead?: { cause: string; detail: string };
  inventory: Inventory;
  interactables: Interactable[];
  task: WorkTask | null;
  fires: Fire[];
  nextFireId: number;
}

export function createWorld(seed = 1, difficulty: Difficulty = 'ranger'): WorldState {
  const props = scatter(seed);
  return {
    seed,
    t: 0,
    hourOfDay: 8,
    day: 1,
    player: { x: 0, y: 0, z: -140, yaw: Math.PI, speed: 0, moving: false, zone: 'lake' },
    colliders: collidersFrom(props),
    needs: createNeeds(),
    env: createEnv(),
    difficulty,
    log: [{ t: 0, day: 1, msg: 'You crawl from the wreck. The radio is dead. Search pattern passes near day 7.' }],
    inventory: {},
    interactables: buildInteractables(seed, props),
    task: null,
    fires: [],
    nextFireId: 1,
  };
}

function pushLog(w: WorldState, msg: string): void {
  w.log.push({ t: w.t, day: w.day, msg });
  if (w.log.length > 200) w.log.shift();
}

/** Advance the world by one fixed tick (CONFIG.SIM_DT seconds). Pure w.r.t. args. */
export function step(w: WorldState, dt = CONFIG.SIM_DT, sprinting = false): void {
  w.t += dt;
  const hoursPerSec = 1 / CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
  w.hourOfDay += dt * hoursPerSec;
  if (w.hourOfDay >= 24) {
    w.hourOfDay -= 24;
    w.day += 1;
  }

  // environment at player: diurnal temp, wind (lake/ridge exposed, forest sheltered)
  const night = w.hourOfDay < 9 || w.hourOfDay > 17;
  w.env.airTempC = airTempAt(w.hourOfDay, CONFIG.WORLD.TEMP_BASE_C, CONFIG.CLIMATE.TEMP_SWING_C);
  const zoneWind =
    w.player.zone === 'lake' || w.player.zone === 'ridge' ? 1.35 : w.player.zone === 'forest' ? 0.6 : 1.0;
  w.env.windKmh = CONFIG.WORLD.WIND_BASE_KMH * zoneWind * (night ? CONFIG.CLIMATE.WIND_NIGHT_MUL : 1);

  if (!w.dead) {
    // fires burn down + warmth at player
    const dtGameH = dt / CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
    for (const f of w.fires) {
      if (tickFire(f, dtGameH, w.env.windKmh)) pushLog(w, 'Your fire has gone out.');
    }
    w.env.fireWarmth = maxWarmth(w.fires, w.player.x, w.player.z);

    const res = tickNeeds(w.needs, w.env, dt, {
      moving: w.player.moving,
      sprinting,
      difficulty: w.difficulty,
    });
    for (const e of res.events) pushLog(w, e);
    if (res.died) {
      w.dead = res.died;
      pushLog(w, `You died of ${res.died.cause} (${res.died.detail}).`);
    }
  }
}

/** feels-like temp at player (HUD). */
export function feelsLike(w: WorldState): number {
  return windchill(w.env.airTempC, w.env.windKmh);
}

/** What can the player interact with right now? (HUD prompt) */
export function currentTarget(w: WorldState): Interactable | null {
  if (w.task) return null;
  // snow is always available as a fallback target; container is checked at beginWork
  return findTarget(w.player.x, w.player.z, w.interactables, true);
}

/** Begin a work task on the nearest target. Returns false if nothing to do. */
export function beginWork(w: WorldState): boolean {
  if (w.dead || w.task) return false;
  const t = currentTarget(w);
  if (!t) return false;
  if (t.kind === 'snow' || t.kind === 'water') {
    const hasContainer = (w.inventory.barkContainer ?? 0) > 0 || (w.inventory.tinCup ?? 0) > 0;
    if (!hasContainer) {
      pushLog(w, 'You need a container (tin cup, bark container) for that.');
      return false;
    }
  }
  w.task = startTask(t);
  return true;
}

/** Advance the active work task; completes with yields when done.
 * dexterity debuff slows work; moving cancels it. */
export function tickWork(w: WorldState, dt: number, dexterity: number): void {
  if (!w.task) return;
  if (w.player.moving) {
    w.task = null; // work requires standing still
    return;
  }
  w.task.remaining -= dt * Math.max(0.25, dexterity);
  if (w.task.remaining > 0) return;

  const target =
    w.task.targetId === -1
      ? ({ id: -1, kind: 'snow', x: w.player.x, z: w.player.z, uses: 99 } as Interactable)
      : w.interactables.find((i) => i.id === w.task!.targetId);
  w.task = null;
  if (!target) return;

  const yields = target.kind === 'wreck' ? WRECK_LOOT : YIELDS[target.kind] ?? [];
  let gotAny = false;
  for (const y of yields) {
    if (invCanAdd(w.inventory, y.item, y.n)) {
      invAdd(w.inventory, y.item, y.n);
      gotAny = true;
    } else {
      pushLog(w, `No room for ${y.item}.`);
    }
  }
  if (gotAny && target.id !== -1) target.uses -= 1;
  if (gotAny) {
    const names = yields.map((y) => `${y.n}× ${y.item}`).join(', ');
    pushLog(w, `Collected: ${names}`);
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

// ---------------------------------------------------------------------------
// Fire & water actions (S4)
// ---------------------------------------------------------------------------

/** Light a fire at the player: needs a tinder bundle; friction roll decides.
 * dexterity = current debuff multiplier (cold hands fumble).
 * Returns 'lit' | 'failed' | 'no-bundle'. */
export function lightFire(w: WorldState, dexterity = 0.7): 'lit' | 'failed' | 'no-bundle' {
  if (w.dead) return 'no-bundle';
  if (!invHas(w.inventory, 'tinderBundle', 1)) return 'no-bundle';
  invRemove(w.inventory, 'tinderBundle', 1);
  const nearFire = w.fires.some((f) => f.lit && Math.hypot(f.x - w.player.x, f.z - w.player.z) < 3);
  const lit =
    nearFire || // relaying from an existing fire never fails
    frictionRoll({
      dexterity,
      handWetness: w.needs.wetness,
      coreTemp: w.needs.coreTemp,
      woodDry: true,
      rng: makeRng(Math.floor(w.t * 1000) ^ w.seed),
    });
  if (!lit) {
    pushLog(w, 'The ember died in your hands. No flame.');
    return 'failed';
  }
  w.fires.push({ id: w.nextFireId++, x: w.player.x, z: w.player.z, fuel: 15, lit: true });
  pushLog(w, 'The tinder catches — fire!');
  return 'lit';
}

/** Feed the nearest fire from inventory. Returns how many items were burned. */
export function feedFire(w: WorldState): number {
  const f = nearestFire(w, 3);
  if (!f) return 0;
  let fed = 0;
  while (invHas(w.inventory, 'deadfall', 1) && f.fuel < 90) {
    invRemove(w.inventory, 'deadfall', 1);
    addFuel(f, 'deadfall');
    fed++;
  }
  if (!fed && invHas(w.inventory, 'kindling', 1) && f.fuel < 60) {
    invRemove(w.inventory, 'kindling', 1);
    addFuel(f, 'kindling');
    fed++;
  }
  if (fed) pushLog(w, `You feed the fire (${fed}).`);
  return fed;
}

export function nearestFire(w: WorldState, maxDist = Infinity): Fire | null {
  let best: Fire | null = null;
  let bd = maxDist;
  for (const f of w.fires) {
    const d = Math.hypot(f.x - w.player.x, f.z - w.player.z);
    if (d < bd) {
      bd = d;
      best = f;
    }
  }
  return best;
}

/** Melt/boil: at a lit fire, convert snow→clean water or raw→clean (tin cup).
 * Eating snow without a fire is possible but chills you (handled in drink()). */
export function boilWater(w: WorldState): boolean {
  const f = nearestFire(w, 3);
  if (!f || !f.lit) return false;
  const hasCup = invHas(w.inventory, 'tinCup', 1) || invHas(w.inventory, 'barkContainer', 1);
  if (!hasCup) return false;
  if (invHas(w.inventory, 'snow', 1)) {
    invRemove(w.inventory, 'snow', 1);
    if (!invCanAdd(w.inventory, 'waterClean', 1)) return false;
    invAdd(w.inventory, 'waterClean', 1);
    pushLog(w, 'Snow melted and boiled. Safe water.');
    return true;
  }
  if (invHas(w.inventory, 'waterRaw', 1)) {
    invRemove(w.inventory, 'waterRaw', 1);
    if (!invCanAdd(w.inventory, 'waterClean', 1)) return false;
    invAdd(w.inventory, 'waterClean', 1);
    pushLog(w, 'Water boiled. Safe water.');
    return true;
  }
  return false;
}

/** Drink from inventory. Clean water = full benefit; raw = benefit + risk;
 * snow without fire = small benefit + core-temp hit (the real mistake). */
export function drink(w: WorldState): boolean {
  if (invHas(w.inventory, 'waterClean', 1)) {
    invRemove(w.inventory, 'waterClean', 1);
    w.needs.carriedWaterL += 1;
    return true;
  }
  if (invHas(w.inventory, 'waterRaw', 1)) {
    invRemove(w.inventory, 'waterRaw', 1);
    w.needs.carriedWaterL += 1;
    if (makeRng(Math.floor(w.t * 7919) ^ w.seed)() < 0.35) {
      pushLog(w, 'That water disagreed with you...');
      w.needs.hydration = Math.max(0, w.needs.hydration - 8); // gut bug
    }
    return true;
  }
  if (invHas(w.inventory, 'snow', 1)) {
    invRemove(w.inventory, 'snow', 1);
    w.needs.hydration = Math.min(100, w.needs.hydration + 12);
    w.needs.coreTemp = Math.max(24, w.needs.coreTemp - 0.4); // eating snow = cold debt
    pushLog(w, 'Eating snow. It helps the thirst and hurts everything else.');
    return true;
  }
  return false;
}

/** Eat berries (the MVP food source until S6 adds snares/fish). */
export function eat(w: WorldState): boolean {
  if (!invHas(w.inventory, 'berries', 1)) return false;
  invRemove(w.inventory, 'berries', 1);
  w.needs.hunger = Math.min(100, w.needs.hunger + 10);
  return true;
}
