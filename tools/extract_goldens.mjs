// Golden-value extraction: runs the REAL boreal TS sim and dumps reference values.
import { makeRng } from './sim/rng.ts';
import { valueNoise2, fbm2, hash2 } from './sim/noise.ts';
import { heightAt, zoneAt, lakeT, streamX } from './sim/terrain.ts';
import { windchill, airTempAt, heatBudget, createNeeds, createEnv, insulationOf } from './sim/needs.ts';
import { hareSignAt, setSnare, tickSnares, buildFishHoles, fishRoll, addInjury, tickInjuries, treatInjury, sepsisDamagePerH } from './sim/dangers.ts';
import { RECIPES, canCraft, craft } from './sim/craft.ts';

const out = {};

// --- rng: first 20 outputs for seeds 1, 42, 12345, 7 (0x9e3779b9-style big seeds too)
const rngSeeds = [1, 42, 12345, 7, 2654435761, 4294967295, 0];
out.rng = {};
for (const s of rngSeeds) {
  const r = makeRng(s);
  out.rng[s] = Array.from({ length: 20 }, () => r());
}
// roll()-style seeds: (seed*0x9e3779b9) ^ (rngN*0x85ebca6b) for seed=1, rngN=1..5
out.roll_seeds = [];
for (let n = 1; n <= 5; n++) {
  const s = ((1 * 0x9e3779b9) | 0) ^ ((n * 0x85ebca6b) | 0);
  const r = makeRng(s >>> 0);
  out.roll_seeds.push({ seed: s >>> 0, v: r() });
}

// --- noise
out.hash2 = [];
for (const [ix, iy, sd] of [[0,0,11],[1,2,11],[-3,7,77],[100,-200,5],[12345,6789,31],[-1,-1,0],[400,-400,47]]) {
  out.hash2.push({ ix, iy, seed: sd, v: hash2(ix, iy, sd) });
}
out.valueNoise2 = [];
for (const [x, y, sd] of [[0.5,0.5,11],[1.25,-2.75,77],[-10.5,33.25,5],[0,0,0],[123.4,56.7,31],[-0.3,-0.7,41]]) {
  out.valueNoise2.push({ x, y, seed: sd, v: valueNoise2(x, y, sd) });
}
out.fbm2 = [];
for (const [x, y, sd, o, f] of [[0.1,0.2,11,4,1],[1.5,-2.5,12,3,2],[-30.5,44.25,77,2,0.01],[0,0,21,2,0.05],[12.3,45.6,31,4,1]]) {
  out.fbm2.push({ x, y, seed: sd, oct: o, freq: f, v: fbm2(x, y, sd, o, f) });
}

// --- terrain
out.heightAt = {};
for (const [x, z] of [[0,-150],[-20,-62],[100,50],[-260,0],[0,200],[-35,0],[streamX(0),0],[streamX(0)+40,0],[-100,-100],[50,-140],[-150,120],[200,-200],[-300,300],[380,-380],[-20,-32],[-40,-6],[0,0],[-80,-90],[150,150],[-399,399]]) {
  out.heightAt[`${x},${z}`] = heightAt(x, z);
}
out.zoneAt = {};
for (const [x, z] of [[0,-150],[-260,0],[0,200],[-20,-62],[streamX(0),0],[100,130],[-150,50],[300,-300],[-141,0],[-139,0],[0,109],[0,111]]) {
  out.zoneAt[`${x},${z}`] = zoneAt(x, z);
}
out.streamX = {};
for (const z of [-160,-150,-62,0,90,200]) out.streamX[z] = streamX(z);

// --- needs
out.windchill = {};
for (const [t, w] of [[-12,30],[-12,10],[-20,25],[-0.5,10],[0,10],[5,30],[-30,4.8],[-35,60],[-14,10],[-18,12],[-18,18],[-16,14]]) {
  out.windchill[`${t},${w}`] = windchill(t, w);
}
out.airTempAt = {};
for (const h of [0,2,8,14,17,23]) out.airTempAt[h] = airTempAt(h, -12, 6);

// heatBudget goldens (createNeeds defaults)
{
  const n = createNeeds();
  const env = createEnv();
  env.airTempC = -18; env.windKmh = 12;
  out.heatBudget = {
    walking_feels25: heatBudget(n, env, windchill(-18, 12), true, false),
    idle_feels20: heatBudget(n, createEnv(), windchill(-14, 10), false, false),
    insulation_default: insulationOf(n, env),
    insulation_wet: (() => { const m = createNeeds(); m.wetness = 0.9; return insulationOf(m, env); })(),
  };
}

// --- dangers (S6; wolves deliberately cut from the MVP) ---

// hareSignAt grid samples (stream-band sign strength × seeded noise)
out.hareSignAt = {};
for (const seed of [1, 7]) {
  for (const [x, z] of [[-35,0],[-40,-6],[-20,-62],[0,-150],[10,90],[60,20],[-100,-100],[0,200],[-33,3],[-37,-3]]) {
    out.hareSignAt[`${x},${z},${seed}`] = hareSignAt(x, z, seed);
  }
}

