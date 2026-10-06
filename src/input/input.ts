/**
 * Input: keyboard → MoveIntent; mouse (pointer lock) → camera orbit deltas.
 * Keys tracked in a live Set; mouse deltas accumulate and are consumed
 * (zeroed) once per frame by main.
 */
import { zeroIntent, type MoveIntent } from '../sim/player';

export interface InputState {
  intent: MoveIntent;
  dYaw: number;
  dPitch: number;
  locked: boolean;
}

export function createInput(canvas: HTMLCanvasElement): InputState {
  const held = new Set<string>();
  const state: InputState = { intent: zeroIntent(), dYaw: 0, dPitch: 0, locked: false };

  window.addEventListener('keydown', (e) => {
    if (e.code === 'Tab') e.preventDefault();
    held.add(e.code);
  });
  window.addEventListener('keyup', (e) => held.delete(e.code));
  window.addEventListener('blur', () => held.clear());

  canvas.addEventListener('click', () => {
    if (!state.locked) canvas.requestPointerLock();
  });
  document.addEventListener('pointerlockchange', () => {
    state.locked = document.pointerLockElement === canvas;
  });
  document.addEventListener('mousemove', (e) => {
    if (!state.locked) return;
    state.dYaw += e.movementX;
    state.dPitch += e.movementY;
  });

  (state as unknown as { _held: Set<string> })._held = held;
  (state as unknown as { _pressed: Set<string> })._pressed = pressed;

  window.addEventListener('keydown', (e) => {
    if (!e.repeat) pressed.add(e.code);
  });
  return state;
}

const pressed = new Set<string>();

/** True while the key is physically held. */
export function isHeld(s: InputState, code: string): boolean {
  return (s as unknown as { _held: Set<string> })._held.has(code);
}

/** True once per physical key press (consumes the event). */
export function consumeKey(code: string): boolean {
  if (pressed.has(code)) {
    pressed.delete(code);
    return true;
  }
  return false;
}

/** Fill s.intent from held keys + current camera yaw (call once per frame). */
export function readIntent(s: InputState, camYaw: number): void {
  const held = (s as unknown as { _held: Set<string> })._held;
  const fwd = (held.has('KeyW') ? 1 : 0) - (held.has('KeyS') ? 1 : 0);
  const strafe = (held.has('KeyD') ? 1 : 0) - (held.has('KeyA') ? 1 : 0);
  s.intent = {
    fwd,
    strafe,
    run: held.has('ShiftLeft') || held.has('ShiftRight'),
    camYaw,
  };
}
