class_name TerrainMesh
## Builds the visible terrain ArrayMesh from the FROZEN sim's Terrain.heightAt —
## no new height math lives here (docs/boreal-analysis.md risk 5). Grid is
## (size+1)^2 verts over size x size meters centered on `center`; flat shading;
## vertex colors: snow above treeline, rock on steep slopes, blue-ish stream
## band, ice on the lake, mossy tone in the bog.


static func build(center := Vector2(Terrain.CRASH.x, Terrain.CRASH.z),
		size := 400.0, grid := 128) -> ArrayMesh:
	var n := grid + 1
	var h: Array = []
	h.resize(n * n)
	for j in n:
		var z := center.y - size * 0.5 + size * float(j) / float(grid)
		for i in n:
			var x := center.x - size * 0.5 + size * float(i) / float(grid)
			h[j * n + i] = Terrain.heightAt(x, z)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	cols.resize(n * n)
	for j in n:
		var z := center.y - size * 0.5 + size * float(j) / float(grid)
		for i in n:
			var x := center.x - size * 0.5 + size * float(i) / float(grid)
			var y: float = h[j * n + i]
			verts[j * n + i] = Vector3(x, y, z)
			cols[j * n + i] = _color_at(x, z, y, h, i, j, n)
	var idx := PackedInt32Array()
	for j in grid:
		for i in grid:
			var a := j * n + i
			idx.append_array([a, a + n, a + 1, a + 1, a + n, a + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material())
	return mesh


## Vertex palette (boreal-src palette.ts SNOW/ROCK/ICE family).
static func _color_at(x: float, z: float, y: float, h: Array,
		i: int, j: int, n: int) -> Color:
	var snow := Color(0.91, 0.93, 0.96)
	var rock := Color(0.49, 0.52, 0.56)
	var c := snow
	# below treeline: snow -> rock/ground with altitude
	if y < 22.0:
		c = rock.lerp(snow, clampf((y - 2.0) / 20.0, 0.0, 1.0))
	# steep slopes expose rock
	var dx: float = h[j * n + mini(i + 1, n - 1)] - h[j * n + maxi(i - 1, 0)]
	var dz: float = h[mini(j + 1, n - 1) * n + i] - h[maxi(j - 1, 0) * n + i]
	var slope := sqrt(dx * dx + dz * dz)  # meters per (grid step ~3.1 m)
	c = c.lerp(rock, clampf((slope - 1.2) / 3.0, 0.0, 0.85))
	# bog: mossy dark green
	if z > 110.0:
		c = c.lerp(Color(0.42, 0.47, 0.36), clampf((z - 110.0) / 50.0, 0.0, 0.7))
	# stream band: blue-ish wet gravel
	if z > -160.0:
		var sw := absf(x - Terrain.streamX(z))
		if sw < 7.0:
			c = c.lerp(Color(0.44, 0.58, 0.68), clampf((7.0 - sw) / 5.0, 0.0, 1.0))
	# lake ice
	if Terrain.lakeT(x, z) < 1.0:
		c = Color(0.74, 0.83, 0.88)
	return c


static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	# no normals in the arrays => engine derives per-face normals (flat shading)
	return m
