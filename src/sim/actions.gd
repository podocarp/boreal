## Player actions — port of world.ts action functions (phase 1 happy paths).
## Wolves/snares/fishing/treat are phase-2 stubs. Shelter build lives in build.gd.
class_name Actions


## Begin a work task on the nearest target (chop/snap/peel/scoop/scavenge).
static func begin_work(w: WorldSim) -> bool:
	if w.dead != null or w.task != null:
		return false
	var tgt: Variant = current_target(w)
	if tgt == null:
		return false
	if tgt.kind == "snow" or tgt.kind == "water":
		var has_container := Items.inv_has(w.inventory, "barkContainer") or Items.inv_has(w.inventory, "tinCup")
		if not has_container:
			w.push_log("You need a container (tin cup, bark container) for that.")
			return false
	w.task = Interact.start_task(tgt)
	return true


static func current_target(w: WorldSim) -> Variant:
	if w.task != null:
		return null
	return Interact.find_target(w.player.x, w.player.z, w.interactables, true)


## Advance the active work task; completes with yields. dexterity slows it;
## moving cancels it. dt REAL seconds.
static func tick_work(w: WorldSim, dt: float, dexterity: float) -> void:
	if w.task == null:
		return
	if w.player.moving:
		w.task = null  # work requires standing still
		return
	w.task.remaining -= dt * maxf(0.25, dexterity)
	if w.task.remaining > 0.0:
		return

	var target: Variant
	if w.task.targetId == -1:
		target = {"id": -1, "kind": "snow", "x": w.player.x, "z": w.player.z, "uses": 99}
	else:
		for it in w.interactables:
			if it.id == w.task.targetId:
				target = it
				break
	var was_shelter: bool = w.task.kind == "shelter"
	var shelter_id: int = w.task.targetId
	w.task = null
	if was_shelter:
		Build.finish_shelter_step(w, shelter_id)
		return
	if target == null:
		return

	var yields: Array = Interact.WRECK_LOOT if target.kind == "wreck" else Interact.YIELDS.get(target.kind, [])
	var got_any := false
	for y in yields:
		if Items.inv_can_add(w.inventory, y.item, y.n):
			Items.inv_add(w.inventory, y.item, y.n)
			got_any = true
		else:
			w.push_log("No room for %s." % y.item)
	if got_any and target.id != -1:
		target.uses -= 1
	if got_any:
		var names: Array[String] = []
		for y in yields:
			names.append("%d× %s" % [y.n, y.item])
		w.push_log("Collected: %s" % ", ".join(names))


## Light a fire at the player: needs a tinder bundle; friction roll decides.
static func light_fire(w: WorldSim, dexterity := 0.7) -> String:
	if w.dead != null:
		return "no-bundle"
	if not Items.inv_has(w.inventory, "tinderBundle"):
		return "no-bundle"
	Items.inv_remove(w.inventory, "tinderBundle")
	var lit := w._near_lit_fire(3.0)  # relaying never fails
	if not lit:
		lit = FireSim.friction_roll(dexterity, w.needs.wetness, w.needs.coreTemp, true, w.roll)
	if not lit:
		w.push_log("The ember died in your hands. No flame.")
		return "failed"
	w.fires.append(FireSim.make(w.nextFireId, w.player.x, w.player.z, 25.0, true))
	w.nextFireId += 1
	w.push_log("The tinder catches — fire!")
	return "lit"


## Feed the nearest fire from inventory. Returns items burned.
static func feed_fire(w: WorldSim) -> int:
	var f: Variant = w.nearest_fire(3.0)
	if f == null:
		return 0
	var fed := 0
	while Items.inv_has(w.inventory, "deadfall") and f.fuel < 90.0:
		Items.inv_remove(w.inventory, "deadfall")
		FireSim.add_fuel(f, "deadfall")
		fed += 1
	if fed == 0 and Items.inv_has(w.inventory, "kindling") and f.fuel < 60.0:
		Items.inv_remove(w.inventory, "kindling")
		FireSim.add_fuel(f, "kindling")
		fed += 1
	if fed > 0:
		w.push_log("You feed the fire (%d)." % fed)
	return fed


## Melt/boil: at a lit fire, convert snow->clean water or raw->clean.
static func boil_water(w: WorldSim) -> bool:
	var f: Variant = w.nearest_fire(3.0)
	if f == null or not f.lit:
		return false
	var has_cup := Items.inv_has(w.inventory, "tinCup") or Items.inv_has(w.inventory, "barkContainer")
	if not has_cup:
		return false
	if Items.inv_has(w.inventory, "snow"):
		Items.inv_remove(w.inventory, "snow")
		if not Items.inv_can_add(w.inventory, "waterClean"):
			return false
		Items.inv_add(w.inventory, "waterClean")
		w.push_log("Snow melted and boiled. Safe water.")
		return true
	if Items.inv_has(w.inventory, "waterRaw"):
		Items.inv_remove(w.inventory, "waterRaw")
		if not Items.inv_can_add(w.inventory, "waterClean"):
			return false
		Items.inv_add(w.inventory, "waterClean")
		w.push_log("Water boiled. Safe water.")
		return true
	return false


