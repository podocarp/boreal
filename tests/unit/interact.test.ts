import { describe, expect, it } from 'vitest';
import { createWorld, beginWork, tickWork, currentTarget } from '../../src/sim/world';
import { scatter } from '../../src/sim/scatter';
import { buildInteractables } from '../../src/sim/interact';
import { craft, canCraft, RECIPES } from '../../src/sim/craft';
import { invAdd, invWeight, CARRY_LIMIT_KG } from '../../src/sim/items';
import { CONFIG } from '../../src/sim/config';

const H = CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR;

describe('interactables', () => {
  it('are generated deterministically and include the wreck + water points', () => {
    const a = buildInteractables(1, scatter(1));
    const b = buildInteractables(1, scatter(1));
    expect(a.length).toBe(b.length);
    expect(a.some((i) => i.kind === 'wreck')).toBe(true);
    expect(a.filter((i) => i.kind === 'water').length).toBeGreaterThan(3);
  });

  it('scavenging the wreck yields the grab bag once', () => {
    const w = createWorld(1);
    w.player.x = 0;
    w.player.z = -140;
    w.player.moving = false;
    expect(currentTarget(w)?.kind).toBe('wreck');
    expect(beginWork(w)).toBe(true);
    const ticks2h = (2 * H) / CONFIG.SIM_DT;
    for (let i = 0; i < ticks2h; i++) tickWork(w, CONFIG.SIM_DT, 1);
    expect(w.inventory.knife).toBe(1);
    expect(w.inventory.flareGun).toBe(1);
    expect(w.inventory.tinCup).toBe(1);
    // wreck is spent — only the dynamic snow target remains
    expect(currentTarget(w)?.kind).not.toBe('wreck');
  });

  it('moving cancels an in-progress task', () => {
    const w = createWorld(1);
    w.player.x = 0;
    w.player.z = -140;
    beginWork(w);
    expect(w.task).not.toBeNull();
    w.player.moving = true;
    tickWork(w, CONFIG.SIM_DT, 1);
    expect(w.task).toBeNull();
  });

  it('low dexterity slows work', () => {
    const mk = () => {
      const w = createWorld(1);
      w.player.x = 0;
      w.player.z = -140;
      beginWork(w);
      return w;
    };
    const fast = mk();
    const slow = mk();
    const ticks1h = H / CONFIG.SIM_DT;
    for (let i = 0; i < ticks1h; i++) {
      tickWork(fast, CONFIG.SIM_DT, 1);
      tickWork(slow, CONFIG.SIM_DT, 0.3);
    }
    expect(fast.task).toBeNull(); // finished (0.5 h task in 1 h)
    expect(slow.task).not.toBeNull(); // still working
  });

  it('snow/water need a container', () => {
    const w = createWorld(1);
    w.player.x = 100;
    w.player.z = 100; // forest, no static interactable nearby → dynamic snow target
    expect(currentTarget(w)?.kind).toBe('snow');
    expect(beginWork(w)).toBe(false); // no container + hint logged
    expect(w.log.some((l) => l.msg.includes('container'))).toBe(true);
    invAdd(w.inventory, 'tinCup', 1);
    expect(beginWork(w)).toBe(true);
  });
});

describe('crafting', () => {
  it('kindling requires the knife and one deadfall', () => {
    const w = createWorld(1);
    const r = RECIPES.find((x) => x.id === 'kindling')!;
    invAdd(w.inventory, 'deadfall', 1);
    expect(canCraft(w.inventory, r)).toBe(false); // no knife
    invAdd(w.inventory, 'knife', 1);
    expect(canCraft(w.inventory, r)).toBe(true);
    expect(craft(w.inventory, r)).toBe(true);
    expect(w.inventory.kindling).toBe(3);
    expect(w.inventory.deadfall).toBeUndefined();
  });

  it('craft is atomic on failure', () => {
    const w = createWorld(1);
    const r = RECIPES.find((x) => x.id === 'tinderBundle')!;
    invAdd(w.inventory, 'bark', 1); // missing kindling
    const before = JSON.stringify(w.inventory);
    expect(craft(w.inventory, r)).toBe(false);
    expect(JSON.stringify(w.inventory)).toBe(before);
  });

  it('carry limit blocks overloading', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'rock', 3); // 7.5 kg
    expect(invWeight(w.inventory)).toBeCloseTo(7.5);
    // fill with deadfall until the limit
    let added = 0;
    for (let i = 0; i < 40; i++) added += invAdd(w.inventory, 'deadfall', 6);
    expect(invWeight(w.inventory)).toBeLessThanOrEqual(CARRY_LIMIT_KG);
    expect(added).toBeGreaterThan(0);
  });
});
