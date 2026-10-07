// Trace one optimal game: camp choice, fire, temps.
import { runGame } from './balance';

const r = runGame('optimal', 1, (w, i) => {
  if (i % 1800 === 0) {
    const f = w.fires.find((x) => x.lit);
    console.log(
      `d${w.day} ${w.hourOfDay.toFixed(1)}h pos(${w.player.x.toFixed(0)},${w.player.z.toFixed(0)})`,
      `fire=${f ? f.fuel.toFixed(0) : '-'} core=${w.needs.coreTemp.toFixed(1)}`,
      `energy=${w.needs.energy.toFixed(0)} task=${w.task?.kind ?? '-'} sleeping=${w.needs.sleeping}`,
      `shelters=${w.shelters.length} log="${w.log[w.log.length - 1]?.msg ?? ''}"`,
    );
  }
});
console.log('result:', JSON.stringify(r));
