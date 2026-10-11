extends SceneTree
# GameLoop wiring tests (headless, scripted, fixed seed — no pixels): the
# snare/fishing/craft/treat actions driven through the loop's action API the
# same way the input map drives them. Asserts on world state:
#   (a) set snare -> advance days -> collect yields food
#   (b) too-close snare rejected (cordage untouched)
#   (c) fish at a hole adds food; fishRoll deterministic on the roll stream
#   (d) treat reduces infection
# plus the greedy craft key and the snare-marker mesh builder.

var fails := 0


func _init():
	_snare_set_spring_collect()
	_snare_too_close_rejected()
	_fish_at_hole()
	_treat_reduces_infection()
	_craft_best_key()
	_snare_marker_builder()
	if fails == 0:
		print("PASS test_dangers_game: loop-wired snare/fish/craft/treat + markers")
		quit(0)
	else:
		print("FAIL test_dangers_game: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


func _make_loop(p_seed := 11) -> GameLoop:
	var loop := GameLoop.new()
	loop.setup(p_seed)
	return loop


## Pin the vitals so cold/hunger/thirst never kill before the system under
## test does (world.step early-returns once dead). Same helper as test_dangers.
func _keep_alive(w: WorldSim) -> void:
	w.needs.hydration = 100.0
	w.needs.hunger = 100.0
	w.needs.energy = 100.0
	w.needs.coreTemp = 37.0
	w.needs.wetness = 0.0


## (a) X sets a snare on fresh sign; stepping days springs it; E at the snare
## converts pending game into meat in the inventory.
func _snare_set_spring_collect() -> void:
	var loop := _make_loop(11)
	var w := loop.world
	# no cordage yet: the loop's X wrapper toasts the materials hint
	if loop.set_snare() != "Need cordage for a snare.":
		_fail("X without cordage should toast the materials hint")
	w.inventory = {"cordage": 1}
	if loop.set_snare() != "":
		_fail("X with cordage on-stream should succeed silently (log toasts itself)")
	if w.snares.size() != 1:
		_fail("loop.set_snare did not register a snare")
		return
	var sprung := false
	for i in 20 * 24 * 120:  # up to 20 game days at SIM_DT
		_keep_alive(w)
		loop.step_tick()
		if not w.snares[0].set:
			sprung = true
			break
	if not sprung:
		_fail("seed-11 on-stream snare never sprang in 20 game-days")
		return
	if w.snares[0].pending != 1:
		_fail("sprung snare should hold pending=1, got %s" % str(w.snares[0].pending))
	# stand on the snare: E collects (TS SNARE_COLLECT_DIST_M = 3)
	w.player.x = w.snares[0].x
	w.player.z = w.snares[0].z
	loop.interact()
	if not Items.inv_has(w.inventory, "meat", 1):
		_fail("E at the sprung snare should yield meat")
	if w.snares[0].pending != 0:
		_fail("pending should clear after collect")
	_keep_alive(w)
	loop.step_tick()  # harvests the new sim-log line into loop.toasts
	var found := false
	for t in loop.toasts:
		if t == "You collect 1× small game from the snare.":
			found = true
	if not found:
		_fail("collect toast not surfaced through the loop")


## (b) TS setSnareAction too-close rule: a second snare within 8 m is refused
## and the cordage stays in the pack.
func _snare_too_close_rejected() -> void:
	var loop := _make_loop(7)
	var w := loop.world
	w.inventory = {"cordage": 2}
	if loop.set_snare() != "":
		_fail("first snare should set")
	if loop.set_snare() != "Too close to another snare — overlapping runs spook the hares.":
		_fail("second snare within 8 m should toast the too-close hint")
	if w.snares.size() != 1:
		_fail("too-close snare must not be registered")
	if w.inventory.get("cordage", 0) != 1:
		_fail("too-close snare must not consume cordage")
	# 10 m away is fine again
	w.player.x += 10.0
	if loop.set_snare() != "":
		_fail("snare 10 m from the first should set")
	if w.snares.size() != 2:
		_fail("second snare not registered")


## (c) G at an ice-edge hole: cordage-gated, adds meat on a catch, and the
## same seed replays the same caught/missed sequence (deterministic fishRoll).
func _fish_at_hole() -> void:
	var loop := _make_loop(9)
	var w := loop.world
	var hole: Dictionary = w.fishHoles[0]
	w.player.x = hole.x
	w.player.z = hole.z
	if loop.fish() != "Need cordage for a line.":
		_fail("G without cordage should toast the materials hint")
	w.inventory = {"cordage": 5}
	# caught and missed both toast via the sim log (return ""), so count the
	# meat delta per cast — that IS the fishRoll outcome.
	var hits: Array[int] = []
	for i in 6:
		var before: int = w.inventory.get("meat", 0)
		var r := loop.fish()
		if r != "":
			_fail("unexpected fish result at a hole with cordage: %s" % r)
		var after: int = w.inventory.get("meat", 0)
		if after - before > 1:
			_fail("one cast should yield at most 1 meat")
		hits.append(after - before)
	var caught := 0
	for h in hits:
		caught += h
	if w.fishHoles[0].usesLeft != Config.DANGERS.FISH_HOLE_USES - caught:
		_fail("usesLeft should drop once per catch: %d vs %d" % [w.fishHoles[0].usesLeft, caught])
	# determinism: identical seed + identical calls -> identical hit sequence
	var loop2 := _make_loop(9)
	loop2.world.player.x = hole.x
	loop2.world.player.z = hole.z
	loop2.world.inventory = {"cordage": 5}
	for i in 6:
		var b2: int = loop2.world.inventory.get("meat", 0)
		loop2.fish()
		if loop2.world.inventory.get("meat", 0) - b2 != hits[i]:
			_fail("fish not deterministic on seed 9 at cast %d" % i)
			break
	# away from every hole
	var loop3 := _make_loop(9)
	loop3.world.player.x = 300.0
	loop3.world.player.z = 300.0
	if loop3.fish() != "No fish hole here.":
		_fail("G away from holes should toast the no-hole hint")


## (d) H with duct tape + lit fire: infection resets to 0, severity halves,
## tape consumed; without the kit the wound stays infected.
func _treat_reduces_infection() -> void:
	var loop := _make_loop(3)
	var w := loop.world
	DangerSim.add_injury(w.injuries, "cut forearm", 80.0)
	w.injuries[0].infected = true
	w.injuries[0].infection = 90.0
	if loop.treat() != "Need duct tape and a lit fire — and a wound worth treating.":
		_fail("H without kit should toast the treat hint")
	if w.injuries[0].infection != 90.0:
		_fail("failed treat must not change the wound")
	w.inventory = {"ductTape": 1}
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 25.0, true))
	w.nextFireId += 1
	if loop.treat() != "":
		_fail("H with tape + lit fire should succeed silently")
	var inj: Dictionary = w.injuries[0]
	if inj.infected or inj.infection != 0.0:
		_fail("treated wound should be clean: infected=%s infection=%f" % [str(inj.infected), inj.infection])
	if inj.severity != 40.0:
		_fail("treated severity should halve 80→40, got %f" % inj.severity)
	if w.inventory.has("ductTape"):
		_fail("duct tape not consumed")


