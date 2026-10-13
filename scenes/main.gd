extends Node3D
## BOREAL phase 2b scene: playable loop (GameLoop drives the frozen sim),
## survival HUD, water shader, flat-ground camp, day/night lighting, and the
## game framing (GameState MENU -> PLAYING -> WON/DEAD + title/end screens).
## Env: $SHOT_OUT (render_shot.sh), $CHECKPOINT ("menu" | "dead" | "won" |
## "camp" | "treeline" | "stream" | "hud" | "water" | "overview" | default:
## follow player), $SHOT_FROZEN (=1: deterministic shots), $LEVEL
## ("generated" = baked terrain-gen world from levels/gen_001; default =
## frozen level, identical).

const SEED := 1
const RENDER_RADIUS := 150.0  # lavapipe budget: cull scatter around the play core
const SHOT_HOUR := 16.5       # golden-hour light for all checkpoints
var _shot_saved := false
var _frozen := false
var _loop: GameLoop
var _state: GameState
var _audio: AudioDirector
var _ui: GameUi
var _player: CharacterBody3D
var _water_mat: ShaderMaterial
var _daynight: DayNight
var _fire_light: OmniLight3D
var _flame: MeshInstance3D
var _sky_mat: ProceduralSkyMaterial
var _camp := Vector3.ZERO
var _hm = null  # TerrainHM when LEVEL=generated, else null (frozen Terrain)
var _snare_root: Node3D  # stake/loop markers, one per world snare


## Staged world build (playtest 2026-10-12): _ready used to build the whole
## world synchronously behind the Godot splash — on web that is one long
## main-thread freeze, and the first PLAYING frames then paid audio decode +
## physics activation as a multi-second spike. Now: a loading overlay with a
## progress bar, one build stage per frame chunk, audio beds pre-decoded
## behind the title, and the menu only after WORLD READY.
var _world_ready := false
var _loading: CanvasLayer


func _make_loading() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = "Loading"
	cl.layer = 20
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(box)
	var lbl := Label.new()
	lbl.text = "LOADING…"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	box.add_child(lbl)
	var center := CenterContainer.new()
	box.add_child(center)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(320, 12)
	bar.max_value = 100.0
	bar.show_percentage = false
	center.add_child(bar)
	return cl


func _stage(p: float) -> void:
	if _loading == null:
		return
	var bar := _loading.find_child("Bar", true, false) as ProgressBar
	if bar != null:
		bar.value = p * 100.0
	# two frames: one to apply the additions, one to paint (web rAF)
	await get_tree().process_frame
	await get_tree().process_frame


func _finish_loading() -> void:
	if _loading != null:
		_loading.queue_free()
		_loading = null


