extends SceneTree
# Audio mapping tests (headless, no pixels, no audio driver): AudioMap is a
# pure state->sound function, so every check runs without an AudioStreamPlayer.
#   (a) determinism: same crafted state dict -> identical mapping, twice
#   (b) crafted states: fire warm -> crackle on; storm 0.9 -> wind loud;
#       calm day -> wind inaudible; moving -> footstep cadence by zone;
#       MENU state -> silence
#   (c) real sim states via from_world: camp fire -> crackle; day-4 storm ->
#       wind loud; storm severity read from the frozen schedule
#   (d) every registered stream file loads to an AudioStream (import pass)
#   (e) the real main scene boots with an AudioDirector node that consumes
#       sim ticks headless (last_mapping updates; nothing plays)

var fails := 0


func _init():
	_test_determinism()
	_test_crafted_states()
	_test_from_world()
	_test_streams_load()
	_test_main_scene()
	if fails == 0:
		print("PASS test_audio_map: pure state->sound mapping + headless director")
		quit(0)
	else:
		print("FAIL test_audio_map: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


func _state(over := {}) -> Dictionary:
	var s := {
		"fire_warmth": 0.0, "wind_kmh": 10.0, "storm_severity": 0.0,
		"moving": false, "speed": 0.0, "zone": "forest",
		"game_state": 1,  # GameState.State.PLAYING
	}
	for k in over:
		s[k] = over[k]
	return s


## (a) pure + deterministic: identical inputs -> identical outputs.
func _test_determinism() -> void:
	var a := AudioMap.map_state(_state({"fire_warmth": 0.6, "wind_kmh": 30.0,
		"moving": true, "speed": 2.6}))
	var b := AudioMap.map_state(_state({"fire_warmth": 0.6, "wind_kmh": 30.0,
		"moving": true, "speed": 2.6}))
	if str(a) != str(b):
		_fail("mapping not deterministic: %s vs %s" % [str(a), str(b)])
	# and it must actually be doing something
	if (a["loops"] as Dictionary).is_empty():
		_fail("warm fire + 30 km/h wind mapped to silence")


## (b) the crafted states from the card.
func _test_crafted_states() -> void:
	# fire warm -> crackle on, volume == warmth
	var m := AudioMap.map_state(_state({"fire_warmth": 0.7}))
	var loops: Dictionary = m["loops"]
	if not loops.has(AudioMap.LOOP_FIRE):
		_fail("fire warmth 0.7 -> no crackle")
	elif absf(float(loops[AudioMap.LOOP_FIRE]) - 0.7) > 1e-9:
		_fail("crackle volume %.3f != warmth 0.7" % loops[AudioMap.LOOP_FIRE])
	# dead fire -> no crackle
	if (AudioMap.map_state(_state())["loops"] as Dictionary).has(AudioMap.LOOP_FIRE):
		_fail("zero warmth still mapped crackle")
	# storm severity 0.9 on an exposed tile -> wind loud
	# (world.ts wind chain: 10 * 1.35 * (1 + 0.9*1.6) = 33.75 km/h)
	m = AudioMap.map_state(_state({"wind_kmh": 10.0 * 1.35 * (1.0 + 0.9 * 1.6),
		"storm_severity": 0.9}))
	loops = m["loops"]
	if not loops.has(AudioMap.LOOP_WIND) or float(loops[AudioMap.LOOP_WIND]) < 0.7:
		_fail("storm 0.9 wind not loud: %s" % str(loops))
	# calm day (base wind, forest) -> wind inaudible
	loops = AudioMap.map_state(_state({"wind_kmh": 10.0 * 0.6}))["loops"]
	if loops.has(AudioMap.LOOP_WIND):
		_fail("calm 6 km/h mapped audible wind: %s" % str(loops))
	# footstep cadence: running faster than walking, stopped -> silent
	var walk := AudioMap.map_state(_state({"moving": true, "speed": 2.6}))
	var run := AudioMap.map_state(_state({"moving": true, "speed": 5.0}))
	var idle := AudioMap.map_state(_state())
	if not (float(run["step_interval"]) < float(walk["step_interval"])):
		_fail("run cadence %.3f not faster than walk %.3f" \
			% [run["step_interval"], walk["step_interval"]])
	if float(idle["step_interval"]) != 0.0 or float(idle["step_vol"]) != 0.0:
		_fail("idle state still maps footsteps")
	# surface changes loudness: lake ice > forest
	if not (float(run["step_vol"]) > 0.0):
		_fail("run step_vol zero")
	var lake := AudioMap.map_state(_state({"moving": true, "speed": 2.6, "zone": "lake"}))
	var forest := AudioMap.map_state(_state({"moving": true, "speed": 2.6, "zone": "forest"}))
	if not (float(lake["step_vol"]) > float(forest["step_vol"])):
		_fail("lake ice not louder than forest: %s vs %s" % [lake["step_vol"], forest["step_vol"]])
	# outside PLAYING -> total silence (loops off, no steps)
	var menu := AudioMap.map_state(_state({"fire_warmth": 1.0, "wind_kmh": 60.0,
		"moving": true, "speed": 5.0, "game_state": 0}))
	if not (menu["loops"] as Dictionary).is_empty() or float(menu["step_interval"]) != 0.0:
		_fail("MENU state mapped sound: %s" % str(menu))


## (c) from a REAL WorldSim: camp fire warmth -> crackle; the frozen day-4
## storm schedule -> loud wind; severity extracted from the schedule.
func _test_from_world() -> void:
	var w := WorldSim.new(1)
	w.player.moving = false
	# no fire yet, early hour: fire loop must be off
	var m := AudioMap.map_state(AudioMap.from_world(w, 1))
	if (m["loops"] as Dictionary).has(AudioMap.LOOP_FIRE):
		_fail("fireless world mapped crackle: %s" % str(m["loops"]))
	# light a big fire AT the player -> warmth 0.85 at stage 4 center
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 100.0, true))
	w.nextFireId += 1
	w.step(Config.SIM_DT)
	m = AudioMap.map_state(AudioMap.from_world(w, 1))
	var loops: Dictionary = m["loops"]
	if not loops.has(AudioMap.LOOP_FIRE) or float(loops[AudioMap.LOOP_FIRE]) < 0.5:
		_fail("lit fire at player -> no strong crackle: %s" % str(loops))
	# day-4 storm (severity 0.85 from the frozen schedule), lake zone, mid-storm
	w.day = 4
	w.hourOfDay = 20.0
	w.player.zone = "lake"
	w.step(Config.SIM_DT)
	var st := AudioMap.from_world(w, 1)
	if absf(float(st["storm_severity"]) - 0.85) > 1e-9:
		_fail("storm severity %.2f != 0.85 (frozen schedule)" % st["storm_severity"])
	m = AudioMap.map_state(st)
	loops = m["loops"]
	if not loops.has(AudioMap.LOOP_WIND) or float(loops[AudioMap.LOOP_WIND]) < 0.8:
		_fail("day-4 storm wind not loud: %s" % str(loops))


