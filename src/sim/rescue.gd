## Rescue & win condition — port of rescue.ts.
class_name RescueSim

## Pass schedule for the whole run: days 7..10, dawn + dusk.
static func search_schedule() -> Array:
	var passes: Array = []
	for day in range(7, 11):
		passes.append({"day": day, "hour": 9.0, "kind": "dawn"})
		passes.append({"day": day, "hour": 16.5, "kind": "dusk"})
	return passes


static func pass_scrubbed(storm_severity: float) -> bool:
	return storm_severity > 0.5


## Detection probability 0..1 for a pass. d: DetectionInput dict.
static func detection_chance(d: Dictionary) -> float:
	var p := 0.02  # drifting luck
	if d.signalSmoke:
		p += 0.9 if d.openGround else 0.5
	elif d.anyFire:
		p += 0.3 if d.openGround else 0.1
	if d.flareUsedRecently:
		p = maxf(p, 0.95)  # one shot, near-certain
	if d.onRidge:
		p += 0.1
	if d.shelterVisible:
		p += 0.08
	if d.movedRecently:
		p += 0.05
	return minf(0.98, p)


static func create_rescue() -> Dictionary:
	return {"resolved": 0, "flareUsedDay": null, "rescued": null, "collapsed": false, "lastPass": null}


## Called every tick by WorldSim.step: resolve a scheduled pass if just crossed.
## detect/rng are Callables. Returns {fired, spotted?, scrubbed?, kind?}.
static func check_pass(r: Dictionary, day: int, hour: float, storm_severity: float,
		detect: Callable, rng: Callable) -> Dictionary:
	var sched := search_schedule()
	while r.resolved < sched.size():
		var passp: Dictionary = sched[r.resolved]
		if day > passp.day or (day == passp.day and hour >= passp.hour):
			r.resolved += 1
			var scrubbed := pass_scrubbed(storm_severity)
			if scrubbed:
				r.lastPass = {"day": passp.day, "kind": passp.kind, "spotted": false, "scrubbed": true}
				return {"fired": true, "scrubbed": true, "kind": passp.kind}
			var p := detection_chance(detect.call())
			var spotted: bool = rng.call() < p
			r.lastPass = {"day": passp.day, "kind": passp.kind, "spotted": spotted, "scrubbed": false}
			return {"fired": true, "spotted": spotted, "kind": passp.kind}
		break
	return {"fired": false}


## Day 10 dawn, not rescued -> exposure collapse (run over).
static func check_collapse(r: Dictionary, day: int) -> bool:
	if r.rescued == null and day > Config.RESCUE.COLLAPSE_DAY:
		r.collapsed = true
		return true
	return false
