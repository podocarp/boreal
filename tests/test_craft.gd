extends SceneTree
# Craft port (craft.ts): recipe table, canCraft gating (requires/inputs/output
# fit), atomic all-or-nothing crafts, greedy first-craftable sequence, plus
# the snare/fishing/treat action flows on the seeded world roll() stream.
# Goldens extracted from the REAL TS sim (tools/extract_goldens.mjs).

const Goldens = preload("res://tests/goldens.gd")

var fails := 0


func _init():
	_recipe_table_goldens()
	_can_craft_matrix_goldens()
	_craft_sequence_goldens()
	_craft_atomic_goldens()
	_craft_world_flow()
	_snare_determinism_across_days()
	_fish_yields_table()
	_treat_wound_reduces_infection()
	if fails == 0:
		print("PASS craft: recipe/canCraft/sequence/atomic goldens + snare/fish/treat flows")
		quit(0)
	else:
		print("FAIL craft: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


func _eq(name: String, got: float, want_bits: int, eps := 0.0) -> void:
	if absf(got - Goldens.f(want_bits)) > eps:
		_fail("%s: got %.17f want %.17f" % [name, got, Goldens.f(want_bits)])


# --- recipe table goldens -----------------------------------------------------

func _recipe_table_goldens() -> void:
	if CraftSim.RECIPES.size() != Goldens.CRAFT_RECIPES.size():
		_fail("recipe count got %d want %d" % [CraftSim.RECIPES.size(), Goldens.CRAFT_RECIPES.size()])
		return
	for i in Goldens.CRAFT_RECIPES.size():
		var want: Dictionary = Goldens.CRAFT_RECIPES[i]
		var got: Variant = CraftSim.recipe_by_id(want.id)
		if got == null:
			_fail("recipe %s missing from CraftSim" % want.id)
			continue
		if got.label != want.label:
			_fail("%s: label got %s want %s" % [want.id, got.label, want.label])
		_eq("%s: hours" % want.id, got.hours, want.hours)
		if got.get("requires") != want.requires:
			_fail("%s: requires got %s want %s" % [want.id, str(got.get("requires")), str(want.requires)])
		if got.in != want.in:
			_fail("%s: inputs got %s want %s" % [want.id, str(got.in), str(want.in)])
		if got.out != want.out:
			_fail("%s: outputs got %s want %s" % [want.id, str(got.out), str(want.out)])
	if CraftSim.recipe_by_id("nope") != null:
		_fail("recipe_by_id should return null for unknown id")


# --- canCraft matrix goldens ----------------------------------------------------

func _can_craft_matrix_goldens() -> void:
	var invs := {
		"empty": {},
		"bark4": {"bark": 4},
		"bark4knife": {"bark": 4, "knife": 1},
		"tinder": {"bark": 1, "kindling": 2},
		"kindlingSrc": {"deadfall": 1, "knife": 1},
		"torch": {"bark": 2, "deadfall": 1},
		"boughs6": {"boughs": 6},
		"cordageBlocked": {"bark": 4, "barkContainer": 2},
	}
	for k in Goldens.CAN_CRAFT:
		if not invs.has(k):
			_fail("canCraft golden for unknown inventory %s" % k)
			continue
		var inv: Dictionary = invs[k]
		var want: Array = Goldens.CAN_CRAFT[k]
		for i in CraftSim.RECIPES.size():
			var got := CraftSim.can_craft(inv, CraftSim.RECIPES[i])
			if got != want[i]:
				_fail("canCraft(%s, %s) got %s want %s" % [k, CraftSim.RECIPES[i].id, str(got), str(want[i])])


# --- greedy first-craftable sequence (main.ts craftBest loop) -------------------

func _craft_sequence_goldens() -> void:
	var inv := {"bark": 9, "kindling": 6, "deadfall": 3, "boughs": 6, "knife": 1}
	var steps: Array[String] = []
	for i in 50:
		var pick: Variant = null
		for r in CraftSim.RECIPES:
			if CraftSim.can_craft(inv, r):
				pick = r
				break
		if pick == null:
			break
		if not CraftSim.craft(inv, pick):
			_fail("craft(%s) failed inside canCraft-true loop" % pick.id)
			break
		steps.append(pick.id)
	var want_steps: Array = Goldens.CRAFT_SEQUENCE.steps
	if steps.size() != want_steps.size():
		_fail("sequence steps got %s want %s" % [str(steps), str(want_steps)])
	else:
		for i in steps.size():
			if steps[i] != want_steps[i]:
				_fail("sequence step %d got %s want %s" % [i, steps[i], want_steps[i]])
	if inv != Goldens.CRAFT_SEQUENCE.inv:
		_fail("sequence final inv got %s want %s" % [str(inv), str(Goldens.CRAFT_SEQUENCE.inv)])


# --- atomicity: blocked craft must not consume inputs ----------------------------

func _craft_atomic_goldens() -> void:
	var inv := {"bark": 4, "barkContainer": 2, "knife": 1}
	var r: Variant = CraftSim.recipe_by_id("barkContainer")
	var ok := CraftSim.craft(inv, r)
	if ok != Goldens.CRAFT_ATOMIC.ok:
		_fail("atomic ok got %s want %s" % [str(ok), str(Goldens.CRAFT_ATOMIC.ok)])
	if inv != Goldens.CRAFT_ATOMIC.inv:
		_fail("atomic inv got %s want %s (blocked craft must not consume inputs)" % [str(inv), str(Goldens.CRAFT_ATOMIC.inv)])


# --- world-level craft action: consumes inputs, grants outputs, logs -------------

func _craft_world_flow() -> void:
	var w := WorldSim.new(5)
	w.inventory = {"bark": 1, "kindling": 2}
	var rolls_before: int = w.rngN
	if not Actions.craft(w, "tinderBundle"):
		_fail("Actions.craft tinderBundle should succeed")
	if w.inventory.get("tinderBundle", 0) != 1 or w.inventory.has("bark") or w.inventory.has("kindling"):
		_fail("tinderBundle craft inventory wrong: %s" % str(w.inventory))
	var logged := false
	for e in w.log:
		if e.msg == "Crafted: Tinder bundle":
			logged = true
	if not logged:
		_fail("craft not logged")
	if w.rngN != rolls_before:
		_fail("craft must not consume world RNG rolls")
	# knife-gated recipe refuses without the knife, inventory untouched
	var w2 := WorldSim.new(5)
	w2.inventory = {"bark": 4}
	if Actions.craft(w2, "barkContainer"):
		_fail("barkContainer without knife should fail")
	if w2.inventory.get("bark", 0) != 4:
		_fail("failed craft mutated inventory")
	if Actions.craft(w2, "nope"):
		_fail("unknown recipe id should fail")


# --- snare: deterministic check results across days (world roll stream) ----------

func _snare_determinism_across_days() -> void:
	var a := WorldSim.new(31)
	var b := WorldSim.new(31)
	a.inventory = {"cordage": 1}
	b.inventory = {"cordage": 1}
	if Actions.set_snare(a) != "set" or Actions.set_snare(b) != "set":
		_fail("set_snare failed on seed-31 worlds")
		return
	var caught_a := 0
	for day in 5:
		for i in 24 * 120:  # one game day at SIM_DT (1/120 h steps)
			_keep_alive(a)
			_keep_alive(b)
			a.step()
			b.step()
		if not a.snares[0].set and caught_a == 0:
			caught_a = a.day
	# identical worlds must agree on every snare field
	if a.snares[0].set != b.snares[0].set:
		_fail("snare set flag diverged across worlds")
	if a.snares[0].ageH != b.snares[0].ageH:
		_fail("snare ageH diverged: %f vs %f" % [a.snares[0].ageH, b.snares[0].ageH])
	if a.snares[0].pending != b.snares[0].pending:
		_fail("snare pending diverged")
	if a.rngN != b.rngN:
		_fail("roll stream diverged")
	# if it sprang, collecting at the snare yields exactly the pending game
	if not a.snares[0].set:
		if a.snares[0].pending != 1:
			_fail("sprung snare pending should be 1, got %s" % str(a.snares[0].pending))
		a.player.x = a.snares[0].x
		a.player.z = a.snares[0].z
		if Actions.check_snares(a) != 1:
			_fail("check_snares should collect 1")
		if Actions.check_snares(a) != 0:
			_fail("check_snares should collect 0 after clearing pending")
	# a snare set far off-stream (quality 0) still ticks but at the floor rate;
	# determinism above is the load-bearing check, plus TS golden hours in
	# test_dangers cover the catch timing itself.


# --- fish yields per TS table -----------------------------------------------------

func _fish_yields_table() -> void:
	# golden hour table: fresh rng(seed 3) per hour
	for e in Goldens.FISH_ROLL:
		var rng := Rng.make_rng(3)
		var got := DangerSim.fish_roll(e.hour, rng.next)
		if got != e.hit:
			_fail("fishRoll(%s) got %s want %s" % [str(e.hour), str(got), str(e.hit)])
	# seed 3's first mulberry32 roll misses every hour's p — the golden table
	# is all-miss; assert the extraction isn't silently empty of structure
	if Goldens.FISH_ROLL.size() != 48:
		_fail("fish golden table should cover 48 half-hours, got %d" % Goldens.FISH_ROLL.size())
	# world flow at a fish hole: cordage-gated, usesLeft decrements only on a
	# catch, and the same seed replays identically
	var w := WorldSim.new(9)
	var hole: Dictionary = w.fishHoles[0]
	w.player.x = hole.x
	w.player.z = hole.z
	if Actions.fish(w) != "materials":
		_fail("fish without cordage should return materials")
	w.inventory = {"cordage": 5}
	var results: Array[String] = []
	for i in 6:
		results.append(Actions.fish(w))
	for r in results:
		if r != "caught" and r != "missed":
			_fail("fish returned %s at a hole with cordage" % r)
	var caught := 0
	for r in results:
		if r == "caught":
			caught += 1
	if w.fishHoles[0].usesLeft != Config.DANGERS.FISH_HOLE_USES - caught:
		_fail("usesLeft should drop once per catch: %d vs %d catches" % [w.fishHoles[0].usesLeft, caught])
	if w.inventory.get("meat", 0) != caught:
		_fail("meat yield should equal catches: %d vs %d" % [w.inventory.get("meat", 0), caught])
	# replay determinism on the roll stream
	var w2 := WorldSim.new(9)
	w2.player.x = hole.x
	w2.player.z = hole.z
	w2.inventory = {"cordage": 5}
	for i in 6:
		if Actions.fish(w2) != results[i]:
			_fail("fish not deterministic on seed 9")
			break
	# far from any hole
	var w3 := WorldSim.new(9)
	w3.player.x = 300.0
	w3.player.z = 300.0
	if Actions.fish(w3) != "no-hole":
		_fail("fish away from holes should return no-hole")


# --- treat_wound reduces infection per TS ------------------------------------------

func _treat_wound_reduces_infection() -> void:
	var w := WorldSim.new(3)
	DangerSim.add_injury(w.injuries, "test wound", 80.0)
	w.injuries[0].infected = true
	w.injuries[0].infection = 90.0
	# needs duct tape + a lit fire at hand
	if Actions.treat_wound(w):
		_fail("treat_wound without duct tape should fail")
	w.inventory = {"ductTape": 1}
	if Actions.treat_wound(w):
		_fail("treat_wound without a lit fire should fail")
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 25.0, true))
	w.nextFireId += 1
	if not Actions.treat_wound(w):
		_fail("treat_wound should succeed with tape + fire")
		return
	var inj: Dictionary = w.injuries[0]
	if inj.infected or inj.infection != 0.0:
		_fail("treated wound should be clean: infected=%s infection=%f" % [str(inj.infected), inj.infection])
	_eq("treated severity", inj.severity, Goldens.TREAT_INJURY.severity)
	if w.inventory.has("ductTape"):
		_fail("duct tape not consumed")
	# TS treatInjury predicate: infected or severity > 30. The treated wound
	# (sev 40) still qualifies — TS re-treats it down to the floor. A list with
	# ONLY a clean low-severity wound is not treatable (TS golden cleanLow).
	DangerSim.add_injury(w.injuries, "scratch", 20.0)
	w.inventory = {"ductTape": 1}
	if not Actions.treat_wound(w):
		_fail("sev-40 wound should be re-treatable (TS find predicate)")
	if w.injuries[0].severity != 20.0:
		_fail("re-treated severity should halve 40→20, got %f" % w.injuries[0].severity)
	if w.injuries[1].severity != 20.0:
		_fail("re-treat must not touch the scratch")
	var w4 := WorldSim.new(3)
	DangerSim.add_injury(w4.injuries, "scratch", 20.0)
	w4.inventory = {"ductTape": 1}
	w4.fires.append(FireSim.make(w4.nextFireId, w4.player.x, w4.player.z, 25.0, true))
	w4.nextFireId += 1
	if Actions.treat_wound(w4):
		_fail("clean-only sev-20 list should not be treatable (TS find predicate)")
	if w4.inventory.get("ductTape", 0) != 1:
		_fail("failed treat must not consume duct tape")


## Pin the vitals so cold/hunger/thirst never kill before the snare does
## (world.step early-returns once dead). Same helper as test_dangers.
func _keep_alive(w: WorldSim) -> void:
	w.needs.hydration = 100.0
	w.needs.hunger = 100.0
	w.needs.energy = 100.0
	w.needs.coreTemp = 37.0
	w.needs.wetness = 0.0
