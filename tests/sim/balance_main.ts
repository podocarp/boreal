import { runGame, summarize, type RunResult } from './balance';

declare const process: { argv: string[] };
const seeds = Number(process.argv[2] ?? 100);
const results: RunResult[] = [];
const t0 = Date.now();
for (const policy of ['naive', 'average', 'optimal'] as const) {
  for (let s = 1; s <= seeds; s++) results.push(runGame(policy, s));
}
console.log(`# balance: ${seeds} seeds/policy, ${((Date.now() - t0) / 1000).toFixed(1)}s`);
console.log(summarize(results));
