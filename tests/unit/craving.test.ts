import { describe, expect, it } from 'vitest';
import { cravingMul, createWorld, eat } from '../../src/sim/world';
import { invAdd } from '../../src/sim/items';
import { CONFIG } from '../../src/sim/config';

describe('craving curve', () => {
  it('multiplier: 1.0 at full, 1+K at empty, monotonic', () => {
    const K = CONFIG.NEEDS.CRAVING_K;
    expect(cravingMul(100)).toBeCloseTo(1, 5);
    expect(cravingMul(0)).toBeCloseTo(1 + K, 5);
    expect(cravingMul(20)).toBeGreaterThan(cravingMul(60));
  });

  it('same cooked meat restores far more when starving than when nearly full', () => {
    const full = createWorld(1);
    invAdd(full.inventory, 'meatCooked', 1);
    full.needs.hunger = 80;
    eat(full);
    const gainFull = full.needs.hunger - 80;

    const starving = createWorld(1);
    invAdd(starving.inventory, 'meatCooked', 1);
    starving.needs.hunger = 10;
    eat(starving);
    const gainStarving = starving.needs.hunger - 10;

    expect(gainStarving).toBeGreaterThan(gainFull * 1.5);
  });

  it('grazing at high hunger is inefficient vs waiting (design intent)', () => {
    // two identical meals at hunger 70 restore less combined than one at 70
    // then one at ~35 (after decay) — the curve punishes snacking.
    const a = createWorld(1);
    invAdd(a.inventory, 'meatCooked', 2);
    a.needs.hunger = 70;
    eat(a);
    const first = a.needs.hunger;
    eat(a); // second meal right away: mostly wasted at high hunger
    const grazeTotal = a.needs.hunger - 70;

    const b = createWorld(1);
    invAdd(b.inventory, 'meatCooked', 2);
    b.needs.hunger = 35;
    eat(b);
    const waitTotal = b.needs.hunger - 35;

    expect(waitTotal).toBeGreaterThan(grazeTotal);
    expect(first).toBeLessThanOrEqual(100);
  });
});
