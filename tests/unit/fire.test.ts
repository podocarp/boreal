import { describe, expect, it } from 'vitest';
import { createWorld, lightFire, feedFire, boilWater, drink, step } from '../../src/sim/world';
import { fireStage, fireWarmth, frictionRoll, tickFire, warmthRadius, type Fire } from '../../src/sim/fire';
import { invAdd } from '../../src/sim/items';
import { CONFIG } from '../../src/sim/config';

const H = CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;

const mkFire = (fuel = 50, lit = true): Fire => ({ id: 1, x: 0, z: 0, fuel, lit });

describe('fire stages & burn', () => {
  it('stage derives from fuel', () => {
    expect(fireStage(mkFire(0))).toBe(0);
    expect(fireStage(mkFire(10))).toBe(1);
    expect(fireStage(mkFire(30))).toBe(2);
    expect(fireStage(mkFire(60))).toBe(3);
    expect(fireStage(mkFire(90))).toBe(4);
  });

  it('small fires burn down faster (per fuel) — neglect collapses stages', () => {
    const small = mkFire(20);
    const big = mkFire(90);
    tickFire(small, 1, 10);
    tickFire(big, 1, 10);
    expect(small.fuel).toBeLessThan(20 - 20 * 0.15); // 30%/h at tinder stage
    expect(big.fuel).toBeGreaterThan(90 - 90 * 0.15); // 9%/h at log stage
  });

  it('a starved fire goes out', () => {
    const f = mkFire(5);
    let out = false;
    for (let i = 0; i < 10 && !out; i++) out = tickFire(f, 1, 10);
    expect(out).toBe(true);
    expect(f.lit).toBe(false);
  });

  it('warmth radius grows with stage and falls with distance', () => {
    expect(warmthRadius(1)).toBeLessThan(warmthRadius(4));
    const f = mkFire(90);
    expect(fireWarmth(f, 0, 0)).toBeGreaterThan(fireWarmth(f, 3, 0));
    expect(fireWarmth(f, 20, 0)).toBe(0);
  });
});

describe('friction fire', () => {
  it('dry skilled attempt succeeds most of the time', () => {
    let wins = 0;
    for (let i = 0; i < 400; i++)
      if (frictionRoll({ dexterity: 0.9, handWetness: 0, coreTemp: 37, woodDry: true, rng: Math.random }))
        wins++;
    expect(wins / 400).toBeGreaterThan(0.65); // p=0.75; 400 samples keeps this non-flaky
  });

  it('wet hands + cold + green wood nearly always fails', () => {
    let wins = 0;
    for (let i = 0; i < 200; i++)
      if (frictionRoll({ dexterity: 0.4, handWetness: 0.9, coreTemp: 34, woodDry: false, rng: Math.random }))
        wins++;
    expect(wins / 200).toBeLessThan(0.1);
  });
});

describe('fire & water gameplay loop', () => {
  it('lighting needs a tinder bundle; relaying near a fire never fails', () => {
    const w = createWorld(1);
    expect(lightFire(w)).toBe('no-bundle');
    invAdd(w.inventory, 'tinderBundle', 1);
    // force deterministic success path: relay from existing fire
    w.fires.push({ id: 99, x: w.player.x, z: w.player.z, fuel: 50, lit: true });
    expect(lightFire(w)).toBe('lit');
    expect(w.fires.length).toBe(2);
  });

  it('feeding burns deadfall and raises fuel', () => {
    const w = createWorld(1);
    w.fires.push({ id: 1, x: w.player.x, z: w.player.z, fuel: 20, lit: true });
    invAdd(w.inventory, 'deadfall', 3);
    const fed = feedFire(w);
    expect(fed).toBeGreaterThan(0);
    expect(w.fires[0].fuel).toBeGreaterThan(20);
  });

  it('boil: snow → clean water only at a lit fire with a cup', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'snow', 1);
    invAdd(w.inventory, 'tinCup', 1);
    expect(boilWater(w)).toBe(false); // no fire
    w.fires.push({ id: 1, x: w.player.x, z: w.player.z, fuel: 50, lit: true });
    expect(boilWater(w)).toBe(true);
    expect(w.inventory.waterClean).toBe(1);
    expect(w.inventory.snow).toBeUndefined();
  });

  it('drinking snow gives little water and costs core temp (the real mistake)', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'snow', 1);
    const t0 = w.needs.coreTemp;
    const h0 = w.needs.hydration;
    expect(drink(w)).toBe(true);
    expect(w.needs.hydration).toBeGreaterThan(h0);
    expect(w.needs.coreTemp).toBeLessThan(t0);
  });

  it('fire warmth keeps a stationary player alive through the night', () => {
    const w = createWorld(1);
    w.player.x = 0;
    w.player.z = -140; // lake: exposed, cold, windy
    w.fires.push({ id: 1, x: 0, z: -140, fuel: 100, lit: true });
    // simulate 8 game hours; feed the fire every in-game hour like a player would
    const ticksPerHour = H / CONFIG.SIM_DT;
    for (let hour = 0; hour < 8; hour++) {
      invAdd(w.inventory, 'deadfall', 6);
      feedFire(w);
      for (let i = 0; i < ticksPerHour; i++) step(w, CONFIG.SIM_DT);
    }
    expect(w.needs.coreTemp).toBeGreaterThan(36); // survived the night warm
    expect(w.dead).toBeUndefined();
  });

  it('without the fire the same night is dangerous', () => {
    const w = createWorld(1);
    w.player.x = 0;
    w.player.z = -140;
    const ticksPerHour = H / CONFIG.SIM_DT;
    for (let hour = 0; hour < 8; hour++) for (let i = 0; i < ticksPerHour; i++) step(w, CONFIG.SIM_DT);
    expect(w.needs.coreTemp).toBeLessThan(35); // clearly colder than the fire case
  });
});
