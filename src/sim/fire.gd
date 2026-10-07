## Fire model — port of fire.ts.
class_name FireSim

const FUEL_VALUE := {"deadfall": 25, "kindling": 8}
const BURN_RATE := [0.0, 30.0, 18.0, 10.0, 7.0]  # %/h by stage
const WARMTH_RADIUS := [0.0, 3.0, 4.5, 6.0, 7.5]  # m by stage


## Fire dict: {id, x, z, fuel, lit}
static func make(id: int, x: float, z: float, fuel: float, lit: bool) -> Dictionary:
	return {"id": id, "x": x, "z": z, "fuel": fuel, "lit": lit}


static func fire_stage(f: Dictionary) -> int:
	if not f.lit or f.fuel <= 0.0:
		return 0
	if f.fuel < 15.0:
		return 1
	if f.fuel < 40.0:
		return 2
	if f.fuel < 75.0:
		return 3
	return 4


static func add_fuel(f: Dictionary, item: String, n := 1) -> void:
	f.fuel = minf(100.0, f.fuel + FUEL_VALUE[item] * n)
	f.lit = true


## 0..1 warmth at a point from one fire.
static func fire_warmth(f: Dictionary, px: float, pz: float) -> float:
	var stage := fire_stage(f)
	if stage == 0:
		return 0.0
	var r: float = WARMTH_RADIUS[stage]
	var d := sqrt((f.x - px) * (f.x - px) + (f.z - pz) * (f.z - pz))
	if d > r:
		return 0.0
	return minf(1.0, (1.0 - d / r) * (stage / 4.0 + 0.35))


static func max_warmth(fires: Array, px: float, pz: float) -> float:
	var m := 0.0
	for f in fires:
		m = maxf(m, fire_warmth(f, px, pz))
	return m


## Tick one fire by game-hours. Returns true if it just went out.
static func tick_fire(f: Dictionary, dt_game_hours: float, wind_kmh: float) -> bool:
	if not f.lit or f.fuel <= 0.0:
		return false
	var stage := fire_stage(f)
	var wind_burn := 1.0 + maxf(0.0, wind_kmh - 15.0) * 0.01
	f.fuel = maxf(0.0, f.fuel - BURN_RATE[stage] * wind_burn * dt_game_hours)
	if f.fuel <= 0.0:
		f.lit = false
		return true
	return false


## Friction-fire roll. rng is a Callable returning float.
static func friction_roll(dexterity: float, hand_wetness: float, core_temp: float,
		wood_dry: bool, rng: Callable) -> bool:
	var p := 0.6
	p += (dexterity - 0.7) * 0.75
	p -= hand_wetness * 0.35
	if core_temp < 34.5:
		p -= 0.2
	if not wood_dry:
		p -= 0.3
	p = maxf(0.05, minf(0.9, p))
	return rng.call() < p
