extends SceneTree
# Dangers port (S6, wolves deliberately cut): snares as a player-placed FOOD
# SOURCE (never a hazard), ice-edge fishing, injury→infection→sepsis machinery.
# Goldens extracted from the REAL TS sim (tools/extract_goldens.mjs).

const Goldens = preload("res://tests/goldens.gd")

var fails := 0


func _init():
	_hare_sign_goldens()
	_snare_tick_goldens()
	_snare_world_flow()
	_fish_roll_table()
	_fish_world_flow()
	_injury_timeline_goldens()
	_sepsis_death_chain()
	_treat_injury_goldens()
	if fails == 0:
		print("PASS dangers: snare/fishing/injury goldens + sepsis death chain")
		quit(0)
	else:
		print("FAIL dangers: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


## Pin the vitals so cold/hunger/thirst never kill before the danger under
## test does (step() early-returns once dead, which would freeze snare/injury
## ticking). Sepsis damage is applied by world.step AFTER this, so the
## infection death chain still runs to completion.
func _keep_alive(w: WorldSim) -> void:
	w.needs.hydration = 100.0
	w.needs.hunger = 100.0
	w.needs.energy = 100.0
	w.needs.coreTemp = 37.0
	w.needs.wetness = 0.0


func _bits(f: float) -> int:
	var b := PackedFloat64Array([f]).to_byte_array()
	var v := 0
	for i in 8:
		v |= int(b[7 - i]) << (8 * (7 - i))
	if v >= (1 << 63):
		v -= (1 << 64)
	return v


func _eq(name: String, got: float, want_bits: int, eps := 1e-12) -> void:
	if absf(got - Goldens.f(want_bits)) > eps:
		_fail("%s: got %.17f want %.17f" % [name, got, Goldens.f(want_bits)])


# --- hareSignAt grid goldens --------------------------------------------------

func _hare_sign_goldens() -> void:
	for key in Goldens.HARE_SIGN_AT:
		var p: PackedStringArray = key.split(",")
		var got := DangerSim.hareSignAt(float(p[0]), float(p[1]), int(p[2]))
		_eq("hareSignAt(%s)" % key, got, Goldens.HARE_SIGN_AT[key])
	# sign is a deterministic band: exactly 0 beyond ±25 m of the stream
	if DangerSim.hareSignAt(60.0, 20.0, 1) != 0.0:
		_fail("hare sign 95 m off the stream should be zero")
	if DangerSim.hareSignAt(Terrain.streamX(0.0), 0.0, 1) < 0.0:
		_fail("hare sign must be non-negative")


# --- snare tick sequences (fixed rng seeds, incl. snow multiplier) ------------

## Replay the TS golden scenario: fresh rng(seed), 1/120-h steps, one snare set
## on the stream at (-35, 0) with sign seed 1. Returns {caughtAtH, ageH, set}.
func _replay_snare(rng_seed: int, snow_mul: float) -> Dictionary:
	var snares: Array = []
	DangerSim.set_snare(snares, 1, -35.0, 0.0, 1)
	var rng := Rng.make_rng(rng_seed)
	var caught_at_h: Variant = null
	for i in 48 * 120:
		var res := DangerSim.tick_snares(snares, 1.0 / 120.0, snow_mul, rng.next)
		if res.caught > 0 and caught_at_h == null:
			caught_at_h = float(i + 1) / 120.0
		if not snares[0].set:
			break
	return {"caughtAtH": caught_at_h, "ageH": snares[0].ageH, "set": snares[0].set}


func _snare_tick_goldens() -> void:
	var cases := {"s1m1": [1, 1.0], "s1m05": [1, 0.5], "s42m1": [42, 1.0],
		"s42m05": [42, 0.5], "s7m1": [7, 1.0]}
	for tag in cases:
		var want: Dictionary = Goldens.SNARE_TICKS[tag]
		var got := _replay_snare(cases[tag][0], cases[tag][1])
		if got.set != want.set:
			_fail("%s: set flag got %s want %s" % [tag, str(got.set), str(want.set)])
		_eq("%s: ageH" % tag, got.ageH, want.ageH, 0.0)
		if got.caughtAtH == null and want.caughtAtH != null:
			_fail("%s: expected catch at golden hour, got none" % tag)
		elif got.caughtAtH != null and want.caughtAtH == null:
			_fail("%s: unexpected catch %s (TS never caught)" % [tag, str(got.caughtAtH)])
		elif got.caughtAtH != null:
			_eq("%s: caughtAtH" % tag, got.caughtAtH, want.caughtAtH, 0.0)
	# deep snow (storm mulch) must delay the catch, never advance it
	var fast: Variant = Goldens.SNARE_TICKS.s42m1.caughtAtH
	var slow: Variant = Goldens.SNARE_TICKS.s42m05.caughtAtH
	if fast != null and slow != null and Goldens.f(slow) <= Goldens.f(fast):
		_fail("snowMul 0.5 should delay the catch")


# --- snare world flow: set → spring → collect (food source, not hazard) -------

func _snare_world_flow() -> void:
	var w := WorldSim.new(11)
	w.inventory = {"cordage": 3}
	# no cordage path first
	var w0 := WorldSim.new(11)
	if Actions.set_snare(w0) != "materials":
		_fail("set_snare without cordage should return materials")
	if Actions.set_snare(w) != "set":
		_fail("set_snare with cordage should return set")
	if w.snares.size() != 1 or w.nextSnareId != 2:
		_fail("snare not registered")
	if w.inventory.get("cordage", 0) != 2:
		_fail("cordage not consumed")
	# overlapping runs spook the hares
	if Actions.set_snare(w) != "too-close":
		_fail("second snare within 8 m should be too-close")
	# world.step() credits pending game when a snare springs (fixed seed ⇒
	# deterministic; p≈0.078/h means a spring within a few days is near-certain)
	var w2 := WorldSim.new(11)
	w2.inventory = {"cordage": 1}
	Actions.set_snare(w2)
	var sprung := false
	for i in 20 * 24 * 120:
		_keep_alive(w2)  # snare ticking stops on death; isolate the snare path
		w2.step()
		if not w2.snares[0].set:
			sprung = true
			break
	if not sprung:
		_fail("seed-11 on-stream snare never sprang in 20 game-days")
	elif w2.snares[0].pending != 1:
		_fail("step() should credit pending=1 on a spring, got %s" % str(w2.snares[0].pending))
	var sprung_logged := false
	for e in w2.log:
		if e.msg == "A snare sprang somewhere down the stream bank.":
			sprung_logged = true
	if not sprung_logged:
		_fail("spring not logged")
	# collect at the snare
	w2.player.x = w2.snares[0].x
	w2.player.z = w2.snares[0].z
	if Actions.check_snares(w2) != 1:
		_fail("check_snares should collect 1 game at the snare")
	if not Items.inv_has(w2.inventory, "meat", 1):
		_fail("collected game not in inventory")
	if w2.snares[0].pending != 0:
		_fail("pending should be cleared after collection")
	# determinism: two identical worlds with a set snare tick identically
	var a := WorldSim.new(21)
	var b := WorldSim.new(21)
	a.inventory = {"cordage": 1}
	b.inventory = {"cordage": 1}
	Actions.set_snare(a)
	Actions.set_snare(b)
	for i in 24 * 120:  # one game day of snare ticking
		_keep_alive(a)
		_keep_alive(b)
		a.step()
		b.step()
	# the snare either survived the day (ageH == 24) or sprang (pending credited)
	if a.snares[0].set:
		if absf(a.snares[0].ageH - 24.0) > 1e-9:
			_fail("survived snare ageH after 1 day: %f" % a.snares[0].ageH)
	else:
		if a.snares[0].pending != 1:
			_fail("sprung snare should have pending=1, got %s" % str(a.snares[0].pending))
	if a.snares[0].set != b.snares[0].set or a.snares[0].ageH != b.snares[0].ageH:
		_fail("snare ticking not deterministic")
	if b.snares[0].pending != a.snares[0].pending:
		_fail("snare pending not deterministic")
	# a bare world never consumes snare rolls (no snares, no state)
	var bare := WorldSim.new(21)
	for i in 24 * 120:
		bare.step()
	if bare.snares.size() != 0:
		_fail("bare world should not grow snares")


# --- fishRoll hour table -------------------------------------------------------

func _fish_roll_table() -> void:
	for e in Goldens.FISH_ROLL:
		var rng := Rng.make_rng(3)
		var got := DangerSim.fish_roll(e.hour, rng.next)
		if got != e.hit:
			_fail("fishRoll(%s): got %s want %s" % [str(e.hour), str(got), str(e.hit)])
	# golden window must be the dawn/dusk side (statistical sanity, fixed rng)
	var hits := 0
	for h in range(0, 10):
		if DangerSim.fish_roll(float(h), Rng.make_rng(100 + h).next):
			hits += 1
	if hits < 4:
		_fail("dawn window should bite often (got %d/10)" % hits)


func _fish_world_flow() -> void:
	var w := WorldSim.new(31)
	# hole table mirrors TS buildFishHoles
	if w.fishHoles.size() != Goldens.FISH_HOLES.size():
		_fail("fish hole count")
	for i in w.fishHoles.size():
		var h: Dictionary = w.fishHoles[i]
		var g: Dictionary = Goldens.FISH_HOLES[i]
		if h.id != g.id or h.usesLeft != g.usesLeft:
			_fail("fish hole %d mismatch" % i)
		_eq("fish hole %d x" % i, h.x, g.x, 0.0)
		_eq("fish hole %d z" % i, h.z, g.z, 0.0)
	# away from any hole
	if Actions.fish(w) != "no-hole":
		_fail("fish away from holes should be no-hole")
	# at a hole without cordage
	var hole: Dictionary = w.fishHoles[2]
	w.player.x = hole.x
	w.player.z = hole.z
	if Actions.fish(w) != "materials":
		_fail("fish without cordage should be materials")
	# with cordage: deterministic per seed; keep fishing until a catch or misses
	w.inventory = {"cordage": 4}
	w.hourOfDay = 5.0  # golden window
	var caught_any := false
	for i in 4:
		var r := Actions.fish(w)
		if r == "caught":
			caught_any = true
			break
		if r != "missed":
			_fail("unexpected fish result %s" % r)
	if not caught_any:
		_fail("4 golden-window casts at one hole all missed (seed 31)")
	if not Items.inv_has(w.inventory, "meat", 1):
		_fail("caught fish not in inventory")
	if hole.usesLeft != 3:
		_fail("a catch should consume one hole use, got %d" % hole.usesLeft)
	# exhaust the hole (misses don't consume uses; cast until usesLeft hits 0)
	var guard := 0
	while hole.usesLeft > 0 and guard < 200:
		Actions.fish(w)
		guard += 1
	if hole.usesLeft != 0:
		_fail("hole should exhaust within 200 casts")
	if Actions.fish(w) != "no-hole":
		_fail("exhausted hole should be no-hole")


# --- injury → infection → sepsis ----------------------------------------------

## Replay the TS golden scenario: severity-40 untreated wound, 1/60-h steps.
func _replay_injury(rng_seed: int) -> Dictionary:
	var list: Array = []
	DangerSim.add_injury(list, "test wound", 40.0)
	var rng := Rng.make_rng(rng_seed)
	var infected_at_h: Variant = null
	var septic_at_h: Variant = null
	for i in 200 * 60:
		var ev := DangerSim.tick_injuries(list, 1.0 / 60.0, rng.next)
		if ev.size() > 0 and infected_at_h == null:
			infected_at_h = float(i + 1) / 60.0
		if list[0].infected and list[0].infection > 60.0 and septic_at_h == null:
			septic_at_h = float(i + 1) / 60.0
		if septic_at_h != null:
			break
	return {"infectedAtH": infected_at_h, "septicAtH": septic_at_h,
		"infection": list[0].infection, "sepsisPerH": DangerSim.sepsis_damage_per_h(list)}


func _injury_timeline_goldens() -> void:
	for seed in [1, 5]:
		var key := "s%d" % seed
		var want: Dictionary = Goldens.INJURY_TIMELINE[key]
		var got := _replay_injury(seed)
		if got.infectedAtH == null or want.infectedAtH == null:
			_fail("%s: infection timing mismatch (%s vs golden)" % [key, str(got.infectedAtH)])
		else:
			_eq("%s: infectedAtH" % key, got.infectedAtH, want.infectedAtH, 0.0)
		if got.septicAtH == null or want.septicAtH == null:
			_fail("%s: sepsis timing mismatch" % key)
		else:
			_eq("%s: septicAtH" % key, got.septicAtH, want.septicAtH, 0.0)
		_eq("%s: infection" % key, got.infection, want.infection, 0.0)
		_eq("%s: sepsisPerH" % key, got.sepsisPerH, want.sepsisPerH, 0.0)


## World-level death chain: an infected septic wound out-heals regen and kills
## with cause 'infection' while the body itself is warm, fed and watered.
func _sepsis_death_chain() -> void:
	var w := WorldSim.new(9)
	# keep the fire going at the player so cold never kills first
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 100.0, true))
	w.nextFireId += 1
	w.needs.health = 100.0
	w.needs.hydration = 100.0
	w.needs.hunger = 100.0
	w.needs.energy = 100.0
	w.needs.coreTemp = 37.0
	# jump straight to the septic state (infection roll is covered by goldens)
	DangerSim.add_injury(w.injuries, "cut", 40.0)
	w.injuries[0].infected = true
	w.injuries[0].infection = 61.0
	var ticks := 0
	while w.dead == null and ticks < 40 * 120:
		_keep_alive(w)  # isolate the sepsis path; step() applies its drain after
		w.step()
		ticks += 1
	if w.dead == null:
		_fail("untreated sepsis should kill within 40 game-hours")
	elif w.dead.cause != "infection":
		_fail("death cause should be infection, got %s" % str(w.dead.cause))
	# band: sepsis 6/h vs regen 2/h ⇒ 100 HP gone in ~17–25 game-hours
	var hours := float(ticks) / 120.0
	if hours < 15.0 or hours > 30.0:
		_fail("sepsis death took %f h, outside TS band 15–30 h" % hours)
	# treated wound does NOT kill: same setup, treated first
	var w2 := WorldSim.new(9)
	w2.fires.append(FireSim.make(w2.nextFireId, w2.player.x, w2.player.z, 100.0, true))
	w2.nextFireId += 1
	w2.needs.health = 100.0
	w2.needs.hydration = 100.0
	w2.needs.hunger = 100.0
	w2.needs.energy = 100.0
	w2.needs.coreTemp = 37.0
	DangerSim.add_injury(w2.injuries, "cut", 40.0)
	w2.injuries[0].infected = true
	w2.injuries[0].infection = 61.0
	if not DangerSim.treat_injury(w2.injuries):
		_fail("treat_injury should accept an infected wound")
	for i in 24 * 120:
		_keep_alive(w2)
		w2.step()
	if w2.dead != null:
		_fail("treated wound should not kill, got %s" % str(w2.dead))


