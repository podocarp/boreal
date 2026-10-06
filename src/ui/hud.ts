/** HUD (DOM overlay): clock, zone, temp, needs bars, debuff warnings, prompt, inventory. */
import type { WorldState } from '../sim/world';
import type { Debuffs } from '../sim/needs';
import { ITEMS, invWeight, type ItemId } from '../sim/items';

const el = document.getElementById('hud')!;
let acc = 0;
let lastText = '';

function bar(v: number, label: string): string {
  const n = Math.round(v / 10);
  return `${label} ${'█'.repeat(n)}${'░'.repeat(10 - n)}`;
}

function invLine(w: WorldState): string {
  const parts = Object.entries(w.inventory).map(
    ([id, n]) => `${ITEMS[id as ItemId].label}×${n}`,
  );
  const kg = invWeight(w.inventory).toFixed(1);
  return parts.length ? `🎒 ${parts.join(' · ')} (${kg}kg)` : '';
}

export function updateHud(
  w: WorldState,
  locked: boolean,
  feelsLikeC: number,
  d: Debuffs,
  prompt = '',
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
      ? 'WASD · Shift sprint · E work · Tab craft · F fire · R feed · Q boil · 1 drink · 2 eat'
      : 'BOREAL — click to take control',
  ];
  if (prompt) lines.push(prompt);
  const inv = invLine(w);
  if (inv) lines.push(inv);
  const logTail = w.log.slice(-1)[0];
  if (logTail) lines.push(`“${logTail.msg}”`);
  if (w.dead) lines.push(`YOU DIED — ${w.dead.cause.toUpperCase()} (${w.dead.detail})`);
  const text = lines.join('\n');
  if (text !== lastText) {
    el.textContent = text;
    lastText = text;
  }
}
