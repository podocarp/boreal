/**
 * Monte-Carlo balance harness (S8 tooling — no gameplay code).
 * Runs full headless games (pure sim) for scripted bot policies over many
 * seeds and reports outcome distributions, so config.ts tuning can target a
 * difficulty band instead of vibes.
 *
 * Usage:  npx vite-node tests/sim/balance.ts [seedsPerPolicy]
 * Output: per-policy rescue/death rates, death-cause + death-night histograms.
 */
import { CONFIG } from '../../src/sim/config';
import { CRASH, zoneAt } from '../../src/sim/terrain';
import {
  beginWork, boilWater, buildShelter, checkSnares, cook, createWorld, drink,
  eat, feedFire, fireFlare, fish, lightFire, setSnareAction, signalSmoke,
  step, tickWork, toggleSleep, treatWound, type WorldState,
} from '../../src/sim/world';
import { updatePlayer } from '../../src/sim/player';
import { computeDebuffs } from '../../src/sim/needs';
import { canCraft, craft, RECIPES } from '../../src/sim/craft';
import { invCanAdd, invHas, invRemove } from '../../src/sim/items';
import { startTask, type Interactable, type InteractKind } from '../../src/sim/interact';

const DT = CONFIG.SIM_DT;

// minimal Node ambient (no @types/node in this project)
declare const process: { argv: string[] };

// ---------------------------------------------------------------------------
// bot helpers
// ---------------------------------------------------------------------------

function dist(x1: number, z1: number, x2: number, z2: number): number {
  return Math.hypot(x1 - x2, z1 - z2);
}

/**
 * Walk-toward helper with real stuck recovery: if the player stops
 * progressing (collider), commit to a perpendicular strafe for a fixed
 * number of ticks (sign chosen once — per-tick random flips just oscillate),
 * then resume. One instance per bot; state resets on arrival.
 */
class Mover {
  didMove = false;
  private bestD = Infinity;
  private tx = NaN;
  private tz = NaN;
  private stuck = 0;
  private sinceArrival = 0;
  private strafeTicks = 0;
  private strafeDir = 1;

  move(w: WorldState, x: number, z: number, rng: () => number): boolean {
    if (x !== this.tx || z !== this.tz) {
      this.tx = x;
      this.tz = z;
      this.bestD = Infinity; // new target → fresh progress baseline
    }
    const dx = x - w.player.x;
    const dz = z - w.player.z;
    const d = Math.hypot(dx, dz);
    if (d < 2.5) {
      // clear stale p.moving (only updatePlayer resets it; tickWork cancels
      // tasks and sleep refuses while moving=true, so arriving must zero it)
      updatePlayer(w, { fwd: 0, strafe: 0, run: false, camYaw: 0 }, DT);
      this.didMove = false;
      this.reset();
      return true;
    }
    // progress-based stuck detection: sliding along a collider counts as
    // stuck (we move but never close the distance)
    if (d < this.bestD - 0.15) {
      this.bestD = d;
      this.stuck = 0;
    } else {
      this.stuck++;
      if (d < this.bestD) this.bestD = d;
    }
    if (this.stuck > 3 && this.strafeTicks === 0) {
      this.strafeDir = rng() < 0.5 ? 1 : -1;
      this.strafeTicks = 25; // ~commit to sidestepping the prop
    }
    this.sinceArrival++; // resets only on arrival; ping-pong retargeting must not reset it
    if (this.sinceArrival > 1500 || this.stuck > 40) {
      // harness-only: bots are policy stand-ins, not pathfinding tests
      // (movement fidelity is covered by player unit tests). Skip the prop.
      w.player.x = x;
      w.player.z = z;
      updatePlayer(w, { fwd: 0, strafe: 0, run: false, camYaw: 0 }, DT);
      this.didMove = false;
      this.reset();
      return true;
    }
    const camYaw = Math.atan2(-dx / d, -dz / d);
    this.didMove = true;
    if (this.strafeTicks > 0) {
      this.strafeTicks--;
      updatePlayer(w, { fwd: 0.35, strafe: this.strafeDir, run: false, camYaw }, DT);
      return false;
    }
    updatePlayer(w, { fwd: 1, strafe: 0, run: false, camYaw }, DT);
    return false;
  }

