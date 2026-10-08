## Camp placement: find the flattest spot near the (frozen) sim CRASH site by
## sampling Terrain.heightAt on a grid — no new height math, read-only.
## The sim's CRASH position itself is untouched; only camp VISUALS move.
class_name CampSite

const RADIUS := 10.0       # search window around CRASH (m); flattest ground
                           # near the wreck sits ~7-8 m west on the lake shelf
const GRID := 0.5          # sample step of the search grid (m)
const FOOTPRINT := 2.0     # half-size of the fire-ring footprint checked (m)
const STEP := 0.5          # footprint flatness sample step (m)


## Flatness of a spot: max-min heightAt over its footprint.
static func flatness(x: float, z: float) -> float:
	var lo := INF
	var hi := -INF
	var dx := -FOOTPRINT
	while dx <= FOOTPRINT + 1e-6:
		var dz := -FOOTPRINT
		while dz <= FOOTPRINT + 1e-6:
			var h := Terrain.heightAt(x + dx, z + dz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			dz += STEP
		dx += STEP
	return hi - lo


## Best camp center near CRASH: minimize footprint flatness; tie-break toward
## CRASH so the camp stays at the wreck. Deterministic (fixed grid, no rng).
static func find_center() -> Vector3:
	var best := Vector2(Terrain.CRASH.x, Terrain.CRASH.z)
	var best_score := INF
	var x := Terrain.CRASH.x - RADIUS
	while x <= Terrain.CRASH.x + RADIUS + 1e-6:
		var z := Terrain.CRASH.z - RADIUS
		while z <= Terrain.CRASH.z + RADIUS + 1e-6:
			var f := flatness(x, z)
			var d2 := (x - Terrain.CRASH.x) * (x - Terrain.CRASH.x) \
				+ (z - Terrain.CRASH.z) * (z - Terrain.CRASH.z)
			# flatness dominates; distance breaks near-ties (cm-scale epsilon)
			var score := f + d2 * 0.001
			if score < best_score:
				best_score = score
				best = Vector2(x, z)
			z += GRID
		x += GRID
	return Vector3(best.x, Terrain.heightAt(best.x, best.y), best.y)
