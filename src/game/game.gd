## GameLoop — owns the frozen WorldSim and drives it with a fixed-step
## accumulator (Config.SIM_DT REAL seconds per tick). dt passed to the sim is
## REAL seconds; conversion to game hours happens ONLY inside the sim.
## Headless-testable: tests call setup() + step_tick() directly, no tree needed.
class_name GameLoop
extends Node

const TICK := Config.SIM_DT

var world: WorldSim
var player: CharacterBody3D      # optional 3D rig; when set, drives the sim position
var toasts: Array[String] = []   # every new sim-log line (HUD + tests)
var tick_count := 0
var paused := false              # SHOT_FROZEN: freeze the sim for deterministic shots
signal toast_shown(text: String)
signal ticked(tick: int)

var _acc := 0.0
var _log_len := 0


func setup(p_seed := 1) -> void:
	world = WorldSim.new(p_seed)
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
	world.player.y = Terrain.heightAt(p.x, p.z)
	world.player.moving = Vector2(player.velocity.x, player.velocity.z).length() > 0.15
	player.global_position.y = world.player.y + 0.85  # capsule center above feet
	player.velocity.y = 0.0


## E — context gather: chop/snap/peel/scoop/snow/scavenge via the sim's
## Interact radius. Returns a toast string ("" = silent).
func interact() -> String:
	if world.dead != null:
		return ""
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


func _unhandled_input(event: InputEvent) -> void:
	if world == null or paused:
		return
	if event.is_action_pressed("interact"):
		_act(interact())
	elif event.is_action_pressed("feed_fire"):
		_act(feed_fire())
	elif event.is_action_pressed("melt"):
		_act(melt())
	elif event.is_action_pressed("cook"):
		_act(cook())
	elif event.is_action_pressed("drink"):
		_act(drink())
	elif event.is_action_pressed("eat"):
		_act(eat())


func _act(msg: String) -> void:
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
