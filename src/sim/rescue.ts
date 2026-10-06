/**
 * Rescue & win condition (docs/DESIGN-world.md "Rescue & win condition").
 * Search window opens day 7: two passes (dawn ~09:00, dusk ~16:30), weather
 * can scrub a pass. Detection at pass time = signal fire + smoke (green boughs),
 * flare (one shot), position (ridge/open = seen, forest = hidden), shelter
 * from altitude, recent movement. Day 10 without rescue → collapse end.
 */
import { CONFIG } from './config';

export interface SearchPass {
  day: number;
  hour: number;
  kind: 'dawn' | 'dusk';
}

/** Pass schedule for the whole run: days 7..10, dawn + dusk. */
export function searchSchedule(): SearchPass[] {
  const passes: SearchPass[] = [];
  for (let day = 7; day <= 10; day++) {
    passes.push({ day, hour: 9, kind: 'dawn' });
    passes.push({ day, hour: 16.5, kind: 'dusk' });
  }
  return passes;
}

/** Storm severity 0..1 at time (storms scrub passes). */
export function passScrubbed(day: number, hour: number, stormSeverity: number): boolean {
  void day; void hour;
  return stormSeverity > 0.5; // whiteout / heavy snow: no flight
}

export interface DetectionInput {
  /** signal fire burning with green-bough smoke column */
  signalSmoke: boolean;
  /** ordinary fire visible (embers at night, steam column by day) */
  anyFire: boolean;
  flareUsedRecently: boolean; // within the pass window
  /** player zone: ridge/open lake = visible; forest/bog = hidden */
  openGround: boolean;
  onRidge: boolean;
  shelterVisible: boolean; // completed shelter in the open
  movedRecently: boolean; // tracks in snow
}

/**
 * Detection probability 0..1 for a pass. Signal smoke is the big lever
 * (Les Stroud's actual play): 0.85 with smoke on open ground vs ~0.12 hiding.
 */
export function detectionChance(d: DetectionInput): number {
  let p = 0.02; // drifting luck
  if (d.signalSmoke) p += d.openGround ? 0.9 : 0.5; // smoke through canopy still reads
  else if (d.anyFire) p += d.openGround ? 0.3 : 0.1;
  if (d.flareUsedRecently) p = Math.max(p, 0.95); // one shot, near-certain
  if (d.onRidge) p += 0.1;
  if (d.shelterVisible) p += 0.08;
  if (d.movedRecently) p += 0.05;
  return Math.min(0.98, p);
}

export interface RescueState {
  /** passes already resolved (index into schedule) */
  resolved: number;
  flareUsedDay: number | null;
  /** set when rescued */
  rescued?: { day: number; kind: string; detail: string };
  /** set when the run ends without rescue (day 10 collapse) */
  collapsed?: boolean;
  /** last pass outcome for the HUD/log */
  lastPass?: { day: number; kind: string; spotted: boolean; scrubbed: boolean };
}

export function createRescue(): RescueState {
  return { resolved: 0, flareUsedDay: null };
}

export interface PassCheck {
  fired: boolean;
  spotted?: boolean;
  scrubbed?: boolean;
  kind?: 'dawn' | 'dusk';
}

/**
 * Called every tick by world.step: if a scheduled pass just crossed, resolve it.
 * Returns the pass result if one fired this tick.
 */
export function checkPass(
  r: RescueState,
  day: number,
  hour: number,
  stormSeverity: number,
  detect: () => DetectionInput,
  rng: () => number,
): PassCheck {
  const sched = searchSchedule();
  while (r.resolved < sched.length) {
    const pass = sched[r.resolved];
    // crossed this pass's hour?
    if (day > pass.day || (day === pass.day && hour >= pass.hour)) {
      r.resolved += 1;
      const scrubbed = passScrubbed(pass.day, pass.hour, stormSeverity);
      if (scrubbed) {
        r.lastPass = { day: pass.day, kind: pass.kind, spotted: false, scrubbed: true };
        return { fired: true, scrubbed: true, kind: pass.kind };
      }
      const p = detectionChance(detect());
      const spotted = rng() < p;
      r.lastPass = { day: pass.day, kind: pass.kind, spotted, scrubbed: false };
      return { fired: true, spotted, kind: pass.kind };
    }
    break;
  }
  return { fired: false };
}

/** Day 10 dawn, not rescued → exposure collapse (run over). */
export function checkCollapse(r: RescueState, day: number): boolean {
  if (!r.rescued && day > CONFIG.RESCUE.COLLAPSE_DAY) {
    r.collapsed = true;
    return true;
  }
  return false;
}
