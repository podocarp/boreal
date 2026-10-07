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
import {
  addInjury, buildFishHoles, fishRoll, setSnare, spawnWolves,
  sepsisDamagePerH, tickInjuries, tickSnares, tickWolves, treatInjury,
  type FishHole, type Injury, type Snare, type Wolf,
} from './dangers';
import {
  checkCollapse, checkPass, createRescue, type DetectionInput, type RescueState,
} from './rescue';
import {
  activeStorm,
  canSleep,
  scoreSite,
  shelterWarmthAt,
  shouldWake,
  sleepRestorePerH,
  SHELTER_STEPS,
  stormWindMul,
  stormWetnessPerH,
  createSleep,
  type Shelter,
  type SleepState,
} from './shelter';

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
  shelters: Shelter[];
  nextShelterId: number;
  sleep: SleepState;
  snares: Snare[];
  nextSnareId: number;
  fishHoles: FishHole[];
  wolves: Wolf[];
  injuries: Injury[];
  /** true while the player shouts (hoo-hoo) — wolf repel */
  shouting: boolean;
  /** wolves spawned this night (reset at dawn) */
  wolvesOut: boolean;
  /** serializable RNG stream counter (mix with seed per roll) */
  rngN: number;
  rescue: RescueState;
  /** signal fire: a fire flagged for smoke (green boughs added) */
  signalFireId: number | null;
  /** game-hours since the flare was fired (null = never) */
  flareAgeH: number | null;
  /** game-hours since the player last moved (tracks in snow) */
  stillH: number;
  /** run ended in rescue */
  rescued?: { day: number; kind: string; detail: string };
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
    shelters: [],
    nextShelterId: 1,
    sleep: createSleep(),
    snares: [],
    nextSnareId: 1,
    fishHoles: buildFishHoles(seed),
    wolves: [],
    injuries: [],
    shouting: false,
    wolvesOut: false,
    rngN: 0,
    rescue: createRescue(),
    signalFireId: null,
    flareAgeH: null,
    stillH: 0,
  };
}

function pushLog(w: WorldState, msg: string): void {
  w.log.push({ t: w.t, day: w.day, msg });
  if (w.log.length > 200) w.log.shift();
}

/** dt (real sim seconds) → game hours. */
function dtGameH(_w: WorldState, dt: number): number {
  return dt / CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
}

