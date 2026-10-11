## Baked world -> Godot resources: vertex-colored flat-shaded ArrayMesh .tres
## + HeightMapShape3D collision .tres. Zero runtime generation for the game.
class_name MeshOut

const BIOME_COLORS := [
	Color(0.16, 0.32, 0.55),  # water
	Color(0.36, 0.56, 0.25),  # grass
	Color(0.13, 0.35, 0.16),  # forest
	Color(0.45, 0.44, 0.42),  # rock
	Color(0.92, 0.94, 0.97),  # snow
]


## Build an ArrayMesh (triangles, vertex color, flat normals) from baked data.
static func build_mesh(heights: PackedFloat32Array, biomes: PackedInt32Array,
		size: int, cell: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	# one vertex per (cell, corner-triangle): 2 tris per cell, flat shading
	for y in size - 1:
		for x in size - 1:
			var i00 := y * size + x
			var i10 := i00 + 1
			var i01 := i00 + size
			var i11 := i01 + 1
			var p00 := Vector3(float(x) * cell, heights[i00], float(y) * cell)
			var p10 := Vector3(float(x + 1) * cell, heights[i10], float(y) * cell)
			var p01 := Vector3(float(x) * cell, heights[i01], float(y + 1) * cell)
			var p11 := Vector3(float(x + 1) * cell, heights[i11], float(y + 1) * cell)
			# tri A: p00 p01 p10 ; tri B: p10 p01 p11 (normal flipped up in _tri)
			_tri(verts, norms, idx, p00, p01, p10)
			_tri(verts, norms, idx, p10, p01, p11)
	var arrays := Array()
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = _colors_in_vertex_order(biomes, size)
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# REQUIRED: without a vertex-color material the default material renders the
	# whole mesh white (the COLOR array is ignored).
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	m.surface_set_material(0, mat)
	return m


## colors must match _tri emission order: A=(i00,i01,i10), B=(i10,i01,i11)
static func _colors_in_vertex_order(biomes: PackedInt32Array, size: int) -> PackedColorArray:
	var cols := PackedColorArray()
	for y in size - 1:
		for x in size - 1:
			var i00 := y * size + x
			var i10 := i00 + 1
			var i01 := i00 + size
			var i11 := i01 + 1
			cols.append(BIOME_COLORS[biomes[i00]])
			cols.append(BIOME_COLORS[biomes[i01]])
			cols.append(BIOME_COLORS[biomes[i10]])
			cols.append(BIOME_COLORS[biomes[i10]])
			cols.append(BIOME_COLORS[biomes[i01]])
			cols.append(BIOME_COLORS[biomes[i11]])
	return cols


static func _tri(verts: PackedVector3Array, norms: PackedVector3Array,
		idx: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var base := verts.size()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	for k in 3:
		norms.append(n)
	idx.append(base)
	idx.append(base + 1)
	idx.append(base + 2)


## HeightMapShape3D resource sized to the grid (cell spacing via scale).
static func build_collision(heights: PackedFloat32Array, size: int, cell: float) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	# width/depth MUST be set before map_data: the setter validates against the
	# current dimensions and silently drops data sized for a 0x0 shape.
	shape.map_width = size
	shape.map_depth = size  # Godot 4.7: map_height was renamed map_depth
	var map := PackedFloat32Array()
	map.resize(size * size)
	for i in size * size:
		map[i] = heights[i]
	shape.map_data = map
	return shape


## Save mesh + collision .tres into `dir` (absolute path). Returns file paths.
static func save(mesh: ArrayMesh, shape: HeightMapShape3D, dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir)
	var mp := dir.path_join("terrain_mesh.tres")
	var sp := dir.path_join("terrain_collision.tres")
	var e1 := ResourceSaver.save(mesh, mp)
	var e2 := ResourceSaver.save(shape, sp)
	return {"mesh": mp, "collision": sp, "mesh_err": e1, "collision_err": e2}
