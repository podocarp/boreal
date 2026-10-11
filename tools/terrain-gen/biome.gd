## Biome classification: pure functions over (height, slope, moisture).
## Deterministic; no state. moisture map = second seeded fBm.
class_name Biome

enum { WATER, GRASS, FOREST, ROCK, SNOW }

const NAMES := ["water", "grass", "forest", "rock", "snow"]

const SNOW_LINE := 34.0     # meters; snow ONLY at/above this elevation
const ROCK_SLOPE := 0.9     # gradient magnitude (m/m) -> bare rock
const ROCK_SLOPE_HIGH := 0.5
const ROCK_HEIGHT := 26.0   # steep + high -> rock
const MOISTURE_FOREST := 0.55


## Pure classifier. water_level in meters.
static func biome(height: float, slope: float, moisture: float, water_level := 12.0) -> int:
	if height < water_level:
		return WATER
	if height >= SNOW_LINE:
		return SNOW
	if slope > ROCK_SLOPE or (height >= ROCK_HEIGHT and slope > ROCK_SLOPE_HIGH):
		return ROCK
	if moisture > MOISTURE_FOREST:
		return FOREST
	return GRASS


## Gradient magnitude (m/m) at cell (x,y) via central differences on a
## row-major size*size heightmap with `cell` meter spacing.
static func slope_at(heights: PackedFloat32Array, size: int, x: int, y: int, cell: float) -> float:
	var xm := maxi(0, x - 1)
	var xp := mini(size - 1, x + 1)
	var ym := maxi(0, y - 1)
	var yp := mini(size - 1, y + 1)
	var dx := (heights[y * size + xp] - heights[y * size + xm]) / (float(xp - xm) * cell)
	var dy := (heights[yp * size + x] - heights[ym * size + x]) / (float(yp - ym) * cell)
	return sqrt(dx * dx + dy * dy)


## Second seeded fBm as moisture map in [0,1].
static func moisture_map(size: int, seed: int, octaves := 4) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(size * size)
	var freq := 5.0 / float(size)
	for y in size:
		for x in size:
			m[y * size + x] = TNoise.fbm2(float(x), float(y), seed + 7777, octaves, freq)
	return m


## Full classification pass. Returns PackedInt32Array of biome enums.
static func classify(heights: PackedFloat32Array, moisture: PackedFloat32Array, size: int, cell: float, water_level := 12.0) -> PackedInt32Array:
	var b := PackedInt32Array()
	b.resize(size * size)
	for y in size:
		for x in size:
			var i := y * size + x
			b[i] = biome(heights[i], slope_at(heights, size, x, y, cell), moisture[i], water_level)
	return b


## Coverage stats: {"counts": {name: n}, "fractions": {name: float}}.
static func coverage(biomes: PackedInt32Array) -> Dictionary:
	var counts := {}
	for n in NAMES:
		counts[n] = 0
	for b in biomes:
		counts[NAMES[b]] += 1
	var fr := {}
	var total := float(biomes.size())
	for n in NAMES:
		fr[n] = float(counts[n]) / total if total > 0.0 else 0.0
	return {"counts": counts, "fractions": fr}
