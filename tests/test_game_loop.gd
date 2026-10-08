extends SceneTree
# GameLoop driver tests (headless, no pixels): fixed-step ticks drive the
# frozen sim; chop/scoop/feed-fire/melt/cook happy paths via the loop's
# action API; needs decay over a game-day; toast events recorded.

var fails := 0


func _init():
	var loop := _make_loop()
	_chop(loop)
	_scoop(loop)
	_feed_fire(loop)
	_melt_and_cook(loop)
	_needs_decay()
	_toasts(loop)
	if fails == 0:
		print("PASS test_game_loop")
		quit(0)
	else:
		print("FAIL test_game_loop: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


func _make_loop() -> GameLoop:
	var loop := GameLoop.new()
	loop.setup(1)
	return loop


## Teleport the sim player onto an interactable of `kind` (nearest one).
func _teleport_to(w: WorldSim, kind: String) -> Variant:
	for it in w.interactables:
		if it.kind == kind and it.uses > 0:
			w.player.x = it.x
			w.player.z = it.z
			return it
	_fail("no interactable of kind " + kind)
	return null


## Run ticks until the work task finishes (bounded).
func _finish_work(loop: GameLoop, max_ticks := 400) -> void:
	var i := 0
	while loop.world.task != null and i < max_ticks:
		loop.step_tick()
		i += 1


func _chop(loop: GameLoop) -> void:
	var w := loop.world
	_teleport_to(w, "deadfall")
	var msg := loop.interact()
	if w.task == null:
		_fail("interact() at deadfall did not start a task (%s)" % msg)
		return
	_finish_work(loop)
	if w.task != null:
		_fail("chop task did not complete")
	if not Items.inv_has(w.inventory, "deadfall"):
		_fail("no deadfall in inventory after chop")
	if not _toast_contains(loop, "Collected"):
		_fail("no 'Collected' toast after chop")


func _scoop(loop: GameLoop) -> void:
	var w := loop.world
	# scoop needs a container: without one, no task starts
	_teleport_to(w, "water")
	loop.interact()
	if w.task != null:
		_fail("scoop should need a container first")
		w.task = null
	Items.inv_add(w.inventory, "tinCup", 1)
	loop.interact()
	if w.task == null:
		_fail("scoop with tinCup should start a task")
		return
	_finish_work(loop)
	if not Items.inv_has(w.inventory, "waterRaw"):
		_fail("no waterRaw after scoop")


func _feed_fire(loop: GameLoop) -> void:
	var w := loop.world
	Items.inv_add(w.inventory, "deadfall", 2)
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 20.0, true))
	w.nextFireId += 1
	var before: float = w.fires[0].fuel
	var msg := loop.feed_fire()
	if w.fires[0].fuel <= before:
		_fail("feed_fire did not raise fuel (%s)" % msg)
	if Items.inv_has(w.inventory, "deadfall", 2):
		_fail("feed_fire did not consume deadfall")


func _melt_and_cook(loop: GameLoop) -> void:
	var w := loop.world
	Items.inv_add(w.inventory, "snow", 1)
	Items.inv_add(w.inventory, "meat", 1)
	if not loop.melt().is_empty() and not Items.inv_has(w.inventory, "waterClean"):
		_fail("melt returned success without waterClean")
	if not Items.inv_has(w.inventory, "waterClean"):
		_fail("melt at lit fire should yield waterClean")
	loop.cook()
	if not Items.inv_has(w.inventory, "meatCooked"):
		_fail("cook at lit fire should yield meatCooked")


func _needs_decay() -> void:
	var loop := _make_loop()
	var w := loop.world
	var h0 := w.needs.hydration
	var g0 := w.needs.hunger
	var e0 := w.needs.energy
	for i in 24 * 120:  # one game-day of 0.25 s real ticks
		loop.step_tick()
	if not w.needs.hydration < h0:
		_fail("hydration should decay over a game-day")
	if not w.needs.hunger < g0:
		_fail("hunger should decay over a game-day")
	if not w.needs.energy < e0:
		_fail("energy should decay over a game-day")
	if absf(w.t - 24.0 * 30.0) > 1e-6:
		_fail("loop time drift: t=%f, expected %f (dt must be REAL seconds)" % [w.t, 720.0])
	loop.free()


func _toasts(loop: GameLoop) -> void:
	loop.world.push_log("toast probe")
	loop.step_tick()
	if not _toast_contains(loop, "toast probe"):
		_fail("push_log line not recorded in toasts")


func _toast_contains(loop: GameLoop, needle: String) -> bool:
	for t in loop.toasts:
		if t.contains(needle):
			return true
	return false
