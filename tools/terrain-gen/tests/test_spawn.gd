## Spawn selection tests: hard constraints over 10 seeds, determinism,
## and barren-map diagnostic (no viable spawn, not garbage).
extends SceneTree


func _init() -> void:
	_test_hard_constraints()
	_test_determinism()
	_test_barren_map()
	_test_no_water_map()
	quit(0)


func _world(seed_v: int) -> Dictionary:
	# 128x128: small maps can legitimately have zero flat+watered cells;
	# probe runs confirmed 10/10 of these seeds yield a spawn at this size.
	var w := Gen.bake(128, seed_v, 5, 2500, 4, SpawnSelect.CELL)
	w["size"] = 128
	return w


## For 10 seeds: chosen spawn must satisfy every hard constraint.
func _test_hard_constraints() -> void:
	var checked := 0
	for seed_v in [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]:
		var w := _world(seed_v)
		var res := SpawnSelect.select(w)
		var spawn: Dictionary = res["spawn"]
		if spawn.is_empty():
			print("FAIL spawn_hard_constraints: seed %d has no spawn (%s)" % [
				seed_v, res["diagnostics"]["reason"]])
			quit(1)
		var x: int = spawn["cell"][0]
		var y: int = spawn["cell"][1]
		var h: PackedFloat32Array = w["heights"]
		var b: PackedInt32Array = w["biomes"]
		var size: int = w["size"]
		# 1. not in water
		if b[y * size + x] == Biome.WATER:
			print("FAIL spawn_hard_constraints: seed %d spawn in water" % seed_v)
			quit(1)
		# 2. flatness over footprint
		var mn := INF
		var mx := -INF
		var x0 := x - SpawnSelect.FOOTPRINT / 2
		var y0 := y - SpawnSelect.FOOTPRINT / 2
		for dy in SpawnSelect.FOOTPRINT:
			for dx in SpawnSelect.FOOTPRINT:
				var v: float = h[(y0 + dy) * size + (x0 + dx)]
				mn = minf(mn, v)
				mx = maxf(mx, v)
		if mx - mn >= SpawnSelect.FLAT_MAX:
			print("FAIL spawn_hard_constraints: seed %d not flat (%.2f m)" % [seed_v, mx - mn])
			quit(1)
		# 3. water within 40 m (brute-force nearest water cell)
		var best := INF
		for i in b.size():
			if b[i] == Biome.WATER:
				var d := sqrt(pow(float(i % size - x), 2.0) + pow(float(i / size - y), 2.0)) * SpawnSelect.CELL
				best = minf(best, d)
		if best > SpawnSelect.WATER_RADIUS_M + 1e-3:
			print("FAIL spawn_hard_constraints: seed %d nearest water %.1f m" % [seed_v, best])
			quit(1)
		checked += 1
	print("PASS spawn_hard_constraints %d seeds verified" % checked)


func _test_determinism() -> void:
	var a := SpawnSelect.select(_world(42))
	var b := SpawnSelect.select(_world(42))
	var same: bool = JSON.stringify(a) == JSON.stringify(b)
	var c := SpawnSelect.select(_world(43))
	var differs: bool = JSON.stringify(a["spawn"]) != JSON.stringify(c["spawn"]) \
			or JSON.stringify(a["candidates"]) != JSON.stringify(c["candidates"])
	if same and differs:
		print("PASS spawn_determinism")
	else:
		print("FAIL spawn_determinism same=%s differs=%s" % [same, differs])
		quit(1)


## Barren fixture: uniform grass plain, no water anywhere -> must report
## "no viable spawn" with water constraint failures, not pick garbage.
func _test_barren_map() -> void:
	var size := 48
	var h := PackedFloat32Array()
	h.resize(size * size)
	h.fill(20.0)  # flat, above water level, but DRY
	var b := PackedInt32Array()
	b.resize(size * size)
	b.fill(Biome.GRASS)
	var res := SpawnSelect.select({"heights": h, "biomes": b, "size": size})
	var ok: bool = res["spawn"] == null \
			and String(res["diagnostics"]["reason"]).contains("no viable spawn") \
			and int(res["diagnostics"]["constraint_failures"]["water"]) > 0
	if ok:
		print("PASS spawn_barren_map_diagnostic")
	else:
		print("FAIL spawn_barren_map_diagnostic: %s" % JSON.stringify(res["diagnostics"]))
		quit(1)


## All-water map: everything fails the in-water constraint; still no spawn.
func _test_no_water_map() -> void:
	var size := 32
	var h := PackedFloat32Array()
	h.resize(size * size)
	h.fill(5.0)  # below water level
	var b := PackedInt32Array()
	b.resize(size * size)
	b.fill(Biome.WATER)
	var res := SpawnSelect.select({"heights": h, "biomes": b, "size": size})
	var scan_area := (size - 2 * SpawnSelect.EDGE_MARGIN) * (size - 2 * SpawnSelect.EDGE_MARGIN)
	if res["spawn"] == null and int(res["diagnostics"]["constraint_failures"]["water"]) == scan_area:
		print("PASS spawn_all_water_no_spawn")
	else:
		print("FAIL spawn_all_water_no_spawn: %s" % JSON.stringify(res["diagnostics"]))
		quit(1)
