## Shelter + sleep + storms — port of shelter.ts.
class_name ShelterSim

const SHELTER_STEPS := ["site", "frame", "ribs", "insulation", "mulch", "bedding"]


static func score_site(x: float, z: float, seed: int) -> Dictionary:
	var zone := Terrain.zoneAt(x, z)
	var parts := {}
	var warnings: Array[String] = []

	parts.wind = 1.0 if zone == "forest" else (0.6 if zone == "bog" else (0.15 if zone == "ridge" or zone == "lake" else 0.5))
	if parts.wind < 0.4:
		warnings.append("Exposed to the wind here.")

	# water within 60 m?
	var near_water := sqrt(x * x + (z + 150.0) * (z + 150.0)) < 170.0 if z < -60.0 else true
	parts.water = 1.0 if near_water else 0.3
	if not near_water:
		warnings.append("Water is a long carry.")

	# fuel: forest density proxy
	var density := NoiseSim.valueNoise2(x * 0.02, z * 0.02, seed + 55)
	parts.fuel = (0.6 + density * 0.4) if zone == "forest" else (0.5 if zone == "bog" else 0.2)
	if parts.fuel < 0.4:
		warnings.append("Standing dead fuel is scarce.")

	# widowmakers
	var widow := NoiseSim.valueNoise2(x * 0.08, z * 0.08, seed + 71)
	parts.widowmaker = 0.2 if widow > 0.8 else 1.0
	if parts.widowmaker < 1.0:
		warnings.append("Dead standing trees overhead — widowmakers!")

	# bog floor = wet
	parts.dry = 0.3 if zone == "bog" else 1.0
	if parts.dry < 1.0:
		warnings.append("Ground stays wet here.")

	var total: float = parts.wind * 0.3 + parts.water * 0.2 + parts.fuel * 0.2 \
		+ parts.widowmaker * 0.15 + parts.dry * 0.15
	return {"total": total, "parts": parts, "warnings": warnings}


## Insulation 0..1 from build progress x site quality. Shelter dict: {id,x,z,step,siteQuality,complete}
static func shelter_insul(s: Variant) -> float:
	if s == null:
		return 0.0
	var progress := float(s.step) / float(SHELTER_STEPS.size())
	return progress * (0.45 + 0.55 * s.siteQuality)


## Warmth bonus at a shelter point (player must be within 2.5 m).
static func shelter_warmth_at(shelters: Array, px: float, pz: float) -> float:
	var best := 0.0
	for s in shelters:
		if sqrt((s.x - px) * (s.x - px) + (s.z - pz) * (s.z - pz)) < 2.5:
			best = maxf(best, shelter_insul(s))
	return best


# --- Sleep ---

static func create_sleep() -> Dictionary:
	return {"active": false, "hours": 0.0}


static func can_sleep() -> bool:
	return true  # sleeping anywhere is possible — that's the gamble


## Energy restore per game-hour while sleeping.
static func sleep_restore_per_h(warm: bool, fed: bool) -> float:
	return Config.NEEDS.SLEEP_RESTORE_PER_H * (1.0 if warm else 0.35) * (1.0 if fed else 0.6)


static func should_wake(sleep: Dictionary, energy: float, hour_of_day: float) -> String:
	if energy >= 100.0:
		return "You wake rested."
	if hour_of_day >= 8.0 and hour_of_day < 12.0 and sleep.hours > 2.0:
		return "Dawn. You wake stiff and cold."
	return ""


# --- Storms (scripted weather events) ---

static func storm_schedule() -> Array:
	return [
		{"day": 2, "startHour": 20.0, "durationH": 6.0, "severity": 0.45},
		{"day": 4, "startHour": 18.0, "durationH": 9.0, "severity": 0.85},
	]


static func active_storm(day: int, hour: float) -> Variant:
	for s in storm_schedule():
		if day == s.day and hour >= s.startHour and hour <= s.startHour + s.durationH:
			return s
	return null


static func storm_wind_mul(s: Variant) -> float:
	return 1.0 + s.severity * 1.6 if s != null else 1.0


static func storm_wetness_per_h(s: Variant) -> float:
	return 0.12 * s.severity if s != null else 0.0