## (d) every registered stream exists and imports as an AudioStream.
func _test_streams_load() -> void:
	var names: Array = AudioMap.LOOP_NAMES + AudioMap.EVENT_STREAMS
	for i in AudioMap.FOOTSTEP_VARIANTS:
		names.append("%s_%02d" % [AudioMap.EVENT_FOOTSTEP, i])
	for n in names:
		var path := "res://assets/audio/%s.ogg" % n
		var s = load(path)
		if s == null:
			_fail("stream missing: " + path)
		elif not (s is AudioStream):
			_fail("%s did not import as AudioStream" % path)


## (e) the real main scene boots headless with an AudioDirector consuming
## ticks (test_wreck pattern: call _ready() directly; nothing plays headless).
func _test_main_scene() -> void:
	OS.set_environment("CHECKPOINT", "")
	OS.set_environment("SHOT_OUT", "")
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("main.tscn missing")
		return
	var scene := packed.instantiate()
	scene._ready()
	var dir := scene.get_node_or_null("AudioDirector")
	if dir == null:
		_fail("no AudioDirector node in the main scene")
		scene.free()
		return
	dir._ready()  # scene never enters the tree here: wire it manually
	var loop: GameLoop = scene.get_node("GameLoop")
	var before: Dictionary = (dir as AudioDirector).last_mapping
	for i in 4:
		loop.step_tick()
	var after: Dictionary = (dir as AudioDirector).last_mapping
	if after.is_empty():
		_fail("AudioDirector.last_mapping never updated from sim ticks")
	elif not after.has("loops"):
		_fail("last_mapping missing 'loops': %s" % str(after))
	# action signal exists (UI confirm hook)
	if not loop.has_signal("action_performed"):
		_fail("GameLoop missing action_performed signal")
	# the director must NOT have created players headless (guarded)
	if OS.has_feature("headless") and dir.get_child_count() > 0:
		_fail("AudioDirector created players under headless")
	scene.free()
