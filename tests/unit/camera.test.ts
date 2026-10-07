import { describe, expect, it } from 'vitest';
import { CAM, createCamState, orbit, updateCam } from '../../src/render/camera';

const clear = () => Infinity;

describe('third-person camera', () => {
  it('is stationary: yaw never drifts without mouse input (no auto-swing)', () => {
    const c = createCamState();
    const yaw0 = c.yaw;
    // walk, sprint, idle — none of these may rotate the camera (user-reported
    // "keeps rotating about" bug; standard third-person = mouse-only orbit)
    const inp = { px: 0, py: 0, pz: 0, pyaw: 2.5, moving: true, sprinting: true };
    for (let i = 0; i < 120; i++) updateCam(c, inp, 0.1, clear);
    inp.moving = false;
    inp.sprinting = false;
    for (let i = 0; i < 120; i++) updateCam(c, inp, 0.1, clear);
    expect(c.yaw).toBeCloseTo(yaw0, 6);
    // ...and mouse input still orbits
    orbit(c, 100, 0, 0.01);
    expect(c.yaw).not.toBeCloseTo(yaw0, 6);
  });

  it('pitch clamps within limits', () => {
    const c = createCamState();
    for (let i = 0; i < 100; i++) orbit(c, 0, 1000, 1);
    expect(c.pitch).toBeGreaterThanOrEqual(CAM.PITCH_MIN - 1e-9);
    for (let i = 0; i < 100; i++) orbit(c, 0, -1000, 1);
    expect(c.pitch).toBeLessThanOrEqual(CAM.PITCH_MAX + 1e-9);
  });

  it('pulls in when obstructed and eases back out', () => {
    const c = createCamState();
    const inp = { px: 0, py: 0, pz: 0, pyaw: 0, moving: false, sprinting: false };
    const blocked = () => 0.8; // wall 0.8 m from pivot
    for (let i = 0; i < 40; i++) updateCam(c, inp, 0.1, blocked);
    expect(c.dist).toBeCloseTo(CAM.DIST_MIN, 1); // clamped at min distance
    const blockedDist = c.dist;
    for (let i = 0; i < 40; i++) updateCam(c, inp, 0.1, clear);
    expect(c.dist).toBeGreaterThan(blockedDist);
    expect(c.dist).toBeCloseTo(CAM.DIST_BASE, 1);
  });

  it('eye stays at pivot + dist along view dir', () => {
    const c = createCamState();
    const pose = updateCam(c, { px: 5, py: 2, pz: -7, pyaw: 1, moving: false, sprinting: false }, 0.1, clear);
    const d = Math.hypot(
      pose.eye[0] - pose.pivot[0],
      pose.eye[1] - pose.pivot[1],
      pose.eye[2] - pose.pivot[2],
    );
    expect(d).toBeCloseTo(c.dist, 2);
  });
});
