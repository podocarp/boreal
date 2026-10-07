## BOREAL — hand-authored analytic terrain — port of terrain.ts.
## heightAt/zoneAt are pure functions shared by sim and render.
class_name Terrain

const LAKE := {"cx": 0.0, "cz": -150.0, "rx": 150.0, "rz": 90.0}
const CRASH := {"x": -20.0, "z": -62.0}


## Stream meanders x = f(z) from the ridge down to the lake.
static func streamX(z: float) -> float:
	return -35.0 + 0.15 * (z + 150.0) + 14.0 * sin(z * 0.02 + 0.4)


static func lakeT(x: float, z: float) -> float:
	var dx := (x - LAKE.cx) / LAKE.rx
	var dz := (z - LAKE.cz) / LAKE.rz
	return sqrt(dx * dx + dz * dz)


static func zoneAt(x: float, z: float) -> String:
	if lakeT(x, z) < 1.0:
		return "lake"
	if absf(x - streamX(z)) < 5.0 and z > -160.0:
		return "stream"
	if z > 110.0 and NoiseSim.fbm2(x * 0.01, z * 0.01, 77, 2) > 0.35:
		return "bog"
	if x < -140.0:
		return "ridge"
	return "forest"


## Terrain height in meters. Lake ice surface sits at y=0.
static func heightAt(x: float, z: float) -> float:
	# rolling boreal base
	var h := NoiseSim.fbm2(x * 0.004, z * 0.004, 11, 4) * 30.0 - 8.0
	h += NoiseSim.fbm2(x * 0.02, z * 0.02, 12, 3) * 3.0

	# western ridge rises
	h += NoiseSim.smoothstep(-120.0, -260.0, x) * 45.0

	# bog flattens toward y~1 with hummocks
	var bogMix := NoiseSim.smoothstep(100.0, 160.0, z) * 0.8
	h = h * (1.0 - bogMix) + (1.0 + NoiseSim.fbm2(x * 0.05, z * 0.05, 21, 2) * 2.5) * bogMix

	# stream channel carved down to lake level
	var chW := absf(x - streamX(z))
	if z > -160.0 and chW < 14.0:
		var carve := 1.0 - NoiseSim.smoothstep(5.0, 14.0, chW)
		var floor_ := maxf(-1.5, _heightAtLakeApproach(z))
		h = h * (1.0 - carve) + floor_ * carve

	# lake basin: flatten to ice at y=0
	var lt := lakeT(x, z)
	var lakeMix := 1.0 - NoiseSim.smoothstep(0.85, 1.15, lt)
	h = h * (1.0 - lakeMix)

	return h


## Stream bed falls gently from the ridge to the lake surface.
static func _heightAtLakeApproach(z: float) -> float:
	return -0.5 + NoiseSim.smoothstep(-160.0, 200.0, z) * 2.5


## Movement speed multiplier by zone (bog soaks you).
static func speedMulAt(zone: String) -> float:
	match zone:
		"bog":
			return 0.55
		"ridge":
			return 0.85
		"stream":
			return 0.7
		_:
			return 1.0
