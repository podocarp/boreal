/**
 * Player movement (pure sim). Camera-relative WASD; player FACES movement
 * direction (Skyrim-style), smoothed. Collides with prop circles + world edge.
 */
import { CONFIG } from './config';
import { heightAt, speedMulAt, zoneAt } from './terrain';
import type { WorldState } from './world';

export interface MoveIntent {
  /** -1..1 (W = +1) */
  fwd: number;
  /** -1..1 (D = +1) */
  strafe: number;
  run: boolean;
  /** camera yaw (radians) — movement basis comes from the camera, never hardcoded */
  camYaw: number;
}

export function zeroIntent(): MoveIntent {
  return { fwd: 0, strafe: 0, run: false, camYaw: 0 };
}

function angleLerp(a: number, b: number, t: number): number {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * t;
}

export function updatePlayer(w: WorldState, intent: MoveIntent, dt: number): void {
  const p = w.player;
  const cy = intent.camYaw;
  // camera basis: forward = (-sin yaw, -cos yaw); right = (cos yaw, -sin yaw)
  const fwdX = -Math.sin(cy);
  const fwdZ = -Math.cos(cy);
  const rightX = Math.cos(cy);
  const rightZ = -Math.sin(cy);

  let mx = fwdX * intent.fwd + rightX * intent.strafe;
  let mz = fwdZ * intent.fwd + rightZ * intent.strafe;
  const mlen = Math.hypot(mx, mz);
  if (mlen > 1) {
    mx /= mlen;
    mz /= mlen;
  }

  const zone = zoneAt(p.x, p.z);
  const base = intent.run ? CONFIG.PLAYER.RUN_SPEED_MPS : CONFIG.PLAYER.WALK_SPEED_MPS;
  const speed = base * speedMulAt(zone);
  p.speed = Math.hypot(mx, mz) * speed;
  p.moving = p.speed > 0.05;

  let nx = p.x + mx * speed * dt;
  let nz = p.z + mz * speed * dt;

  // prop collision: slide (push out of circle)
  for (const c of w.colliders) {
    const dx = nx - c.x;
    const dz = nz - c.z;
    const d2 = dx * dx + dz * dz;
    const rr = c.r + CONFIG.PLAYER.RADIUS_M;
    if (d2 < rr * rr && d2 > 1e-9) {
      const d = Math.sqrt(d2);
      nx = c.x + (dx / d) * rr;
      nz = c.z + (dz / d) * rr;
    }
  }

  // world edge
  const R = CONFIG.WORLD.SIZE_M;
  const dist = Math.hypot(nx, nz);
  if (dist > R) {
    nx = (nx / dist) * R;
    nz = (nz / dist) * R;
  }

  p.x = nx;
  p.z = nz;
  p.y = heightAt(nx, nz);
  p.zone = zone;

  // face movement direction, smoothed
  if (p.moving) {
    const target = Math.atan2(mx, mz);
    p.yaw = angleLerp(p.yaw, target, Math.min(1, CONFIG.PLAYER.TURN_RATE_RADPS * dt));
  }
}
