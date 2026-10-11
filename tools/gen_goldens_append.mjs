// One-shot: append dangers golden constants to tests/goldens.gd from the
// extract_goldens.mjs JSON dump. Run: node tools/gen_goldens_append.mjs < g.json
// (or pass the json path as argv[2]). Regenerate the JSON first with
// `node tools/extract_goldens.mjs > g.json`.
import { readFileSync, appendFileSync } from 'node:fs';

const g = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const buf = Buffer.alloc(8);
const bits = (v) => { buf.writeDoubleLE(v); return buf.readBigUInt64LE().toString(); };
const neg = (b) => { let x = BigInt(b); if (x >= 1n << 63n) x -= 1n << 64n; return x.toString(); };
const fb = (v) => (v === 0 ? '0' : neg(bits(v)));

const L = [];
L.push('');
L.push('# --- dangers (S6): snares / fishing / injuries (wolves cut from MVP) ---');
L.push('# hareSignAt grid samples: key "x,z,seed"');
L.push('const HARE_SIGN_AT = {');
for (const k of Object.keys(g.hareSignAt)) L.push(`\t"${k}": ${fb(g.hareSignAt[k])},`);
L.push('}');
L.push('');
L.push('# snare tick sequences: fresh makeRng(seed), 1/120-h steps, on-stream snare.');
L.push('# caughtAtH = game-hour of first catch (null = never in 48 h); ageH/set final.');
L.push('const SNARE_TICKS = {');
for (const [tag, e] of Object.entries(g.snareTicks))
  L.push(`\t"${tag}": {"caughtAtH": ${e.caughtAtH === null ? 'null' : fb(e.caughtAtH)}, "ageH": ${fb(e.ageH)}, "set": ${e.set}},`);
L.push('}');
L.push('');
L.push('# fishRoll hour table (fresh rng seed 3 per hour, hour 0..23 step 0.5)');
L.push('const FISH_ROLL = [');
for (const e of g.fishRoll) L.push(`\t{"hour": ${e.hour.toFixed(1)}, "hit": ${e.hit}},`);
L.push(']');
L.push('');
L.push('# buildFishHoles(1) table');
L.push('const FISH_HOLES = [');
for (const h of g.fishHoles) L.push(`\t{"id": ${h.id}, "x": ${fb(h.x)}, "z": ${fb(h.z)}, "usesLeft": ${h.usesLeft}},`);
L.push(']');
L.push('');
L.push('# injury timeline: severity-40 untreated wound, 1/60-h steps, fresh rng(seed)');
L.push('const INJURY_TIMELINE = {');
for (const [k, e] of Object.entries(g.injuryTimeline))
  L.push(`\t"${k}": {"infectedAtH": ${e.infectedAtH === null ? 'null' : fb(e.infectedAtH)}, "septicAtH": ${e.septicAtH === null ? 'null' : fb(e.septicAtH)}, "infection": ${fb(e.infection)}, "sepsisPerH": ${fb(e.sepsisPerH)}},`);
L.push('}');
L.push('');
L.push('# treatInjury semantics (infected sev-80 treated; clean sev-20 not treatable)');
L.push('const TREAT_INJURY = {');
L.push(`\t"ok": ${g.treatInjury.ok}, "severity": ${fb(g.treatInjury.severity)}, "infected": ${g.treatInjury.infected}, "infection": ${fb(g.treatInjury.infection)},`);
L.push(`\t"cleanLowOk": ${g.treatInjury.cleanLow.ok}, "cleanLowSeverity": ${fb(g.treatInjury.cleanLow.severity)},`);
L.push('}');
L.push('');
L.push('# --- craft (craft.ts) ---');
L.push('# RECIPES table in TS order: inputs/outputs, hours (game-hours), requires');
L.push('const CRAFT_RECIPES = [');
for (const r of g.craftRecipes) {
  const io = (list) => list.map((e) => `{"item": "${e.item}", "n": ${e.n}}`).join(', ');
  L.push(`\t{"id": "${r.id}", "label": "${r.label}", "in": [${io(r.in)}], "out": [${io(r.out)}], "hours": ${fb(r.hours)}, "requires": ${r.requires === null ? 'null' : `"${r.requires}"`}},`);
}
L.push(']');
L.push('');
L.push('# canCraft matrix: fixed inventories × RECIPES order');
L.push('const CAN_CRAFT = {');
for (const [k, arr] of Object.entries(g.canCraft))
  L.push(`\t"${k}": [${arr.map((b) => String(b)).join(', ')}],`);
L.push('}');
L.push('');
L.push('# greedy craft sequence (first-craftable loop): steps + final inventory');
L.push('const CRAFT_SEQUENCE = {');
L.push(`\t"steps": [${g.craftSequence.steps.map((s) => `"${s}"`).join(', ')}],`);
L.push(`\t"inv": {${Object.entries(g.craftSequence.inv).map(([k, v]) => `"${k}": ${v}`).join(', ')}},`);
L.push('}');
L.push('');
L.push('# atomicity: blocked craft (output stack full) must not consume inputs');
L.push('const CRAFT_ATOMIC = {');
L.push(`\t"ok": ${g.craftAtomic.ok}, "inv": {${Object.entries(g.craftAtomic.inv).map(([k, v]) => `"${k}": ${v}`).join(', ')}},`);
L.push('}');

appendFileSync('tests/goldens.gd', L.join('\n') + '\n');
console.log('appended', L.length, 'lines');
