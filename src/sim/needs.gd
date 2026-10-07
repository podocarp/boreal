## BOREAL — needs & thermoregulation — port of needs.ts.
## dt is REAL seconds; convert to game hours via REAL_SECONDS_PER_GAME_HOUR.
class_name Needs

var hydration := 85.0
var hunger := 80.0
var energy := 90.0
var health := 100.0
var coreTemp := 37.0
var wetness := 0.1
var sleeping := false
var autoSip := true
var carriedWaterL := 0.0


static func create() -> Needs:
	return Needs.new()


class Env extends RefCounted:
	var airTempC := Config.WORLD.TEMP_BASE_C
	var windKmh := Config.WORLD.WIND_BASE_KMH
	var fireWarmth := 0.0
	var shelterInsul := 0.0


static func create_env() -> Env:
	return Env.new()


## Environment Canada windchill index; above 0 C returns air temp.
static func windchill(tempC: float, windKmh: float) -> float:
	if tempC >= 0.0:
		return tempC
	var v := maxf(4.8, windKmh)
	var vv := pow(v, 0.16)
	return 13.12 + 0.6215 * tempC - 11.37 * vv + 0.3965 * tempC * vv


## Diurnal air temp: cosine peaking at 14:00, coldest ~02:00.
static func airTempAt(hour: float, base: float, swing: float) -> float:
	var t := fmod(hour - 14.0 + 24.0, 24.0) / 24.0
	return base + swing * cos(t * PI * 2.0)


static func compute_debuffs(n: Needs) -> Dictionary:
	var N := Config.NEEDS
	var T := Config.THERMO
	var cold: bool = n.coreTemp < T.COLD_C
	var veryCold: bool = n.coreTemp < T.VERY_COLD_C
	var hypo: bool = n.coreTemp < T.HYPOTHERMIA_C
	var thirsty: bool = n.hydration < N.DEBUFF_FROM
	var hungry: bool = n.hunger < N.DEBUFF_FROM
	var sleepy: bool = n.energy < N.DEBUFF_FROM
	var shivering: bool = cold and not n.sleeping
	return {
		"steadiness": NoiseSim.clampf(1.0 - (0.35 if shivering else 0.0) - (0.3 if hypo else 0.0), 0.2, 1.0),
		"dexterity": NoiseSim.clampf(1.0 - (0.4 if veryCold else 0.0) - (0.3 if hypo else 0.0) - (0.15 if sleepy else 0.0), 0.15, 1.0),
		"strength": NoiseSim.clampf(1.0 - (0.3 if hungry else 0.0) - (0.25 if hypo else 0.0), 0.2, 1.0),
		"focus": NoiseSim.clampf(1.0 - (0.2 if thirsty else 0.0) - (0.25 if sleepy else 0.0) - (0.35 if hypo else 0.0), 0.15, 1.0),
		"shivering": shivering,
		"confusion": NoiseSim.clampf((T.HYPOTHERMIA_C - n.coreTemp) / 4.0, 0.2, 1.0) if hypo else 0.0,
		"drowsiness": NoiseSim.clampf((N.DEBUFF_FROM - n.energy) / N.DEBUFF_FROM, 0.0, 1.0),
	}


## Effective insulation: clothing base + shelter bonus, gutted by wetness.
static func insulationOf(n: Needs, env: Env) -> float:
	var T := Config.THERMO
	return NoiseSim.clampf(
		(T.BASE_INSULATION + env.shelterInsul * T.SHELTER_INSUL_BONUS)
			* (1.0 - n.wetness * T.WETNESS_INSUL_PENALTY),
		0.15, 2.5)


## Heat budget °C/h: positive = warming.
static func heatBudget(n: Needs, env: Env, feelsLikeC: float, moving: bool, sprinting: bool) -> float:
	var T := Config.THERMO
	var coldLoad := maxf(0.0, -feelsLikeC)
	var heatFuel := 1.0 if n.hunger > 25.0 else 0.6 + (n.hunger / 25.0) * 0.4
	var insul := insulationOf(n, env)
	var loss: float = (T.LOSS_K * coldLoad) / insul
	var exertion: float = T.EXERTION_HEAT * 2.0 if sprinting else (T.EXERTION_HEAT if moving else 0.0)
	var gain: float = env.fireWarmth * T.FIRE_HEAT_GAIN + exertion + T.METABOLIC_HEAT * heatFuel
	return gain - loss


## 0 at the critical band edge, 1 at zero.
static func _critical_depth(v: float) -> float:
	return (Config.NEEDS.CRITICAL_BAND - maxf(0.0, v)) / Config.NEEDS.CRITICAL_BAND


