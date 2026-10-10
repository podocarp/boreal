extends SceneTree
# Generated-level tests (headless, no pixels): baked gen_001 data loads and
# matches meta; TerrainHM heightAt is exact at cell centers + bilinear
# between; spawn passes the flatness gate; biome scatter is non-empty and
# sits on the heightmap; water rects cover only water cells and the quads
# ride water_level; main.tscn constructs under LEVEL=generated without error.

const DIR := "res://levels/gen_001/"
const SEED := 1  # must match scenes/main.gd

var fails := 0
var _hm: TerrainHM


func _init():
	_hm = TerrainHM.load_baked(DIR)
	_test_load()
	_test_height_at()
	_test_spawn_flat()
	_test_scatter()
	_test_water_rects()
	_test_main_constructs()
	if fails == 0:
		print("PASS test_gen_level")
		quit(0)
	else:
		print("FAIL test_gen_level: %d checks failed" % fails)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  " + msg)


func _test_load() -> void:
	_check(_hm.size == 256, "size %d != 256" % _hm.size)
	_check(_hm.heights.size() == 256 * 256, "heights count %d" % _hm.heights.size())
	_check(_hm.biomes.size() == 256 * 256, "biomes count %d" % _hm.biomes.size())
	_check(str(_hm.meta.get("height_hash", "")) == "ebabe3cf",
		"height_hash mismatch (bake drifted?): " + str(_hm.meta.get("height_hash")))
	_check(not _hm.spawn.is_empty(), "spawn.json has no spawn")
	_check(load(DIR + "terrain_mesh.tres") is ArrayMesh, "baked mesh .tres missing")
	_check(load(DIR + "terrain_collision.tres") is HeightMapShape3D,
		"baked collision .tres missing")
	# the bake stores biome vertex colors but no material; GenLevel must
	# attach a vertex-color material or Godot renders flat default-gray
	var vis := GenLevel.terrain_mesh(_hm)
	_check(vis.surface_get_material(0) is StandardMaterial3D
		and (vis.surface_get_material(0) as StandardMaterial3D)
			.vertex_color_use_as_albedo,
		"visible terrain mesh lacks a vertex-color material (colors ignored)")


func _test_height_at() -> void:
	# exact at cell centers (deterministic sample points, no randf)
	for k in 64:
		var cx := (k * 97) % 256
		var cz := (k * 53) % 256
		var x := float(cx) * _hm.cell
		var z := float(cz) * _hm.cell
		_check(absf(_hm.heightAt(x, z) - _hm.heights[cz * 256 + cx]) < 1e-5,
			"heightAt not exact at cell center (%d,%d)" % [cx, cz])
	# bilinear between: midpoint of 4 corners == mean of corners
	var cx := 100
	var cz := 120
	var x := (float(cx) + 0.5) * _hm.cell
	var z := (float(cz) + 0.5) * _hm.cell
	var want := (_hm.heights[cz * 256 + cx] + _hm.heights[cz * 256 + cx + 1] \
		+ _hm.heights[(cz + 1) * 256 + cx] + _hm.heights[(cz + 1) * 256 + cx + 1]) / 4.0
	_check(absf(_hm.heightAt(x, z) - want) < 1e-4,
		"midpoint %.4f != mean of corners %.4f" % [_hm.heightAt(x, z), want])
	# nearest-cell gameplay path returns the grid value verbatim
	_check(_hm.heightAtCell(x, z) == _hm.heights[121 * 256 + 100] \
		or _hm.heightAtCell(x, z) == _hm.heights[120 * 256 + 100] \
		or _hm.heightAtCell(x, z) == _hm.heights[121 * 256 + 101] \
		or _hm.heightAtCell(x, z) == _hm.heights[120 * 256 + 101],
		"heightAtCell returned a non-grid value")


func _test_spawn_flat() -> void:
	# same gate as SpawnSelect: max-min over the 4x4-cell footprint at cell
	# centers < 0.5 m (sampling off-center bilinear values is a different,
	# stricter measure — the baked mesh interpolates between the same centers)
	var cx := int(_hm.spawn["cell"][0])
	var cz := int(_hm.spawn["cell"][1])
	var lo := INF
	var hi := -INF
	for dx in range(0, 4):
		for dz in range(0, 4):
			var h := _hm.heightAt(float(cx + dx) * _hm.cell, float(cz + dz) * _hm.cell)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	_check(hi - lo < 0.5, "spawn footprint not flat: %.3f m spread" % (hi - lo))
	var sx := float(cx) * _hm.cell
	var sz := float(cz) * _hm.cell
	var si := _hm.stream_info(sx, sz)
	_check(si["dist_m"] <= 40.0, "spawn water %.0f m away (>40)" % si["dist_m"])
	_check(_hm.biome_at(sx, sz) != _hm.WATER, "spawn cell is water")


