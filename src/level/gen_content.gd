## Deterministic biome-driven scatter + lake-quad decomposition for the
## generated level. Static helpers over a TerrainHM (kept out of the adapter
## so each level file stays small). All randomness is a seeded RNG; iteration
## is row-major => byte-deterministic output.
class_name GenContent


## Biome-driven scatter: forest cells -> spruce/birch, grass cells -> lone
## trees, rock cells -> rocks; jitter from a seeded RNG only. Props carry
## y = heightAtCell (gameplay nearest-cell). Camp clearing (7 m) and
## jitter-into-water cells are skipped.
static func scatter_props(hm: TerrainHM, seed_: int, center: Vector2,
		radius: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var props: Array = []
	var r2 := radius * radius
	for cy in hm.size:
		var z := float(cy) * hm.cell
		for cx in hm.size:
			var x := float(cx) * hm.cell
			var dx := x - center.x
			var dz := z - center.y
			if dx * dx + dz * dz > r2:
				continue
			var kind := ""
			var roll := rng.randf()
			match hm.biomes[cy * hm.size + cx]:
				hm.FOREST:
					if roll < 0.30:
						kind = "spruce"
					elif roll < 0.42:
						kind = "birch"
				hm.GRASS:
					if roll < 0.05:
						kind = "spruce"
				hm.ROCK:
					if roll < 0.45:
						kind = "rock"
			if kind == "":
				continue
			var px := x + (rng.randf() - 0.5) * hm.cell * 0.9
			var pz := z + (rng.randf() - 0.5) * hm.cell * 0.9
			var cdx := px - center.x
			var cdz := pz - center.y
			if cdx * cdx + cdz * cdz < 49.0 or hm.biome_at(px, pz) == hm.WATER:
				continue  # camp clearing / jittered into water
			var v := rng.randf()
			var scale := 0.7 + v * 1.1 if kind == "spruce" \
				else (0.6 + v * 0.7 if kind == "birch" else 0.5 + v * 1.4)
			props.append({"kind": kind, "x": px, "z": pz, "scale": scale,
				"rot": rng.randf() * TAU, "y": hm.heightAtCell(px, pz)})
	return props


## Axis-aligned rectangle decomposition of the water-cell set (greedy row
## runs extended downward). Rects in world meters; every covered cell is
## water by construction. v0 lakes: one flat water quad per rect.
static func water_rects(hm: TerrainHM) -> Array:
	var size := hm.size
	var taken := PackedByteArray()
	taken.resize(size * size)
	var rects: Array = []
	for cy in size:
		for cx in size:
			var i := cy * size + cx
			if hm.biomes[i] != hm.WATER or taken[i] == 1:
				continue
			var w := 1
			while cx + w < size and hm.biomes[cy * size + cx + w] == hm.WATER \
					and taken[cy * size + cx + w] == 0:
				w += 1
			var hgt := 1
			while cy + hgt < size:
				var ok := true
				for k in w:
					var j := (cy + hgt) * size + cx + k
					if hm.biomes[j] != hm.WATER or taken[j] == 1:
						ok = false
						break
				if not ok:
					break
				hgt += 1
			for yy in hgt:
				for xx in w:
					taken[(cy + yy) * size + cx + xx] = 1
			rects.append({"x0": float(cx) * hm.cell, "z0": float(cy) * hm.cell,
				"x1": float(cx + w) * hm.cell, "z1": float(cy + hgt) * hm.cell})
	return rects
