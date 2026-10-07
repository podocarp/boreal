## BOREAL — pure simulation core — port of world.ts (phase 1: no wolves/snares/
## injuries; those hooks return "not implemented"). dt is REAL seconds everywhere;
## convert to game hours only via REAL_SECONDS_PER_GAME_HOUR.
class_name WorldSim

var seed: int
var t := 0.0                 # elapsed sim seconds
var hourOfDay := 8.0
var day := 1
var player := {}             # {x,y,z,yaw,speed,moving,zone}
var colliders: Array = []
var needs: Needs
var env: Needs.Env
var difficulty := "ranger"
var log: Array = []          # [{t, day, msg}]
var dead: Variant = null     # {cause, detail}
var inventory := {}
var interactables: Array = []
var task: Variant = null     # WorkTask dict
var fires: Array = []
var nextFireId := 1
var shelters: Array = []
var nextShelterId := 1
var sleep := {}
var shouting := false
var wolvesOut := false
var rngN := 0
var rescue := {}
var signalFireId: Variant = null
var flareAgeH: Variant = null
var stillH := 0.0
var rescued: Variant = null


func _init(p_seed := 1, p_difficulty := "ranger") -> void:
	seed = p_seed
	difficulty = p_difficulty
	var props := Scatter.scatter(seed)
	colliders = Scatter.colliders_from(props)
	needs = Needs.create()
	env = Needs.create_env()
	player = {"x": Terrain.CRASH.x, "y": 0.0, "z": Terrain.CRASH.z,
		"yaw": 0.0, "speed": 0.0, "moving": false, "zone": "lake"}
	log = [{"t": 0.0, "day": 1,
		"msg": "You crawl from the wreck. The radio is dead. Search pattern passes near day 7."}]
	interactables = Interact.build_interactables(seed, props)
	sleep = ShelterSim.create_sleep()
	rescue = RescueSim.create_rescue()


func push_log(msg: String) -> void:
	log.append({"t": t, "day": day, "msg": msg})
	if log.size() > 200:
		log.pop_front()


## dt (real sim seconds) -> game hours.
func dt_game_h(dt: float) -> float:
	return dt / Config.TIME.REAL_SECONDS_PER_GAME_HOUR


## Deterministic roll from the world's RNG stream (serializable).
func roll() -> float:
	rngN = Rng.i32(rngN + 1)
	return Rng.make_rng(Rng.u32(Rng.i32(seed * 0x9E3779B9) ^ Rng.i32(rngN * 0x85EBCA6B))).next()


