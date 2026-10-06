/** HUD (DOM overlay): clock, zone, temp, needs bars, debuff warnings, log tail. */
import type { WorldState } from '../sim/world';
import type { Debuffs } from '../sim/needs';

const el = document.getElementById('hud')!;
let acc = 0;
let lastText = '';

function bar(v: number, label: string): string {
  const n = Math.round(v / 10);
  return `${label} ${'█'.repeat(n)}${'░'.repeat(10 - n)}`;
}

export function updateHud(
  w: WorldState,
  locked: boolean,
  feelsLikeC: number,
  d: Debuffs,
): void {
  acc += 1;
  if (acc % 15 !== 1) return; // ~4 Hz refresh
  const hh = Math.floor(w.hourOfDay).toString().padStart(2, '0');
  const mm = Math.floor((w.hourOfDay % 1) * 60).toString().padStart(2, '0');
  const warn: string[] = [];
  if (d.shivering) warn.push('SHIVERING');
  if (w.needs.coreTemp < 34.5) warn.push('HYPOTHERMIA');
  if (d.drowsiness > 0.6) warn.push('DROWSY');
  if (w.needs.hunger < 25) warn.push('HUNGRY');
  if (w.needs.hydration < 25) warn.push('THIRSTY');
  if (w.needs.wetness > 0.5) warn.push('WET');
  const lines = [
    `DAY ${w.day}  ${hh}:${mm}  ${w.env.airTempC.toFixed(0)}°C (feels ${feelsLikeC.toFixed(0)}°C)  ${w.player.zone}`,
    `HP ${bar(w.needs.health, '♥')}  ${bar(w.needs.hydration, '~')}  ${bar(w.needs.hunger, '✚')}  ${bar(w.needs.energy, '☾')}`,
    warn.length ? `⚠ ${warn.join(' · ')}` : locked
      ? 'WASD move · Shift sprint · mouse look · Esc release'
      : 'BOREAL — click to take control',
  ];
  if (w.dead) lines.push(`YOU DIED — ${w.dead.cause.toUpperCase()} (${w.dead.detail})`);
  const text = lines.join('\n');
  if (text !== lastText) {
    el.textContent = text;
    lastText = text;
  }
}
