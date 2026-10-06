import { describe, expect, it } from 'vitest';
import { createWorld } from '../../src/sim/world';
import { updatePlayer, zeroIntent } from '../../src/sim/player';
import { heightAt } from '../../src/sim/terrain';
import { CONFIG } from '../../src/sim/config';

describe('player movement', () => {
  it('moves camera-relative, not world-locked', () => {
    const w = createWorld(1);
    const start = { x: w.player.x, z: w.player.z };
    // camera yaw 0 → forward is -z
    updatePlayer(w, { ...zeroIntent(), fwd: 1, camYaw: 0 }, 1);
    expect(w.player.z).toBeLessThan(start.z);
    expect(w.player.x).toBeCloseTo(start.x, 5);
  });

  it('yaw 90° rotates the basis correctly (W → -x)', () => {
    const w = createWorld(1);
    const start = { x: w.player.x, z: w.player.z };
    updatePlayer(w, { ...zeroIntent(), fwd: 1, camYaw: Math.PI / 2 }, 1);
    expect(w.player.x).toBeLessThan(start.x);
    expect(w.player.z).toBeCloseTo(start.z, 5);
  });

  it('faces the movement direction when walking', () => {
    const w = createWorld(1);
    for (let i = 0; i < 8; i++) updatePlayer(w, { ...zeroIntent(), fwd: 1, camYaw: 0 }, 0.25);
    // moving toward -z → facing yaw ≈ π
    let dy = w.player.yaw - Math.PI;
    while (dy > Math.PI) dy -= Math.PI * 2;
    while (dy < -Math.PI) dy += Math.PI * 2;
    expect(Math.abs(dy)).toBeLessThan(0.2);
  });

  it('slides along prop colliders instead of passing through', () => {
    const w = createWorld(1);
    w.colliders = [{ x: 0, z: -145, r: 2 }]; // wall directly north of start
    for (let i = 0; i < 40; i++) updatePlayer(w, { ...zeroIntent(), fwd: 1, camYaw: 0 }, 0.25);
    const d = Math.hypot(w.player.x - 0, w.player.z - -145);
    expect(d).toBeGreaterThanOrEqual(2 + CONFIG.PLAYER.RADIUS_M - 0.01);
  });

  it('stays inside the world edge', () => {
    const w = createWorld(1);
    for (let i = 0; i < 4000; i++)
      updatePlayer(w, { ...zeroIntent(), fwd: 1, run: true, camYaw: 0.3 }, 0.25);
    expect(Math.hypot(w.player.x, w.player.z)).toBeLessThanOrEqual(CONFIG.WORLD.SIZE_M + 0.01);
  });

  it('player y tracks terrain height', () => {
    const w = createWorld(1);
    for (let i = 0; i < 200; i++) updatePlayer(w, { ...zeroIntent(), fwd: 1, camYaw: 0 }, 0.25);
    expect(w.player.y).toBeCloseTo(heightAt(w.player.x, w.player.z), 3);
  });
});
