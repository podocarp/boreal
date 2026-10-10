extends Node3D
## BOREAL phase 2b scene: playable loop (GameLoop drives the frozen sim),
## survival HUD, water shader, flat-ground camp, day/night lighting.
## Env: $SHOT_OUT (render_shot.sh), $CHECKPOINT ("camp" | "treeline" |
## "stream" | "hud" | "water" | "overview" | default: follow player),
## $SHOT_FROZEN (=1: deterministic shots), $LEVEL ("generated" = baked
## terrain-gen world from levels/gen_001; default = frozen level, identical).

const SEED := 1
const RENDER_RADIUS := 150.0  # lavapipe budget: cull scatter around the play core
const SHOT_HOUR := 16.5       # golden-hour light for all checkpoints
var _shot_saved := false
var _frozen := false
var _loop: GameLoop
var _water_mat: ShaderMaterial
var _daynight: DayNight
var _fire_light: OmniLight3D
var _flame: MeshInstance3D
var _sky_mat: ProceduralSkyMaterial
var _camp := Vector3.ZERO
var _hm = null  # TerrainHM when LEVEL=generated, else null (frozen Terrain)


func _ready() -> void:
	_frozen = OS.get_environment("SHOT_FROZEN") == "1"
	if OS.get_environment("LEVEL") == "generated":
		_hm = GenLevel.load_hm()
	var env := _add_environment()
	var sun := _add_sun()
	_camp = GenLevel.camp_center(_hm) if _hm != null else CampSite.find_center()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = GenLevel.terrain_mesh(_hm) if _hm != null \
		else TerrainMesh.build(Vector2(Terrain.CRASH.x, Terrain.CRASH.z), 400.0, 128)
	add_child(terrain)
	if _hm != null:
		add_child(GenLevel.collision_body(_hm))
	add_child(_make_scatter())
	_add_water()
	_add_camp()
	_loop = GameLoop.new()
	_loop.name = "GameLoop"
	_loop.setup(SEED)
	if _hm != null:  # swap the terrain provider + re-seat the sim at the bake
		_loop.terrain = _hm
		GenLevel.apply_to_sim(_loop, _hm, SEED)
	add_child(_loop)
	if OS.get_environment("SHOT_OUT") != "":
		_loop.world.hourOfDay = SHOT_HOUR  # golden-hour light for all checkpoints
	_loop.world.fires.append(FireSim.make(_loop.world.nextFireId,
		_camp.x, _camp.z, 60.0, true))
	_loop.world.nextFireId += 1
	_loop.paused = _frozen
	_daynight = DayNight.new()
	_daynight.name = "DayNight"
	_daynight.sun = sun
	_daynight.sky_mat = _sky_mat
	_daynight.environment = env
	add_child(_daynight)
	var hud := SurvivalHud.new()
	hud.name = "Hud"
	hud.loop = _loop
	add_child(hud)
	match OS.get_environment("CHECKPOINT"):
		"camp":
			hud.visible = false
			_add_checkpoint_cam(Vector3(_camp.x + 4.0, 0.0, _camp.z - 13.0), _camp, 2.0)
		"water", "overview":
			# generated-level checkpoints (see GenLevel.checkpoint_cam)
			if _hm == null:
				add_child(_make_player())
			else:
				hud.visible = false
				var cam: Array = GenLevel.checkpoint_cam(_hm, _camp,
					OS.get_environment("CHECKPOINT"))
				_add_checkpoint_cam(cam[0], cam[1], cam[2])
		"treeline":
			hud.visible = false
			_add_checkpoint_cam(Vector3(Terrain.CRASH.x + 26.0, 0.0, Terrain.CRASH.z + 12.0),
				Vector3(Terrain.CRASH.x + 8.0, 0.0, Terrain.CRASH.z + 34.0), 2.0)
		"stream":
			hud.visible = false
			# look UPSTREAM (+z): the ribbon now terminates where the frozen
			# channel ends (lake-flatten region), so looking downstream would
			# show mostly clipped lake shelf.
			var z := -30.0
			_add_checkpoint_cam(Vector3(Terrain.streamX(z), 0.0, z),
				Vector3(Terrain.streamX(z + 40.0), 0.0, z + 40.0), 1.7)
		"hud":
			_add_checkpoint_cam(Vector3(_camp.x - 10.0, 0.0, _camp.z - 9.0), _camp, 2.2)
		_:
			add_child(_make_player())


func _add_environment() -> Environment:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 40.0
	_sky_mat = sky_mat
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_sky_affect = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	return env


func _add_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.06  # kill acne banding on the flat snow
	sun.shadow_normal_bias = 0.08
	add_child(sun)
	return sun


## Sim scatter props (seed SEED): one MultiMeshInstance3D per glTF model.
func _make_scatter() -> Node3D:
	if _hm != null:
		return GenLevel.build_scatter(_hm, SEED, _camp, RENDER_RADIUS)
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


func _add_water() -> void:
	var water := GenLevel.build_water(_hm, _frozen) if _hm != null \
		else WaterRender.build(_frozen)
	_water_mat = water.material_override
	add_child(water)


## Camp on the flattest spot near CRASH (CampSite grid search).
func _add_camp() -> void:
	var camp := CampVisuals.build(_camp)
	add_child(camp)
	_fire_light = camp.get_node("CampfireGlow")
	_flame = camp.get_node("Flame")

## Vendored SDK rig; spawn = sim CRASH site (or baked starter patch).
func _make_player() -> CharacterBody3D:
	return PlayerRig.make(_camp if _hm != null else Vector3.INF, _hm)


## Static camera: eye meters above the ground at the camera spot, looking at
## the target's ground + 1.5. Heights via the active terrain provider.
func _add_checkpoint_cam(pos: Vector3, target: Vector3, eye: float) -> void:
	var h_at := func(x: float, z: float) -> float:
		return _hm.heightAt(x, z) if _hm != null else Terrain.heightAt(x, z)
	pos.y = h_at.call(pos.x, pos.z) + eye
	var cam := Camera3D.new()
	cam.name = "CheckpointCamera"
	cam.position = pos
	add_child(cam)  # look_at requires being inside the tree
	cam.look_at(Vector3(target.x, h_at.call(target.x, target.z) + 1.5, target.z), Vector3.UP)
	cam.current = true


func _process(_d: float) -> void:
	if _loop != null:
		_daynight.apply(_loop.world.hourOfDay)
		if not _frozen:
			_water_mat.set_shader_parameter("u_time", _loop.world.t)
			var stage := 0
			for f in _loop.world.fires:
				stage = maxi(stage, FireSim.fire_stage(f))
			_flame.visible = stage > 0
			_fire_light.visible = stage > 0
			_fire_light.light_energy = 0.5 + 0.3 * float(stage)
			_flame.scale = Vector3.ONE * lerpf(0.5, 1.1, float(stage) / 4.0)
	if _shot_saved:
		return
	_shot_saved = true
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("SHOT_OUT")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit.call_deferred()
