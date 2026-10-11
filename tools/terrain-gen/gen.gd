## Terrain generation pipeline: fBm heightmap + erosion + biomes + stats.
## All static, all seeded — terrain_gen.gd is only a CLI wrapper around this.
class_name Gen

const AMPLITUDE := 55.0   # meters, pre-erosion relief
const WATER_LEVEL := 12.0 # meters


## fBm heightmap: size*size PackedFloat32Array in [0, AMPLITUDE].
## `cell` = meters per cell; base frequency = 4 cycles across the map.
## persistence 0.3 keeps high-frequency roughness low so that 8 m footprints
## under 0.5 m relief (SpawnSelect.FLAT_MAX) actually exist on the map.
static func heightmap(size: int, seed: int, octaves := 5) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(size * size)
	var freq := 4.0 / float(size)
	for y in size:
		for x in size:
			var n := fbm_shaped(float(x), float(y), seed, octaves, freq)
			h[y * size + x] = n * AMPLITUDE
	return h


## fBm with persistence 0.3 and pow(1.35) shaping (valleys flatter, peaks sharper).
static func fbm_shaped(x: float, y: float, seed: int, octaves: int, freq: float) -> float:
	var sum := 0.0
	var amp := 1.0
	var total := 0.0
	var f := freq
	for i in octaves:
		sum += TNoise.value2(x * f, y * f, seed + i * 101) * amp
		total += amp
		amp *= 0.3
		f *= 2.0
	return pow(sum / total, 1.35)


## Full bake: heightmap -> hydraulic -> thermal -> moisture -> biomes.
## Returns {heights, moisture, biomes, stats}.
static func bake(size: int, seed: int, octaves := 5, hydraulic_particles := 12000,
		thermal_passes := 3, cell := 2.0) -> Dictionary:
	var heights := heightmap(size, seed, octaves)
	Erosion.hydraulic(heights, size, seed + 1, hydraulic_particles)
	Erosion.thermal(heights, size, thermal_passes)
	var moisture := Biome.moisture_map(size, seed, 4)
	var biomes := Biome.classify(heights, moisture, size, cell, WATER_LEVEL)
	return {
		"heights": heights,
		"moisture": moisture,
		"biomes": biomes,
		"stats": stats(heights, biomes, seed, size, cell),
	}


## Metadata block for the baked output.
static func stats(heights: PackedFloat32Array, biomes: PackedInt32Array, seed: int, size: int, cell: float) -> Dictionary:
	var mn := INF
	var mx := -INF
	var sum := 0.0
	for v in heights:
		mn = minf(mn, v)
		mx = maxf(mx, v)
		sum += v
	var cov := Biome.coverage(biomes)
	return {
		"seed": seed,
		"size": size,
		"cell_size_m": cell,
		"min_height": mn,
		"max_height": mx,
		"mean_height": sum / float(heights.size()),
		"water_level": WATER_LEVEL,
		"biome_counts": cov["counts"],
		"biome_fractions": cov["fractions"],
		"height_hash": hash_heights(heights),
	}


## FNV-1a 32-bit over the raw float32 bytes — cheap determinism fingerprint.
## (32-bit prime keeps products inside int64; no wrapping surprises.)
static func hash_heights(heights: PackedFloat32Array) -> String:
	var h := 2166136261
	var mask := 0xFFFFFFFF
	for b in heights.to_byte_array():
		h = (h ^ int(b)) & mask
		h = (h * 16777619) & mask
	return "%08x" % h