## Advance needs + thermoregulation by dt REAL seconds.
## Returns { "died": {cause, detail} | null, "events": [String] }.
static func tick(n: Needs, env: Env, dt: float, moving: bool, sprinting: bool, difficulty: String) -> Dictionary:
	var N := Config.NEEDS
	var T := Config.THERMO
	var events: Array[String] = []
	# dt is REAL seconds; convert to game hours via the time scale
	var h := dt / Config.TIME.REAL_SECONDS_PER_GAME_HOUR
	var dm := Config.difficulty_mul(difficulty)

	# --- energy (sleep restore is applied by world.step, not here) ---
	if not n.sleeping:
		var drain: float = N.ENERGY_DECAY_PER_H
		if sprinting:
			drain *= 2.2
		elif moving:
			drain *= 1.3
		n.energy = NoiseSim.clampf(n.energy - drain * dm * h, 0.0, 100.0)

	# --- hunger (shivering burns more; food = fuel for cold) ---
	var shivering: bool = n.coreTemp < T.COLD_C
	var hungerDrain: float = N.HUNGER_DECAY_PER_H * (N.SHIVER_HUNGER_MUL if shivering else 1.0)
	if sprinting:
		hungerDrain *= 1.6
	n.hunger = NoiseSim.clampf(n.hunger - hungerDrain * dm * h, 0.0, 100.0)

	# --- hydration + auto-sip (idle only) ---
	var thirstDrain: float = N.HYDRATION_DECAY_PER_H * (1.8 if sprinting else (1.25 if moving else 1.0))
	n.hydration = NoiseSim.clampf(n.hydration - thirstDrain * dm * h, 0.0, 100.0)
	if n.autoSip and not n.sleeping and not moving and n.hydration < N.AUTO_SIP_BELOW and n.carriedWaterL > 0.0:
		var points: float = minf(N.AUTO_SIP_POINTS_PER_H * h, 100.0 - n.hydration)
		var liters: float = points / N.HYDRATION_PER_LITER
		var sip := minf(liters, n.carriedWaterL)
		if sip > 1e-9:
			n.hydration = NoiseSim.clampf(n.hydration + sip * N.HYDRATION_PER_LITER, 0.0, 100.0)
			n.carriedWaterL = maxf(0.0, n.carriedWaterL - sip)

	# --- thermoregulation ---
	var feels := windchill(env.airTempC, env.windKmh)
	var budget := heatBudget(n, env, feels, moving, sprinting)
	var prev := n.coreTemp
	var dT: float = clampf(budget * h, -T.MAX_COOL_PER_H * h, T.MAX_WARM_PER_H * h)
	n.coreTemp = clampf(n.coreTemp + dT, 24.0, 38.5)

	if prev > T.COLD_C and n.coreTemp <= T.COLD_C:
		events.append("You start shivering — the cold is getting in.")
	if prev > T.VERY_COLD_C and n.coreTemp <= T.VERY_COLD_C:
		events.append("Hands clumsy, thoughts slow. Very cold.")
	if prev > T.HYPOTHERMIA_C and n.coreTemp <= T.HYPOTHERMIA_C:
		events.append("Hypothermia sets in — confusion, drowsiness.")

	# --- health: critical bands only ---
	if n.hydration < N.CRITICAL_BAND:
		n.health -= N.CRITICAL_THIRST_HP_PER_H * (1.0 + 5.0 * _critical_depth(n.hydration)) * dm * h
	if n.hunger < N.CRITICAL_BAND:
		n.health -= N.CRITICAL_HUNGER_HP_PER_H * (1.0 + 9.0 * _critical_depth(n.hunger)) * dm * h
	if n.coreTemp < T.HYPOTHERMIA_C:
		var sev: float = 3.0 if n.coreTemp < 30.0 else 1.0
		n.health -= T.HYPO_HP_PER_H * sev * dm * h
	if n.hydration > 50.0 and n.hunger > 50.0 and n.coreTemp > T.COLD_C and n.energy > 20.0 and n.health < 100.0:
		n.health += N.REGEN_HP_PER_H * h
	n.health = clampf(n.health, 0.0, 100.0)

	var died: Variant = null
	if n.health <= 0.0:
		if n.coreTemp < T.HYPOTHERMIA_C:
			died = {"cause": "hypothermia", "detail": "core temp %.1f °C" % n.coreTemp}
		elif n.hydration < N.CRITICAL_BAND:
			died = {"cause": "dehydration", "detail": "water ran out"}
		elif n.hunger < N.CRITICAL_BAND:
			died = {"cause": "starvation", "detail": "calories ran out"}
		else:
			died = {"cause": "exposure", "detail": "the north wore you down"}
	return {"died": died, "events": events}
