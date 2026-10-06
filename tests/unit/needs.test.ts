import { describe, expect, it } from 'vitest';
import {
  airTempAt,
  computeDebuffs,
  createEnv,
  createNeeds,
  tickNeeds,
  windchill,
} from '../../src/sim/needs';
import { CONFIG } from '../../src/sim/config';

const H = CONFIG.TIME.REAL_SECONDS_PER_GAME_HOUR; // one game hour in sim seconds

function run(
  n: ReturnType<typeof createNeeds>,
  env: ReturnType<typeof createEnv>,
  hours: number,
  opts: { moving?: boolean; sprinting?: boolean } = {},
) {
  const events: string[] = [];
  let died: { cause: string; detail: string } | undefined;
  const ticksPerHour = H / CONFIG.SIM_DT;
  for (let i = 0; i < hours * ticksPerHour; i++) {
    const r = tickNeeds(n, env, CONFIG.SIM_DT, {
      moving: opts.moving ?? false,
      sprinting: opts.sprinting ?? false,
      difficulty: 'ranger',
    });
    events.push(...r.events);
    if (r.died) {
      died = r.died;
      break;
    }
  }
  return { n, events, died };
}

describe('windchill / diurnal', () => {
  it('windchill only lowers temperature', () => {
    expect(windchill(-12, 30)).toBeLessThan(-12);
    expect(windchill(5, 30)).toBeCloseTo(5, 0); // no windchill above freezing
  });
  it('coldest before dawn, warmest mid-afternoon', () => {
    const t = (h: number) => airTempAt(h, -12, 6);
    expect(t(14)).toBeGreaterThan(t(2));
    expect(t(2)).toBeLessThan(-15);
  });
});

describe('thermoregulation tuning targets (DESIGN-needs.md)', () => {
  it('active + dry + clothed at feels −20 °C is roughly stable', () => {
    const n = createNeeds();
    const env = createEnv();
    env.airTempC = -18;
    env.windKmh = 12; // feels ≈ -25; walking exertion offsets
    const { n: r } = run(n, env, 6, { moving: true });
    expect(r.coreTemp).toBeGreaterThan(36.0); // stays out of the cold band
  });

  it('idle at night, no fire/shelter → hypothermia band in ~4-6 game hours', () => {
    const n = createNeeds();
    const env = createEnv();
    env.airTempC = -14;
    env.windKmh = 10; // feels ≈ -20 (the design's reference condition)
    let hours = 0;
    let died;
    for (; hours < 12; hours++) {
      const r = tickNeeds(n, env, H, { moving: false, sprinting: false, difficulty: 'ranger' });
      died = r.died;
      if (n.coreTemp <= CONFIG.THERMO.HYPOTHERMIA_C || died) break;
    }
    expect(n.coreTemp).toBeLessThanOrEqual(CONFIG.THERMO.HYPOTHERMIA_C);
    expect(hours).toBeGreaterThanOrEqual(3);
    expect(hours).toBeLessThanOrEqual(7);
    expect(died).toBeUndefined(); // hypothermia band ≠ instant death
  });

  it('fire rescues you: same conditions + fire warmth → stabilizes above hypothermia', () => {
    const n = createNeeds();
    n.coreTemp = 34.8; // already very cold
    const env = createEnv();
    env.airTempC = -18;
    env.windKmh = 18;
    env.fireWarmth = 0.9;
    const { n: r } = run(n, env, 4);
    expect(r.coreTemp).toBeGreaterThan(35.5);
  });

  it('soaked at −12 °C overnight is a real crisis (big temp drop without fire)', () => {
    const n = createNeeds();
    n.wetness = 0.9;
    const env = createEnv();
    env.airTempC = -12;
    env.windKmh = 10;
    const { n: r } = run(n, env, 8);
    expect(r.coreTemp).toBeLessThan(34.5); // into very-cold band within a night
  });

  it('shelter + bedding materially improves the night', () => {
    const mk = () => {
      const n = createNeeds();
      const env = createEnv();
      env.airTempC = -16;
      env.windKmh = 14;
      return { n, env };
    };
    const a = mk();
    const b = mk();
    b.env.shelterInsul = 1;
    run(a.n, a.env, 8);
    run(b.n, b.env, 8);
    expect(b.n.coreTemp).toBeGreaterThan(a.n.coreTemp + 1.5);
  });

  it('hunger starves heat production (food = fuel)', () => {
    const mk = (hunger: number) => {
      const n = createNeeds();
      n.hunger = hunger;
      const env = createEnv();
      env.airTempC = -14;
      env.windKmh = 12;
      return n;
    };
    const fed = mk(90);
    const starving = mk(5);
    const env = createEnv();
    env.airTempC = -14;
    env.windKmh = 12;
    run(fed, env, 6);
    run(starving, env, 6);
    expect(starving.coreTemp).toBeLessThan(fed.coreTemp);
  });
});