  reset(): void {
    this.bestD = Infinity;
    this.stuck = 0;
    this.strafeTicks = 0;
    this.sinceArrival = 0;
  }
}

function nearestKind(w: WorldState, kinds: InteractKind[]): Interactable | null {
  let best: Interactable | null = null;
  let bd = Infinity;
  for (const it of w.interactables) {
    if (it.uses <= 0 || !kinds.includes(it.kind)) continue;
    const d = dist(it.x, it.z, w.player.x, w.player.z);
    if (d < bd) {
      bd = d;
      best = it;
    }
  }
  return best;
}

function craftFirst(w: WorldState, id: string): boolean {
  const r = RECIPES.find((x) => x.id === id);
  return !!r && canCraft(w.inventory, r) && craft(w.inventory, r);
}

const isNight = (h: number): boolean => h < 9 || h > 17;

// ---------------------------------------------------------------------------
// policies
// ---------------------------------------------------------------------------

interface Bot {
  tick(w: WorldState): void;
  maintain(w: WorldState): void;
  phase: string;
  mover: Mover;
}

/** shared "camp" routine: fire upkeep, water, eat, sleep. */
class BaseBot implements Bot {
  mover = new Mover();
  phase = '?';
  rng: () => number;
  campX: number;
  campZ: number;
  fireBuilt = false;
  shelterDone = false;
  urgentWood = false;
  camped = false;
  constructor(seed: number, campX: number, campZ: number) {
    this.rng = () => {
      // xorshift-ish deterministic per-bot stream
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    };
    this.campX = campX;
    this.campZ = campZ;
  }

  /** Scout a camp: near water (scarce), in forest (wind), with fuel within
   * reach — what a competent player does after looting the wreck. */
  protected scoutCamp(w: WorldState): void {
    // Camp near the wreck (search area + loot drop) but on forested ground:
    // the starter grove beside the crash site is the designed first camp.
    const scoreAt = (x: number, z: number): number => {
      const zone = zoneAt(x, z);
      let s = zone === 'forest' ? 2 : zone === 'bog' ? 0.5 : 0;
      for (const k of ['deadfall', 'bark', 'boughs', 'berries'] as const) {
        if (w.interactables.some((o) => o.kind === k && o.uses > 0 && dist(o.x, o.z, x, z) < 30)) s += 1;
      }
      if (w.fishHoles.some((h) => h.usesLeft > 0 && dist(h.x, h.z, x, z) < 30)) s += 1;
      if (w.interactables.some((o) => o.kind === 'water' && o.uses > 0 && dist(o.x, o.z, x, z) < 30)) s += 1;
      s -= dist(x, z, CRASH.x, CRASH.z) / 25; // strong: camp IS the crash area
      return s;
    };
    let best = { x: CRASH.x, z: CRASH.z + 20, score: scoreAt(CRASH.x, CRASH.z + 20) };
    for (let x = CRASH.x - 45; x <= CRASH.x + 45; x += 5) {
      for (let z = CRASH.z - 10; z <= CRASH.z + 55; z += 5) {
        const s = scoreAt(x, z);
        if (s > best.score) best = { x, z, score: s };
      }
    }
    this.campX = Math.round(best.x);
    this.campZ = Math.round(best.z);
    this.camped = true;
  }

