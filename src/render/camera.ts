/**
 * Third-person over-shoulder camera (Skyrim/Dinkum style) — spec in docs/TECH.md.
 * Pure math (no three.js) so it's unit-testable: compute() returns eye+pivot.
 */
import { clamp } from '../sim/noise';

export interface CamState {
  yaw: number;
  pitch: number;
  /** current collision-eased distance */
  dist: number;
}

export interface CamInput {
  px: number; py: number; pz: number; // player pos
  pyaw: number; // player facing
  moving: boolean;
  sprinting: boolean;
}

export const CAM = {
  SHOULDER_OFFSET_M: 0.35,
  PIVOT_HEIGHT_M: 1.5,
  DIST_MIN: 1.2,
  DIST_BASE: 2.1,
  DIST_SPRINT_BONUS: 0.35,
  PITCH_MIN: -1.22, // look up ~70°
  PITCH_MAX: 1.05, // look down ~60°
  COLLIDE_EASE_IN: 14, // fast pull-in on obstruction
  COLLIDE_EASE_OUT: 3, // slow ease back out (anti-strobe)
};

export function createCamState(): CamState {
  return { yaw: Math.PI, pitch: 0.15, dist: CAM.DIST_BASE };
}

/** Apply mouse delta; returns new yaw/pitch clamped. Convention: pitch>0 looks
 * DOWN (eye above pivot), pitch<0 looks up. Mouse up (dPitch<0) → look up. */
export function orbit(c: CamState, dYaw: number, dPitch: number, sens: number): void {
  c.yaw -= dYaw * sens;
  c.pitch = clamp(c.pitch + dPitch * sens, CAM.PITCH_MIN, CAM.PITCH_MAX);
}

export interface CamPose {
  eye: [number, number, number];
  pivot: [number, number, number];
}

/**
 * Compute camera pose. `rayDist(from,to)` returns free distance along the
 * pivot→eye segment (Infinity if clear) — injected so this stays pure/testable.
 */
export function updateCam(
  c: CamState,
  inp: CamInput,
  dt: number,
  rayDist: (from: [number, number, number], to: [number, number, number]) => number,
): CamPose {
  // Standard third-person: yaw changes ONLY from mouse input (no auto-swing,
  // no idle recenter — users reported the drift as nauseating; orbit() above
  // is the sole yaw source). `inp.pyaw/moving/sprinting` stay in the API for
  // future modes but do not move the camera.

  // pivot→eye direction = -cameraForward (camera sits behind the pivot)
  const cp = Math.cos(c.pitch);
  const dirX = Math.sin(c.yaw) * cp;
  const dirY = Math.sin(c.pitch);
  const dirZ = Math.cos(c.yaw) * cp;

  // shoulder pivot (right-biased relative to camera yaw)
  const rightX = Math.cos(c.yaw);
  const rightZ = -Math.sin(c.yaw);
  const pivot: [number, number, number] = [
    inp.px + rightX * CAM.SHOULDER_OFFSET_M,
    inp.py + CAM.PIVOT_HEIGHT_M,
    inp.pz + rightZ * CAM.SHOULDER_OFFSET_M,
  ];

  const want =
    CAM.DIST_BASE + (inp.sprinting ? CAM.DIST_SPRINT_BONUS : 0);
  const eye: [number, number, number] = [
    pivot[0] + dirX * want,
    pivot[1] + dirY * want,
    pivot[2] + dirZ * want,
  ];

  const free = rayDist(pivot, eye);
  const target = clamp(free - 0.25, CAM.DIST_MIN, want);
  const rate = target < c.dist ? CAM.COLLIDE_EASE_IN : CAM.COLLIDE_EASE_OUT;
  c.dist += (target - c.dist) * Math.min(1, rate * dt);

  return {
    pivot,
    eye: [
      pivot[0] + dirX * c.dist,
      pivot[1] + dirY * c.dist,
      pivot[2] + dirZ * c.dist,
    ],
  };
}

