import { describe, expect, it } from 'vitest';
import {
  checkSnares, cook, createWorld, eat, feedFire, fish, lightFire,
  setSnareAction, step, treatWound,
} from '../../src/sim/world';
import { computeDebuffs } from '../../src/sim/needs';
import { tickWork } from '../../src/sim/world';
import { hareSignAt, tickWolves } from '../../src/sim/dangers';
import { invAdd, invHas } from '../../src/sim/items';
import { CONFIG } from '../../src/sim/config';
import { streamX } from '../../src/sim/terrain';

const H = CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
const run = (w: ReturnType<typeof createWorld>, gameHours: number) => {
  const ticks = (gameHours * H) / CONFIG.SIM_DT;
  for (let i = 0; i < ticks; i++) {
    step(w, CONFIG.SIM_DT);
    tickWork(w, CONFIG.SIM_DT, computeDebuffs(w.needs).dexterity);
  }
};
/** run() but keeps non-tested needs topped up (isolate the system under test) */
const runStable = (w: ReturnType<typeof createWorld>, gameHours: number, keepHealth = false) => {
  const ticks = (gameHours * H) / CONFIG.SIM_DT;
  for (let i = 0; i < ticks; i++) {
    step(w, CONFIG.SIM_DT);
    if (!w.dead) {
      w.needs.hydration = 100;
      w.needs.hunger = 100;
      w.needs.energy = 100;
      w.needs.coreTemp = 37;
      w.needs.wetness = 0;
      if (keepHealth) w.needs.health = 100;
      w.wolves = []; // isolate the system under test from the pack
    }
  }
};

describe('snares', () => {
  it('need cordage; placement quality follows hare sign near the stream', () => {
    const w = createWorld(1);
    expect(setSnareAction(w)).toBe('materials');
    invAdd(w.inventory, 'cordage', 2);
    w.player.x = streamX(-80) + 4;
    w.player.z = -80;
    expect(setSnareAction(w)).toBe('set');
    expect(w.snares[0].quality).toBeGreaterThan(0.3);
    // overlapping snare rejected
    expect(setSnareAction(w)).toBe('too-close');
    // far from the stream = thin sign
    expect(hareSignAt(-260, 0, 1)).toBeLessThan(0.1);
  });

  it('catch over time and collect at the snare', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'cordage', 1);
    w.player.x = streamX(-80) + 4;
    w.player.z = -80;
    setSnareAction(w);
    // run up to 3 game-days of snare time (freshness decays but quality high)
    for (let i = 0; i < 72 && !w.snares[0].pending; i++) runStable(w, 1);
    expect(w.snares[0].pending ?? 0).toBeGreaterThan(0);
    expect(checkSnares(w)).toBe(1);
    expect(invHas(w.inventory, 'meat', 1)).toBe(true);
  });
});

describe('fishing & cooking', () => {
  it('fish at holes with cordage; dawn bite; cooked meat fills you more', () => {
    const w = createWorld(1);
    const hole = w.fishHoles[0];
    w.player.x = hole.x;
    w.player.z = hole.z;
    expect(fish(w)).toBe('materials');
    invAdd(w.inventory, 'cordage', 1);
    w.hourOfDay = 8; // golden hour
    let caught = 0;
    for (let i = 0; i < 12 && caught < 1; i++) if (fish(w) === 'caught') caught++;
    expect(caught).toBe(1);
    expect(invHas(w.inventory, 'meat', 1)).toBe(true);

    // cook at fire
    invAdd(w.inventory, 'tinderBundle', 1);
    invAdd(w.inventory, 'deadfall', 3);
    lightFire(w, 1);
    feedFire(w);
    expect(cook(w)).toBe(true);
    w.needs.hunger = 0;
    eat(w);
    expect(w.needs.hunger).toBeGreaterThanOrEqual(45);
  });

  it('raw meat is a gut risk', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'meat', 1);
    w.needs.hunger = 0;
    w.needs.hydration = 100;
    eat(w);
    expect(w.needs.hunger).toBeGreaterThanOrEqual(30);
  });
});

describe('wolves', () => {
  it('day 1 is safe; night day 2+ brings the pack; fire + shouting repel', () => {
    const w = createWorld(1);
    w.day = 1;
    w.hourOfDay = 22;
    run(w, 1);
    expect(w.wolves.length).toBe(0);
    w.day = 2;
    run(w, 0.1);
    expect(w.wolves.length).toBeGreaterThanOrEqual(2);

    // weakened player next to a big fire, shouting: wolves must not close to bite
    w.needs.coreTemp = 30; // weakened → interested
    let bitten = false;
    for (let i = 0; i < 60 * 10; i++) {
      w.shouting = true;
      if (w.fires.length === 0) w.fires.push({ id: 99, x: w.player.x, z: w.player.z, fuel: 100, lit: true });
      step(w, CONFIG.SIM_DT);
      if (w.injuries.length > 0) bitten = true;
    }
    expect(bitten).toBe(false);
    expect(w.wolves.every((x) => x.state === 'fleeing')).toBe(true);
  });

  it('a weakened player far from fire at night can be bitten and wounded', () => {
    const w = createWorld(1);
    w.day = 3;
    w.hourOfDay = 23;
    w.needs.coreTemp = 30;
    run(w, 0.1); // spawn pack
    let bitten = false;
    for (let i = 0; i < 60 * 40 && !bitten; i++) {
      step(w, CONFIG.SIM_DT);
      bitten = w.injuries.length > 0;
    }
    expect(bitten).toBe(true);
  });

  it('tickWolves enforces the reaction delay (no instant bite)', () => {
    const wolves = [{ id: 1, x: 3, z: 0, state: 'prowling' as const, acquireT: 0, coolT: 0, fear: 0, phase: 0, strafePeriod: 1.5 }];
    const res = tickWolves(wolves, 0.05, {
      px: 0, pz: 0, night: true, fireX: null, fireZ: 0, fireR: 0,
      playerWeakened: true, playerShouting: false, rng: () => 0.99,
    });
    expect(res.damage).toBe(0);
  });
});

describe('injury → infection', () => {
  it('untreated bites infect; duct tape + fire treats; sepsis kills', () => {
    const w = createWorld(1);
    w.injuries.push({ severity: 60, infected: false, infection: 0, label: 'wolf bite' });
    for (let i = 0; i < 96 && !w.injuries[0].infected; i++) runStable(w, 1, true);
    expect(w.injuries[0].infected).toBe(true);

    // treat with tape at a fire
    invAdd(w.inventory, 'ductTape', 1);
    for (let i = 0; i < 8 && !w.fires.some((f) => f.lit); i++) {
      invAdd(w.inventory, 'tinderBundle', 1);
      invAdd(w.inventory, 'deadfall', 3);
      lightFire(w, 1);
      step(w, CONFIG.SIM_DT); // advance the RNG stream between attempts
    }
    feedFire(w);
    expect(w.fires.some((f) => f.lit)).toBe(true);
    expect(treatWound(w)).toBe(true);
    expect(w.injuries[0].infected).toBe(false);
  });

  it('advanced sepsis drains health to death', () => {
    const w = createWorld(1);
    w.injuries.push({ severity: 80, infected: true, infection: 90, label: 'wolf bite' });
    for (let i = 0; i < 90 && !w.dead; i++) runStable(w, 1);
    expect(w.dead?.cause).toBe('infection');
  });
});