/** Deterministic roll from the world's RNG stream (serializable). */
export function roll(w: WorldState): number {
  w.rngN = (w.rngN + 1) | 0;
  return makeRng((w.seed * 0x9e3779b9) ^ (w.rngN * 0x85ebca6b))();
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
  const storm = activeStorm(w.day, w.hourOfDay);
  w.env.windKmh =
    CONFIG.WORLD.WIND_BASE_KMH * zoneWind * (night ? CONFIG.CLIMATE.WIND_NIGHT_MUL : 1) * stormWindMul(storm);

  // flare aging + stillness (tracks in snow fade)
  if (w.flareAgeH !== null) w.flareAgeH += dtGameH(w, dt);
  w.stillH = w.player.moving ? 0 : w.stillH + dtGameH(w, dt);

  if (!w.dead && !w.rescued) {
    // storm wetness: wet snow soaks clothing unless sheltered
    if (storm) {
      const sheltered = shelterWarmthAt(w.shelters, w.player.x, w.player.z) > 0.5 ||
        w.fires.some((f) => f.lit && Math.hypot(f.x - w.player.x, f.z - w.player.z) < 3);
      const gain = stormWetnessPerH(storm) * (sheltered ? 0.25 : 1) * dtGameH(w, dt);
      w.needs.wetness = Math.min(1, w.needs.wetness + gain);
    }
    // drying by fire (slow)
    const nearFire = w.fires.some((f) => f.lit && Math.hypot(f.x - w.player.x, f.z - w.player.z) < 3);
    if (nearFire && w.needs.wetness > 0) {
      w.needs.wetness = Math.max(0, w.needs.wetness - 0.1 * dtGameH(w, dt));
    }

    // fires burn down + warmth at player
    for (const f of w.fires) {
      if (tickFire(f, dtGameH(w, dt), w.env.windKmh)) pushLog(w, 'Your fire has gone out.');
    }
    w.env.fireWarmth = maxWarmth(w.fires, w.player.x, w.player.z);
    w.env.shelterInsul = shelterWarmthAt(w.shelters, w.player.x, w.player.z);

    // sleep: energy restore scaled by warmth/food; sleeping in the cold is the gamble
    if (w.needs.sleeping) {
      w.sleep.hours += dtGameH(w, dt);
      const warm =
        w.needs.coreTemp > CONFIG.THERMO.COLD_C ||
        w.env.shelterInsul > 0.5 ||
        w.env.fireWarmth > 0.25;
      const restore = sleepRestorePerH(warm, w.needs.hunger > 25);
      w.needs.energy = Math.min(100, w.needs.energy + restore * dtGameH(w, dt));
      const wake = shouldWake(w.sleep, w.needs.energy, w.hourOfDay);
      if (wake) {
        w.needs.sleeping = false;
        w.sleep.active = false;
        pushLog(w, wake);
      }
    }

    // --- S6: food & dangers ---
    // snares catch over time (deep-snow mulch from recent storm halves rate)
    if (w.snares.some((s) => s.set)) {
      const snowMul = activeStorm(w.day, w.hourOfDay) ? 0.5 : 1;
      const { caught, ids } = tickSnares(w.snares, dtGameH(w, dt), snowMul, () => roll(w));
      for (const id of ids) {
        const s = w.snares.find((x) => x.id === id)!;
        s.pending = (s.pending ?? 0) + 1; // must be collected at the snare
      }
      if (caught) pushLog(w, 'A snare sprang somewhere down the stream bank.');
    }

    // wolves: nights from day 2; gone at dawn
    if (night && w.day >= 2 && !w.wolvesOut) {
      w.wolves = spawnWolves(w.seed + w.day * 97);
      w.wolvesOut = true;
    } else if (!night && w.wolvesOut) {
      w.wolves = [];
      w.wolvesOut = false;
    }
    if (w.wolves.length > 0) {
      const fire = w.env.fireWarmth > 0.1 ? nearestFire(w) : null;
      const weakened =
        w.needs.coreTemp < CONFIG.THERMO.COLD_C ||
        w.needs.health < 60 ||
        w.needs.energy < 20 ||
        (w.needs.sleeping && w.needs.health < 50); // sleeping at camp ≠ easy kill; you wake to snarls
      const resW = tickWolves(w.wolves, dt, {
        px: w.player.x,
        pz: w.player.z,
        night,
        fireX: fire && fire.lit ? fire.x : null,
        fireZ: fire && fire.lit ? fire.z : 0,
        fireR: fire && fire.lit ? 6 : 0,
        playerWeakened: weakened,
        playerShouting: w.shouting,
        rng: () => roll(w),
      });
      for (const e of resW.events) pushLog(w, e);
      if (resW.damage > 0) {
        w.needs.health = Math.max(0, w.needs.health - resW.damage * 0.5);
        addInjury(w.injuries, 'wolf bite', 35 + resW.damage);
        if (w.needs.health <= 0) {
          w.dead = { cause: 'wolf attack', detail: 'The pack finished what the cold started.' };
          pushLog(w, 'The pack closes in. The snow goes red.');
        }
      }
    }
    w.shouting = false; // held per-frame from input

    // injuries → infection
    for (const e of tickInjuries(w.injuries, dtGameH(w, dt), () => roll(w))) pushLog(w, e);

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

    // sepsis drains health AFTER regen (untreated infection out-heals recovery)
    const sep = sepsisDamagePerH(w.injuries);
    if (sep > 0 && !w.dead) {
      w.needs.health = Math.max(0, w.needs.health - sep * dtGameH(w, dt));
      if (w.needs.health <= 0) {
        w.dead = { cause: 'infection', detail: 'Blood poisoning from an untreated wound.' };
        pushLog(w, 'Fever takes you. The wound won.');
      }
    }

    // --- S7: rescue search passes + collapse deadline ---
    const pass = checkPass(w.rescue, w.day, w.hourOfDay, storm?.severity ?? 0,
      () => detectionInput(w), () => roll(w));
    if (pass.fired) {
      if (pass.scrubbed) {
        pushLog(w, `The ${pass.kind} search is scrubbed — whiteout. No flight.`);
      } else if (pass.spotted) {
        w.rescued = {
          day: w.day,
          kind: pass.kind ?? 'dawn',
          detail: 'The pilot sees your smoke and banks toward you.',
        };
        pushLog(w, 'RESCUED — engine noise swells out of the south.');
      } else {
        pushLog(w, `The ${pass.kind} pass goes overhead. They don't see you.`);
      }
    }
    if (!w.rescued && checkCollapse(w.rescue, w.day)) {
      w.dead = { cause: 'exposure', detail: 'Ten days. The search gave up. So did you.' };
      pushLog(w, 'Day 10. No engines. The cold wins by default.');
    }
  }
}

