import { describe, expect, it } from 'vitest';
import { createWorld, nearestFire } from '../../src/sim/world';
import { contextActions, primaryAction } from '../../src/sim/actions';
import { invAdd } from '../../src/sim/items';
import { CRASH } from '../../src/sim/terrain';

const ctx = { dexterity: 0.7 };
const ids = (w: ReturnType<typeof createWorld>) => contextActions(w, ctx).map((a) => a.id);

describe('contextual actions', () => {
  it('at the wreck the primary verb is scavenging', () => {
    const w = createWorld(1);
    w.player.x = CRASH.x;
    w.player.z = CRASH.z;
    expect(primaryAction(w, ctx)?.id).toBe('work');
  });

  it('fire verbs appear only near a fire', () => {
    const w = createWorld(1);
    w.player.x = 100;
    w.player.z = 100; // forest, away from everything
    invAdd(w.inventory, 'deadfall', 3);
    expect(ids(w)).not.toContain('feed');
    w.fires.push({ id: 1, x: w.player.x, z: w.player.z, fuel: 80, lit: true });
    const withFire = ids(w);
    expect(withFire).toContain('feed');
    expect(withFire).toContain('signal');
  });

  it('disabled options carry a hint explaining why', () => {
    const w = createWorld(1);
    w.player.x = 100;
    w.player.z = 100;
    w.fires.push({ id: 1, x: w.player.x, z: w.player.z, fuel: 80, lit: true });
    const feed = contextActions(w, ctx).find((a) => a.id === 'feed')!;
    expect(feed.enabled).toBe(false); // no wood in pack
    expect(feed.hint).toMatch(/deadfall|kindling/);
  });

  it('eat/drink appear only with consumables; craft only when craftable', () => {
    const w = createWorld(1);
    w.player.x = 100;
    w.player.z = 100;
    let list = ids(w);
    expect(list).not.toContain('eat');
    expect(list).not.toContain('drink');
    invAdd(w.inventory, 'berries', 1);
    invAdd(w.inventory, 'waterClean', 1);
    invAdd(w.inventory, 'bark', 2);
    invAdd(w.inventory, 'knife', 1);
    invAdd(w.inventory, 'deadfall', 1);
    list = ids(w);
    expect(list).toContain('eat');
    expect(list).toContain('drink');
    expect(list.some((i) => i.startsWith('craft:'))).toBe(true);
  });

  it('sleeping collapses the menu to wake-only', () => {
    const w = createWorld(1);
    w.needs.sleeping = true;
    expect(ids(w)).toEqual(['wake']);
  });

  it('running an action mutates the world (feed burns wood)', () => {
    const w = createWorld(1);
    w.player.x = 100;
    w.player.z = 100;
    w.fires.push({ id: 1, x: w.player.x, z: w.player.z, fuel: 40, lit: true });
    invAdd(w.inventory, 'deadfall', 2);
    const feed = contextActions(w, ctx).find((a) => a.id === 'feed')!;
    feed.run(w);
    expect(nearestFire(w, 3)!.fuel).toBeGreaterThan(40);
  });

  it('sleep survives a crowded pack; menu never empty', () => {
    const w = createWorld(1);
    invAdd(w.inventory, 'bark', 2);
    invAdd(w.inventory, 'knife', 1);
    invAdd(w.inventory, 'deadfall', 1);
    invAdd(w.inventory, 'berries', 1);
    invAdd(w.inventory, 'cordage', 1);
    invAdd(w.inventory, 'waterClean', 1);
    const list = contextActions(w, ctx);
    expect(list.length).toBeGreaterThan(0);
    expect(list.map((a) => a.id)).toContain('sleep');
  });
});
