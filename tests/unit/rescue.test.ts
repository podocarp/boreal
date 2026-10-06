import { describe, expect, it } from 'vitest';
import {
  createWorld, detectionInput, fireFlare, signalSmoke, step,
} from '../../src/sim/world';
import { checkPass, createRescue, detectionChance, searchSchedule } from '../../src/sim/rescue';
import { invAdd } from '../../src/sim/items';
import { CONFIG } from '../../src/sim/config';

const H = CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;

describe('search schedule', () => {
  it('days 7-10, dawn + dusk passes', () => {
    const s = searchSchedule();
    expect(s.length).toBe(8);
    expect(s[0]).toEqual({ day: 7, hour: 9, kind: 'dawn' });
    expect(s[1].kind).toBe('dusk');
  });

  it('detection: signal smoke on open ground dominates hiding', () => {
    const base = {
      signalSmoke: false, anyFire: false, flareUsedRecently: false,
      openGround: true, onRidge: false, shelterVisible: false, movedRecently: false,
    };
    const smoke = detectionChance({ ...base, signalSmoke: true, anyFire: true });
    const hidden = detectionChance({ ...base, openGround: false });
    const flare = detectionChance({ ...base, flareUsedRecently: true });
    expect(smoke).toBeGreaterThan(0.7);
    expect(hidden).toBeLessThan(0.15);
    expect(flare).toBeGreaterThan(0.9);
    expect(smoke).toBeLessThan(flare);
  });

  it('storm scrubs the pass', () => {
    const r = createRescue();
    const res = checkPass(r, 7, 9.5, 0.85, () => detectionInput(createWorld(1)), () => 0);
    expect(res.fired).toBe(true);
    expect(res.scrubbed).toBe(true);
  });
});

describe('rescue loop', () => {
  it('day 7 dawn pass with signal smoke on the lake → rescued', () => {
    const w = createWorld(1);
    w.player.x = 0;
    w.player.z = -140; // lake shore, open
    invAdd(w.inventory, 'boughs', 4);
    w.fires.push({ id: 1, x: 0, z: -140, fuel: 100, lit: true });
    signalSmoke(w);
    expect(w.signalFireId).toBe(1);
    // jump to just before the day-7 dawn pass
    w.day = 7;
    w.hourOfDay = 8.9;
    // keep the player alive & still until the pass
    const ticks = (0.3 * H) / CONFIG.SIM_DT;
    for (let i = 0; i < ticks && !w.rescued; i++) {
      w.player.x = 0; w.player.z = -140;
      w.needs.hydration = 100; w.needs.hunger = 100; w.needs.energy = 100;
      w.needs.coreTemp = 37; w.needs.wetness = 0; w.needs.health = 100;
      w.wolves = [];
      step(w, CONFIG.SIM_DT);
    }
    expect(w.rescued).toBeTruthy();
    expect(w.rescued?.day).toBe(7);
  });

  it('flare guarantees detection at the next pass', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'flare', 1);
    invAdd(w.inventory, 'flareGun', 1);
    expect(fireFlare(w)).toBe(true);
    expect(w.inventory.flare).toBeUndefined();
    w.day = 7;
    w.hourOfDay = 8.9;
    const ticks = (0.3 * H) / CONFIG.SIM_DT;
    for (let i = 0; i < ticks && !w.rescued; i++) {
      w.needs.hydration = 100; w.needs.hunger = 100; w.needs.energy = 100;
      w.needs.coreTemp = 37; w.needs.wetness = 0; w.needs.health = 100;
      w.wolves = [];
      step(w, CONFIG.SIM_DT);
    }
    expect(w.rescued).toBeTruthy();
  });

  it('hiding in the forest with no fire → passes miss; day 10 collapse', () => {
    const w = createWorld(1);
    w.player.x = -150;
    w.player.z = 100; // deep forest
    let missed = 0;
    const ticks = (11 * 24 * H) / CONFIG.SIM_DT; // run past day 10
    for (let i = 0; i < ticks && !w.dead; i++) {
      w.player.x = -150; w.player.z = 100;
      w.needs.hydration = 100; w.needs.hunger = 100; w.needs.energy = 100;
      w.needs.coreTemp = 37; w.needs.wetness = 0; w.needs.health = 100;
      w.wolves = [];
      const before = w.rescue.resolved;
      step(w, CONFIG.SIM_DT);
      if (w.rescue.resolved > before && !w.rescue.lastPass?.spotted && !w.rescue.lastPass?.scrubbed) missed++;
    }
    expect(w.dead?.cause).toBe('exposure');
    expect(w.rescue.collapsed).toBe(true);
    expect(missed).toBeGreaterThan(0);
  });

  it('detectionInput reflects signal fire going out', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'boughs', 4);
    w.fires.push({ id: 1, x: w.player.x, z: w.player.z, fuel: 100, lit: true });
    signalSmoke(w);
    expect(detectionInput(w).signalSmoke).toBe(true);
    w.fires[0].lit = false;
    expect(detectionInput(w).signalSmoke).toBe(false);
  });
});
