import { describe, expect, it } from 'vitest';
import { createWorld, makeRng, step } from '../../src/sim/world';
import { CONFIG } from '../../src/sim/config';

describe('sim clock', () => {
  it('advances time and rolls the day over', () => {
    const w = createWorld(1);
    const startHour = w.hourOfDay;
    // 24 in-game hours worth of ticks
    const ticks = Math.ceil(24 * CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR / CONFIG.SIM_DT);
    for (let i = 0; i < ticks; i++) step(w);
    expect(w.day).toBe(2);
    expect(w.hourOfDay).toBeCloseTo(startHour, 0);
  });

  it('is deterministic for a given seed', () => {
    const a = makeRng(42);
    const b = makeRng(42);
    for (let i = 0; i < 100; i++) expect(a()).toBe(b());
  });
});
