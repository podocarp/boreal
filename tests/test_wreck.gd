extends SceneTree
# Wreck asset tests (headless, no pixels): the crash-site model loads and
# yields a Mesh; WreckVisuals.build poses a sane normalized wreck at the site;
# the real main scene places a "Wreck" node at the crash site on BOTH level
# modes (analytic Terrain.CRASH and the generated level's baked spawn + (6,-6)),
# matching the sim's own wreck interactable position.

const SEED := 1  # must match scenes/main.gd

var fails := 0


func _init():
	_test_model_loads()
	_test_build_pose()
	_test_main_analytic()
	_test_main_generated()
	if fails == 0:
		print("PASS test_wreck")
		quit(0)
	else:
		print("FAIL test_wreck: %d checks failed" % fails)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  " + msg)


func _test_model_loads() -> void:
	var mesh := WreckVisuals.mesh()
	_check(mesh != null, "wreck model did not load / yielded no Mesh")
	if mesh == null:
		return
	_check(mesh.get_surface_count() >= 1, "wreck mesh has no surfaces")


func _test_build_pose() -> void:
	var site := Vector3(10.0, 0.0, 20.0)
	var wreck := WreckVisuals.build(site, 3.0, Vector3(12.0, 0.0, 25.0))
	_check(wreck != null, "WreckVisuals.build returned null")
	if wreck == null:
		return
	_check(wreck.name == "Wreck", "wreck root named '%s'" % wreck.name)
	_check(wreck.position == Vector3(site.x, 3.0 - WreckVisuals.SINK, site.z),
		"wreck origin not at site (sink applied): %s" % str(wreck.position))
	# a MeshInstance3D must exist under the wrapper
	var found := false
	var stack: Array = [wreck]
	while not stack.is_empty() and not found:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found = true
		for c in n.get_children():
			stack.append(c)
	_check(found, "no MeshInstance3D under the wreck wrapper")
	# normalized size: largest horizontal dim ~ TARGET_SPAN
	var box := WreckVisuals.merged_aabb(wreck)
	var span := maxf(box.size.x, box.size.z)
	_check(absf(span - WreckVisuals.TARGET_SPAN) < 0.5,
		"wreck span %.2f off target %.2f" % [span, WreckVisuals.TARGET_SPAN])
	# deterministic: same inputs -> identical transform
	var again := WreckVisuals.build(site, 3.0, Vector3(12.0, 0.0, 25.0))
	_check(again.transform == wreck.transform, "wreck pose not deterministic")
	again.free()
	wreck.free()


## Instantiate the real main scene (test_gen_level pattern: call _ready()
## directly so the shot-save quit() never fires) and find the Wreck node.
func _wreck_in_main(level: String) -> Dictionary:
	OS.set_environment("LEVEL", level)
	OS.set_environment("CHECKPOINT", "")
	OS.set_environment("SHOT_OUT", "")
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main.tscn missing")
	if packed == null:
		return {}
	var main := packed.instantiate()
	root.add_child(main)
	main._ready()
	var out := {"main": main}
	out["wreck"] = main.get_node_or_null("Wreck")
	var loop: Node = main.get_node_or_null("GameLoop")
	out["loop"] = loop
	return out


func _test_main_analytic() -> void:
	var r := _wreck_in_main("")
	if r.is_empty():
		return
	var main: Node = r["main"]
	var wreck: Node3D = r["wreck"]
	_check(wreck != null, "no Wreck node in analytic main scene")
	if wreck != null:
		_check(absf(wreck.position.x - Terrain.CRASH.x) < 1e-3
			and absf(wreck.position.z - Terrain.CRASH.z) < 1e-3,
			"analytic wreck at %s, expected at CRASH (%.1f, %.1f)"
			% [str(wreck.position), Terrain.CRASH.x, Terrain.CRASH.z])
		# the sim's own wreck interactable must sit under the visual
		var loop: Node = r["loop"]
		var hit := false
		for it in loop.world.interactables:
			if it.kind == "wreck" \
					and absf(float(it.x) - wreck.position.x) < 1e-3 \
					and absf(float(it.z) - wreck.position.z) < 1e-3:
				hit = true
		_check(hit, "no sim wreck interactable at the visual's position")
	main.free()


func _test_main_generated() -> void:
	var r := _wreck_in_main("generated")
	if r.is_empty():
		return
	var main: Node = r["main"]
	var wreck: Node3D = r["wreck"]
	_check(wreck != null, "no Wreck node in generated main scene")
	if wreck != null:
		var loop: Node = r["loop"]
		var hit := false
		for it in loop.world.interactables:
			if it.kind == "wreck" \
					and absf(float(it.x) - wreck.position.x) < 1e-3 \
					and absf(float(it.z) - wreck.position.z) < 1e-3:
				hit = true
		_check(hit, "generated wreck visual not at the sim wreck interactable")
	main.free()
	OS.set_environment("LEVEL", "")
