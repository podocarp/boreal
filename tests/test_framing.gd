extends SceneTree
# Game-framing tests (headless, scripted, fixed seeds — no pixels): the
# GameState machine (MENU -> PLAYING -> WON / DEAD) driving off real sim
# outcomes, plus restart-from-same-seed.
#   (a) drive the sim to the day-7 dawn pass with a lit signal fire on open
#       ground (seed 34 spots deterministically) -> state WON
#   (b) force hypothermia (core temp pinned below HYPOTHERMIA_C, no fire) ->
#       DEAD with cause "hypothermia"
#   (c) restart -> fresh WorldSim (same seed), state PLAYING, needs reset,
#       toasts/tick counters cleared
#   (d) transition guards + the real main scene boots into MENU with the
#       title screen up (and end screens render their cause/day text)

var fails := 0


func _init():
	_win_drives_state()
	_death_drives_state()
	_restart_fresh_world()
	_transition_guards()
	_main_scene_boots_to_menu()
	if fails == 0:
		print("PASS test_framing: MENU/PLAYING/WON/DEAD + restart-from-seed")
		quit(0)
	else:
		print("FAIL test_framing: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


## GameState wired to a fresh loop, starting in PLAYING (the machine's own
## MENU->PLAYING gate is covered by _transition_guards).
func _make_state(p_seed: int) -> GameState:
	var loop := GameLoop.new()
	loop.setup(p_seed)
	var gs := GameState.new()
	gs.setup(loop, p_seed)
	gs.force_state(GameState.State.PLAYING)
	return gs


func _keep_alive(w: WorldSim) -> void:
	w.needs.hydration = 100.0
	w.needs.hunger = 100.0
	w.needs.energy = 100.0
	w.needs.coreTemp = 37.0
	w.needs.wetness = 0.0


## (a) Real rescue detection: signal fire + open ground (lake) at the day-7
## dawn pass. Seed 34 spots on the seeded roll stream (p = 0.92 open-ground
## signal smoke); the state machine must flip PLAYING -> WON off the sim's
## own `rescued` record — no direct state poke.
func _win_drives_state() -> void:
	var gs := _make_state(34)
	var w := gs.loop.world
	w.player.zone = "lake"
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 200.0, true))
	w.signalFireId = w.nextFireId
	w.nextFireId += 1
	var guard := 0
	while gs.state == GameState.State.PLAYING and guard < 24 * 120 * 8:
		_keep_alive(w)
		gs.loop.step_tick()
		guard += 1
	if gs.state != GameState.State.WON:
		_fail("signal-fire run should reach WON, got state %d after %d ticks" \
			% [gs.state, guard])
		return
	if w.rescued == null or w.rescued.day != 7:
		_fail("rescued record missing or not day 7: %s" % str(w.rescued))
	# WON is terminal: further ticks must not move the state
	gs.loop.step_tick()
	if gs.state != GameState.State.WON:
		_fail("WON should be terminal")


## (b) Hypothermia death: core temp pinned below HYPOTHERMIA_C with no fire
## warmth -> health drains -> DEAD, cause string from the sim.
func _death_drives_state() -> void:
	var gs := _make_state(5)
	var w := gs.loop.world
	var guard := 0
	while gs.state == GameState.State.PLAYING and guard < 24 * 120 * 10:
		w.needs.hydration = 100.0
		w.needs.hunger = 100.0
		w.needs.energy = 100.0
		w.needs.coreTemp = 30.0  # below HYPOTHERMIA_C (33): HYPO_HP_PER_H drains health
		w.needs.wetness = 0.0
		gs.loop.step_tick()
		guard += 1
	if gs.state != GameState.State.DEAD:
		_fail("pinned hypothermia should reach DEAD, got state %d after %d ticks" \
			% [gs.state, guard])
		return
	if w.dead == null or w.dead.cause != "hypothermia":
		_fail("death cause should be hypothermia, got %s" % str(w.dead))
	if w.dead.detail == null or str(w.dead.detail) == "":
		_fail("death record should carry a detail string")


