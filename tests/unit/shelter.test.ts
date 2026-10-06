import { describe, expect, it } from 'vitest';
import { createWorld, buildShelter, toggleSleep, step, tickWork } from '../../src/sim/world';
import { computeDebuffs } from '../../src/sim/needs';
import { scoreSite, shelterInsul, activeStorm, stormSchedule, SHELTER_STEPS } from '../../src/sim/shelter';
import { invAdd } from '../../src/sim/items';
import { CONFIG } from '../../src/sim/config';

const H = CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;
const run = (w: ReturnType<typeof createWorld>, gameHours: number) => {
  const ticks = (gameHours * H) / CONFIG.SIM_DT;
  for (let i = 0; i < ticks; i++) {
    step(w, CONFIG.SIM_DT);
    tickWork(w, CONFIG.SIM_DT, computeDebuffs(w.needs).dexterity);
  }
};

describe('site scoring', () => {
  it('forest near lake beats ridge/bog sites', () => {
    const good = scoreSite(-40, -60, 1); // forest just off the lake shore
    const bad = scoreSite(-260, 0, 1); // ridge: wind + scarce fuel
    expect(good.total).toBeGreaterThan(bad.total);
  });
  it('warns about widowmakers where flagged', () => {
    // find a widowmaker spot deterministically
    let found = false;
    for (let i = 0; i < 500 && !found; i++) {
      const s = scoreSite((i * 13.7) % 300 - 150, (i * 29.3) % 300 - 150, 1);
      if (s.warnings.some((x) => x.includes('widowmaker'))) found = true;
    }
    expect(found).toBe(true);
  });
});

describe('shelter build loop', () => {
  it('builds step by step, consuming materials, ending complete', () => {
    const w = createWorld(1);
    w.player.x = -40;
    w.player.z = -80;
    invAdd(w.inventory, 'boughs', 12);
    invAdd(w.inventory, 'deadfall', 4);
    for (let stepIdx = 0; stepIdx < SHELTER_STEPS.length; stepIdx++) {
      expect(buildShelter(w)).toBe('started');
      run(w, 0.5); // finish the 0.4h task
      expect(w.task).toBeNull();
    }
    const s = w.shelters[0];
    expect(s.complete).toBe(true);
    expect(shelterInsul(s)).toBeGreaterThan(0.5);
    expect(buildShelter(w)).toBe('complete');
  });

  it('blocks on missing materials', () => {
    const w = createWorld(1);
    w.player.x = -40;
    w.player.z = -80;
    expect(buildShelter(w)).toBe('started'); // site step is free
    run(w, 0.5);
    expect(buildShelter(w)).toBe('materials'); // frame needs deadfall
  });

  it('a complete shelter materially improves the night vs exposed', () => {
    const mk = () => {
      const w = createWorld(1);
      w.player.x = -40;
      w.player.z = -80;
      w.needs.energy = 100;
      return w;
    };
    const exposed = mk();
    const sheltered = mk();
    // build shelter on sheltered
    invAdd(sheltered.inventory, 'boughs', 12);
    invAdd(sheltered.inventory, 'deadfall', 4);
    for (let i = 0; i < SHELTER_STEPS.length; i++) {
      buildShelter(sheltered);
      run(sheltered, 0.5);
    }
    // both sleep 6h at night (sheltered inside, exposed outside);
    // equalize state AFTER the build work so we compare sleep quality only
    for (const w of [sheltered, exposed]) {
      w.needs.energy = 30;
      w.needs.coreTemp = 37;
      w.needs.hunger = 80;
      w.hourOfDay = 22;
      w.needs.sleeping = true;
      w.sleep.hours = 0;
    }
    // Compare after 3 h — before either wakes — so we measure restore RATE
    // and heat retention, not wake-up timing.
    run(sheltered, 3);
    run(exposed, 3);
    expect(sheltered.needs.sleeping).toBe(true); // still asleep at 3 h
    // sheltered: stays warm → full restore rate; exposed: chills → 35% rate
    expect(sheltered.needs.coreTemp).toBeGreaterThan(exposed.needs.coreTemp);
    expect(sheltered.needs.energy).toBeGreaterThan(exposed.needs.energy + 10);
  });
});

describe('sleep', () => {
  it('sleep restores energy and wakes rested at full', () => {
    const w = createWorld(1);
    w.player.x = -40;
    w.player.z = -60; // forest
    w.needs.energy = 30;
    w.needs.hunger = 80;
    w.hourOfDay = 22; // night, away from the dawn-wake window
    // a fire keeps the sleeper warm → full restore rate
    w.fires.push({ id: 1, x: w.player.x, z: w.player.z, fuel: 100, lit: true });
    expect(toggleSleep(w)).toBe(true);
    run(w, 6);
    expect(w.needs.sleeping).toBe(false); // woke rested
    expect(w.needs.energy).toBeGreaterThan(90);
  });

  it('sleeping in the open through the storm night is the death gamble', () => {
    const w = createWorld(1);
    w.player.x = 0;
    w.player.z = -140; // lake: exposed
    w.needs.energy = 30;
    w.hourOfDay = 20;
    toggleSleep(w);
    // stay asleep (the gamble is committing to the night): 14 h through the
    // day-2 storm night
    const ticks = (14 * H) / CONFIG.SIM_DT;
    for (let i = 0; i < ticks && !w.dead; i++) {
      w.needs.sleeping = true;
      step(w, CONFIG.SIM_DT);
    }
    expect(w.dead?.cause).toBe('hypothermia');
  });
});

describe('storms', () => {
  it('scheduled storms hit days 2 and 4 evenings', () => {
    expect(stormSchedule().length).toBe(2);
    expect(activeStorm(2, 22)).not.toBeNull();
    expect(activeStorm(2, 10)).toBeNull();
    expect(activeStorm(4, 20)?.severity).toBeGreaterThan(0.7);
  });

  it('storm soaks an exposed player and wets a sheltered one less', () => {
    const exposed = createWorld(1);
    exposed.player.x = 0;
    exposed.player.z = -140;
    exposed.day = 4;
    exposed.hourOfDay = 19;
    const sheltered = createWorld(1);
    sheltered.player.x = 0;
    sheltered.player.z = -140;
    sheltered.day = 4;
    sheltered.hourOfDay = 19;
    sheltered.shelters.push({ id: 1, x: 0, z: -140, step: 6, siteQuality: 0.9, complete: true });
    run(exposed, 3);
    run(sheltered, 3);
    expect(exposed.needs.wetness).toBeGreaterThan(0.1);
    expect(sheltered.needs.wetness).toBeLessThan(exposed.needs.wetness);
  });
});