describe('needs pacing & death chains', () => {
  it('hydration full→empty ≈ 2+ game days idle', () => {
    const n = createNeeds();
    n.hydration = 100;
    const env = createEnv();
    env.airTempC = 0; // warm: no shiver confound
    let hours = 0;
    while (n.hydration > 0 && hours < 100) {
      tickNeeds(n, env, H, { moving: false, sprinting: false, difficulty: 'ranger' });
      hours++;
    }
    expect(hours).toBeGreaterThanOrEqual(48);
    expect(hours).toBeLessThanOrEqual(72);
  });

  it('auto-sip keeps hydration topped from carried water while idle', () => {
    const n = createNeeds();
    n.hydration = 55;
    n.carriedWaterL = 2;
    const env = createEnv();
    env.airTempC = 0;
    const { n: r } = run(n, env, 4);
    expect(r.hydration).toBeGreaterThan(55); // net gain from sipping
    expect(r.carriedWaterL).toBeLessThan(2); // consumed stock
  });

  it('auto-sip does NOT run while moving (batch management stays a choice)', () => {
    const n = createNeeds();
    n.hydration = 55;
    n.carriedWaterL = 2;
    const env = createEnv();
    env.airTempC = 0;
    run(n, env, 4, { moving: true });
    expect(n.hydration).toBeLessThan(55); // only drains while traveling
    expect(n.carriedWaterL).toBe(2);
  });

  it('death at zero hydration takes ~8-10 h, not instantly', () => {
    const n = createNeeds();
    n.hydration = 0;
    n.health = 100;
    const env = createEnv();
    env.airTempC = 0;
    let hours = 0;
    let died;
    while (hours < 30) {
      const r = tickNeeds(n, env, H, { moving: false, sprinting: false, difficulty: 'ranger' });
      hours++;
      if (r.died) {
        died = r.died;
        break;
      }
    }
    expect(died?.cause).toBe('dehydration');
    expect(hours).toBeGreaterThanOrEqual(6);
    expect(hours).toBeLessThanOrEqual(14);
  });

  it('debuffs appear before critical bands (signposted slide)', () => {
    const n = createNeeds();
    n.energy = 40;
    n.hunger = 40;
    const d = computeDebuffs(n);
    expect(d.strength).toBeLessThan(1);
    expect(d.focus).toBeLessThan(1);
    expect(n.health).toBe(100); // no HP damage at 40%
  });

  it('hypothermia chain: idle night outside → death with named cause', () => {
    const n = createNeeds();
    const env = createEnv();
    env.airTempC = -22;
    env.windKmh = 25;
    let died;
    for (let i = 0; i < 24 * 3; i++) {
      const r = tickNeeds(n, env, H, { moving: false, sprinting: false, difficulty: 'ranger' });
      if (r.died) {
        died = r.died;
        break;
      }
    }
    expect(died?.cause).toBe('hypothermia');
  });
});
