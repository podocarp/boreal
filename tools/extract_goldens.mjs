// Golden-value extraction: runs the REAL boreal TS sim and dumps reference values.
import { makeRng } from './sim/rng.ts';
import { valueNoise2, fbm2, hash2 } from './sim/noise.ts';
import { heightAt, zoneAt, lakeT, streamX } from './sim/terrain.ts';
import { windchill, airTempAt, heatBudget, createNeeds, createEnv, insulationOf } from './sim/needs.ts';

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

console.log(JSON.stringify(out, null, 1));