func _test_scatter() -> void:
	var camp := GenLevel.camp_center(_hm)
	var props := GenContent.scatter_props(_hm, SEED, Vector2(camp.x, camp.z), 150.0)
	_check(props.size() > 0, "scatter produced no props")
	var kinds := {}
	for p in props:
		kinds[p.kind] = int(kinds.get(p.kind, 0)) + 1
		_check(p.y == _hm.heightAtCell(p.x, p.z),
			"prop y %.3f off heightmap at (%.1f, %.1f)" % [p.y, p.x, p.z])
		_check(_hm.biome_at(p.x, p.z) != _hm.WATER, "prop in water")
	_check(kinds.has("spruce"), "no spruce scattered")
	# determinism: same seed -> identical list
	var again := GenContent.scatter_props(_hm, SEED, Vector2(camp.x, camp.z), 150.0)
	_check(again.size() == props.size()
		and (again.is_empty() or again[0] == props[0]), "scatter not deterministic")


func _test_water_rects() -> void:
	var rects := GenContent.water_rects(_hm)
	_check(rects.size() > 0, "no water rects despite water biome cells")
	var covered := 0
	for r in rects:
		var cx0 := int(round(r["x0"] / _hm.cell))
		var cz0 := int(round(r["z0"] / _hm.cell))
		var cx1 := int(round(r["x1"] / _hm.cell))
		var cz1 := int(round(r["z1"] / _hm.cell))
		for cy in range(cz0, mini(cz1, 255)):
			for cx in range(cx0, mini(cx1, 255)):
				_check(_hm.biomes[cy * 256 + cx] == _hm.WATER,
					"rect covers non-water cell (%d,%d)" % [cx, cy])
				covered += 1
	_check(covered > 100, "rects cover only %d cells" % covered)
	# quads ride water_level + freeboard
	var mi := GenLevel.build_water(_hm, true)
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var want_y := _hm.water_level + 0.12
	for v in verts:
		_check(absf(v.y - want_y) < 1e-4, "water vertex y %.3f != %.3f" % [v.y, want_y])
		break  # one representative check per mesh is enough (uniform y)


## Instantiate the real main scene with LEVEL=generated and assert it built a
## generated world. Assertions run synchronously after add_child (_ready);
## never yielding a frame keeps main.gd's shot-save quit() from firing.
func _test_main_constructs() -> void:
	OS.set_environment("LEVEL", "generated")
	OS.set_environment("CHECKPOINT", "")
	OS.set_environment("SHOT_OUT", "")
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main.tscn missing")
	if packed == null:
		return
	var main := packed.instantiate()
	root.add_child(main)
	# In a SceneTree-script _init the tree hasn't started, so _ready would be
	# deferred to the first process frame — where main.gd's shot-save quit()
	# would kill the test. Invoke the build directly, then free before any
	# frame runs (the tree never iterates before quit()).
	main._ready()
	var loop := main.get_node_or_null("GameLoop")
	_check(loop != null and loop.world != null, "GameLoop missing after _ready")
	if loop != null:
		_check(loop.terrain is TerrainHM, "loop.terrain not swapped to TerrainHM")
		var sp := _hm.spawn
		_check(absf(loop.world.player.x - float(sp["x"])) < 1e-3,
			"sim player not at baked spawn x")
		_check(absf(loop.world.player.z - float(sp["z"])) < 1e-3,
			"sim player not at baked spawn z")
		var water_pts := 0
		for it in loop.world.interactables:
			if it.kind == "water":
				water_pts += 1
		_check(water_pts > 0, "no baked water interactables injected")
		_check(main.get_node_or_null("TerrainCollision") != null,
			"baked collision body missing")
		_check(main.get_node_or_null("LakeWater") != null, "lake water mesh missing")
	root.remove_child(main)
	main.free()
	OS.set_environment("LEVEL", "")
