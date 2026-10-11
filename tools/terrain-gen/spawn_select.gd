## Factorio-inspired starter-patch scorer over a baked map.
## Hard constraints (must pass): not-in-water, water within 40 m, flatness.
## Soft score: tree band in ring, gentle slope for expansion, animal candidates.
## Deterministic: row-major scan, tie-break = lower cell index wins.
## Ring stats come from integral images (O(1) per candidate) — a naive
## per-candidate ring scan is O(candidates * R^2) and too slow at 256^2.
class_name SpawnSelect

const CELL := 2.0            # meters per cell (matches Gen default)
const FOOTPRINT := 4         # cells -> 8 m footprint (4x4 cells)
const FLAT_MAX := 0.5        # max-min over footprint, meters
const WATER_RADIUS_M := 40.0
const TREE_RING_IN_M := 15.0
const TREE_RING_OUT_M := 40.0
const TREE_MIN := 3          # forest cells in ring (barren penalty below)
const TREE_MAX := 28         # forest cells in ring (too-rich penalty above)
const ANIMAL_IN_M := 15.0    # animal candidates: not this close
const ANIMAL_OUT_M := 60.0
const SLOPE_BOX_M := 12.0    # box for expansion-room slope average
const EDGE_MARGIN := 4       # cells: keep spawn off map border
const NX4: Array[int] = ([1, -1, 0, 0])
const NY4: Array[int] = ([0, 0, 1, -1])


## Main entry. world = {heights, biomes, size}. Returns spawn JSON-ready dict:
## {spawn: {x,z,y,yaw,cell}|null, candidates: [top-5], diagnostics: {...}}
static func select(world: Dictionary) -> Dictionary:
	var heights: PackedFloat32Array = world["heights"]
	var biomes: PackedInt32Array = world["biomes"]
	var size: int = world["size"]
	var water := _nearest_water_dist_cells(biomes, size)
	# integral images over the whole map (float-based, see _integral)
	var forest := PackedFloat32Array()
	var edge := PackedFloat32Array()
	var slope := PackedFloat32Array()
	forest.resize(size * size)
	edge.resize(size * size)
	slope.resize(size * size)
	for i in size * size:
		forest[i] = 1.0 if biomes[i] == Biome.FOREST else 0.0
		if biomes[i] == Biome.FOREST and _has_grass_neighbor(biomes, size, i % size, i / size):
			edge[i] = 1.0
		slope[i] = Biome.slope_at(heights, size, i % size, i / size, CELL)
	var forest_ii := _integral(forest, size)
	var edge_ii := _integral(edge, size)
	var slope_ii := _integral(slope, size)

	var candidates: Array = []
	var fails := {"water": 0, "flat": 0, "border": 0}
	var viable := 0
	for y in range(EDGE_MARGIN, size - EDGE_MARGIN):
		for x in range(EDGE_MARGIN, size - EDGE_MARGIN):
			var i := y * size + x
			if biomes[i] == Biome.WATER:
				fails["water"] += 1
				continue
			var wd := water[i]
			if wd < 0.0 or float(wd) * CELL > WATER_RADIUS_M:
				fails["water"] += 1
				continue
			if not _flat_enough(heights, size, x, y):
				fails["flat"] += 1
				continue
			viable += 1
			var s := _score(forest_ii, edge_ii, slope_ii, size, x, y, wd)
			candidates.append({
				"cell": [x, y], "index": i,
				"x": _m(x), "z": _m(y), "y": heights[i],
				"scores": s, "total": s["tree_score"] + s["slope_score"] + s["animal_score"] + s["water_score"],
			})
	candidates.sort_custom(_cmp)
	var out := {
		"spawn": null,
		"candidates": candidates.slice(0, 5),
		"diagnostics": {
			"viable_cells": viable,
			"constraint_failures": fails,
			"reason": "",
		},
	}
	if candidates.is_empty():
		out["diagnostics"]["reason"] = "no viable spawn: every cell failed hard constraints (see constraint_failures)"
		return out
	var best: Dictionary = candidates[0]
	out["spawn"] = {
		"x": best["x"], "z": best["z"], "y": best["y"],
		"yaw": _facing_water(biomes, size, best["cell"][0], best["cell"][1]),
		"cell": best["cell"],
	}
	out["diagnostics"]["reason"] = "highest soft score among %d viable cells; water %.1fm away; trees-in-ring=%d; tie-break=lowest cell index" % [
		viable, float(water[best["index"]]) * CELL, best["scores"]["trees"]]
	return out


## cell coord -> world meters
static func _m(v: int) -> float:
	return float(v) * CELL


## sort: total desc, then cell index asc (deterministic tie-break)
static func _cmp(a: Dictionary, b: Dictionary) -> bool:
	if a["total"] != b["total"]:
		return a["total"] > b["total"]
	return a["index"] < b["index"]


## max-min over FOOTPRINT x FOOTPRINT cells centered at (x,y).
static func _flat_enough(heights: PackedFloat32Array, size: int, x: int, y: int) -> bool:
	var x0 := x - FOOTPRINT / 2
	var y0 := y - FOOTPRINT / 2
	var mn := INF
	var mx := -INF
	for dy in FOOTPRINT:
		for dx in FOOTPRINT:
			var v := heights[(y0 + dy) * size + (x0 + dx)]
			mn = minf(mn, v)
			mx = maxf(mx, v)
	return mx - mn < FLAT_MAX


