## BOREAL — deterministic config (port of boreal-src/src/sim/config.ts)
## All tunables live here. Rates are per GAME HOUR; dt is REAL seconds.
class_name Config

const SIM_DT := 0.25  # fixed sim timestep, real seconds

const TIME := {
	"REAL_SECONDS_PER_GAME_HOUR": 30.0,
	"RESCUE_WINDOW_DAY": 7,
}

const RESCUE := {
	"COLLAPSE_DAY": 10,
	"FLARE_WINDOW_H": 1.0,
}

const WORLD := {
	"SIZE_M": 400.0,
	"TEMP_BASE_C": -12.0,
	"WIND_BASE_KMH": 10.0,
}

const PLAYER := {
	"WALK_SPEED_MPS": 1.4,
	"RUN_SPEED_MPS": 3.2,
	"EYE_HEIGHT_M": 1.65,
	"RADIUS_M": 0.35,
	"TURN_RATE_RADPS": 10.0,
}

const NEEDS := {
	"HYDRATION_DECAY_PER_H": 1.75,
	"HUNGER_DECAY_PER_H": 1.0,
	"ENERGY_DECAY_PER_H": 4.0,
	"SHIVER_HUNGER_MUL": 1.5,
	"SLEEP_RESTORE_PER_H": 15.0,
	"DEBUFF_FROM": 45.0,
	"CRITICAL_BAND": 15.0,
	"CRITICAL_THIRST_HP_PER_H": 1.5,
	"CRITICAL_HUNGER_HP_PER_H": 0.5,
	"REGEN_HP_PER_H": 2.0,
	"AUTO_SIP_BELOW": 60.0,
	"AUTO_SIP_POINTS_PER_H": 35.0,
	"HYDRATION_PER_LITER": 50.0,
	"CRAVING_K": 0.8,
	"DIFF": {"bushman": 0.7, "survivorman": 1.3},
}

const THERMO := {
	"COLD_C": 36.0,
	"VERY_COLD_C": 34.5,
	"HYPOTHERMIA_C": 33.0,
	"LOSS_K": 0.07,
	"BASE_INSULATION": 1.0,
	"SHELTER_INSUL_BONUS": 0.8,
	"WETNESS_INSUL_PENALTY": 0.6,
	"METABOLIC_HEAT": 0.6,
	"EXERTION_HEAT": 1.2,
	"FIRE_HEAT_GAIN": 2.6,
	"MAX_COOL_PER_H": 2.5,
	"MAX_WARM_PER_H": 1.5,
	"HYPO_HP_PER_H": 8.0,
}

const CLIMATE := {
	"TEMP_SWING_C": 6.0,
	"WIND_NIGHT_MUL": 1.4,
}


static func difficulty_mul(d: String) -> float:
	if d == "bushman":
		return NEEDS.DIFF.bushman
	if d == "survivorman":
		return NEEDS.DIFF.survivorman
	return 1.0