// snare tick sequences from fixed seeds: 48 game-hours at 1/12 h steps.
// Each entry: catch hour (null = never caught), final ageH, final set flag.
out.snareTicks = {};
for (const [tag, seed, snowMul] of [["s1m1",1,1],["s1m05",1,0.5],["s42m1",42,1],["s42m05",42,0.5],["s7m1",7,1]]) {
  const snares = [];
  setSnare(snares, 1, -35, 0, 1);          // fixed spot (stream meanders: sign here is 0)
  const rng = makeRng(seed);
  let caughtAtH = null;
  for (let i = 0; i < 48 * 120; i++) {
    const res = tickSnares(snares, 1 / 120, snowMul, rng);
    if (res.caught > 0 && caughtAtH === null) caughtAtH = (i + 1) / 120;
    if (!snares[0].set) break;
  }
  out.snareTicks[tag] = { caughtAtH, ageH: snares[0].ageH, set: snares[0].set };
}

// fishRoll hour table: fresh rng per hour, seed 3; hour 0..23 step 0.5
out.fishRoll = [];
for (let h = 0; h < 24; h += 0.5) {
  out.fishRoll.push({ hour: h, hit: fishRoll(h, makeRng(3)) });
}

// fish hole table (positions ride streamX; uses fixed at 4)
out.fishHoles = buildFishHoles(1).map((h) => ({ id: h.id, x: h.x, z: h.z, usesLeft: h.usesLeft }));

// injury → infection → sepsis timeline: severity 40 untreated, 1/60-h steps,
// fresh rng(seed) per scenario. Records infection hour, hour infection crosses
// 60 (sepsis threshold), sepsis damage rate, and treatInjury reset semantics.
out.injuryTimeline = {};
for (const seed of [1, 5]) {
  const list = [];
  addInjury(list, 'test wound', 40);
  const rng = makeRng(seed);
  let infectedAtH = null, septicAtH = null;
  for (let i = 0; i < 200 * 60; i++) {
    const ev = tickInjuries(list, 1 / 60, rng);
    if (ev.length && infectedAtH === null) infectedAtH = (i + 1) / 60;
    if (list[0].infected && list[0].infection > 60 && septicAtH === null) septicAtH = (i + 1) / 60;
    if (septicAtH !== null) break;
  }
  out.injuryTimeline[`s${seed}`] = {
    infectedAtH, septicAtH,
    infection: list[0].infection,
    sepsisPerH: sepsisDamagePerH(list),
  };
}

// treatInjury semantics: infected+80 severity treated → clean, halved;
// then a 20-severity clean wound is NOT treatable (TS find predicate).
{
  const list = [];
  addInjury(list, 'a', 80);
  list[0].infected = true;
  list[0].infection = 90;
  const ok = treatInjury(list);
  out.treatInjury = { ok, severity: list[0].severity, infected: list[0].infected, infection: list[0].infection };
  const list2 = [];
  addInjury(list2, 'b', 20);
  out.treatInjury.cleanLow = { ok: treatInjury(list2), severity: list2[0].severity };
}

// --- craft (craft.ts) ---

// recipe table (declarative; hours are game-hours of work)
out.craftRecipes = RECIPES.map((r) => ({
  id: r.id, label: r.label, in: r.in, out: r.out, hours: r.hours, requires: r.requires ?? null,
}));

// canCraft matrix: fixed inventories × RECIPES order
out.canCraft = {};
{
  const invs = {
    empty: {},
    bark4: { bark: 4 },
    bark4knife: { bark: 4, knife: 1 },
    tinder: { bark: 1, kindling: 2 },
    kindlingSrc: { deadfall: 1, knife: 1 },
    torch: { bark: 2, deadfall: 1 },
    boughs6: { boughs: 6 },
    // knife recipes blocked without the knife; cordage fits (stack 4, weight ok)
    cordageBlocked: { bark: 4, barkContainer: 2 },
  };
  for (const [k, inv] of Object.entries(invs))
    out.canCraft[k] = RECIPES.map((r) => canCraft(inv, r));
}

// greedy craft sequence (main.ts craftBest: first craftable recipe, repeat):
// steps taken + final inventory. Deterministic, no RNG.
{
  const inv = { bark: 9, kindling: 6, deadfall: 3, boughs: 6, knife: 1 };
  const steps = [];
  for (let i = 0; i < 50; i++) {
    const r = RECIPES.find((x) => canCraft(inv, x));
    if (!r) break;
    craft(inv, r);
    steps.push(r.id);
  }
  out.craftSequence = { steps, inv };
}

// atomicity: barkContainer needs 4 bark AND output fit; stack-full barkContainer
// (2/2) must block the craft WITHOUT consuming the bark.
{
  const inv = { bark: 4, barkContainer: 2, knife: 1 };
  const ok = craft(inv, RECIPES.find((r) => r.id === 'barkContainer'));
  out.craftAtomic = { ok, inv };
}

console.log(JSON.stringify(out, null, 1));