## BFS distance (cells) to nearest WATER cell; -1 if no water on map.
static func _nearest_water_dist_cells(biomes: PackedInt32Array, size: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(size * size)
	d.fill(-1)
	var queue: Array[int] = []
	for i in biomes.size():
		if biomes[i] == Biome.WATER:
			d[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x := i % size
		var y := i / size
		for n in 4:
			var nx := x + NX4[n]
			var ny := y + NY4[n]
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var j := ny * size + nx
			if d[j] < 0:
				d[j] = d[i] + 1
				queue.append(j)
	return d


## Soft scores. tree/slope/animal/water sub-scores in [0,1]; trees/animals raw.
static func _score(forest_ii: PackedFloat32Array, edge_ii: PackedFloat32Array,
		slope_ii: PackedFloat32Array, size: int, x: int, y: int, wd_cells: int) -> Dictionary:
	var trees := int(_ii_box(forest_ii, size, x, y, int(ceilf(TREE_RING_OUT_M / CELL))) \
			- _ii_box(forest_ii, size, x, y, int(floorf(TREE_RING_IN_M / CELL)) - 1))
	var animals := int(_ii_box(edge_ii, size, x, y, int(ceilf(ANIMAL_OUT_M / CELL))) \
			- _ii_box(edge_ii, size, x, y, int(floorf(ANIMAL_IN_M / CELL))))
	var half := int(roundf(SLOPE_BOX_M / CELL))
	var n := (2 * half + 1) * (2 * half + 1)
	var mean_slope := _ii_box(slope_ii, size, x, y, half) / float(n)
	# tree band: 1.0 inside [TREE_MIN, TREE_MAX], penalized on BOTH sides
	var tree_score := 0.0
	if trees >= TREE_MIN and trees <= TREE_MAX:
		tree_score = 1.0
	elif trees < TREE_MIN:
		tree_score = maxf(0.0, float(trees) / float(TREE_MIN))
	else:
		tree_score = maxf(0.0, 1.0 - float(trees - TREE_MAX) / 40.0)
	var slope_score := clampf(1.0 - mean_slope, 0.0, 1.0)
	var animal_score := clampf(float(animals) / 6.0, 0.0, 1.0)
	var water_score := clampf(1.0 - float(wd_cells) * CELL / WATER_RADIUS_M, 0.0, 1.0)
	return {
		"trees": trees, "tree_score": tree_score, "animals": animals,
		"slope_score": slope_score, "animal_score": animal_score,
		"water_score": water_score, "mean_slope": mean_slope,
	}


## forest cell with an adjacent grass cell = forest-edge (animal candidate)
static func _has_grass_neighbor(biomes: PackedInt32Array, size: int, x: int, y: int) -> bool:
	for n in 4:
		var nx := x + NX4[n]
		var ny := y + NY4[n]
		if nx >= 0 and ny >= 0 and nx < size and ny < size \
				and biomes[ny * size + nx] == Biome.GRASS:
			return true
	return false


# --- integral images (row-major, (size+1) stride with zero top/left border) ---
## One float-based helper for all three maps (forest mask, edge mask, slope).

static func _integral(src: PackedFloat32Array, size: int) -> PackedFloat32Array:
	var ii := PackedFloat32Array()
	ii.resize((size + 1) * (size + 1))
	for y in size:
		var row := 0.0
		for x in size:
			row += src[y * size + x]
			ii[(y + 1) * (size + 1) + (x + 1)] = ii[y * (size + 1) + (x + 1)] + row
	return ii


## Sum over the square of half-width `r` cells centered at (x,y), clamped to map.
static func _ii_box(ii: PackedFloat32Array, size: int, x: int, y: int, r: int) -> float:
	if r < 0:
		return 0.0
	var s := size + 1
	var x1 := clampi(x - r, 0, size)
	var y1 := clampi(y - r, 0, size)
	var x2 := clampi(x + r + 1, 0, size)
	var y2 := clampi(y + r + 1, 0, size)
	return ii[y2 * s + x2] - ii[y1 * s + x2] - ii[y2 * s + x1] + ii[y1 * s + x1]


## yaw (radians, atan2(dz, dx)) pointing from spawn toward nearest water.
static func _facing_water(biomes: PackedInt32Array, size: int, x: int, y: int) -> float:
	var seen := PackedByteArray()
	seen.resize(size * size)
	var queue: Array = [[x, y, x, y]]
	seen[y * size + x] = 1
	var head := 0
	while head < queue.size():
		var e: Array = queue[head]
		head += 1
		var cx: int = e[0]
		var cy: int = e[1]
		if biomes[cy * size + cx] == Biome.WATER and not (cx == x and cy == y):
			return atan2(float(e[3] - y), float(e[2] - x))
		for n in 4:
			var nx := cx + NX4[n]
			var ny := cy + NY4[n]
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			if seen[ny * size + nx] == 0:
				seen[ny * size + nx] = 1
				queue.append([nx, ny, e[2], e[3]])
	return 0.0