## Advance the world by one fixed tick (dt REAL seconds). Order mirrors world.ts step().
func step(dt := Config.SIM_DT, sprinting := false) -> void:
	t += dt
	hourOfDay += dt / Config.TIME.REAL_SECONDS_PER_GAME_HOUR
	if hourOfDay >= 24.0:
		hourOfDay -= 24.0
		day += 1

	# environment at player: diurnal temp, wind (lake/ridge exposed, forest sheltered)
	var night := hourOfDay < 9.0 or hourOfDay > 17.0
	env.airTempC = Needs.airTempAt(hourOfDay, Config.WORLD.TEMP_BASE_C, Config.CLIMATE.TEMP_SWING_C)
	var zone_wind := 1.35 if (player.zone == "lake" or player.zone == "ridge") else (0.6 if player.zone == "forest" else 1.0)
	var storm: Variant = ShelterSim.active_storm(day, hourOfDay)
	env.windKmh = Config.WORLD.WIND_BASE_KMH * zone_wind * (Config.CLIMATE.WIND_NIGHT_MUL if night else 1.0) * ShelterSim.storm_wind_mul(storm)

	# flare aging + stillness (tracks in snow fade)
	if flareAgeH != null:
		flareAgeH += dt_game_h(dt)
	stillH = 0.0 if player.moving else stillH + dt_game_h(dt)

	if dead != null or rescued != null:
		return

	# storm wetness: wet snow soaks clothing unless sheltered
	if storm != null:
		var sheltered := ShelterSim.shelter_warmth_at(shelters, player.x, player.z) > 0.5 \
			or _near_lit_fire(3.0)
		var gain := ShelterSim.storm_wetness_per_h(storm) * (0.25 if sheltered else 1.0) * dt_game_h(dt)
		needs.wetness = minf(1.0, needs.wetness + gain)
	# drying by fire (slow)
	if _near_lit_fire(3.0) and needs.wetness > 0.0:
		needs.wetness = maxf(0.0, needs.wetness - 0.1 * dt_game_h(dt))

	# fires burn down + warmth at player
	for f in fires:
		if FireSim.tick_fire(f, dt_game_h(dt), env.windKmh):
			push_log("Your fire has gone out.")
	env.fireWarmth = FireSim.max_warmth(fires, player.x, player.z)
	env.shelterInsul = ShelterSim.shelter_warmth_at(shelters, player.x, player.z)

	# sleep: energy restore scaled by warmth/food (restore lives HERE, not in needs.tick)
	if needs.sleeping:
		sleep.hours += dt_game_h(dt)
		var warm := needs.coreTemp > Config.THERMO.COLD_C or env.shelterInsul > 0.5 or env.fireWarmth > 0.25
		var restore := ShelterSim.sleep_restore_per_h(warm, needs.hunger > 25.0)
		needs.energy = minf(100.0, needs.energy + restore * dt_game_h(dt))
		var wake := ShelterSim.should_wake(sleep, needs.energy, hourOfDay)
		if wake != "":
			needs.sleeping = false
			sleep.active = false
			push_log(wake)

	# [phase 2 stubs: snares, wolves, injuries — no rolls while empty]

	var res := Needs.tick(needs, env, dt, player.moving, sprinting, difficulty)
	for e in res.events:
		push_log(e)
	if res.died != null:
		dead = res.died
		push_log("You died of %s (%s)." % [res.died.cause, res.died.detail])

	# [phase 2 stub: sepsis damage AFTER regen]

	# rescue search passes + collapse deadline
	var pass_res := RescueSim.check_pass(rescue, day, hourOfDay,
		storm.severity if storm != null else 0.0,
		detection_input, roll)
	if pass_res.fired:
		if pass_res.get("scrubbed", false):
			push_log("The %s search is scrubbed — whiteout. No flight." % pass_res.kind)
		elif pass_res.get("spotted", false):
			rescued = {"day": day, "kind": pass_res.kind,
				"detail": "The pilot sees your smoke and banks toward you."}
			push_log("RESCUED — engine noise swells out of the south.")
		else:
			push_log("The %s pass goes overhead. They don't see you." % pass_res.kind)
	if rescued == null and RescueSim.check_collapse(rescue, day):
		dead = {"cause": "exposure", "detail": "Ten days. The search gave up. So did you."}
		push_log("Day 10. No engines. The cold wins by default.")


## What the pilot would see at a search pass.
func detection_input() -> Dictionary:
	var signal_fire: Variant = null
	if signalFireId != null:
		for f in fires:
			if f.id == signalFireId and f.lit:
				signal_fire = f
				break
	var open_ground: bool = player.zone == "lake" or player.zone == "ridge"
	var any_shelter_complete := false
	for s in shelters:
		if s.complete:
			any_shelter_complete = true
			break
	return {
		"signalSmoke": signal_fire != null,
		"anyFire": _any_lit_fire(),
		"flareUsedRecently": flareAgeH != null and flareAgeH < Config.RESCUE.FLARE_WINDOW_H,
		"openGround": open_ground,
		"onRidge": player.zone == "ridge",
		"shelterVisible": any_shelter_complete,
		"movedRecently": stillH < 1.0,
	}


func feels_like() -> float:
	return Needs.windchill(env.airTempC, env.windKmh)


func _dist_fire(f: Dictionary) -> float:
	return sqrt((f.x - player.x) * (f.x - player.x) + (f.z - player.z) * (f.z - player.z))


func _near_lit_fire(max_dist: float) -> bool:
	for f in fires:
		if f.lit and _dist_fire(f) < max_dist:
			return true
	return false


func _any_lit_fire() -> bool:
	for f in fires:
		if f.lit:
			return true
	return false


func nearest_fire(max_dist := INF) -> Variant:
	var best: Variant = null
	var bd := max_dist
	for f in fires:
		var d := _dist_fire(f)
		if d < bd:
			bd = d
			best = f
	return best