func _treat_injury_goldens() -> void:
	var g: Dictionary = Goldens.TREAT_INJURY
	var list: Array = []
	DangerSim.add_injury(list, "a", 80.0)
	list[0].infected = true
	list[0].infection = 90.0
	var ok := DangerSim.treat_injury(list)
	if ok != g.ok:
		_fail("treat ok mismatch")
	_eq("treated severity", list[0].severity, g.severity, 0.0)
	if list[0].infected != g.infected:
		_fail("treated wound should be clean")
	_eq("treated infection", list[0].infection, g.infection, 0.0)
	# clean low-severity wound is NOT treatable (TS find predicate)
	var list2: Array = []
	DangerSim.add_injury(list2, "b", 20.0)
	var ok2 := DangerSim.treat_injury(list2)
	if ok2 != g.cleanLowOk:
		_fail("clean sev-20 wound should not be treatable")
	_eq("untreated severity", list2[0].severity, g.cleanLowSeverity, 0.0)
	# world-level treatWound: needs duct tape + lit fire
	var w := WorldSim.new(13)
	DangerSim.add_injury(w.injuries, "cut", 60.0)
	if Actions.treat_wound(w):
		_fail("treat_wound without duct tape should fail")
	w.inventory = {"ductTape": 1}
	if Actions.treat_wound(w):
		_fail("treat_wound without fire should fail")
	w.fires.append(FireSim.make(1, w.player.x, w.player.z, 50.0, true))
	if not Actions.treat_wound(w):
		_fail("treat_wound with tape + fire should succeed")
	if w.inventory.get("ductTape", 0) != 0:
		_fail("treat_wound should consume the tape")
	if w.injuries[0].severity != 30.0 or w.injuries[0].infected:
		_fail("treat_wound should halve severity and clean the wound")