## (c) Restart: fresh WorldSim from the SAME seed, state back to PLAYING,
## needs at their create() values, dead/rescued cleared, loop counters reset.
func _restart_fresh_world() -> void:
	var gs := _make_state(5)
	var w0 := gs.loop.world
	# drive it to a death the slow way (same pin as (b))
	var guard := 0
	while gs.state == GameState.State.PLAYING and guard < 24 * 120 * 10:
		w0.needs.hydration = 100.0
		w0.needs.hunger = 100.0
		w0.needs.energy = 100.0
		w0.needs.coreTemp = 30.0
		gs.loop.step_tick()
		guard += 1
	if gs.state != GameState.State.DEAD:
		_fail("restart pre-condition: run should be DEAD")
		return
	var old_world := gs.loop.world
	var old_ticks := gs.loop.tick_count
	gs.restart()
	if gs.state != GameState.State.PLAYING:
		_fail("restart should land in PLAYING, got %d" % gs.state)
	var w1 := gs.loop.world
	if w1 == old_world:
		_fail("restart must build a NEW WorldSim")
	if w1.seed != 5:
		_fail("restart must reuse the run seed, got %d" % w1.seed)
	if w1.dead != null or w1.rescued != null:
		_fail("restarted world should be alive")
	var fresh := Needs.create()
	if w1.needs.hydration != fresh.hydration or w1.needs.hunger != fresh.hunger \
			or w1.needs.energy != fresh.energy or w1.needs.health != fresh.health \
			or w1.needs.coreTemp != fresh.coreTemp:
		_fail("restarted needs should equal create() defaults")
	if gs.loop.tick_count != 0 or gs.loop.toasts.size() != 0:
		_fail("restart should reset tick counter + toasts (was %d ticks)" % old_ticks)
	if w1.day != 1 or w1.t != 0.0:
		_fail("restarted world should be at day 1 / t 0")
	# the fresh world still dies the same way (same seed, same policy)
	guard = 0
	while gs.state == GameState.State.PLAYING and guard < 24 * 120 * 10:
		w1.needs.hydration = 100.0
		w1.needs.hunger = 100.0
		w1.needs.energy = 100.0
		w1.needs.coreTemp = 30.0
		gs.loop.step_tick()
		guard += 1
	if gs.state != GameState.State.DEAD:
		_fail("restarted run should replay to DEAD on the same seed")


## (d) Transition rules: start only from MENU; restart only from WON/DEAD;
## sim outcomes only observed while PLAYING.
func _transition_guards() -> void:
	var loop := GameLoop.new()
	loop.setup(2)
	var gs := GameState.new()
	gs.setup(loop, 2)
	if gs.state != GameState.State.MENU:
		_fail("machine should boot in MENU")
	if not loop.paused:
		_fail("sim should be paused in MENU")
	gs.restart()  # not allowed from MENU
	if gs.state != GameState.State.MENU:
		_fail("restart from MENU must be a no-op")
	gs.start()
	if gs.state != GameState.State.PLAYING or loop.paused:
		_fail("start should enter PLAYING unpaused")
	gs.start()  # already playing: no-op
	if gs.state != GameState.State.PLAYING:
		_fail("second start must be a no-op")
	# outcomes are ignored outside PLAYING (e.g. a poked death while in MENU)
	gs.goto(GameState.State.MENU)
	loop.world.dead = {"cause": "exposure", "detail": "poke"}
	gs.loop.step_tick()
	if gs.state != GameState.State.MENU:
		_fail("MENU must not react to sim outcomes")
	gs.goto(GameState.State.PLAYING)
	# now the same dead record flips it on the next tick
	gs.loop.step_tick()
	if gs.state != GameState.State.DEAD:
		_fail("PLAYING should flip to DEAD on world.dead")
	if not loop.paused:
		_fail("sim should pause on DEAD")
	gs.restart()
	if gs.state != GameState.State.PLAYING:
		_fail("restart from DEAD should enter PLAYING")
	if loop.world.dead != null:
		_fail("bare restart (no rebuild hook) should clear dead via fresh world")


## The real main scene boots into MENU with the title screen visible, and the
## end-screen checkpoints render the right copy. Same synchronous-_ready
## trick as test_gen_level (the tree never iterates, so the shot-save quit()
## never fires).
func _main_scene_boots_to_menu() -> void:
	OS.set_environment("CHECKPOINT", "")
	OS.set_environment("SHOT_OUT", "")
	OS.set_environment("LEVEL", "")
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("main.tscn missing")
		return
	var main := packed.instantiate()
	root.add_child(main)
	main._ready()
	var gs: GameState = main.get_node_or_null("GameState")
	var ui: GameUi = main.get_node_or_null("GameUi")
	if gs == null or ui == null:
		_fail("GameState/GameUi missing from main scene")
		root.remove_child(main)
		main.free()
		return
	if gs.state != GameState.State.MENU:
		_fail("live boot should start in MENU, got %d" % gs.state)
	if ui.mode != GameUi.Mode.MENU:
		_fail("title screen should be up on boot")
	if ui.headline.text != "BOREAL":
		_fail("title headline should read BOREAL, got %s" % ui.headline.text)
	var loop: GameLoop = main.get_node_or_null("GameLoop")
	if loop == null or not loop.paused:
		_fail("sim should be paused behind the title screen")
	# Enter on the menu starts play and hides the overlay
	ui._accept()
	if gs.state != GameState.State.PLAYING or ui.mode != GameUi.Mode.NONE:
		_fail("start_pressed should enter PLAYING and hide the menu")
	# death screen copy via the state-change handler
	loop.world.dead = {"cause": "hypothermia", "detail": "core temp 29.4 °C"}
	gs.force_state(GameState.State.DEAD)
	if ui.mode != GameUi.Mode.END or not ("hypothermia" in ui.body.text):
		_fail("death screen should show the cause: %s" % ui.body.text)
	if not ("survived" in ui.body.text):
		_fail("death screen should show days survived")
	# restart through the UI path rebuilds the world
	ui._accept()
	if gs.state != GameState.State.PLAYING or loop.world.dead != null:
		_fail("restart_pressed should rebuild + enter PLAYING")
	if ui.mode != GameUi.Mode.NONE:
		_fail("end screen should hide on restart")
	root.remove_child(main)
	main.free()
