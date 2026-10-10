## BOREAL — food & dangers — port of dangers.ts (S6): snares, ice-edge
## fishing, injuries → infection → sepsis.
##
## DELIBERATE SCOPE CUT (owner directive 2026-10-10): the wolf FSM
## (WolfState/Wolf/spawnWolves/tickWolves, dangers.ts ~99-253) is NOT ported —
## wolves are out of the MVP. Everything else in dangers.ts is here, faithful.
## Berries needed no port: they ride the frozen Interact/Items tables
## (interact kind 'berries' → item 'berries', eaten by Actions.eat).
##
## rng params are Callables returning [0,1) — the world passes its seeded
## roll(); no randf() anywhere. dtGameH is GAME hours (convert real seconds
## via Config.TIME.REAL_SECONDS_PER_GAME_HOUR before calling).
class_name DangerSim


# --- Snares (snowshoe hare runs) --------------------------------------------

## Fresh snare dict (mirrors the TS Snare interface; `pending` is null until a
## catch happens — TS uses undefined, GDScript uses null).
static func make_snare(id: int, x: float, z: float, quality: float) -> Dictionary:
	return {"id": id, "x": x, "z": z, "set": true, "ageH": 0.0,
		"quality": quality, "pending": null}


## Hare runs: deterministic bands along the stream banks + bog edges.
static func hareSignAt(x: float, z: float, seed: int) -> float:
	# sign strength 0..1: near stream (±25 m) or bog edge, with noise
	var d_stream := absf(x - Terrain.streamX(z))
	var s := maxf(0.0, 1.0 - d_stream / Config.DANGERS.HARE_SIGN_BAND_M)
	var n := Rng.make_rng(Rng.i32(int(floor(x * 10.0)) ^ int(floor(z * 10.0)) ^ seed)).next()
	return minf(1.0, s * (0.5 + n * 0.5))


static func set_snare(list: Array, next_id: int, x: float, z: float, seed: int) -> Dictionary:
	var s := make_snare(next_id, x, z, hareSignAt(x, z, seed))
	list.append(s)
	return s


## Tick snares (game hours). Catch roll per hour scales with placement quality
## and freshness; deep snow (storm recency) halves it — caller passes snowMul.
static func tick_snares(snares: Array, dtGameH: float, snowMul: float, rng: Callable) -> Dictionary:
	var caught := 0
	var ids: Array = []
	for s in snares:
		if not s.set:
			continue
		s.ageH += dtGameH
		var freshness: float = 1.0 if s.ageH < Config.DANGERS.SNARE_FRESH_H \
			else maxf(Config.DANGERS.SNARE_FRESH_MIN, 1.0 - (s.ageH - Config.DANGERS.SNARE_FRESH_H) / Config.DANGERS.SNARE_FRESH_DECAY_H)
		var p: float = Config.DANGERS.SNARE_BASE_P * (0.3 + s.quality) * freshness * snowMul  # per game hour
		if rng.call() < p * dtGameH:
			caught += 1
			ids.append(s.id)
			s.set = false  # snare destroyed in the struggle (realistic + creates a loop)
	return {"caught": caught, "ids": ids}


# --- Fishing (ice-edge holes) -------------------------------------------------

static func build_fish_holes(seed: int) -> Array:
	# a few reliable holes where the stream meets the lake + bends
	var holes: Array = []
	var id := 1
	for z in Config.DANGERS.FISH_HOLE_ZS:
		holes.append({"id": id, "x": Terrain.streamX(z), "z": float(z), "usesLeft": Config.DANGERS.FISH_HOLE_USES})
		id += 1
	return holes


## Fishing success: dawn/dusk best; needs cordage+hook (caller checks items).
static func fish_roll(hour: float, rng: Callable) -> bool:
	var golden: float = Config.DANGERS.FISH_P_GOLDEN if (hour < 10.0 or hour > 15.5) \
		else Config.DANGERS.FISH_P_DAY
	return rng.call() < golden


# --- Injury → infection -------------------------------------------------------
## Injury sources without wolves: the TS world.ts has exactly ONE addInjury
## call site (wolf bite) and fishRoll failure has no injury semantics, so per
## the scope directive we wire the machinery (addInjury/tickInjuries/
## treatInjury/sepsisDamagePerH) but invent no new injury sources.

static func add_injury(list: Array, label: String, severity: float) -> void:
	list.append({"severity": severity, "infected": false, "infection": 0.0, "label": label})


## Infection progression: untreated wounds + wet/cold raise risk; first aid
## (finite) cleans and halves severity. Sepsis damages health (caller applies).
static func tick_injuries(list: Array, dtGameH: float, rng: Callable) -> Array:
	var events: Array = []
	for inj in list:
		if not inj.infected:
			# ~5% per game hour untreated, scaled by severity
			if rng.call() < Config.DANGERS.INFECT_P_PER_H * (inj.severity / 50.0) * dtGameH:
				inj.infected = true
				events.append("Your %s is turning red and hot — infected." % inj.label)
		else:
			inj.infection = minf(100.0, inj.infection + Config.DANGERS.INFECTION_PER_H * dtGameH)
	return events


static func treat_injury(list: Array) -> bool:
	for inj in list:
		if inj.infected or inj.severity > Config.DANGERS.TREAT_SEVERITY_GT:
			inj.infected = false
			inj.infection = 0.0
			inj.severity = maxf(Config.DANGERS.TREAT_SEVERITY_FLOOR, inj.severity / 2.0)
			return true
	return false


## Health drain from sepsis (game hours). Out-heals natural regen: untreated
## sepsis is a death sentence — that's what makes first aid a real resource.
static func sepsis_damage_per_h(list: Array) -> float:
	var d := 0.0
	for inj in list:
		if inj.infected and inj.infection > Config.DANGERS.SEPSIS_INFECTION_GT:
			d += Config.DANGERS.SEPSIS_HP_PER_H
	return d
