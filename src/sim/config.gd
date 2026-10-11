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
	# DIVERGENCE from TS (survivability rebalance 2026-10-11): 4.0 -> 2.5.
	# Energy is SOFT (Project Zomboid model): it never blocks walking, it
	# degrades you on a ladder (dexterity, move speed, sprint lockout) and
	# never forces sleep or incapacitates (owner directive 2026-10-11).
	"ENERGY_DECAY_PER_H": 2.5,
	"SHIVER_HUNGER_MUL": 1.5,
	"SLEEP_RESTORE_PER_H": 15.0,
	"DEBUFF_FROM": 45.0,
	"CRITICAL_BAND": 15.0,
	"CRITICAL_THIRST_HP_PER_H": 1.5,
	# DIVERGENCE from TS (weight-based calorie model, owner directive
	# 2026-10-11 v2): CRITICAL_HUNGER_HP_PER_H removed — an empty stomach no
	# longer drains health directly. Hunger-at-0 burns body MASS (see the
	# WEIGHT block); only deep mass loss (malnutrition cutoff) drains health.
	"REGEN_HP_PER_H": 2.0,
	# DIVERGENCE from TS (survivability rebalance 2026-10-11): auto-sip fires
	# on ALL movement (sitting/walking/running are all fine), suppressed only
	# while preoccupied (task in progress) or asleep. Sip = half a bottle
	# (a water unit is 1 L -> 0.5 L = 25 pts), clamped to carried amount.
	# With AUTO_SIP_BELOW at 50 the sip lands you ~75, so it is self-limiting
	# (no per-tick chug loop).
	"AUTO_SIP_BELOW": 50.0,
	"AUTO_SIP_LITER": 0.5,
	"HYDRATION_PER_LITER": 50.0,
	"CRAVING_K": 0.8,
	"DIFF": {"bushman": 0.7, "survivorman": 1.3},
	# Stamina ladder (survivability rebalance 2026-10-11):
	"SPRINT_LOCKOUT_ENERGY": 15.0,   # below this you cannot sprint
	"WALK_SLOW_AT_ZERO": 0.3,        # up to -30% move speed at energy 0
	"HUNGRY_DEX_PENALTY": 0.15,      # starving slows your hands (Zomboid: hungry != frozen)
	# Owner directive 2026-10-11 (supersedes the collapse spec): NO
	# collapse/pass-out mechanic — "passing out simply means death in a
	# survival situation". Energy is pure performance (work speed, walk
	# speed, sprint lockout) and never stops or incapacitates the player.
	# There is deliberately no forced-sleep path anywhere in the sim.
	#
	# --- Weight-based calorie model (owner directive 2026-10-11 v2) ---
	# No "fat reserve" bar: the internal calorie counter surfaces as WEIGHT.
	# An average adult starts at 80 kg; an empty stomach burns body mass.
	# KCAL_PER_KG = 7700 is the real energy density of 1 kg of body tissue
	# (standard ~7000-7700 kcal figure) and BASE_DEFICIT_KCAL_PER_DAY = 2500
	# is the real adult deficit (0.32 kg/day). The game compresses that to
	# STARVE_KG_PER_DAY (~10x game scale) so a never-eats player crosses the
	# malnutrition cutoff around day 8-11 of the 10-day run: starvation is a
	# real tail risk, hypothermia stays the #1 killer.
	"WEIGHT_START_KG": 80.0,
	"KCAL_PER_KG": 7700.0,
	"BASE_DEFICIT_KCAL_PER_DAY": 2500.0,
	"STARVE_KG_PER_DAY": 3.2,        # game-scale base; shiver/activity muls stack on top
	"FILL_KG_PER_DAY": 0.4,          # surplus->mass cap: no binge back to 80 overnight
	"WEIGHT_THIN_KG": 74.0,          # -7.5%: mild lethargy (small speed penalties)
	"WEIGHT_WEAK_KG": 68.0,          # -15%: weakened (bigger penalties, energy drains faster)
	"WEIGHT_MALNOURISHED_KG": 60.0,  # -25%: critical (penalties maxed + health drain)
	"STARVATION_HP_PER_H": 1.5,
	"WEAK_ENERGY_MUL": 1.3,          # weakened: energy drains faster
	"WALK_SLOW_THIN": 0.07,
	"WALK_SLOW_WEAK": 0.15,
	"WALK_SLOW_MALNOURISHED": 0.25,
	# Sleep deprivation (Change 3): waking streaks past DROWSY_AFTER_H grow a
	# drowsiness debuff (reuses the drowsiness channel) up to full at
	# DROWSY_FULL_H; sleeping (voluntary) resets the streak.
	"DROWSY_AFTER_H": 30.0,
	"DROWSY_FULL_H": 42.0,
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
	# Weight model: burning body mass (empty stomach) adds a SMALL metabolic
	# heat contribution — modest on purpose, cold stays the main killer.
	"METABOLIC_BURN_HEAT": 0.15,
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

# Food & dangers (dangers.ts S6; wolves deliberately cut from the MVP).
const DANGERS := {
	"HARE_SIGN_BAND_M": 25.0,       # hareSignAt: sign dies off ±25 m from stream
	"SNARE_BASE_P": 0.06,           # catch prob per game hour at quality+0.3 = 1
	"SNARE_FRESH_H": 24.0,          # bait freshness plateau (game hours)
	"SNARE_FRESH_DECAY_H": 48.0,    # freshness decay past the plateau
	"SNARE_FRESH_MIN": 0.25,        # freshness floor
	"SNARE_SNOW_MUL": 0.5,          # deep-snow (active storm) catch multiplier
	"SNARE_SET_MIN_DIST_M": 8.0,    # overlapping runs spook the hares
	"SNARE_COLLECT_DIST_M": 3.0,    # collect game within reach of the snare
	"FISH_HOLE_ZS": [-150, -120, -60, 20, 90],
	"FISH_HOLE_USES": 4,
	"FISH_REACH_M": 4.0,
	"FISH_P_GOLDEN": 0.65,          # dawn/dusk bite
	"FISH_P_DAY": 0.4,
	"INFECT_P_PER_H": 0.05,         # untreated infection prob per game hour
	"INFECTION_PER_H": 2.5,         # infection progression per game hour
	"SEPSIS_INFECTION_GT": 60.0,    # sepsis kicks in above this
	"SEPSIS_HP_PER_H": 6.0,         # health drain per game hour (out-heals regen 2/h)
	"TREAT_SEVERITY_GT": 30.0,      # treatInjury targets infected or severity > 30
	"TREAT_SEVERITY_FLOOR": 5.0,    # treated severity floor (halved otherwise)
}


static func difficulty_mul(d: String) -> float:
	if d == "bushman":
		return NEEDS.DIFF.bushman
	if d == "survivorman":
		return NEEDS.DIFF.survivorman
	return 1.0