  protected gather(w: WorldState, kinds: InteractKind[], want: number): void {
    // if the pack can't take even one of what we're fetching, dump bulk wood
    // first (a full pack of deadfall must never deadlock the tinder chain)
    if (kinds.every((k) => !invCanAdd(w.inventory, k, 1))) {
      if ((w.inventory.deadfall ?? 0) > 0) {
        invRemove(w.inventory, 'deadfall', 1);
        this.phase = 'dump-wood';
        return;
      }
    }
    const t = nearestKind(w, kinds);
    if (!t) {
      this.phase = 'idle(no-target:' + kinds.join(',') + ')';
      this.idle(w);
      return;
    }
    this.phase = 'gather:' + t.kind;
    if (!this.mover.move(w, t.x, t.z, this.rng)) return;
    // start the task on THIS target — beginWork picks the nearest interactable
    // (or the snow fallback), so an exhausted prop mid-walk turned gathering
    // into an endless snow-scoop loop
    if (!w.task) w.task = startTask(t);
  }

  protected idle(w: WorldState): void {
    // mill about camp slightly so "moving" debuff logic behaves
    this.phase = 'idle';
    this.mover.move(w, this.campX + 1, this.campZ + 1, this.rng);
  }

  protected campFire(w: WorldState): void {
    // Thirst overrides ALL logistics: snow is everywhere, scoop at the feet
    // immediately (a real player dying of thirst doesn't walk to the wood pile)
    if (
      w.needs.hydration < 30 &&
      !invHas(w.inventory, 'snow', 1) &&
      !invHas(w.inventory, 'waterClean', 1) &&
      !invHas(w.inventory, 'waterRaw', 1) &&
      !w.task
    ) {
      this.phase = 'emergency-snow';
      beginWork(w); // dynamic snow target follows the player
      return;
    }

    // Fire-first loop, ordered like a competent player:
    // light what you can carry NOW, then bulk fuel only once a fire burns.
    const campFireObj = w.fires
      .filter((f) => dist(f.x, f.z, this.campX, this.campZ) < 6)
      .sort((a, b) => b.fuel - a.fuel)[0];
    const lit = campFireObj?.lit && campFireObj.fuel > 0 ? campFireObj : undefined;
    if (this.fireBuilt && (!lit || lit.fuel < 20)) this.fireBuilt = false;

    const df = w.inventory.deadfall ?? 0;
    const kd = w.inventory.kindling ?? 0;
    const bk = w.inventory.bark ?? 0;
    const atCamp = dist(w.player.x, w.player.z, this.campX, this.campZ) <= 3;
    // Night rule: no chore trips after dark. A real player huddles by the
    // fire (or keeps moving for heat) — wandering at −18 °C is the #1 harness
    // death. Fetching resumes at dawn.
    const night = isNight(w.hourOfDay);

    const goCamp = () => {
      this.phase = 'to-camp';
      this.mover.move(w, this.campX, this.campZ, this.rng);
    };

    if (!this.fireBuilt) {
      // Bulk-stock the tinder chain BEFORE crafting: a failed friction light
      // consumes the bundle, so retries must be craft-only, not fetch-again.
      // deadfall→kindling(×3), kindling×2+bark→bundle, bundle→fire.
      if ((!night || this.urgentWood) && df < 4 && invCanAdd(w.inventory, 'deadfall', 2)) {
        this.phase = 'stock-deadfall';
        this.gather(w, ['deadfall'], 4);
        return;
      }
      if ((!night || this.urgentWood) && bk < 2 && invCanAdd(w.inventory, 'bark', 2)) {
        this.phase = 'stock-bark';
        this.gather(w, ['bark'], 2);
        return;
      }
      if (!atCamp) return goCamp();
      this.phase = 'build-fire';
      if (!invHas(w.inventory, 'tinderBundle', 1)) {
        if (kd < 2) craftFirst(w, 'kindling');
        craftFirst(w, 'tinderBundle');
      }
      this.fireBuilt = lightFire(w, computeDebuffs(w.needs).dexterity) === 'lit';
      if (this.fireBuilt && invHas(w.inventory, 'deadfall', 1)) feedFire(w);
      return;
    }

    // fire is lit: keep it fed (bulk fetch only with pack room), then camp chores
    const fireCritical = !lit || lit.fuel < 15;
    // night fetches are allowed ONLY for a dying fire — get up in the dark,
    // grab wood, come back (what Survivorman actually does at 2 a.m.)
    if ((!night || fireCritical) && (!lit || lit.fuel < 50) && df < 6 && invCanAdd(w.inventory, 'deadfall', 2)) {
      this.phase = 'fetch-fuel';
      if (night) this.urgentWood = true;
      this.gather(w, ['deadfall'], 6);
      return;
    }
    if (night && !atCamp && !this.urgentWood) return goCamp(); // night: camp only
    if (this.urgentWood && df >= 2) this.urgentWood = false; // got wood, head home
    if (!atCamp) return goCamp();
    this.phase = 'camp-fire';
    // evening reserve: after 15:00 feed only to ~70 and keep deadfall in the
    // pack for the night watch (stuffing the fire at bedtime = midnight death)
    const feedCap = isNight(w.hourOfDay) || w.hourOfDay > 15 ? 70 : 90;
    if (invHas(w.inventory, 'deadfall', 1) && lit && lit.fuel < feedCap) feedFire(w);
    else if (invHas(w.inventory, 'deadfall', 1) && !lit) feedFire(w);
    if (invHas(w.inventory, 'snow', 1) || invHas(w.inventory, 'waterRaw', 1)) boilWater(w);
    if (invHas(w.inventory, 'waterClean', 1)) drink(w);
    if (invHas(w.inventory, 'meat', 1)) cook(w);
    if (invHas(w.inventory, 'meatCooked', 1) && w.needs.hunger < 55) eat(w);
    if (!w.task && w.needs.hydration < 60 && w.needs.carriedWaterL < 0.5 && !invHas(w.inventory, 'waterClean', 1) && !invHas(w.inventory, 'snow', 1)) {
      beginWork(w); // snow scoop at feet (tin cup from the wreck)
    }
  }

