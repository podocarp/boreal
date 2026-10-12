## Crash-site wreck visuals: the DeJunes low-poly Cessna FBX (CC0-ish
## royalty-free, see assets/wreck/LICENSE.txt) posed as a crash at the sim's
## wreck interactable on BOTH levels (analytic Terrain.CRASH and the generated
## level's baked spawn + (6,-6), matching GenLevel.apply_to_sim).
##
## Code-built like everything else (no .tscn). The model is normalized at
## runtime from its own merged vertex AABB (the FBX carries messy Blender
## export scales), then posed: nose toward camp, nose-down pitch, one-wing
## roll, slight ground sink. All constants — deterministic, no RNG.
##
## WHITE-TREE LESSON: never apply material_overlay tints to this mesh — it has
## no vertex colors (README handover notes). The FBX materials
## (red/white livery) render as-is.
class_name WreckVisuals

const MODEL_PATH := "res://assets/wreck/plane_cessna.fbx"
const TARGET_SPAN := 8.5   # meters across the model's largest horizontal dim
const SINK := 0.35         # ground penetration of the crash pose (m)
const PITCH_DEG := -10.0   # nose-down
const ROLL_DEG := 22.0     # resting on one wing
const YAW := 0.0           # extra yaw after nose-toward-camp alignment (deg)


## First Mesh inside the imported FBX (for semantic "model loads" tests).
static func mesh() -> Mesh:
	return ScatterRender.mesh_from_gltf(MODEL_PATH)


## Wreck node at crash site `site` (ground height `h`). Returns null only if
## the model failed to import.
static func build(site: Vector3, h: float, toward: Vector3) -> Node3D:
	var res: Resource = load(MODEL_PATH)
	if res == null or not (res is PackedScene):
		push_warning("wreck model missing: " + MODEL_PATH)
		return null
	var model := (res as PackedScene).instantiate() as Node3D
	if model == null:
		return null
	var box := merged_aabb(model)
	if box.size.length() <= 0.0:
		model.free()
		return null
	# normalize: center x/z on origin, floor at y=0, scale to TARGET_SPAN
	var s := TARGET_SPAN / maxf(box.size.x, box.size.z)
	var wrapper := Node3D.new()
	wrapper.name = "Wreck"
	model.name = "Model"
	model.scale = Vector3.ONE * s
	model.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * s
	wrapper.add_child(model)
	# Solid hull so the player can't walk through the fuselage (playtest
	# 2026-10-12). Box from the normalized AABB, child of the wrapper so it
	# rides the crash pose. Layer 1 = world solids the capsule collides with.
	var body := StaticBody3D.new()
	body.name = "WreckCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Fuselage block only — NOT the full AABB: the 8.5 m wingspan box would
	# wall off the scavenge interactable at the wreck center (INTERACT_RADIUS).
	shape.size = Vector3(2.6, maxf(box.size.y * s, 1.6), 2.6)
	# model is centered x/z and floored at y=0 in wrapper space
	cs.position = Vector3(0.0, shape.size.y * 0.5, 0.0)
	cs.shape = shape
	body.add_child(cs)
	wrapper.add_child(body)
	# crash pose: nose toward camp, then pitch/roll, then sink into the snow
	var yaw := atan2(toward.x - site.x, toward.z - site.z) + deg_to_rad(YAW)
	wrapper.transform = Transform3D(
		Basis(Vector3.UP, yaw)
		* Basis(Vector3.RIGHT, deg_to_rad(ROLL_DEG))
		* Basis(Vector3.FORWARD, deg_to_rad(PITCH_DEG)),
		Vector3(site.x, h - SINK, site.z))
	return wrapper


## Merged world-space AABB over every MeshInstance3D vertex (the per-mesh
## aabb() is unreliable on this FBX; scan the actual vertices).
static func merged_aabb(n: Node3D) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var stack: Array = [[n, Transform3D()]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var c: Node = e[0]
		var xf: Transform3D = e[1] * (c as Node3D).transform if c is Node3D else e[1]
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var m: Mesh = (c as MeshInstance3D).mesh
			for surf in m.get_surface_count():
				for v in (m.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var w := xf * v
					lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
					hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
		for ch in c.get_children():
			stack.append([ch, xf])
	if lo.x == INF:
		return AABB()
	return AABB(lo, hi - lo)
