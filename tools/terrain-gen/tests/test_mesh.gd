## Mesh/collision output tests: array sizes, round-trip through .tres,
## and the HeightMapShape3D width-before-data ordering pitfall.
extends SceneTree

const TMP := "user://mesh_test_out"


func _init() -> void:
	var size := 32
	var h := PackedFloat32Array()
	h.resize(size * size)
	for i in size * size:
		h[i] = float(i % size) * 0.1
	var b := PackedInt32Array()
	b.resize(size * size)
	for i in size * size:
		b[i] = Biome.GRASS if i % 3 else Biome.FOREST
	_test_mesh_arrays(h, b, size)
	_test_collision_roundtrip(h, size)
	quit(0)


func _test_mesh_arrays(h: PackedFloat32Array, b: PackedInt32Array, size: int) -> void:
	var m := MeshOut.build_mesh(h, b, size, 2.0)
	var a := m.surface_get_arrays(0)
	var expect := (size - 1) * (size - 1) * 6
	var ok: bool = m.get_surface_count() == 1 \
			and a[Mesh.ARRAY_VERTEX].size() == expect \
			and a[Mesh.ARRAY_COLOR].size() == expect \
			and a[Mesh.ARRAY_INDEX].size() == expect
	# all normals point up (flat shading)
	if ok:
		for n in a[Mesh.ARRAY_NORMAL]:
			ok = ok and (n as Vector3).y > 0.0
	if ok:
		print("PASS mesh_arrays verts=%d" % expect)
	else:
		print("FAIL mesh_arrays expect=%d got=%d" % [expect, a[Mesh.ARRAY_VERTEX].size()])
		quit(1)


func _test_collision_roundtrip(h: PackedFloat32Array, size: int) -> void:
	var shape := MeshOut.build_collision(h, size, 2.0)
	DirAccess.make_dir_recursive_absolute(TMP)
	var p := TMP.path_join("col.tres")
	var err := ResourceSaver.save(shape, p)
	var loaded := load(p) as HeightMapShape3D
	var ok := err == OK and loaded != null and loaded.map_width == size \
			and loaded.map_depth == size and loaded.map_data.size() == size * size
	if ok:
		# data must survive intact (pitfall: silently dropped if set before dims)
		for i in [0, 17, size * size - 1]:
			ok = ok and absf(loaded.map_data[i] - h[i]) < 1e-5
	if ok:
		print("PASS mesh_collision_roundtrip")
	else:
		print("FAIL mesh_collision_roundtrip err=%d loaded=%s" % [err, loaded])
		quit(1)
