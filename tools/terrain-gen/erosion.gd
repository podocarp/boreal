## Hydraulic (particle) + thermal (talus creep) erosion. Operates in-place on a
## PackedFloat32Array heightmap (row-major, size*size). Fully seeded/deterministic:
## same heights + same seed => byte-identical result.
class_name Erosion

const GRAVITY := 9.81
const EVAPORATION := 0.005   # water depth loss per step
const CAPACITY_MULT := 4.0   # sediment capacity multiplier
const EROSION_SPEED := 0.05  # fraction of (capacity - sediment) eroded per step
const DEPOSIT_RATE := 0.25   # fraction of excess sediment deposited per step
const MAX_STEPS := 512       # per-particle lifetime cap

# 8-neighborhood in fixed order (deterministic tie-break: first lowest wins).
const NX: Array[int] = ([1, -1, 0, 0, 1, 1, -1, -1])
const NY: Array[int] = ([0, 0, 1, -1, 1, -1, 1, -1])


## Particle hydraulic erosion. `particles` drops, each starting at a random
## position with water=1.0. Returns total sediment moved (for stats).
static func hydraulic(heights: PackedFloat32Array, size: int, seed: int, particles: int) -> float:
	var rng := Rng.make_rng(seed)
	var moved := 0.0
	for p in particles:
		var x := rng.next() * float(size - 2) + 0.5
		var y := rng.next() * float(size - 2) + 0.5
		var water := 1.0
		var sediment := 0.0
		var speed := 1.0
		for step in MAX_STEPS:
			var ix := int(x)
			var iy := int(y)
			var idx := iy * size + ix
			var h := heights[idx]
			# lowest of 8 neighbors (strictly lower wins; fixed order tie-break)
			var best := -1
			var best_h := h
			for n in 8:
				var nx := ix + NX[n]
				var ny := iy + NY[n]
				if nx < 1 or ny < 1 or nx >= size - 1 or ny >= size - 1:
					continue
				var nh := heights[ny * size + nx]
				if nh < best_h:
					best_h = nh
					best = n
			if best < 0:
				# local minimum: drop sediment here, particle dies
				var dep := sediment * 0.5
				heights[idx] += dep
				sediment -= dep
				moved += dep
				break
			var drop := h - best_h
			speed = sqrt(speed * speed + drop * GRAVITY) * 0.95
			var capacity := maxf(drop, 0.01) * speed * water * CAPACITY_MULT
			if sediment > capacity:
				var d := (sediment - capacity) * DEPOSIT_RATE
				heights[idx] += d
				sediment -= d
				moved += d
			else:
				var e := minf((capacity - sediment) * EROSION_SPEED, drop * 0.5)
				heights[idx] -= e
				sediment += e
				moved += e
			water *= 1.0 - EVAPORATION
			if water < 0.01:
				break
			x += float(NX[best])
			y += float(NY[best])
	return moved


## Thermal erosion: talus-angle creep over `passes` row-major sweeps.
## `talus` = max stable height difference between adjacent cells (meters).
static func thermal(heights: PackedFloat32Array, size: int, passes := 4, talus := 0.15, k := 0.25) -> void:
	for pass_i in passes:
		for y in size:
			for x in size:
				var idx := y * size + x
				var h := heights[idx]
				# east and south neighbors only (each pair handled once per sweep)
				if x + 1 < size:
					_couple(heights, idx, idx + 1, talus, k)
				if y + 1 < size:
					_couple(heights, idx, idx + size, talus, k)


static func _couple(heights: PackedFloat32Array, a: int, b: int, talus: float, k: float) -> void:
	var d := heights[a] - heights[b]
	var ad := absf(d)
	if ad <= talus:
		return
	var move := (ad - talus) * 0.5 * k
	if d > 0.0:
		heights[a] -= move
		heights[b] += move
	else:
		heights[a] += move
		heights[b] -= move
