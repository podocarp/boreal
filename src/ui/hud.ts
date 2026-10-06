/** HUD (DOM overlay): clock, zone, temp, needs bars, debuff warnings, prompt, inventory. */
import type { WorldState } from '../sim/world';
import type { Debuffs } from '../sim/needs';
import { ITEMS, invWeight, type ItemId } from '../sim/items';

const el = document.getElementById('hud')!;
let acc = 0;
let lastText = '';

// --- end screen (death / rescue summary) ---
const endEl = document.createElement('div');
endEl.style.cssText =
  'position:absolute;inset:0;display:none;align-items:center;justify-content:center;' +
  'background:rgba(6,10,16,0.82);color:#e8eef4;font:16px/1.6 monospace;white-space:pre-wrap;';
el.parentElement?.appendChild(endEl);
let endShown = false;

export function showEndScreen(w: WorldState): void {
  if (endShown) return;
  endShown = true;
  const rescued = w.rescued;
  const title = rescued
    ? `RESCUED — DAY ${rescued.day} (${rescued.kind})`
    : `YOU DIED — ${w.dead?.cause.toUpperCase() ?? 'EXPOSURE'}`;
  const sub = rescued ? rescued.detail : (w.dead?.detail ?? '');
  const highlights = w.log
    .filter((e) => /fire|shelter|wolf|snare|fish|rescu|storm|flare|smoke|died|RESCUED/i.test(e.msg))
    .slice(-10)
    .map((e) => `Day ${e.day}: ${e.msg}`);
  endEl.textContent = [
    title,
    sub,
    '',
    `Survived ${w.day - 1} full days, ${Math.floor(w.hourOfDay)} h into day ${w.day}.`,
    ...highlights,
    '',
    'Press Enter to try again.',
  ].join('\n');
  endEl.style.display = 'flex';
}

export function hideEndScreen(): void {
  endShown = false;
  endEl.style.display = 'none';
}

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
    w.needs.sleeping
      ? `💤 SLEEPING — DAY ${w.day} ${hh}:${mm}`
      : `DAY ${w.day}  ${hh}:${mm}  ${w.env.airTempC.toFixed(0)}°C (feels ${feelsLikeC.toFixed(0)}°C)  ${w.player.zone}`,
    `HP ${bar(w.needs.health, '♥')}  ${bar(w.needs.hydration, '~')}  ${bar(w.needs.hunger, '✚')}  ${bar(w.needs.energy, '☾')}`,
    warn.length ? `⚠ ${warn.join(' · ')}` : locked
      ? 'WASD · E work · Tab craft · F fire · R feed · Q boil · G shelter · Z sleep · C/X snare · V fish · B cook · T treat · Space shout'
      : 'BOREAL — click to take control',
  ];
  if (prompt) lines.push(prompt);
  const inv = invLine(w);
  if (inv) lines.push(inv);
  const logTail = w.log.slice(-1)[0];
  if (logTail) lines.push(`“${logTail.msg}”`);
  if (w.dead || w.rescued) showEndScreen(w);
  const text = lines.join('\n');
  if (text !== lastText) {
    el.textContent = text;
    lastText = text;
  }
}