  /** true = went to sleep this tick (or already asleep). Only sleeps when
   * standing still at camp with a fire, or when collapsing from exhaustion. */
  protected sleep(w: WorldState): boolean {
    if (w.needs.sleeping) {
      this.phase = 'sleeping';
      return true;
    }
    if (w.player.moving) return false;
    const litAtCamp = w.fires.some((f) => f.lit && dist(f.x, f.z, this.campX, this.campZ) < 4);
    const atCamp = dist(w.player.x, w.player.z, this.campX, this.campZ) < 3;
    const fireFuel = w.fires.filter((f) => f.lit && dist(f.x, f.z, this.campX, this.campZ) < 4).sort((a, b) => b.fuel - a.fuel)[0];
    // a stage-2 fire burns 18%/h — only a well-fed fire (≥70) survives to dawn
    const safeNight = isNight(w.hourOfDay) && atCamp && !!fireFuel && fireFuel.fuel > 70;
    // collapse-nap only at camp WITH a healthy fire, or in daylight — an
    // open-air or fireless nap at night is a hypothermia death sentence
    // (verified by the harness: this was the #1 average-bot death)
    const campFuel = w.fires
      .filter((f) => f.lit && dist(f.x, f.z, this.campX, this.campZ) < 4)
      .reduce((m, f) => Math.max(m, f.fuel), 0);
    const collapse = w.needs.energy < 15 && (campFuel > 25 || !isNight(w.hourOfDay));
    if (safeNight || collapse) {
      this.phase = 'sleep';
      toggleSleep(w);
      return w.needs.sleeping;
    }
    return false;
  }

