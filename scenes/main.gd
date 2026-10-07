extends Node3D
## Boreal phase 2a scene: terrain mesh + MultiMesh scatter from the frozen sim,
## arctic lighting, vendored third-person player at the crash site.
## Reads $SHOT_OUT (render_shot.sh contract) and $CHECKPOINT to place a curated
## camera: "camp" | "treeline" | "stream" (default: follow-cam on the player).

const SEED := 1
const RENDER_RADIUS := 150.0  # lavapipe budget: cull scatter around the play core
var _shot_saved := false


func _ready() -> void:
	_add_environment()
	_add_sun()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = TerrainMesh.build(Vector2(Terrain.CRASH.x, Terrain.CRASH.z), 400.0, 128)
	add_child(terrain)
	add_child(_make_scatter())
	_add_camp()
	match OS.get_environment("CHECKPOINT"):
		"camp":
			# from the lake ice: camp mid-ground, starter-grove hill behind
			_add_checkpoint_cam(Vector3(Terrain.CRASH.x + 4.0, 0.0, Terrain.CRASH.z - 14.0),
				Vector3(Terrain.CRASH.x, 0.0, Terrain.CRASH.z), 2.0)
		"treeline":
			# from the grove edge, looking into the starter stand
			_add_checkpoint_cam(Vector3(Terrain.CRASH.x + 26.0, 0.0, Terrain.CRASH.z + 12.0),
				Vector3(Terrain.CRASH.x + 8.0, 0.0, Terrain.CRASH.z + 34.0), 2.0)
		"stream":
			# stand in the channel, look downstream toward the lake; banks frame it
			var z := -30.0
			var sx := Terrain.streamX(z)
			_add_checkpoint_cam(Vector3(sx, 0.0, z),
				Vector3(Terrain.streamX(z - 40.0), 0.0, z - 40.0), 1.7)
		_:
			add_child(_make_player())


func _add_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.58, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.7, 0.68)
	sky_mat.ground_bottom_color = Color(0.55, 0.6, 0.68)
	sky_mat.ground_horizon_color = Color(0.72, 0.7, 0.68)
	sky_mat.sun_angle_max = 40.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.76, 0.83)
	env.fog_density = 0.0035
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)


func _add_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-10.0, -69.0, 0.0)  # low warm sun from the west, shadows cross frame
	sun.light_color = Color(1.0, 0.68, 0.42)
	sun.light_energy = 3.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_bias = 0.06  # kill acne banding on the flat snow
	sun.directional_shadow_normal_bias = 0.08
	add_child(sun)


## All sim scatter props (seed SEED) as one MultiMeshInstance3D per glTF model.
func _make_scatter() -> Node3D:
	var root := Node3D.new()
	root.name = "Scatter"
	var center := Vector2(Terrain.CRASH.x, Terrain.CRASH.z + 10.0)
	var instances := ScatterRender.build_instances(
		Scatter.scatter(SEED), center, RENDER_RADIUS)
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


## Camp read at the crash site: ring of rocks + warm fire glow (wreck model is
## a known asset gap — see docs/asset-inventory.md).
func _add_camp() -> void:
	var rock_mesh := ScatterRender.mesh_from_gltf(
		"res://assets/nature/Rock_Medium_1.gltf")
	if rock_mesh != null:
		var xforms: Array = []
		for k in 9:
			var a := TAU * float(k) / 9.0
			var rx := Terrain.CRASH.x + cos(a) * 1.5
			var rz := Terrain.CRASH.z + sin(a) * 1.5
			var b := Basis(Vector3.UP, a * 2.3).scaled(Vector3.ONE * 0.5)
			xforms.append(Transform3D(b, Vector3(rx, Terrain.heightAt(rx, rz) - 0.25, rz)))
		add_child(ScatterRender.make_multimesh(rock_mesh, xforms, "CampRocks"))
	var fire := OmniLight3D.new()
	fire.name = "CampfireGlow"
	fire.position = Vector3(Terrain.CRASH.x,
		Terrain.heightAt(Terrain.CRASH.x, Terrain.CRASH.z) + 1.2, Terrain.CRASH.z)
	fire.light_color = Color(1.0, 0.42, 0.12)
	fire.light_energy = 20.0
	fire.omni_range = 10.0
	add_child(fire)
	# visible flame: small emissive cone (no flame asset in any pack)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.6
	cone.height = 1.7
	flame.mesh = cone
	var fmat := StandardMaterial3D.new()
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.42, 0.1)
	fmat.emission_energy_multiplier = 1.4
	fmat.albedo_color = Color(1.0, 0.35, 0.1)
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fmat
	flame.position = Vector3(Terrain.CRASH.x,
		Terrain.heightAt(Terrain.CRASH.x, Terrain.CRASH.z) + cone.height * 0.5 + 0.05,
		Terrain.CRASH.z)
	add_child(flame)


## Vendored SDK third-person rig; player spawns at the sim's crash site.
func _make_player() -> CharacterBody3D:
	var PlayerMover: GDScript = load("res://vendor/sdk/player_mover.gd")
	var ThirdPersonCamera: GDScript = load("res://vendor/sdk/camera_third_person.gd")
	var p: CharacterBody3D = PlayerMover.new()
	p.name = "Player"
	p.walk_speed = Config.PLAYER.WALK_SPEED_MPS
	p.sprint_speed = Config.PLAYER.RUN_SPEED_MPS
	p.position = Vector3(Terrain.CRASH.x,
		Terrain.heightAt(Terrain.CRASH.x, Terrain.CRASH.z) + 1.2, Terrain.CRASH.z)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	col.shape = shape
	p.add_child(col)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.79, 0.25, 0.18)  # PALETTE.PARKA — red hero silhouette
	body.material_override = mat
	p.add_child(body)
	var arm: SpringArm3D = ThirdPersonCamera.new()
	arm.name = "CameraThirdPerson"
	arm.target = p
	arm.target_path = NodePath("..")
	arm.pitch = -0.12
	arm.yaw = -2.8  # face the starter grove (CRASH + (10, 28)) at spawn
	arm.apply_look(0.0, 0.0)
	p.add_child(arm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	arm.add_child(cam)
	p.camera_pivot = arm
	return p


## Static camera: eye `eye` meters above the ground at the camera spot,
## looking at the target's ground + 1.5.
func _add_checkpoint_cam(pos: Vector3, target: Vector3, eye: float) -> void:
	pos.y = Terrain.heightAt(pos.x, pos.z) + eye
	var cam := Camera3D.new()
	cam.name = "CheckpointCamera"
	cam.position = pos
	add_child(cam)  # look_at requires being inside the tree
	cam.look_at(Vector3(target.x, Terrain.heightAt(target.x, target.z) + 1.5, target.z), Vector3.UP)
	cam.current = true


func _process(_d: float) -> void:
	if _shot_saved:
		return
	_shot_saved = true
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("SHOT_OUT")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit.call_deferred()
