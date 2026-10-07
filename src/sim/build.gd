## Shelter build steps — split out of the world.ts action block (actions.gd
## keeps the verb list; this owns the 6-step debris-shelter build).
class_name Build

## Cost per shelter build step. Step order: site/frame/ribs/insulation/mulch/bedding.
const SHELTER_STEP_COST := [
	{},
	{"deadfall": 2},
	{"deadfall": 2},
	{"boughs": 6},
	{},
	{"boughs": 6},
]


static func build_shelter(w: WorldSim) -> String:
	if w.dead != null or w.task != null:
		return "busy"
	var s: Variant = null
	for sh in w.shelters:
		if sqrt((sh.x - w.player.x) * (sh.x - w.player.x) + (sh.z - w.player.z) * (sh.z - w.player.z)) < 3.0:
			s = sh
			break
	if s == null:
		if not has_cost(w.inventory, SHELTER_STEP_COST[0]):
			return "materials"
		s = {"id": w.nextShelterId, "x": w.player.x, "z": w.player.z, "step": 0,
			"siteQuality": ShelterSim.score_site(w.player.x, w.player.z, w.seed).total,
			"complete": false}
		w.nextShelterId += 1
		w.shelters.append(s)
	if s.step >= ShelterSim.SHELTER_STEPS.size():
		return "complete"
	var cost: Dictionary = SHELTER_STEP_COST[s.step]
	if not has_cost(w.inventory, cost):
		return "materials"
	var secs: float = 0.4 * Config.TIME.REAL_SECONDS_PER_GAME_HOUR
	w.task = {"targetId": s.id, "remaining": secs, "total": secs, "kind": "shelter"}
	return "started"


static func has_cost(inv: Dictionary, cost: Dictionary) -> bool:
	if cost.get("boughs", 0) > 0 and not Items.inv_has(inv, "boughs", cost.boughs):
		return false
	if cost.get("deadfall", 0) > 0 and not Items.inv_has(inv, "deadfall", cost.deadfall):
		return false
	return true


static func pay_cost(inv: Dictionary, cost: Dictionary) -> void:
	if cost.get("boughs", 0) > 0:
		Items.inv_remove(inv, "boughs", cost.boughs)
	if cost.get("deadfall", 0) > 0:
		Items.inv_remove(inv, "deadfall", cost.deadfall)


## Completes a shelter step (called from Actions.tick_work when task.kind == "shelter").
static func finish_shelter_step(w: WorldSim, shelter_id: int) -> void:
	var s: Variant = null
	for x in w.shelters:
		if x.id == shelter_id:
			s = x
			break
	if s == null:
		return
	pay_cost(w.inventory, SHELTER_STEP_COST[s.step])
	s.step += 1
	s.complete = s.step >= ShelterSim.SHELTER_STEPS.size()
	var label: String = ShelterSim.SHELTER_STEPS[mini(s.step, ShelterSim.SHELTER_STEPS.size()) - 1]
	w.push_log("Shelter complete — debris walls, bough bedding." if s.complete else "Shelter: %s done." % label)