func _ready() -> void:
	_frozen = OS.get_environment("SHOT_FROZEN") == "1"
	_loading = _make_loading()
	add_child(_loading)
	if OS.get_environment("LEVEL") == "generated":
		_hm = GenLevel.load_hm()
	var env := _add_environment()
	var sun := _add_sun()
	await _stage(0.10)
	_camp = GenLevel.camp_center(_hm) if _hm != null else CampSite.find_center()
	_add_wreck()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = GenLevel.terrain_mesh(_hm) if _hm != null \
		else TerrainMesh.build(Vector2(Terrain.CRASH.x, Terrain.CRASH.z), 400.0, 128)
	add_child(terrain)
	await _stage(0.25)
	if _hm != null:
		add_child(GenLevel.collision_body(_hm))
	else:
		add_child(_frozen_terrain_collision())
	await _stage(0.35)
	add_child(_make_scatter())
	await _stage(0.55)
	_add_water()
	_add_camp()
	await _stage(0.65)
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
	_state = GameState.new()
	_state.name = "GameState"
	_state.frozen = _frozen
	_state.rebuild = _rebuild_world
	add_child(_state)
	_state.setup(_loop, SEED)
	_state.state_changed.connect(_on_state_changed)
	_audio = AudioDirector.new()
	_audio.name = "AudioDirector"
	_audio.loop = _loop
	_audio.state = _state
	add_child(_audio)  # _ready wires ticked/action/state_changed; headless-safe
	_daynight = DayNight.new()
	_daynight.name = "DayNight"
	_daynight.sun = sun
	_daynight.sky_mat = _sky_mat
	_daynight.environment = env
	add_child(_daynight)
	await _stage(0.80)
	var hud := SurvivalHud.new()
	hud.name = "Hud"
	hud.loop = _loop
	add_child(hud)
	_ui = GameUi.new()
	_ui.name = "GameUi"
	add_child(_ui)
	_ui.build()  # explicit: _ready is deferred under headless scene-construct tests
	_ui.start_pressed.connect(_state.start)
	_ui.restart_pressed.connect(_state.restart)
	_snare_root = Node3D.new()
	_snare_root.name = "SnareMarkers"
	add_child(_snare_root)
	await _stage(0.95)
	match OS.get_environment("CHECKPOINT"):
		"menu":
			# title screen over the frozen camp view
			hud.visible = false
			_add_checkpoint_cam(Vector3(_camp.x + 4.0, 0.0, _camp.z - 13.0), _camp, 2.0)
			_state.force_state(GameState.State.MENU)
		"dead":
			# deterministic end-screen shot: poke the sim's death record
			_add_checkpoint_cam(Vector3(_camp.x + 4.0, 0.0, _camp.z - 13.0), _camp, 2.0)
			_loop.world.dead = {"cause": "hypothermia", "detail": "core temp 29.4 °C"}
			_state.force_state(GameState.State.DEAD)
		"won":
			_add_checkpoint_cam(Vector3(_camp.x + 4.0, 0.0, _camp.z - 13.0), _camp, 2.0)
			_loop.world.rescued = {"day": 8, "kind": "dawn",
				"detail": "The pilot sees your smoke and banks toward you."}
			_state.force_state(GameState.State.WON)
		"camp":
			_state.force_state(GameState.State.PLAYING)
			hud.visible = false
			# pulled back/up vs the other camp cams so the crash-site wreck
			# (Terrain.CRASH, ~8 m east of the flat camp spot) fits in frame
			_add_checkpoint_cam(Vector3(_camp.x + 4.0, 0.0, _camp.z - 18.0), _camp, 2.6)
		"water", "overview":
			# generated-level checkpoints (see GenLevel.checkpoint_cam)
			_state.force_state(GameState.State.PLAYING)
			if _hm == null:
				_add_player()
			else:
				hud.visible = false
				var cam: Array = GenLevel.checkpoint_cam(_hm, _camp,
					OS.get_environment("CHECKPOINT"))
				_add_checkpoint_cam(cam[0], cam[1], cam[2])
		"treeline":
			_state.force_state(GameState.State.PLAYING)
			hud.visible = false
			_add_checkpoint_cam(Vector3(Terrain.CRASH.x + 26.0, 0.0, Terrain.CRASH.z + 12.0),
				Vector3(Terrain.CRASH.x + 8.0, 0.0, Terrain.CRASH.z + 34.0), 2.0)
		"stream":
			_state.force_state(GameState.State.PLAYING)
			hud.visible = false
			# look UPSTREAM (+z): the ribbon now terminates where the frozen
			# channel ends (lake-flatten region), so looking downstream would
			# show mostly clipped lake shelf.
			var z := -30.0
			_add_checkpoint_cam(Vector3(Terrain.streamX(z), 0.0, z),
				Vector3(Terrain.streamX(z + 40.0), 0.0, z + 40.0), 1.7)
		"hud":
			_state.force_state(GameState.State.PLAYING)
			_add_checkpoint_cam(Vector3(_camp.x - 10.0, 0.0, _camp.z - 9.0), _camp, 2.2)
		_:
			# live play: title screen first; PLAYING starts on Enter/click
			_add_player()
			_state.force_state(GameState.State.MENU)
	_world_ready = true
	_finish_loading()


## Live-play rig (kept as a member so restart can re-seat it at spawn).
func _add_player() -> void:
	_player = _make_player()
	add_child(_player)


## Restart hook: fresh WorldSim from the SAME seed, then re-apply everything
## _ready layered on top of setup(): terrain provider, baked-world injection,
## the camp fire, and the 3D rig's seat. No process restart.
func _rebuild_world() -> void:
	_loop.setup(SEED)
	if _hm != null:
		_loop.terrain = _hm
		GenLevel.apply_to_sim(_loop, _hm, SEED)
	_loop.world.fires.append(FireSim.make(_loop.world.nextFireId,
		_camp.x, _camp.z, 60.0, true))
	_loop.world.nextFireId += 1
	if _player != null:
		var sp := _camp if _hm != null else Vector3(Terrain.CRASH.x, 0.0, Terrain.CRASH.z)
		var sy: float = _hm.heightAt(sp.x, sp.z) if _hm != null \
			else Terrain.heightAt(sp.x, sp.z)
		# local position: the rig is a direct child of the (identity) root, and
		# headless scene-construct tests build the tree without entering it.
		_player.position = Vector3(sp.x, sy + 0.85, sp.z)
		_player.velocity = Vector3.ZERO
	for c in _snare_root.get_children():
		c.queue_free()  # stale markers (snare ids restart at 1)


func _on_state_changed(_prev: int, next: int) -> void:
	var playing: bool = next == GameState.State.PLAYING
	if _player != null:
		_player.set_physics_process(playing)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing \
		else Input.MOUSE_MODE_VISIBLE
	match next:
		GameState.State.MENU:
			_ui.show_menu()
		GameState.State.PLAYING:
			_ui.hide_all()
		GameState.State.WON:
			var r: Dictionary = _loop.world.rescued
			_ui.show_end(true, "Rescued on day %d — %s flight.\n%s\n\nYou survived %d %s." \
				% [r.day, r.kind, r.detail, _loop.world.day,
					"day" if _loop.world.day == 1 else "days"])
		GameState.State.DEAD:
			var d: Dictionary = _loop.world.dead
			_ui.show_end(false, "Cause of death: %s (%s)\n\nYou survived %d %s." \
				% [d.cause, d.detail, _loop.world.day,
					"day" if _loop.world.day == 1 else "days"])


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


