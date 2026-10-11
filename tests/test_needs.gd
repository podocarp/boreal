extends SceneTree
# Port of boreal-src/tests/unit/needs.test.ts: the tuning-target assertions are
# the port's correctness oracle for float behavior (docs/boreal-analysis.md §5).

const Goldens = preload("res://tests/goldens.gd")

const H := Config.TIME.REAL_SECONDS_PER_GAME_HOUR  # one game hour in sim seconds

var fails := 0


func _init():
	_windchill_goldens()
	_air_temp_goldens()
	_heat_budget_goldens()
	_tuning_targets()
	_pacing_and_death()
	_stamina_ladder()
	_weight_model()
	_sleep_requirement()
	if fails == 0:
		print("PASS needs: windchill goldens + TS tuning targets hold")
		quit(0)
	else:
		print("FAIL needs: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


## Run needs forward `hours` game-hours in SIM_DT ticks (mirrors the TS run()).
func _run(n: Needs, env: Needs.Env, hours: float, moving := false, sprinting := false) -> Dictionary:
	var events: Array[String] = []
	var died: Variant = null
	var ticks_per_hour := int(H / Config.SIM_DT)
	for i in int(hours * ticks_per_hour):
		var r := Needs.tick(n, env, Config.SIM_DT, moving, sprinting, "ranger")
		events.append_array(r.events)
		if r.died != null:
			died = r.died
			break
	return {"died": died, "events": events}


func _windchill_goldens() -> void:
	for e in Goldens.WINDCHILL:
		var got := Needs.windchill(e.t, e.w)
		if absf(got - Goldens.f(e.v)) > 1e-9:
			_fail("windchill(%s,%s): got %.17f want %.17f" % [str(e.t), str(e.w), got, Goldens.f(e.v)])
	if not Needs.windchill(-12.0, 30.0) < -12.0:
		_fail("windchill must lower temperature")
	if absf(Needs.windchill(5.0, 30.0) - 5.0) > 0.5:
		_fail("no windchill above freezing")


func _air_temp_goldens() -> void:
	for hh in Goldens.AIR_TEMP_AT:
		var got := Needs.airTempAt(hh, -12.0, 6.0)
		if absf(got - Goldens.f(Goldens.AIR_TEMP_AT[hh])) > 1e-9:
			_fail("airTempAt(%s): got %.17f want %.17f" % [str(hh), got, Goldens.f(Goldens.AIR_TEMP_AT[hh])])
	if not Needs.airTempAt(14.0, -12.0, 6.0) > Needs.airTempAt(2.0, -12.0, 6.0):
		_fail("afternoon must be warmer than pre-dawn")


func _heat_budget_goldens() -> void:
	var n := Needs.create()
	var env := Needs.create_env()
	env.airTempC = -18.0
	env.windKmh = 12.0
	var hb := Goldens.HEAT_BUDGET
	var got := Needs.heatBudget(n, env, Needs.windchill(-18.0, 12.0), true, false)
	if absf(got - Goldens.f(hb.walking_feels25)) > 1e-9:
		_fail("heatBudget walking: got %.17f want %.17f" % [got, Goldens.f(hb.walking_feels25)])
	got = Needs.heatBudget(Needs.create(), Needs.create_env(), Needs.windchill(-14.0, 10.0), false, false)
	if absf(got - Goldens.f(hb.idle_feels20)) > 1e-9:
		_fail("heatBudget idle: got %.17f want %.17f" % [got, Goldens.f(hb.idle_feels20)])
	if absf(Needs.insulationOf(n, env) - Goldens.f(hb.insulation_default)) > 1e-12:
		_fail("insulation default")
	var wet := Needs.create()
	wet.wetness = 0.9
	if absf(Needs.insulationOf(wet, env) - Goldens.f(hb.insulation_wet)) > 1e-12:
		_fail("soaked = 40%% insulation")


func _tuning_targets() -> void:
	# active + dry + clothed at feels ~-25 C is roughly stable
	var n := Needs.create()
	var env := Needs.create_env()
	env.airTempC = -18.0
	env.windKmh = 12.0
	_run(n, env, 6.0, true)
	if not n.coreTemp > 36.0:
		_fail("walking at feels -25 should stay out of cold band, core=%.3f" % n.coreTemp)

	# idle at night, no fire/shelter -> hypothermia band in ~4-6 game hours
	n = Needs.create()
	env = Needs.create_env()
	env.airTempC = -14.0
	env.windKmh = 10.0
	var hours := 0
	var died: Variant = null
	while hours < 12:
		var r := Needs.tick(n, env, H, false, false, "ranger")
		died = r.died
		if n.coreTemp <= Config.THERMO.HYPOTHERMIA_C or died != null:
			break
		hours += 1
	if not n.coreTemp <= Config.THERMO.HYPOTHERMIA_C:
		_fail("idle night should reach hypothermia band")
	if hours < 3 or hours > 7:
		_fail("hypothermia band should take 3-7 h, got %d" % hours)
	if died != null:
		_fail("hypothermia band != instant death")

	# fire rescues you
	n = Needs.create()
	n.coreTemp = 34.8
	env = Needs.create_env()
	env.airTempC = -18.0
	env.windKmh = 18.0
	env.fireWarmth = 0.9
	_run(n, env, 4.0)
	if not n.coreTemp > 35.5:
		_fail("fire should stabilize core, got %.3f" % n.coreTemp)

	# soaked at -12 C overnight is a real crisis
	n = Needs.create()
	n.wetness = 0.9
	env = Needs.create_env()
	env.airTempC = -12.0
	env.windKmh = 10.0
	_run(n, env, 8.0)
	if not n.coreTemp < 34.5:
		_fail("soaked overnight should hit very-cold band, got %.3f" % n.coreTemp)

	# shelter + bedding materially improves the night
	var mk := func() -> Array:
		var a := Needs.create()
		var e := Needs.create_env()
		e.airTempC = -16.0
		e.windKmh = 14.0
		return [a, e]
	var a: Array = mk.call()
	var b: Array = mk.call()
	b[1].shelterInsul = 1.0
	_run(a[0], a[1], 8.0)
	_run(b[0], b[1], 8.0)
	if not b[0].coreTemp > a[0].coreTemp + 1.5:
		_fail("shelter should help by >1.5 C")

	# hunger starves heat production (food = fuel)
	var fed := Needs.create()
	fed.hunger = 90.0
	var starving := Needs.create()
	starving.hunger = 5.0
	env = Needs.create_env()
	env.airTempC = -14.0
	env.windKmh = 12.0
	_run(fed, env, 6.0)
	_run(starving, env, 6.0)
	if not starving.coreTemp < fed.coreTemp:
		_fail("starving should be colder than fed")


func _pacing_and_death() -> void:
	# hydration full -> empty ~2+ game days idle
	var n := Needs.create()
	n.hydration = 100.0
	var env := Needs.create_env()
	env.airTempC = 0.0
	var hours := 0
	while n.hydration > 0.0 and hours < 100:
		Needs.tick(n, env, H, false, false, "ranger")
		hours += 1
	if hours < 48 or hours > 72:
		_fail("hydration empty should take 48-72 h, got %d" % hours)

	# auto-sip keeps hydration topped from carried water while idle
	n = Needs.create()
	n.hydration = 55.0
	n.carriedWaterL = 2.0
	env = Needs.create_env()
	env.airTempC = 0.0
	_run(n, env, 4.0)
	if not n.hydration > 55.0:
		_fail("auto-sip should net-gain hydration")
	if not n.carriedWaterL < 2.0:
		_fail("auto-sip should consume stock")

	# DIVERGENCE from TS (survivability rebalance 2026-10-11): auto-sip DOES
	# run while moving — sitting, walking, running are all fine. TS asserted
	# "moving should only drain"; the new intent is that a walking player
	# with carried water never dehydrates below the sip threshold.
	n = Needs.create()
	n.hydration = 55.0
	n.carriedWaterL = 2.0
	env = Needs.create_env()
	env.airTempC = 0.0
	_run(n, env, 4.0, true)
	if not n.hydration > 55.0:
		_fail("auto-sip should fire while walking, hydration=%.2f" % n.hydration)
	if not n.carriedWaterL < 2.0:
		_fail("walking should sip stock")

	# DIVERGENCE (same): a sip is half a bottle (0.5 L = 25 pts), clamped to
	# the carried amount. 0.2 L carried -> exactly 0.2 L consumed.
	n = Needs.create()
	n.hydration = 40.0
	n.carriedWaterL = 0.2
	env = Needs.create_env()
	env.airTempC = 0.0
	Needs.tick(n, env, Config.SIM_DT, false, false, "ranger")
	if absf(n.carriedWaterL) > 1e-9:
		_fail("sip must clamp to carried amount, left=%f" % n.carriedWaterL)
	# tick drains thirst first, then sips: 40 - 1.75/120 + 10
	var want := 40.0 - Config.NEEDS.HYDRATION_DECAY_PER_H * Config.SIM_DT / Config.TIME.REAL_SECONDS_PER_GAME_HOUR + 10.0
	if absf(n.hydration - want) > 1e-9:
		_fail("0.2 L sip = 10 pts, expected hydration %.6f, got %.6f" % [want, n.hydration])

	# DIVERGENCE (same): full sip chunk = 0.5 L = 25 pts in one tick
	n = Needs.create()
	n.hydration = 40.0
	n.carriedWaterL = 2.0
	Needs.tick(n, env, Config.SIM_DT, true, false, "ranger")
	if absf(n.carriedWaterL - 1.5) > 1e-9:
		_fail("sip should consume 0.5 L, left=%f" % n.carriedWaterL)

	# DIVERGENCE (same): auto-sip is suppressed while preoccupied (task in
	# progress) — the new suppression replaces the old "not moving" gate.
	n = Needs.create()
	n.hydration = 40.0
	n.carriedWaterL = 2.0
	Needs.tick(n, env, Config.SIM_DT, false, false, "ranger", true)
	if n.carriedWaterL != 2.0:
		_fail("preoccupied should suppress auto-sip")
	if not n.hydration < 40.0:
		_fail("preoccupied tick should only drain")
	# ...and while sleeping
	n = Needs.create()
	n.hydration = 40.0
	n.carriedWaterL = 2.0
	n.sleeping = true
	Needs.tick(n, env, Config.SIM_DT, false, false, "ranger")
	if n.carriedWaterL != 2.0:
		_fail("sleeping should suppress auto-sip")

	# death at zero hydration takes ~8-10 h, not instantly
	n = Needs.create()
	n.hydration = 0.0
	n.health = 100.0
	env = Needs.create_env()
	env.airTempC = 0.0
	hours = 0
	var died: Variant = null
	while hours < 30:
		var r := Needs.tick(n, env, H, false, false, "ranger")
		hours += 1
		if r.died != null:
			died = r.died
			break
	if died == null or died.cause != "dehydration":
		_fail("expected dehydration death")
	if hours < 6 or hours > 14:
		_fail("dehydration death should take 6-14 h, got %d" % hours)

	# debuffs appear before critical bands
	n = Needs.create()
	n.energy = 40.0
	n.hunger = 40.0
	var d := Needs.compute_debuffs(n)
	if not d.strength < 1.0 or not d.focus < 1.0:
		_fail("debuffs should appear at 40")
	if n.health != 100.0:
		_fail("no HP damage at 40")

	# hypothermia chain: idle night outside -> death with named cause
	n = Needs.create()
	env = Needs.create_env()
	env.airTempC = -22.0
	env.windKmh = 25.0
	died = null
	for i in 24 * 3:
		var r := Needs.tick(n, env, H, false, false, "ranger")
		if r.died != null:
			died = r.died
			break
	if died == null or died.cause != "hypothermia":
		_fail("expected hypothermia death")


## DIVERGENCE from TS (survivability rebalance 2026-10-11): the stamina
## ladder — soft energy never blocks walking; it slows you and locks sprint.
## Owner directive 2026-10-11: NO collapse/pass-out — energy is pure
## performance and never incapacitates (the TS forced-sleep-on-exhaustion
## path is deliberately NOT ported).
func _stamina_ladder() -> void:
	var N := Config.NEEDS

	# baseline decay nerf: 2.5/h idle (was 4.0)
	var n := Needs.create()
	n.energy = 90.0
	var env := Needs.create_env()
	env.airTempC = 0.0
	Needs.tick(n, env, H, false, false, "ranger")
	if absf(n.energy - (90.0 - N.ENERGY_DECAY_PER_H)) > 1e-9:
		_fail("idle energy decay should be %.1f/h, got %.6f" % [N.ENERGY_DECAY_PER_H, 90.0 - n.energy])

	# move-speed penalty scales in below DEBUFF_FROM, max -30% at 0
	n = Needs.create()
	n.energy = N.DEBUFF_FROM
	if absf(Needs.moveSpeedFactor(n) - 1.0) > 1e-12:
		_fail("no speed penalty at DEBUFF_FROM")
	n.energy = N.DEBUFF_FROM / 2.0
	if absf(Needs.moveSpeedFactor(n) - (1.0 - N.WALK_SLOW_AT_ZERO * 0.5)) > 1e-12:
		_fail("speed penalty should scale linearly")
	n.energy = 0.0
	if absf(Needs.moveSpeedFactor(n) - (1.0 - N.WALK_SLOW_AT_ZERO)) > 1e-12:
		_fail("speed penalty at 0 energy should be -%.0f%%" % (N.WALK_SLOW_AT_ZERO * 100.0))

	# sprint lockout at SPRINT_LOCKOUT_ENERGY
	n = Needs.create()
	n.energy = N.SPRINT_LOCKOUT_ENERGY
	if not Needs.sprint_allowed(n):
		_fail("sprint should be allowed at the lockout threshold")
	n.energy = N.SPRINT_LOCKOUT_ENERGY - 0.1
	if Needs.sprint_allowed(n):
		_fail("sprint should be locked below SPRINT_LOCKOUT_ENERGY")

	# hunger joins the dexterity ladder (Zomboid: hungry != frozen)
	n = Needs.create()
	n.energy = 90.0
	n.hunger = N.DEBUFF_FROM - 5.0
	var d := Needs.compute_debuffs(n)
	if absf(d.dexterity - (1.0 - N.HUNGRY_DEX_PENALTY)) > 1e-9:
		_fail("starving should cost dexterity, got %f" % d.dexterity)
	n.hunger = N.DEBUFF_FROM + 5.0
	if absf(Needs.compute_debuffs(n).dexterity - 1.0) > 1e-12:
		_fail("no dexterity penalty above DEBUFF_FROM")

	# NO collapse/pass-out (owner directive 2026-10-11): energy pinned at 0
	# in the cold for hours must never force sleep and must never add a
	# death cause of its own — pure performance only.
	n = Needs.create()
	n.energy = 0.0
	env = Needs.create_env()
	env.airTempC = -20.0
	env.windKmh = 20.0
	for i in int(6.0 * 2):  # 6 game-hours at energy 0, falling core
		var r := Needs.tick(n, env, H / 2.0, false, false, "ranger")
		if n.sleeping:
			_fail("energy 0 must never force sleep (no collapse mechanic)")
		if r.died != null and r.died.cause == "exhaustion":
			_fail("energy must never be a death cause")


## DIVERGENCE from TS (weight-based calorie model, owner directive
## 2026-10-11 v2): hunger-at-0 burns MASS, not health; the malnutrition
## cutoff is the only starvation death; surplus eating regains mass slowly.
## The TS goldens that pinned hunger->health drain are deliberately not
## re-ported here (superseded by the weight model).
func _weight_model() -> void:
	var N := Config.NEEDS

	# (a) hunger 0 for 48 h loses weight but does NOT kill before the
	# cutoff chain (warm env so hypothermia can't steal the assertion).
	var n := Needs.create()
	n.hunger = 0.0
	n.carriedWaterL = 100.0  # auto-sip pins hydration: dehydration must not steal the assertion
	var env := Needs.create_env()
	env.airTempC = 0.0
	var died: Variant = null
	for i in int(48.0):
		var r := Needs.tick(n, env, H, false, false, "ranger")
		if r.died != null:
			died = r.died
			break
	if died != null:
		_fail("48 h empty stomach must not kill (cutoff chain only), got %s" % str(died.cause))
	if not n.weightKg < 80.0 - 4.0:
		_fail("48 h empty stomach should burn >4 kg, weight=%.2f" % n.weightKg)
	if n.health != 100.0:
		_fail("hunger-at-0 must not drain health above the cutoff, hp=%.2f" % n.health)
	# band toasts fired downward: thin + weakened crossed by ~48 h at 3.2 kg/d
	var words := [Needs.weight_word(1), Needs.weight_word(2), Needs.weight_word(3)]
	if words != ["thin", "weakened", "malnourished"]:
		_fail("condition words must be ok/thin/weakened/malnourished")

	# (b) weight < 60 => health drain => nameable starvation death
	n = Needs.create()
	n.hunger = 0.0
	n.weightKg = 59.9
	n.carriedWaterL = 100.0  # auto-sip pins hydration: starvation must be the killer
	env = Needs.create_env()
	env.airTempC = 0.0
	died = null
	var hours := 0
	while hours < 200 and died == null:
		var r := Needs.tick(n, env, H, false, false, "ranger")
		died = r.died
		hours += 1
	if died == null or died.cause != "starvation":
		_fail("malnutrition must kill with cause 'starvation', got %s" % str(died))
	if not str(died.detail).contains("malnutrition") or not str(died.detail).contains("kg"):
		_fail("starvation death must be nameable with weight, got '%s'" % str(died.detail))

	# cutoff ladder: penalties appear at the cutoffs, energy drains faster weakened
	n = Needs.create()
	n.weightKg = 73.9
	if Needs.weight_band(n) != 1:
		_fail("73.9 kg should be band 1 (thin)")
	var d_ok := Needs.compute_debuffs(Needs.create())
	var d_thin := Needs.compute_debuffs(n)
	if not d_thin.dexterity < d_ok.dexterity or not d_thin.strength < d_ok.strength:
		_fail("thin should cost dexterity + strength")
	if absf(Needs.moveSpeedFactor(n) - (1.0 - N.WALK_SLOW_THIN)) > 1e-9:
		_fail("thin should slow walk by %.0f%%" % (N.WALK_SLOW_THIN * 100.0))
	n.weightKg = 59.0
	if Needs.weight_band(n) != 3:
		_fail("59 kg should be band 3 (malnourished)")
	if absf(Needs.moveSpeedFactor(n) - (1.0 - N.WALK_SLOW_MALNOURISHED)) > 1e-9:
		_fail("malnourished should slow walk by %.0f%%" % (N.WALK_SLOW_MALNOURISHED * 100.0))
	# weakened energy drain multiplier
	var weak := Needs.create()
	weak.weightKg = 67.0
	weak.energy = 90.0
	var ok := Needs.create()
	ok.energy = 90.0
	env = Needs.create_env()
	env.airTempC = 0.0
	Needs.tick(weak, env, H, false, false, "ranger")
	Needs.tick(ok, env, H, false, false, "ranger")
	if not (90.0 - weak.energy) > (90.0 - ok.energy) * N.WEAK_ENERGY_MUL - 1e-6:
		_fail("weakened should drain energy %.0f%% faster (weak %.3f vs ok %.3f)" % [
			(N.WEAK_ENERGY_MUL - 1.0) * 100.0, 90.0 - weak.energy, 90.0 - ok.energy])

	# (g) surplus eating raises weight slowly (FILL_KG_PER_DAY cap respected)
	var w := WorldSim.new(11)
	w.needs.hunger = 100.0
	w.needs.weightKg = 70.0
	w.inventory = {"meatCooked": 8}
	var w0: float = w.needs.weightKg
	for i in 8:
		Actions.eat(w)  # all surplus -> calorieBank (hunger already full)
	if w.needs.calorieBank <= 0.0:
		_fail("eating at a full stomach must bank surplus kcal")
	# run 2 game-days of ticks; fill is capped at FILL_KG_PER_DAY
	for i in int(2.0 * 24.0 * 2.0):  # half-hour steps
		Needs.tick(w.needs, Needs.create_env(), H / 2.0, false, false, "ranger")
	var gained: float = w.needs.weightKg - w0
	if gained <= 0.0:
		_fail("surplus calories should regain mass")
	if gained > N.FILL_KG_PER_DAY * 2.0 + 1e-6:
		_fail("mass regain must respect FILL_KG_PER_DAY cap, gained %.3f kg in 2 d" % gained)
	# a binge cannot recover 10 kg overnight: 8 cooked meats = 4800 kcal banked
	# = 0.62 kg of real mass, but the DAY cap means <= 0.4 kg after 24 h.
	if w.needs.weightKg > 80.0:
		_fail("weight must never exceed the 80 kg start")

	# metabolic coupling: burning mass adds a small heat contribution.
	# fed (heatFuel 1.0) vs empty stomach (heatFuel 0.6 + burn bonus):
	# difference must be exactly METABOLIC_HEAT*0.4 - METABOLIC_BURN_HEAT.
	var burn := Needs.create()
	burn.hunger = 0.0
	var fed := Needs.create()
	fed.hunger = 80.0
	env = Needs.create_env()
	env.airTempC = -14.0
	env.windKmh = 10.0
	var feels := Needs.windchill(-14.0, 10.0)
	var hb_burn := Needs.heatBudget(burn, env, feels, false, false)
	var hb_fed := Needs.heatBudget(fed, env, feels, false, false)
	# food stays better fuel (cold stays #1): the burn bonus must not flip it
	if not hb_fed > hb_burn:
		_fail("fed should still out-burn empty stomach (cold stays #1)")
	var want_gap := Config.THERMO.METABOLIC_HEAT * 0.4 - Config.THERMO.METABOLIC_BURN_HEAT
	if absf((hb_fed - hb_burn) - want_gap) > 1e-9:
		_fail("metabolic burn heat contribution wrong: gap %.6f want %.6f" % [hb_fed - hb_burn, want_gap])


## DIVERGENCE from TS (Change 3, owner directive 2026-10-11): sleep is a
## requirement — energy restores ONLY while sleeping, and long waking
## streaks grow a drowsiness debuff until you sleep.
func _sleep_requirement() -> void:
	var N := Config.NEEDS

	# (e) idle/standing does NOT restore energy; food does not either.
	var n := Needs.create()
	n.energy = 30.0
	var env := Needs.create_env()
	env.airTempC = 0.0
	for i in int(6.0):
		Needs.tick(n, env, H, false, false, "ranger")
	if not n.energy < 30.0:
		_fail("idle must only drain energy, got %.3f" % n.energy)
	var w := WorldSim.new(12)
	w.needs.energy = 30.0
	w.inventory = {"meatCooked": 1}
	Actions.eat(w)
	if absf(w.needs.energy - 30.0) > 1e-9:
		_fail("food must not restore energy, got %.3f" % w.needs.energy)
	# ...and sleeping DOES (world.step applies the restore)
	w.needs.sleeping = true
	w.sleep.active = true
	w.needs.coreTemp = 37.0
	w.needs.hunger = 80.0
	for i in 120:
		w.step()
	if not w.needs.energy > 30.0 + 10.0:
		_fail("sleep should restore energy, got %.3f" % w.needs.energy)

	# (f) waking > 30 h adds a growing drowsiness debuff; sleeping clears it
	n = Needs.create()
	n.energy = 100.0
	env = Needs.create_env()
	env.airTempC = 0.0
	for i in int(N.DROWSY_AFTER_H):
		Needs.tick(n, env, H, false, false, "ranger")
		n.energy = 100.0  # pin energy: the debuff under test is deprivation alone
	if Needs.deprivation(n) > 0.0:
		_fail("no deprivation before DROWSY_AFTER_H")
	for i in int(6.0):
		Needs.tick(n, env, H, false, false, "ranger")
		n.energy = 100.0
	var dep := Needs.deprivation(n)
	if dep <= 0.0:
		_fail("36 h awake should add deprivation, got %.3f" % dep)
	var d := Needs.compute_debuffs(n)
	if not d.drowsiness > 0.0:
		_fail("drowsiness channel should be active when sleep-deprived")
	if not d.focus < 1.0 or not d.dexterity < 1.0:
		_fail("sleep deprivation should cost focus + dexterity")
	for i in int(N.DROWSY_FULL_H):
		Needs.tick(n, env, H, false, false, "ranger")
		n.energy = 100.0
	if Needs.deprivation(n) < 1.0:
		_fail("deprivation should saturate at DROWSY_FULL_H")
	# sleeping clears the streak
	n.sleeping = true
	Needs.tick(n, env, H, false, false, "ranger")
	if n.awakeH != 0.0 or Needs.deprivation(n) > 0.0:
		_fail("sleeping must reset the waking streak")