  /** While asleep: wake just enough to feed the fire from the wood pile and
   * settle again — real survivors lose sleep to keep the fire alive, and a
   * fire that dies at midnight is the #1 harness death. */
  maintain(w: WorldState): void {
    if (!w.needs.sleeping) return;
    const f = w.fires
      .filter((x) => x.lit && dist(x.x, x.z, this.campX, this.campZ) < 4)
      .sort((a, b) => b.fuel - a.fuel)[0];
    if (f && f.fuel < 30 && invHas(w.inventory, 'deadfall', 1)) {
      feedFire(w);
      return;
    }
    // fire dying and no wood in the pack: get up and fetch (night rule yields)
    if (f && f.fuel < 12 && !(w.inventory.deadfall ?? 0)) {
      toggleSleep(w);
      this.urgentWood = true;
      return;
    }
    // fire fully out at camp: wake and relight — sleeping through this is the
    // harness's #1 optimal-bot death (freezes at −18 °C with warm=0)
    if (!f) {
      toggleSleep(w);
      this.fireBuilt = false;
      this.urgentWood = true;
    }
  }

  tick(w: WorldState): void {
    // default: camp + sleep; subclasses extend
    if (this.sleep(w)) return;
    // night curfew: head for camp before dark (thirst is the only override —
    // snow is underfoot anywhere)
    const atCamp = dist(w.player.x, w.player.z, this.campX, this.campZ) < 8;
    const thirsty = w.needs.hydration < 25;
    if (isNight(w.hourOfDay) && !atCamp && !thirsty && !this.urgentWood && !w.task) {
      this.phase = 'curfew';
      this.mover.move(w, this.campX, this.campZ, this.rng);
      return;
    }
    this.campFire(w);
  }
}

/** naive: loots, fire at the exposed wreck site, no shelter, no food loop, no signal */
class NaiveBot extends BaseBot {
  looted = false;
  constructor(seed: number) {
    super(seed, 0, -137); // open lake shore at the wreck — windy
  }
  override tick(w: WorldState): void {
    if (!this.looted) {
      this.phase = 'to-wreck';
      if (!this.mover.move(w, CRASH.x, CRASH.z, this.rng)) return;
      // check completion BEFORE starting another task (else snow-loops forever)
      if (!w.task && invHas(w.inventory, 'knife', 1)) {
        this.looted = true;
        return;
      }
      this.phase = 'loot';
      if (!w.task) beginWork(w);
      return;
    }
    super.tick(w);
  }
}

/** average: forest-edge camp, shelter, snares, eats properly; forgets to signal */
class AverageBot extends BaseBot {
  looted = false;
  shelterDone = false;
  snares = 0;
  snareFails = 0;
  constructor(seed: number) {
    super(seed, -40, -60); // forest near lake shore
  }

  /** one committed shelter step; returns true when shelter complete */
  protected shelterTick(w: WorldState): boolean {
    const s = w.shelters.find((sh) => dist(sh.x, sh.z, this.campX, this.campZ) < 4);
    if (s?.complete) return true;
    const step = s ? s.step : 0;
    // step costs mirror world.ts SHELTER_STEPS: 1,2 = deadfall×2; 3,5 = boughs×6
    const need: 'boughs' | 'deadfall' | null =
      step === 1 || step === 2 ? 'deadfall' : step === 3 || step === 5 ? 'boughs' : null;
    const want = need === 'boughs' ? 6 : 2;
    if (need && (w.inventory[need] ?? 0) < want) {
      // COMMIT to gathering — do not re-check camp distance mid-fetch (that
      // caused a camp<->prop oscillation)
      this.gather(w, [need], want);
      return false;
    }
    if (dist(w.player.x, w.player.z, this.campX, this.campZ) > 2) {
      this.phase = 'to-camp-shelter';
      this.mover.move(w, this.campX, this.campZ, this.rng);
      return false;
    }
    this.phase = 'shelter';
    const r = buildShelter(w);
    return r === 'complete';
  }