## B crafts the first craftable recipe (TS craftBest greedy order) and refuses
## politely when nothing is craftable.
func _craft_best_key() -> void:
	var loop := _make_loop(2)
	var w := loop.world
	if loop.craft_best() != "Nothing you can craft right now.":
		_fail("B with empty pack should toast the nothing hint")
	w.inventory = {"bark": 1, "kindling": 2}
	if loop.craft_best() != "":
		_fail("B with tinder materials should craft silently")
	if not Items.inv_has(w.inventory, "tinderBundle", 1):
		_fail("tinderBundle not crafted (greedy order should pick tinderBundle first)")
	_keep_alive(w)
	loop.step_tick()  # harvests the new sim-log line into loop.toasts
	var found := false
	for t in loop.toasts:
		if t == "Crafted: Tinder bundle":
			found = true
	if not found:
		_fail("craft toast not surfaced through the loop")


## Snare marker builder: node shape + the pending-game indicator toggling.
func _snare_marker_builder() -> void:
	var s := DangerSim.make_snare(1, 10.0, 20.0, 0.8)
	var marker := SnareMarkers.make_marker(s, 5.0)
	if marker == null:
		_fail("make_marker returned null")
		return
	if marker.position != Vector3(10.0, 5.0, 20.0):
		_fail("marker not placed at the snare position: %s" % str(marker.position))
	var game: MeshInstance3D = marker.get_node_or_null("Game")
	if game == null:
		_fail("marker missing Game indicator")
		return
	if game.visible:
		_fail("pending-game indicator should be hidden for a fresh snare")
	s.pending = 1
	SnareMarkers.update_marker(marker, s)
	if not game.visible:
		_fail("pending-game indicator should show once the snare holds game")
	marker.free()
