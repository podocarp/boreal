## AudioMap — the PURE sim-state -> sound mapping (no Node, no wall-clock,
## no audio APIs; headless-testable). AudioDirector consumes its output each
## tick; tests craft state dicts and assert on the mapping directly.
##
## Input state dict (all plain values; see from_world() for the sim extractor):
##   fire_warmth:    float 0..1  (env.fireWarmth — fire warmth AT the player)
##   wind_kmh:       float       (env.windKmh — already storm-multiplied)
##   storm_severity: float 0..1  (active storm severity, 0 when none)
##   moving:         bool        (player.moving)
##   speed:          float m/s   (player.speed)
##   zone:           String      (player.zone: forest/lake/ridge/...)
##   game_state:     int         (GameState.State; PLAYING gates everything)
##
## Output: { "loops": {name: vol 0..1}, "step_interval": float,
##           "step_vol": float }
## One-shots (ui_confirm / plane_flyby / death_sting) are EVENT-driven, not
## level-driven — AudioDirector routes them off GameState transitions and
## action signals, so they are deliberately absent from the mapping.
##
## NOTE: wolves are CUT from the MVP (owner directive 2026-10-10: solo + slow
## environmental death is the tension), so there is no growl mapping — the TS
## wolf FSM stays unported on purpose.
class_name AudioMap


const LOOP_FIRE := "fire_crackle"
const LOOP_WIND := "wind_loop"

const EVENT_CONFIRM := "ui_confirm"
const EVENT_FLYBY := "plane_flyby"
const EVENT_DEATH := "death_sting"
const EVENT_FOOTSTEP := "footstep"

## Stream registry (file names under res://assets/audio/, minus .ogg).
const LOOP_NAMES := [LOOP_FIRE, LOOP_WIND]
const EVENT_STREAMS := [EVENT_CONFIRM, EVENT_FLYBY, EVENT_DEATH]
const FOOTSTEP_VARIANTS := 5

## Tuning (audible ranges, not sim values — the sim is never read back).
const WIND_FLOOR_KMH := 12.0   # below this the wind bed is inaudible
const WIND_FULL_KMH := 38.0    # windKmh at/above this = full wind volume
const STEP_RUN_MPS := 2.2      # cadence floor: interval at/above this speed
const STEP_IDLE_MPS := 0.3     # cadence ceiling at walking start
const STEP_INTERVAL_RUN := 0.28
const STEP_INTERVAL_WALK := 0.52
const STEP_VOL_BASE := 0.55
const STEP_VOL_ICE := 0.75      # lake ice crunches louder than powder
const STEP_VOL_FOREST := 0.45   # muffled under the canopy


## Wind bed volume from windKmh (linear between floor and full). Storms enter
## this via env.windKmh = WIND_BASE * zone_mul * storm_wind_mul(severity),
## so severity 0.9 on an exposed tile lands ~0.85.
static func wind_volume(wind_kmh: float) -> float:
	return clampf((wind_kmh - WIND_FLOOR_KMH) / (WIND_FULL_KMH - WIND_FLOOR_KMH),
		0.0, 1.0)


## Fire crackle bed volume = warmth at the player (0 off, 1 right at a big fire).
static func fire_volume(fire_warmth: float) -> float:
	return clampf(fire_warmth, 0.0, 1.0)


## Footstep interval from speed (walk -> run cadence). 0 = not moving.
static func footstep_interval(speed: float) -> float:
	if speed <= 0.0:
		return 0.0
	var t := clampf((speed - STEP_IDLE_MPS) / (STEP_RUN_MPS - STEP_IDLE_MPS), 0.0, 1.0)
	return lerpf(STEP_INTERVAL_WALK, STEP_INTERVAL_RUN, t)


## Footstep volume from surface zone.
static func footstep_volume(zone: String) -> float:
	match zone:
		"lake":
			return STEP_VOL_ICE
		"forest":
			return STEP_VOL_FOREST
		_:
			return STEP_VOL_BASE


## The central pure mapping. Deterministic: same state dict -> same result.
static func map_state(s: Dictionary) -> Dictionary:
	var loops := {}
	var playing: bool = int(s.get("game_state", 1)) == 1  # GameState.State.PLAYING
	if playing:
		var fv := fire_volume(float(s.get("fire_warmth", 0.0)))
		if fv > 0.0:
			loops[LOOP_FIRE] = fv
		var wv := wind_volume(float(s.get("wind_kmh", 0.0)))
		if wv > 0.0:
			loops[LOOP_WIND] = wv
	var speed := float(s.get("speed", 0.0))
	var moving: bool = bool(s.get("moving", false)) and playing
	return {
		"loops": loops,
		"step_interval": footstep_interval(speed) if moving else 0.0,
		"step_vol": footstep_volume(String(s.get("zone", ""))) if moving else 0.0,
	}


## Extract the mapping input from a WorldSim + GameState.State. Pure read of
## sim fields (storm severity recomputed from the frozen schedule, same call
## the sim itself makes in step()).
static func from_world(w: WorldSim, game_state: int) -> Dictionary:
	var storm: Variant = ShelterSim.active_storm(w.day, w.hourOfDay)
	return {
		"fire_warmth": w.env.fireWarmth,
		"wind_kmh": w.env.windKmh,
		"storm_severity": float(storm.severity) if storm != null else 0.0,
		"moving": w.player.moving,
		"speed": w.player.speed,
		"zone": w.player.zone,
		"game_state": game_state,
	}