/** What the pilot would see at a search pass. */
export function detectionInput(w: WorldState): DetectionInput {
  const signal = w.signalFireId !== null
    ? w.fires.find((f) => f.id === w.signalFireId && f.lit) ?? null
    : null;
  const anyFire = w.fires.some((f) => f.lit);
  const open = w.player.zone === 'lake' || w.player.zone === 'ridge';
  return {
    signalSmoke: signal !== null,
    anyFire,
    flareUsedRecently: w.flareAgeH !== null && w.flareAgeH < CONFIG.RESCUE.FLARE_WINDOW_H,
    openGround: open,
    onRidge: w.player.zone === 'ridge',
    shelterVisible: w.shelters.some((s) => s.complete),
    movedRecently: w.stillH < 1,
  };
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
  const wasShelter = w.task.kind === 'shelter';
  const shelterId = w.task.targetId;
  w.task = null;
  if (wasShelter) {
    finishShelterStep(w, shelterId);
    return;
  }
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
      rng: () => roll(w),
    });
  if (!lit) {
    pushLog(w, 'The ember died in your hands. No flame.');
    return 'failed';
  }
  w.fires.push({ id: w.nextFireId++, x: w.player.x, z: w.player.z, fuel: 25, lit: true });
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
    if (roll(w) < 0.35) {
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

/** Eat (cooked meat > berries > raw meat). */
export function eat(w: WorldState): boolean {
  return eat2(w);
}

// ---------------------------------------------------------------------------
// Food & dangers actions (S6)
// ---------------------------------------------------------------------------

/** Set a snare at the player (costs 1 cordage). Quality from hare sign. */
export function setSnareAction(w: WorldState): 'set' | 'materials' | 'too-close' {
  if (w.dead) return 'materials';
  if (!invHas(w.inventory, 'cordage', 1)) return 'materials';
  if (w.snares.some((s) => s.set && Math.hypot(s.x - w.player.x, s.z - w.player.z) < 8)) {
    return 'too-close'; // overlapping runs spook the hares
  }
  invRemove(w.inventory, 'cordage', 1);
  const s = setSnare(w.snares, w.nextSnareId++, w.player.x, w.player.z, w.seed);
  pushLog(w, s.quality > 0.5 ? 'Snare set on fresh sign — good spot.' : 'Snare set. The sign here is thin.');
  return 'set';
}

/** Collect game from any snare within reach. */
export function checkSnares(w: WorldState): number {
  let got = 0;
  for (const s of w.snares) {
    if ((s.pending ?? 0) > 0 && Math.hypot(s.x - w.player.x, s.z - w.player.z) < 3) {
      if (invCanAdd(w.inventory, 'meat', s.pending!)) {
        invAdd(w.inventory, 'meat', s.pending!);
        got += s.pending!;
        s.pending = 0;
      } else pushLog(w, 'No room for the game.');
    }
  }
  if (got) pushLog(w, `You collect ${got}× small game from the snare.`);
  return got;
}

/** Fish at an ice-edge hole (needs cordage; dawn/dusk bite better). */
export function fish(w: WorldState): 'caught' | 'missed' | 'no-hole' | 'materials' {
  if (w.dead) return 'no-hole';
  const hole = w.fishHoles.find((h) => h.usesLeft > 0 && Math.hypot(h.x - w.player.x, h.z - w.player.z) < 4);
  if (!hole) return 'no-hole';
  if (!invHas(w.inventory, 'cordage', 1)) return 'materials';
  if (fishRoll(w.hourOfDay, () => roll(w))) {
    hole.usesLeft -= 1;
    invAdd(w.inventory, 'meat', 1);
    pushLog(w, 'A pickerel comes up the hole. Meat.');
    return 'caught';
  }
  pushLog(w, 'The line goes slack. Nothing.');
  return 'missed';
}

/** Cook raw meat at a lit fire. */
export function cook(w: WorldState): boolean {
  const f = nearestFire(w, 3);
  if (!f || !f.lit || !invHas(w.inventory, 'meat', 1)) return false;
  invRemove(w.inventory, 'meat', 1);
  invAdd(w.inventory, 'meatCooked', 1);
  pushLog(w, 'You roast the meat over the coals.');
  return true;
}

/** Treat the worst wound with duct tape + boiled-water rinse (needs fire). */
export function treatWound(w: WorldState): boolean {
  if (!invHas(w.inventory, 'ductTape', 1)) return false;
  const f = nearestFire(w, 3);
  if (!f || !f.lit) return false;
  if (!treatInjury(w.injuries)) return false;
  invRemove(w.inventory, 'ductTape', 1);
  pushLog(w, 'You rinse the wound with boiled water and close it with tape. It hurts. It helps.');
  return true;
}

/** Eat: cooked meat >> berries > raw meat (risk). */
/** Craving multiplier: hungrier => same food restores more (Raft-style). */
export function cravingMul(hunger: number): number {
  return 1 + CONFIG.NEEDS.CRAVING_K * (1 - hunger / 100);
}

export function eat2(w: WorldState): boolean {
  const crave = cravingMul(w.needs.hunger);
  if (invHas(w.inventory, 'meatCooked', 1)) {
    invRemove(w.inventory, 'meatCooked', 1);
    w.needs.hunger = Math.min(100, w.needs.hunger + 45 * crave);
    return true;
  }
  if (invHas(w.inventory, 'berries', 1)) {
    invRemove(w.inventory, 'berries', 1);
    w.needs.hunger = Math.min(100, w.needs.hunger + 10 * crave);
    return true;
  }
  if (invHas(w.inventory, 'meat', 1)) {
    invRemove(w.inventory, 'meat', 1);
    w.needs.hunger = Math.min(100, w.needs.hunger + 30 * crave);
    if (roll(w) < 0.5) {
      pushLog(w, 'Raw meat. Your gut knows it.');
      w.needs.hydration = Math.max(0, w.needs.hydration - 10);
    }
    return true;
  }
  return false;
}

/** Fire the flare gun (one shot — near-certain detection at a pass). */
export function fireFlare(w: WorldState): boolean {
  if (w.dead || w.rescued) return false;
  if (!invHas(w.inventory, 'flare', 1) || !invHas(w.inventory, 'flareGun', 1)) return false;
  invRemove(w.inventory, 'flare', 1);
  w.flareAgeH = 0;
  pushLog(w, 'The flare screams up into the grey. One shot. Make it count.');
  return true;
}

/** Throw green boughs on a fire → white smoke column (signal fire). */
export function signalSmoke(w: WorldState): boolean {
  const f = nearestFire(w, 3);
  if (!f || !f.lit || !invHas(w.inventory, 'boughs', 2)) return false;
  invRemove(w.inventory, 'boughs', 2);
  w.signalFireId = f.id;
  pushLog(w, 'Green boughs on the coals — a fat column of white smoke rises.');
  return true;
}

// ---------------------------------------------------------------------------
// Shelter & sleep actions (S5)
// ---------------------------------------------------------------------------

/** Cost per build step (materials). Step order: site/frame/ribs/insulation/mulch/bedding. */
const SHELTER_STEP_COST: { boughs?: number; deadfall?: number }[] = [
  {}, // site: just choose + clear
  { deadfall: 2 }, // ridgepole frame
  { deadfall: 2 }, // ribbing
  { boughs: 6 }, // bough insulation (thickness matters)
  {}, // debris mulch (free, gathered on site)
  { boughs: 6 }, // bedding platform (critical: ground steal)
];

/** Start the next shelter build step at the player's position. */
export function buildShelter(w: WorldState): 'started' | 'complete' | 'materials' | 'far' | 'busy' {
  if (w.dead || w.task) return 'busy';
  let s = w.shelters.find((sh) => Math.hypot(sh.x - w.player.x, sh.z - w.player.z) < 3);
  if (!s) {
    if (w.shelters.length > 0 && !w.shelters.some((sh) => sh.step < SHELTER_STEPS.length)) {
      // all shelters complete; starting a new one is allowed anywhere
    }
    const cost = SHELTER_STEP_COST[0];
    if (!hasCost(w.inventory, cost)) return 'materials';
    s = {
      id: w.nextShelterId++,
      x: w.player.x,
      z: w.player.z,
      step: 0,
      siteQuality: scoreSite(w.player.x, w.player.z, w.seed).total,
      complete: false,
    };
    w.shelters.push(s);
  }
  if (s.step >= SHELTER_STEPS.length) return 'complete';
  const cost = SHELTER_STEP_COST[s.step];
  if (!hasCost(w.inventory, cost)) return 'materials';
  w.task = {
    targetId: s.id,
    remaining: 0.4 * CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR,
    total: 0.4 * CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR,
    kind: 'shelter',
  };
  return 'started';
}

function hasCost(inv: Inventory, cost: { boughs?: number; deadfall?: number }): boolean {
  if (cost.boughs && !invHas(inv, 'boughs', cost.boughs)) return false;
  if (cost.deadfall && !invHas(inv, 'deadfall', cost.deadfall)) return false;
  return true;
}

function payCost(inv: Inventory, cost: { boughs?: number; deadfall?: number }): void {
  if (cost.boughs) invRemove(inv, 'boughs', cost.boughs);
  if (cost.deadfall) invRemove(inv, 'deadfall', cost.deadfall);
}

/** Complete a shelter step (called from tickWork when task.kind==='shelter'). */
function finishShelterStep(w: WorldState, shelterId: number): void {
  const s = w.shelters.find((x) => x.id === shelterId);
  if (!s) return;
  const cost = SHELTER_STEP_COST[s.step];
  payCost(w.inventory, cost);
  s.step += 1;
  s.complete = s.step >= SHELTER_STEPS.length;
  const label = SHELTER_STEPS[Math.min(s.step, SHELTER_STEPS.length) - 1];
  pushLog(w, s.complete ? 'Shelter complete — debris walls, bough bedding.' : `Shelter: ${label} done.`);
}

/** Lie down / get up. Sleeping is possible anywhere — that's the gamble. */
export function toggleSleep(w: WorldState): boolean {
  if (w.dead) return false;
  if (w.needs.sleeping) {
    w.needs.sleeping = false;
    w.sleep.active = false;
    pushLog(w, 'You drag yourself upright.');
    return false;
  }
  if (!canSleep()) return false;
  w.needs.sleeping = true;
  w.sleep.active = true;
  w.sleep.hours = 0;
  const insul = shelterWarmthAt(w.shelters, w.player.x, w.player.z);
  pushLog(w, insul > 0.5 ? 'You crawl into the shelter and sleep.' : 'You try to sleep out in the open. Risky.');
  return true;
}
