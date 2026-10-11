## GameLoop — owns the frozen WorldSim and drives it with a fixed-step
## accumulator (Config.SIM_DT REAL seconds per tick). dt passed to the sim is
## REAL seconds; conversion to game hours happens ONLY inside the sim.
## Headless-testable: tests call setup() + step_tick() directly, no tree needed.
class_name GameLoop
extends Node

const TICK := Config.SIM_DT

var world: WorldSim
var player: CharacterBody3D      # optional 3D rig; when set, drives the sim position
var terrain = Terrain            # duck-typed heightAt provider; LEVEL=generated
                                 # swaps in a TerrainHM (baked data) — the
                                 # frozen sim itself is never modified.
var toasts: Array[String] = []   # every new sim-log line (HUD + tests)
var tick_count := 0
var paused := false              # SHOT_FROZEN: freeze the sim for deterministic shots
signal toast_shown(text: String)
signal ticked(tick: int)
signal action_performed(name: String)  # every action key press (UI confirm SFX)

var _acc := 0.0
var _log_len := 0


## (Re)create the world from p_seed. Safe to call mid-process for restart:
## toasts/tick counters reset too, so the HUD and framing layer resync clean.
func setup(p_seed := 1) -> void:
	world = WorldSim.new(p_seed)
	toasts.clear()
	tick_count = 0
	_acc = 0.0
	_log_len = world.log.size()


func _physics_process(delta: float) -> void:
	if paused:
		return
	_sync_player()
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		step_tick()


## One fixed 0.25 s real tick: world step + work-task progress + toast harvest.
func step_tick() -> void:
	var sprint := player != null and Input.is_action_pressed("sprint")
	world.step(TICK, sprint)
	Actions.tick_work(world, TICK, Needs.compute_debuffs(world.needs).dexterity)
	_collect_toasts()
	tick_count += 1
	ticked.emit(tick_count)


## Snap the sim player to the 3D rig (terrain-follow; mover runs with gravity 0).
func _sync_player() -> void:
	if player == null:
		return
	var p := player.global_position
	world.player.x = p.x
	world.player.z = p.z
	world.player.y = terrain.heightAt(p.x, p.z)
	world.player.moving = Vector2(player.velocity.x, player.velocity.z).length() > 0.15
	player.global_position.y = world.player.y + 0.85  # capsule center above feet
	player.velocity.y = 0.0


## E — collect a sprung snare within reach (TS contextActions tier 2), else
## context gather: chop/snap/peel/scoop/snow/scavenge via the sim's Interact
## radius. Returns a toast string ("" = silent; sim-log lines toast themselves).
func interact() -> String:
	if world.dead != null:
		return ""
	if Actions.check_snares(world) > 0:
		return ""  # "You collect N× small game..." already pushed to the sim log
	var tgt: Variant = Actions.current_target(world)
	if tgt == null:
		return "Nothing within reach."
	if not Actions.begin_work(world):
		return ""  # begin_work pushed its own log line (e.g. needs container)
	return "Working: %s" % Interact.INTERACT_LABEL.get(tgt.kind, tgt.kind)


func feed_fire() -> String:
	var n := Actions.feed_fire(world)
	return "Fed the fire (%d)." % n if n > 0 else "No fire to feed nearby."


func melt() -> String:
	return "Snow melted — safe water." if Actions.boil_water(world) \
		else "Need a lit fire and a container."


func cook() -> String:
	return "Meat roasting." if Actions.cook(world) else "Nothing to cook (or no fire)."


func drink() -> String:
	return "" if Actions.drink(world) else "Nothing to drink."


func eat() -> String:
	return "" if Actions.eat(world) else "Nothing to eat."


## X — set a snare where hare sign allows (TS setSnareAction: cordage-gated,
## 8 m too-close check). Success logs its own quality line.
func set_snare() -> String:
	match Actions.set_snare(world):
		"set":
			return ""
		"materials":
			return "Need cordage for a snare."
		_:
			return "Too close to another snare — overlapping runs spook the hares."


## G — fish an ice-edge hole within reach (TS fish: cordage-gated, dawn/dusk
## bite better). Caught/missed each log their own line.
func fish() -> String:
	match Actions.fish(world):
		"caught", "missed":
			return ""
		"materials":
			return "Need cordage for a line."
		_:
			return "No fish hole here."


## B — craft the first craftable recipe (TS main.ts craftBest greedy loop,
## golden-tested in test_craft). Success logs "Crafted: <label>".
func craft_best() -> String:
	for r in CraftSim.RECIPES:
		if CraftSim.can_craft(world.inventory, r):
			Actions.craft(world, r.id)
			return ""
	return "Nothing you can craft right now."


## H — treat the worst wound (TS treatWound: duct tape + lit fire; the TS
## find-predicate only accepts infected or severity > 30 wounds).
func treat() -> String:
	return "" if Actions.treat_wound(world) \
		else "Need duct tape and a lit fire — and a wound worth treating."


func _unhandled_input(event: InputEvent) -> void:
	if world == null or paused:
		return
	if event.is_action_pressed("interact"):
		_act("interact", interact())
	elif event.is_action_pressed("feed_fire"):
		_act("feed_fire", feed_fire())
	elif event.is_action_pressed("melt"):
		_act("melt", melt())
	elif event.is_action_pressed("cook"):
		_act("cook", cook())
	elif event.is_action_pressed("drink"):
		_act("drink", drink())
	elif event.is_action_pressed("eat"):
		_act("eat", eat())
	elif event.is_action_pressed("set_snare"):
		_act("set_snare", set_snare())
	elif event.is_action_pressed("fish"):
		_act("fish", fish())
	elif event.is_action_pressed("craft"):
		_act("craft", craft_best())
	elif event.is_action_pressed("treat"):
		_act("treat", treat())


func _act(name: String, msg: String) -> void:
	action_performed.emit(name)
	if msg != "":
		toast_shown.emit(msg)


## Drain new sim-log entries into `toasts` (log is capped at 200 with
## pop_front; on wrap, resync the cursor to the tail).
func _collect_toasts() -> void:
	if world.log.size() < _log_len:
		_log_len = world.log.size()
	while _log_len < world.log.size():
		var msg: String = world.log[_log_len].msg
		_log_len += 1
		toasts.append(msg)
		toast_shown.emit(msg)
