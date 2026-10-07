/**
 * Radial context menu — hold RMB, aim the mouse in a direction, release to do.
 * (Arma 3 action-wheel pattern; works under pointer lock because it steers by
 * accumulated mouse delta, not cursor position.)
 * While open: camera orbit and movement are suppressed by main.
 */
import type { ActionOption } from '../sim/actions';

const el = document.createElement('div');
el.style.cssText =
  'position:absolute;inset:0;display:none;pointer-events:none;' +
  'font:14px/1.3 monospace;color:#e8eef4;';
document.getElementById('hud')?.parentElement?.appendChild(el);

interface Slot {
  opt: ActionOption;
  angle: number; // radians, screen-space (0 = right, CW positive)
}

let slots: Slot[] = [];
let open = false;
let sel = -1;
let dx = 0;
let dy = 0;
const RADIUS = 130;

export function menuIsOpen(): boolean {
  return open;
}

/** Open the wheel with a fresh action list (called on RMB-down by main). */
export function openMenu(actions: ActionOption[]): void {
  const list = actions.slice(0, 10);
  if (!list.length) return;
  slots = list.map((opt, i) => ({
    opt,
    // start at top (-90°), clockwise
    angle: -Math.PI / 2 + (i * 2 * Math.PI) / list.length,
  }));
  open = true;
  sel = 0;
  dx = 0;
  dy = 0;
  render();
}

/** Feed accumulated mouse delta while held (called per frame). */
export function menuSteer(dmx: number, dmy: number): void {
  if (!open) return;
  dx += dmx;
  dy += dmy;
  const len = Math.hypot(dx, dy);
  if (len > 18) {
    const a = Math.atan2(dy, dx);
    let best = 0;
    let bd = Infinity;
    slots.forEach((s, i) => {
      let d = Math.abs(a - s.angle);
      if (d > Math.PI) d = 2 * Math.PI - d;
      if (d < bd) {
        bd = d;
        best = i;
      }
    });
    sel = best;
  } else {
    sel = -1;
  }
  render();
}

/** Close and return the chosen action (null if none / cancelled). */
export function closeMenu(): ActionOption | null {
  if (!open) return null;
  open = false;
  el.style.display = 'none';
  const s = sel >= 0 ? slots[sel] : undefined;
  slots = [];
  return s && s.opt.enabled ? s.opt : null;
}

function render(): void {
  const cx = window.innerWidth / 2;
  const cy = window.innerHeight / 2;
  const parts: string[] = [];
  slots.forEach((s, i) => {
    const x = cx + Math.cos(s.angle) * RADIUS;
    const y = cy + Math.sin(s.angle) * RADIUS;
    const on = i === sel;
    const col = !s.opt.enabled ? '#5a646e' : on ? '#ffd166' : '#cfd8e0';
    const weight = on ? 'bold ' : '';
    parts.push(
      `<div style="position:absolute;left:${x}px;top:${y}px;transform:translate(-50%,-50%);` +
        `text-align:center;color:${col};font-weight:${weight ? 'bold' : 'normal'};` +
        `text-shadow:0 1px 3px #000;max-width:180px">` +
        `${on ? '▶ ' : ''}${s.opt.label}` +
        (s.opt.hint ? `<div style="font-size:11px;color:#8a94a0">${s.opt.hint}</div>` : '') +
        `</div>`,
    );
  });
  parts.push(
    `<div style="position:absolute;left:${cx}px;top:${cy}px;transform:translate(-50%,-50%);` +
      `color:#8a94a0;font-size:12px;text-shadow:0 1px 3px #000">release: do · esc: cancel</div>`,
  );
  el.innerHTML = parts.join('');
  el.style.display = 'block';
}
