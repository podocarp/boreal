extends SceneTree
# Semantic render tests (no pixels): terrain mesh builds from the frozen sim,
# scatter MultiMesh counts match the sim's scatter, all copied assets load.

const SEED := 1
const RENDER_RADIUS := 150.0  # must match scenes/main.gd

var fails := 0


func _init():
	_test_terrain_mesh()
	_test_scatter_counts()
	_test_assets_load()
	if fails == 0:
		print("PASS test_render")
		quit(0)
	else:
		print("FAIL test_render: %d checks failed" % fails)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  " + msg)


func _test_terrain_mesh() -> void:
	var mesh := TerrainMesh.build(Vector2(Terrain.CRASH.x, Terrain.CRASH.z), 400.0, 128)
	_check(mesh != null, "terrain mesh is null")
	if mesh == null:
		return
	_check(mesh.get_surface_count() == 1, "expected 1 surface, got %d" % mesh.get_surface_count())
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(verts.size() == 129 * 129,
		"vertex count %d != 129*129" % verts.size())
	_check(idx.size() == 128 * 128 * 6, "index count %d unexpected" % idx.size())
	# a vertex must sit exactly on heightAt (no new height math)
	# (grid step = 400/128 = 3.125 m; pick exact grid indices i=114, j=70)
	var x := Terrain.CRASH.x - 200.0 + 400.0 * 114.0 / 128.0
	var z := Terrain.CRASH.z - 200.0 + 400.0 * 70.0 / 128.0
	var want := Terrain.heightAt(x, z)
	var found := false
	for v in verts:
		if absf(v.x - x) < 0.01 and absf(v.z - z) < 0.01:
			_check(absf(v.y - want) < 1e-3,
				"vertex y %.4f != heightAt %.4f" % [v.y, want])
			found = true
			break
	_check(found, "no grid vertex at (%.0f, %.0f)" % [x, z])


func _test_scatter_counts() -> void:
	var props := Scatter.scatter(SEED)
	var center := Vector2(Terrain.CRASH.x, Terrain.CRASH.z + 10.0)
	var instances := ScatterRender.build_instances(props, center, RENDER_RADIUS)
	var total := 0
	for path in instances:
		total += instances[path].size()
	# expected count: same cull predicate, recomputed straight from the sim
	var expected := 0
	for p in props:
		var dx: float = p.x - center.x
		var dz: float = p.z - center.y
		if dx * dx + dz * dz <= RENDER_RADIUS * RENDER_RADIUS:
			expected += 1
	_check(total == expected,
		"instance total %d != sim scatter in radius %d" % [total, expected])
	_check(total > 100, "too few instances (%d) — cull or kind mapping broken" % total)
	# every kind maps to a model path
	for p in props:
		_check(ScatterRender.MODELS.has(p.kind), "unmapped kind " + str(p.kind))
		if ScatterRender.MODELS.has(p.kind):
			var path: String = ScatterRender.MODELS[p.kind][
				ScatterRender.variant_index(0, p.kind)]
			_check(ScatterRender.MODELS[p.kind].has(path), "variant path missing")


func _test_assets_load() -> void:
	var paths: Array = []
	for kind in ScatterRender.MODELS:
		paths.append_array(ScatterRender.MODELS[kind])
	paths.append("res://assets/nature/DeadTree_1.gltf")
	paths.append("res://vendor/sdk/player_mover.gd")
	paths.append("res://vendor/sdk/camera_third_person.gd")
	for p in paths:
		var res: Resource = load(p)
		_check(res != null, "asset failed to load: " + p)
		if res != null and p.ends_with(".gltf"):
			var mesh := ScatterRender.mesh_from_gltf(p)
			_check(mesh != null, "no Mesh extracted from " + p)