  override tick(w: WorldState): void {
    if (!this.looted) {
      this.phase = 'to-wreck';
      if (!this.mover.move(w, CRASH.x, CRASH.z, this.rng)) return;
      if (!w.task && invHas(w.inventory, 'knife', 1)) {
        this.looted = true;
        this.scoutCamp(w);
        return;
      }
      this.phase = 'loot';
      if (!w.task) beginWork(w);
      return;
    }
    if (!this.camped) this.scoutCamp(w);

    // 1) base survival loop whenever critical or the camp fire needs tending
    const litAtCamp = w.fires.some((f) => f.lit && dist(f.x, f.z, this.campX, this.campZ) < 4);
    const critical = w.needs.hydration < 40 || w.needs.energy < 30 || w.needs.coreTemp < CONFIG.THERMO.COLD_C || w.needs.hunger < 30;
    const atCampNow = dist(w.player.x, w.player.z, this.campX, this.campZ) < 8;
    if (critical || !litAtCamp || (isNight(w.hourOfDay) && !atCampNow)) {
      super.tick(w); // includes the night curfew
      return;
    }

    // 2) snares FIRST (passive food beats comfort; sets are cheap and catch
    //    while you do everything else)
    if (this.snares < 2) {
      this.phase = 'snare';
      if (!invHas(w.inventory, 'cordage', 1)) {
        if (invHas(w.inventory, 'bark', 4)) craftFirst(w, 'cordage');
        else {
          this.gather(w, ['bark'], 4);
          return;
        }
      }
      if (invHas(w.inventory, 'cordage', 1)) {
        const t = nearestKind(w, ['water']); // stream banks = hare sign
        if (t && dist(w.player.x, w.player.z, t.x, t.z) > 3) {
          this.mover.move(w, t.x, t.z + 4, this.rng);
          return;
        }
        if (setSnareAction(w) === 'set') this.snares += 1;
        else if (++this.snareFails > 20) this.snares = 2; // no hare sign here; move on
        return;
      }
    }
    checkSnares(w);

    // 3) shelter when calm
    if (!this.shelterDone) {
      if (this.shelterTick(w)) this.shelterDone = true;
      super.tick(w);
      return;
    }
    super.tick(w);
  }
}

/** optimal: average + dawn fishing, wound care, signal fire + open shore by day 7 */
class OptimalBot extends AverageBot {
  signalling = false;
  constructor(seed: number) {
    super(seed);
  }
  override tick(w: WorldState): void {
    // repel wolves while awake
    if (w.wolves.length > 0 && !w.needs.sleeping) w.shouting = true;
    // treat wounds at fire when tape available
    if (w.injuries.some((i) => i.infected || i.severity > 30) && invHas(w.inventory, 'ductTape', 1)) {
      treatWound(w);
    }
    // fish at dawn when idle and near a hole
    if (!w.task && w.hourOfDay < 10 && w.needs.hydration > 45 && invHas(w.inventory, 'cordage', 1) && dist(w.player.x, w.player.z, this.campX, this.campZ) < 40) {
      const hole = w.fishHoles.find((h) => h.usesLeft > 0);
      if (hole) {
        this.phase = 'fish';
        if (!this.mover.move(w, hole.x, hole.z, this.rng)) return;
        fish(w);
        return;
      }
    }
    // day 6+: move to open shore, big fire, signal smoke, stay for dawn pass
    if (w.day >= 6 && !this.signalling) {
      this.phase = 'signal-move';
      this.campX = 0;
      this.campZ = -137;
      this.fireBuilt = w.fires.some((f) => f.lit && dist(f.x, f.z, CRASH.x, CRASH.z) < 6);
      if (!this.mover.move(w, 0, -137, this.rng)) return;
      if (!this.fireBuilt) {
        if (invHas(w.inventory, 'tinderBundle', 1)) {
          this.fireBuilt = lightFire(w, 1) === 'lit';
        } else if (invHas(w.inventory, 'kindling', 2) && invHas(w.inventory, 'bark', 1)) craftFirst(w, 'tinderBundle');
        else if (invHas(w.inventory, 'deadfall', 1)) craftFirst(w, 'kindling');
        else this.gather(w, ['deadfall', 'bark'], 6);
        return;
      }
      if (invHas(w.inventory, 'deadfall', 1)) feedFire(w);
      if (!w.signalFireId && invHas(w.inventory, 'boughs', 2)) signalSmoke(w);
      if (w.signalFireId) this.signalling = true;
      // flare as insurance once the pass is imminent and smoke isn't up
      if (!this.signalling && w.day === 7 && w.hourOfDay > 8 && invHas(w.inventory, 'flare', 1)) fireFlare(w);
    }
    super.tick(w);
  }
}