## Heightfield collider for the frozen level (the generated level bakes its
## own via GenLevel.collision_body). The sim pins the player to heightAt, so
## this exists for the spring-arm camera ray: without it the camera clips
## straight through hills (web 0.1.0 "see right through the hill" report —
## combined with the single-sided mesh, hills looked like holes).
func _frozen_terrain_collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shape := HeightMapShape3D.new()
	const N := 128
	const SIZE := 400.0
	# map_data is row-major over map_width x map_depth (Godot 4.7: packed
	# floats, not an Image; the depth property is map_DEPTH, not map_height —
	# playtest 2026-10-12: the wrong name failed at runtime and the level
	# shipped with NO terrain floor: players fell through after a few steps).
	var data := PackedFloat32Array()
	data.resize(N * N)
	shape.map_width = N
	shape.map_depth = N
	var cx := Terrain.CRASH.x
	var cz := Terrain.CRASH.z
	for j in N:
		var z := cz - SIZE * 0.5 + SIZE * float(j) / float(N - 1)
		for i in N:
			var x := cx - SIZE * 0.5 + SIZE * float(i) / float(N - 1)
			data[j * N + i] = Terrain.heightAt(x, z)
	shape.map_data = data
	cs.shape = shape
	body.add_child(cs)
	# HeightMapShape cells are 1 m; scale to SIZE/(N-1) so the shape spans
	# SIZE meters. The shape is centered on the body origin -> place at CRASH.
	body.scale = Vector3(SIZE / float(N - 1), 1.0, SIZE / float(N - 1))
	body.position = Vector3(cx, 0.0, cz)
	# Layer 1|2: floor for the player capsule (move_and_slide, real gravity —
	# playtest 2026-10-12: gravity 0 + y-pinning felt like floating through
	# the world) AND camera-retract surface for the spring arm (mask 2).
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	return body


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
	root.add_child(ScatterRender.collider_body(instances))
	return root


func _add_water() -> void:
	var water := GenLevel.build_water(_hm, _frozen) if _hm != null \
		else WaterRender.build(_frozen)
	_water_mat = water.material_override
	add_child(water)


## Crash-site wreck: analytic level = Terrain.CRASH; generated level = the
## baked spawn + (6,-6) where GenLevel.apply_to_sim puts the wreck
## interactable. Static decor — restart does not touch it.
func _add_wreck() -> void:
	var site := Vector3(_camp.x + 6.0, 0.0, _camp.z - 6.0) if _hm != null \
		else Vector3(Terrain.CRASH.x, 0.0, Terrain.CRASH.z)
	var h: float = _hm.heightAt(site.x, site.z) if _hm != null \
		else Terrain.heightAt(site.x, site.z)
	var wreck := WreckVisuals.build(site, h, _camp)
	if wreck != null:
		add_child(wreck)


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


## Keep one stake/loop marker per world snare (created on set, kept after a
## spring so the pending game stays visible). Cheap: only diffs by count.
func _sync_snare_markers() -> void:
	var snares: Array = _loop.world.snares
	var h_at := func(x: float, z: float) -> float:
		return _hm.heightAt(x, z) if _hm != null else Terrain.heightAt(x, z)
	for s in snares:
		var mname := "Snare_%d" % int(s.id)
		var marker: Node3D = _snare_root.get_node_or_null(mname)
		if marker == null:
			marker = SnareMarkers.make_marker(s, h_at.call(s.x, s.z))
			_snare_root.add_child(marker)
		else:
			SnareMarkers.update_marker(marker, s)


func _process(_d: float) -> void:
	# staged _ready: _loop exists before _daynight/_water_mat are added
	if _loop != null and _daynight != null and _water_mat != null:
		_daynight.apply(_loop.world.hourOfDay)
		_sync_snare_markers()
		if not _frozen:
			_water_mat.set_shader_parameter("u_time", _loop.world.t)
			var stage := 0
			for f in _loop.world.fires:
				stage = maxi(stage, FireSim.fire_stage(f))
			_flame.visible = stage > 0
			_fire_light.visible = stage > 0
			_fire_light.light_energy = 0.5 + 0.3 * float(stage)
			_flame.scale = Vector3.ONE * lerpf(0.5, 1.1, float(stage) / 4.0)
	# Screenshot-shot mode ONLY: when SHOT_OUT is unset this must do nothing.
	# (Bug, web release 0.1.0: quit() ran unconditionally, so live play killed
	# its own scene tree on frame 2 — frozen menu, dead input, wasm shell
	# spinning on a dead engine. Headless screenshot tests always set SHOT_OUT,
	# so only interactive play exposed it.)
	# _world_ready gate: _ready is staged now; shooting before the world is
	# built would capture the loading bar.
	if _shot_saved or not _world_ready:
		return
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		return
	_shot_saved = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit.call_deferred()