## Drink from inventory. Clean = full benefit; raw = risk; snow = cold debt.
static func drink(w: WorldSim) -> bool:
	if Items.inv_has(w.inventory, "waterClean"):
		Items.inv_remove(w.inventory, "waterClean")
		w.needs.carriedWaterL += 1.0
		return true
	if Items.inv_has(w.inventory, "waterRaw"):
		Items.inv_remove(w.inventory, "waterRaw")
		w.needs.carriedWaterL += 1.0
		if w.roll() < 0.35:
			w.push_log("That water disagreed with you...")
			w.needs.hydration = maxf(0.0, w.needs.hydration - 8.0)
		return true
	if Items.inv_has(w.inventory, "snow"):
		Items.inv_remove(w.inventory, "snow")
		w.needs.hydration = minf(100.0, w.needs.hydration + 12.0)
		w.needs.coreTemp = maxf(24.0, w.needs.coreTemp - 0.4)
		w.push_log("Eating snow. It helps the thirst and hurts everything else.")
		return true
	return false


## Craving multiplier: hungrier => same food restores more.
static func craving_mul(hunger: float) -> float:
	return 1.0 + Config.NEEDS.CRAVING_K * (1.0 - hunger / 100.0)


## Eat: cooked meat >> berries > raw meat (risk).
static func eat(w: WorldSim) -> bool:
	var crave := craving_mul(w.needs.hunger)
	if Items.inv_has(w.inventory, "meatCooked"):
		Items.inv_remove(w.inventory, "meatCooked")
		w.needs.hunger = minf(100.0, w.needs.hunger + 45.0 * crave)
		return true
	if Items.inv_has(w.inventory, "berries"):
		Items.inv_remove(w.inventory, "berries")
		w.needs.hunger = minf(100.0, w.needs.hunger + 10.0 * crave)
		return true
	if Items.inv_has(w.inventory, "meat"):
		Items.inv_remove(w.inventory, "meat")
		w.needs.hunger = minf(100.0, w.needs.hunger + 30.0 * crave)
		if w.roll() < 0.5:
			w.push_log("Raw meat. Your gut knows it.")
			w.needs.hydration = maxf(0.0, w.needs.hydration - 10.0)
		return true
	return false


## Cook raw meat at a lit fire.
static func cook(w: WorldSim) -> bool:
	var f: Variant = w.nearest_fire(3.0)
	if f == null or not f.lit or not Items.inv_has(w.inventory, "meat"):
		return false
	Items.inv_remove(w.inventory, "meat")
	Items.inv_add(w.inventory, "meatCooked")
	w.push_log("You roast the meat over the coals.")
	return true


## Throw green boughs on a fire -> signal smoke.
static func signal_smoke(w: WorldSim) -> bool:
	var f: Variant = w.nearest_fire(3.0)
	if f == null or not f.lit or not Items.inv_has(w.inventory, "boughs", 2):
		return false
	Items.inv_remove(w.inventory, "boughs", 2)
	w.signalFireId = f.id
	w.push_log("Green boughs on the coals — a fat column of white smoke rises.")
	return true


static func fire_flare(w: WorldSim) -> bool:
	if w.dead != null or w.rescued != null:
		return false
	if not Items.inv_has(w.inventory, "flare") or not Items.inv_has(w.inventory, "flareGun"):
		return false
	Items.inv_remove(w.inventory, "flare")
	w.flareAgeH = 0.0
	w.push_log("The flare screams up into the grey. One shot. Make it count.")
	return true


## Lie down / get up. Sleeping is possible anywhere — that's the gamble.
static func toggle_sleep(w: WorldSim) -> bool:
	if w.dead != null:
		return false
	if w.needs.sleeping:
		w.needs.sleeping = false
		w.sleep.active = false
		w.push_log("You drag yourself upright.")
		return false
	if not ShelterSim.can_sleep():
		return false
	w.needs.sleeping = true
	w.sleep.active = true
	w.sleep.hours = 0.0
	var insul := ShelterSim.shelter_warmth_at(w.shelters, w.player.x, w.player.z)
	w.push_log("You crawl into the shelter and sleep." if insul > 0.5 else "You try to sleep out in the open. Risky.")
	return true# --- phase 2 stubs ---

static func set_snare(_w: WorldSim) -> String:
	return "not implemented"


static func check_snares(_w: WorldSim) -> int:
	return 0


static func fish(_w: WorldSim) -> String:
	return "not implemented"


static func treat_wound(_w: WorldSim) -> bool:
	return false
