/** HUD (DOM overlay). Sprint 1: clock, zone, controls hint. */
import type { WorldState } from '../sim/world';

const el = document.getElementById('hud')!;
let acc = 0;
let lastText = '';

export function updateHud(w: WorldState, locked: boolean): void {
  acc += 1;
  if (acc % 15 !== 1) return; // ~4 Hz refresh
  const hh = Math.floor(w.hourOfDay).toString().padStart(2, '0');
  const mm = Math.floor((w.hourOfDay % 1) * 60).toString().padStart(2, '0');
  const text = [
    `DAY ${w.day}  ${hh}:${mm}   zone: ${w.player.zone}`,
    locked
      ? 'WASD move · Shift sprint · mouse look · Esc release'
      : 'BOREAL — click to take control',
  ].join('\n');
  if (text !== lastText) {
    el.textContent = text;
    lastText = text;
  }
}
