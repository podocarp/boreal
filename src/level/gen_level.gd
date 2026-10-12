## Generated-level glue (LEVEL=generated): builds the world from the baked
## terrain-gen artifacts in levels/gen_001/ (mesh, collision, biome scatter,
## lake quads) and injects baked-world data into the frozen sim (spawn pose,
## colliders, interactables) WITHOUT touching src/sim/. All queries go
## through the TerrainHM adapter; the frozen analytic Terrain stays the
## default provider for the original level.
class_name GenLevel

const LEVEL_DIR := "res://levels/gen_001/"
const WATER_FREEBOARD := 0.12  # lake surface sits this far above water_level

static var _hm: TerrainHM


## Cached adapter over the baked dir (loads JSONs once per process).
static func load_hm() -> TerrainHM:
	if _hm == null:
		_hm = TerrainHM.load_baked(LEVEL_DIR)
	return _hm


## Camp/spawn center = spawn.json starter patch (flat by construction).
static func camp_center(hm: TerrainHM) -> Vector3:
	return Vector3(float(hm.spawn["x"]), hm.heightAtCell(
		float(hm.spawn["x"]), float(hm.spawn["z"])), float(hm.spawn["z"]))


## Visible terrain: the baked vertex-colored ArrayMesh, loaded as-is. The
## bake already carries a vertex-color material (mesh_out.gd); duplicating it
## here dropped the COLOR array on the GPU (ground rendered white).
static func terrain_mesh(hm: TerrainHM) -> Mesh:
	var m: Mesh = load(LEVEL_DIR + "terrain_mesh.tres")
	assert(m != null, "baked mesh missing: " + LEVEL_DIR)
	return m


## Physics: HeightMapShape3D from the bake. Parent scale (cell,1,cell) sets
## the spacing; heights stay in meters (terrain-gen README contract).
static func collision_body(hm: TerrainHM) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.scale = Vector3(hm.cell, 1.0, hm.cell)
	# Camera-only layer (see main.gd._frozen_terrain_collision): the sim pins
	# the player to heightAt; a layer-1 collider would fight move_and_slide.
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = load(LEVEL_DIR + "terrain_collision.tres")
	body.add_child(cs)
	return body


## Biome-driven scatter props -> MultiMeshInstance3D per glTF model, using the
## glTF materials as-is (like the frozen level). NO material_overlay tint: the
## baked glTF meshes carry no vertex colors, so the unshaded tint material
## rendered every tree as a flat white silhouette. Props sit on heightAtCell.
static func build_scatter(hm: TerrainHM, seed_: int, center: Vector3,
		radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Scatter"
	var instances := ScatterRender.build_instances(
		GenContent.scatter_props(hm, seed_, Vector2(center.x, center.z), radius),
		Vector2.INF, 1e9, hm)
	for path in instances:
		var xforms: Array = instances[path]
		if xforms.is_empty():
			continue
		var mesh := ScatterRender.mesh_from_gltf(path)
		if mesh == null:
			push_warning("missing model " + path)
			continue
		root.add_child(ScatterRender.make_multimesh(mesh, xforms,
			path.get_file().get_basename()))
	return root


## Lakes: flat quads at water_level + freeboard over the water-cell rect
## decomposition, reusing the stream water shader. UV.x is pinned mid-rect
## so the channel-edge foam/edge-darkening terms stay off on lake quads.
static func build_water(hm: TerrainHM, frozen: bool) -> MeshInstance3D:
	var rects := GenContent.water_rects(hm)
	var y := hm.water_level + WATER_FREEBOARD
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in rects:
		var base := verts.size()
		var x0: float = r["x0"]
		var x1: float = r["x1"]
		var z0: float = r["z0"]
		var z1: float = r["z1"]
		verts.append(Vector3(x0, y, z0))
		verts.append(Vector3(x1, y, z0))
		verts.append(Vector3(x1, y, z1))
		verts.append(Vector3(x0, y, z1))
		for k in 4:
			norms.append(Vector3.UP)
			uvs.append(Vector2(0.5, z0 + (z1 - z0) * float(k >= 2)))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2,
			base, base + 2, base + 3]))
	var arrays := Array()
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "LakeWater"
	mi.mesh = mesh
	mi.material_override = WaterRender.build_material(frozen)
	return mi


## Checkpoint camera [pos, target, eye] for the generated level.
## water: stand on the east bank — camp foreground, stream running away.
## overview: elevated drone view of the starter patch (water + tree ring).
static func checkpoint_cam(hm: TerrainHM, camp: Vector3, which: String) -> Array:
	if which == "water":
		var wp := hm.nearest_water(camp.x, camp.z)
		return [Vector3(camp.x + 9.0, 0.0, camp.z + 4.0),
			Vector3(wp.x, 0.0, wp.y - 10.0), 2.2]
	return [Vector3(camp.x - 30.0, 0.0, camp.z - 24.0), camp, 35.0]


## Inject baked-world data into the frozen sim (data only, no sim edits):
## spawn pose at the starter patch, colliders + interactables from the biome
## scatter, wreck at spawn, water scoop points on the near lake shore.
static func apply_to_sim(loop: GameLoop, hm: TerrainHM, seed_: int) -> void:
	var w := loop.world
	var c := camp_center(hm)
	w.player.x = c.x
	w.player.z = c.z
	w.player.y = c.y
	var props := GenContent.scatter_props(hm, seed_, Vector2(c.x, c.z), 150.0)
	w.colliders = Scatter.colliders_from(props)
	var kept: Array = []
	for it in Interact.build_interactables(seed_, props):
		if it.kind != "water" and it.kind != "wreck":
			kept.append(it)  # analytic stream/wreck entries don't apply
	# wreck sits ~8.5 m from the camp center, matching the analytic level's
	# CRASH-to-camp spacing — at (2,-2) the 8.5 m model swallowed the fire ring
	kept.append({"id": 900001, "kind": "wreck", "x": c.x + 6.0,
	"z": c.z - 6.0, "uses": 1})
	var id := 900002
	for r in GenContent.water_rects(hm):
		if float(r["x1"]) < c.x - 80.0 or float(r["x0"]) > c.x + 80.0 \
				or float(r["z1"]) < c.z - 80.0 or float(r["z0"]) > c.z + 80.0:
			continue
		var wx := clampf(c.x, float(r["x0"]) + hm.cell, float(r["x1"]) - hm.cell)
		var wz := clampf(c.z, float(r["z0"]) + hm.cell, float(r["z1"]) - hm.cell)
		kept.append({"id": id, "kind": "water", "x": wx, "z": wz, "uses": 99})
		id += 1
	w.interactables = kept
