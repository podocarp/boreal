import { describe, expect, it } from 'vitest';
import { heightAt, lakeT, speedMulAt, streamX, zoneAt } from '../../src/sim/terrain';
import { collidersFrom, scatter } from '../../src/sim/scatter';
import { createWorld } from '../../src/sim/world';

describe('terrain', () => {
  it('is deterministic and finite everywhere sampled', () => {
    for (let i = 0; i < 200; i++) {
      const x = (i * 37.13) % 760 - 380;
      const z = (i * 53.7) % 760 - 380;
      expect(Number.isFinite(heightAt(x, z))).toBe(true);
    }
  });

  it('lake is flat at ice level in its center', () => {
    expect(lakeT(0, -150)).toBeLessThan(1);
    expect(Math.abs(heightAt(0, -150))).toBeLessThan(0.5);
  });

  it('stream carves down toward the lake', () => {
    const mid = heightAt(streamX(0), 0);
    expect(mid).toBeLessThan(heightAt(streamX(0) + 40, 0)); // channel below surroundings
  });

  it('zones classify sensibly', () => {
    expect(zoneAt(0, -150)).toBe('lake');
    expect(zoneAt(-260, 0)).toBe('ridge');
    expect(zoneAt(0, 200)).not.toBe('lake');
    expect(speedMulAt('bog')).toBeLessThan(1);
  });
});

describe('scatter', () => {
  it('is deterministic and keeps props off the lake/stream', () => {
    const a = scatter(3);
    const b = scatter(3);
    expect(a.length).toBe(b.length);
    expect(a.length).toBeGreaterThan(100);
    for (const p of a) {
      expect(lakeT(p.x, p.z)).toBeGreaterThanOrEqual(1.1);
      if (p.z > -160) expect(Math.abs(p.x - streamX(p.z))).toBeGreaterThanOrEqual(8);
    }
  });

  it('colliders never spawn on the player start', () => {
    const w = createWorld(1);
    expect(collidersFrom(scatter(1)).length).toBeGreaterThan(0);
    for (const c of w.colliders) {
      const d = Math.hypot(c.x - w.player.x, c.z - w.player.z);
      expect(d).toBeGreaterThan(c.r + 0.35);
    }
  });
});
