extends SceneTree
# World determinism + action happy paths (chop/snap/peel/scoop/feed-fire/melt/
# cook/scavenge/sleep). Mirrors world.test.ts intent: same seed + same tick
# count + same actions => identical state hash.

var fails := 0


func _init():
	_determinism()
	_feed_fire()
	_melt_and_cook()
	_scavenge_and_work()
	_sleep()
	if fails == 0:
		print("PASS world: determinism + action happy paths")
		quit(0)
	else:
		print("FAIL world: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


func _step(w: WorldSim, ticks: int) -> void:
	for i in ticks:
		w.step()


## FNV-1a over the full observable sim state (floats via exact bit patterns).
var _h := 0
const _M64 := -1  # 0xFFFFFFFFFFFFFFFF as signed int64

func _mix(v: int) -> void:
	for i in 8:
		_h ^= (v >> (8 * i)) & 0xFF
		_h = (_h * 0x100000001b3) & _M64


func _hash(w: WorldSim) -> String:
	_h = -3750763034362895579  # 0xcbf29ce484222325
	_mix(w.seed)
	_mix(w.day)
	_mix(int(w.rngN))
	for v in [w.t, w.hourOfDay, w.player.x, w.player.y, w.player.z, w.player.yaw,
			w.needs.hydration, w.needs.hunger, w.needs.energy, w.needs.health,
			w.needs.coreTemp, w.needs.wetness, w.needs.carriedWaterL,
			w.env.airTempC, w.env.windKmh, w.env.fireWarmth, w.env.shelterInsul,
			w.stillH]:
		_mix(_bits(v))
	for id in w.inventory:
		_mix(hash(id))
		_mix(w.inventory[id])
	for f in w.fires:
		_mix(f.id)
		_mix(_bits(f.fuel))
		_mix(1 if f.lit else 0)
	for s in w.shelters:
		_mix(s.id)
		_mix(s.step)
		_mix(_bits(s.siteQuality))
	_mix(1 if w.needs.sleeping else 0)
	_mix(w.rescue.resolved)
	_mix(1 if w.dead != null else 0)
	_mix(1 if w.rescued != null else 0)
	_mix(w.log.size())
	_mix(hash(w.log[w.log.size() - 1].msg) if not w.log.is_empty() else 0)
	return str(_h)


func _bits(f: float) -> int:
	var b := PackedFloat64Array([f]).to_byte_array()
	var v := 0
	for i in 8:
		v |= int(b[7 - i]) << (8 * (7 - i))
	if v >= (1 << 63):
		v -= (1 << 64)
	return v


func _determinism() -> void:
	# two identical 2-game-day runs (2*24*120 ticks) from seed 1
	var a := WorldSim.new(1)
	var b := WorldSim.new(1)
	_step(a, 2 * 24 * 120)
	_step(b, 2 * 24 * 120)
	if _hash(a) != _hash(b):
		_fail("2-day run not deterministic: %s vs %s" % [_hash(a), _hash(b)])
	# sanity: time advanced exactly 2 game days
	if absf(a.t - 2 * 24 * 30.0) > 1e-6:
		_fail("t after 2 days: %f" % a.t)
	if a.day != 3:
		_fail("day after 2 days: %d" % a.day)
	# different seed must diverge
	var c := WorldSim.new(2)
	_step(c, 2 * 24 * 120)
	if _hash(a) == _hash(c):
		_fail("seed 1 and 2 identical")


func _feed_fire() -> void:
	var w := WorldSim.new(5)
	w.inventory = {"deadfall": 4, "kindling": 2}
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 20.0, true))
	w.nextFireId += 1
	var fed := Actions.feed_fire(w)
	# TS feedFire: feeds while fuel < 90 -> 3 deadfall (20->45->70->95), then stops
	if fed != 3:
		_fail("expected 3 deadfall fed, got %d" % fed)
	if w.fires[0].fuel != 95.0:
		_fail("fuel should be 95, got %f" % w.fires[0].fuel)
	if w.inventory.get("deadfall", 0) != 1:
		_fail("one deadfall should remain")
	# fire burns down over game hours; stage collapse (7->10->18->30 %/h)
	# empties fuel 95 in ~8.3 h (same cascade as TS tick_fire)
	var f: Dictionary = w.fires[0]
	for i in int(6.0 * 120.0):
		FireSim.tick_fire(f, 1.0 / 120.0, 10.0)
	if not f.lit:
		_fail("fed fire should survive 6 h, fuel=%f" % f.fuel)
	for i in int(6.0 * 120.0):
		FireSim.tick_fire(f, 1.0 / 120.0, 10.0)
	if f.lit:
		_fail("fuel-95 fire should be out by 12 h (stage cascade)")


func _melt_and_cook() -> void:
	var w := WorldSim.new(5)
	w.inventory = {"tinCup": 1, "snow": 1, "meat": 1}
	# no fire: boil fails
	if Actions.boil_water(w):
		_fail("boil without fire should fail")
	w.fires.append(FireSim.make(1, w.player.x, w.player.z, 50.0, true))
	if not Actions.boil_water(w):
		_fail("melt snow should succeed")
	if not Items.inv_has(w.inventory, "waterClean"):
		_fail("no clean water after melt")
	if not Actions.cook(w):
		_fail("cook should succeed")
	if not Items.inv_has(w.inventory, "meatCooked"):
		_fail("no cooked meat")
	# drink clean water -> carriedWaterL
	if not Actions.drink(w):
		_fail("drink should succeed")
	if absf(w.needs.carriedWaterL - 1.0) > 1e-9:
		_fail("carriedWaterL should be 1, got %f" % w.needs.carriedWaterL)


func _scavenge_and_work() -> void:
	var w := WorldSim.new(1)
	# teleport to the wreck and scavenge (0.5 game-h = 15 real s = 60 ticks)
	var wreck: Variant = null
	for it in w.interactables:
		if it.kind == "wreck":
			wreck = it
			break
	if wreck == null:
		_fail("no wreck interactable")
		return
	w.player.x = wreck.x
	w.player.z = wreck.z
	if not Actions.begin_work(w):
		_fail("begin_work at wreck failed")
	for i in 61:
		Actions.tick_work(w, Config.SIM_DT, 1.0)
	if w.task != null:
		_fail("wreck task should be complete")
	for item in ["knife", "tinCup", "blanket", "flareGun", "flare", "ductTape", "kindling"]:
		if not Items.inv_has(w.inventory, item):
			_fail("wreck loot missing %s" % item)
	if wreck.uses != 0:
		_fail("wreck should be spent")
	# moving cancels a work task
	var tgt: Variant = Actions.current_target(w)
	if tgt != null and tgt.kind == "snow":
		if Actions.begin_work(w):
			w.player.moving = true
			Actions.tick_work(w, Config.SIM_DT, 1.0)
			if w.task != null:
				_fail("moving should cancel task")
			w.player.moving = false


func _sleep() -> void:
	var w := WorldSim.new(3)
	w.needs.energy = 50.0
	w.needs.coreTemp = 37.0
	if not Actions.toggle_sleep(w):
		_fail("toggle_sleep should start sleep")
	if not w.needs.sleeping:
		_fail("needs.sleeping should be true")
	# warm + fed: energy restores (restore applied in world.step, not needs.tick)
	_step(w, 120)  # 1 game-hour
	if not w.needs.energy > 50.0 + 10.0:
		_fail("sleep should restore ~15/h when warm+fed, got %f" % w.needs.energy)
	# waking at dawn
	w.hourOfDay = 9.0
	w.sleep.hours = 3.0
	_step(w, 1)
	if w.needs.sleeping:
		_fail("should wake at dawn")