// ---------------------------------------------------------------------------
// runner
// ---------------------------------------------------------------------------

export interface RunResult {
  policy: string;
  seed: number;
  outcome: 'rescued' | 'dead';
  cause?: string;
  day: number;
  hour: number;
}

export function runGame(policy: 'naive' | 'average' | 'optimal', seed: number, trace?: (w: WorldState, i: number) => void): RunResult {
  const w = createWorld(seed);
  const bot: Bot =
    policy === 'naive' ? new NaiveBot(seed) : policy === 'average' ? new AverageBot(seed) : new OptimalBot(seed);
  const maxTicks = 11 * 24 * (CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR / DT);
  for (let i = 0; i < maxTicks && !w.dead && !w.rescued; i++) {
    bot.mover.didMove = false;
    if (w.needs.sleeping) bot.maintain(w);
    else if (!w.task) bot.tick(w);
    (w as WorldState & { _phase?: string })._phase = bot.phase;
    // if the bot chose a non-movement action while p.moving was still true,
    // settle it — stale movement blocks sleep, auto-sip, and drains energy
    if (w.player.moving && !bot.mover.didMove) updatePlayer(w, { fwd: 0, strafe: 0, run: false, camYaw: 0 }, DT);
    // a bot that starts a task intends to stand (mover only clears p.moving
    // on arrival; if it was already at target, moving stays stuck true and
    // tickWork would cancel every task)
    if (w.task && w.player.moving) updatePlayer(w, { fwd: 0, strafe: 0, run: false, camYaw: 0 }, DT);
    step(w, DT, false);
    tickWork(w, DT, computeDebuffs(w.needs).dexterity);
    trace?.(w, i);
  }
  return {
    policy,
    seed,
    outcome: w.rescued ? 'rescued' : 'dead',
    cause: w.dead?.cause,
    day: w.day,
    hour: Math.floor(w.hourOfDay),
  };
}

export function summarize(results: RunResult[]): string {
  const byPolicy = new Map<string, RunResult[]>();
  for (const r of results) {
    if (!byPolicy.has(r.policy)) byPolicy.set(r.policy, []);
    byPolicy.get(r.policy)!.push(r);
  }
  const lines: string[] = [];
  for (const [policy, rs] of byPolicy) {
    const n = rs.length;
    const rescued = rs.filter((r) => r.outcome === 'rescued');
    const deaths = rs.filter((r) => r.outcome === 'dead');
    const causes = new Map<string, number>();
    const nights = new Map<number, number>();
    for (const d of deaths) {
      causes.set(d.cause ?? '?', (causes.get(d.cause ?? '?') ?? 0) + 1);
      nights.set(d.day, (nights.get(d.day) ?? 0) + 1);
    }
    const avgRescueDay = rescued.length
      ? (rescued.reduce((s, r) => s + r.day, 0) / rescued.length).toFixed(1)
      : '—';
    lines.push(
      `${policy.padEnd(8)} n=${n}  rescued ${((rescued.length / n) * 100).toFixed(0)}% (avg day ${avgRescueDay})  died ${((deaths.length / n) * 100).toFixed(0)}%`,
    );
    lines.push(`  causes: ${[...causes].sort((a, b) => b[1] - a[1]).map(([c, k]) => `${c}=${k}`).join(', ') || 'none'}`);
    lines.push(`  death days: ${[...nights].sort((a, b) => a[0] - b[0]).map(([d, k]) => `d${d}=${k}`).join(', ') || 'none'}`);
  }
  return lines.join('\n');
}

// main (only when executed directly via vite-node; vitest imports won't match)
