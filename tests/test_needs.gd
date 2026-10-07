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

	# auto-sip does NOT run while moving
	n = Needs.create()
	n.hydration = 55.0
	n.carriedWaterL = 2.0
	env = Needs.create_env()
	env.airTempC = 0.0
	_run(n, env, 4.0, true)
	if not n.hydration < 55.0:
		_fail("moving should only drain")
	if n.carriedWaterL != 2.0:
		_fail("moving should not sip")

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
