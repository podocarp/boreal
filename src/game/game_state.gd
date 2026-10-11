## Game-state machine: MENU -> PLAYING -> WON / DEAD.
## Watches the GameLoop's WorldSim on every sim tick: world.rescued -> WON,
## world.dead -> DEAD (the sim computes both; this class only routes them).
## Owns restart: re-creates the world from the SAME seed without restarting
## the process — via the optional `rebuild` hook (main.gd re-applies the
## terrain provider, camp fire and player seat there), else a bare
## loop.setup(run_seed). Pure logic: no UI, no pixels, headless-testable.
class_name GameState
extends Node

enum State { MENU, PLAYING, WON, DEAD }

var loop: GameLoop
var state: int = State.MENU
var run_seed := 1
var frozen := false        # SHOT_FROZEN: keep the sim paused in PLAYING too
var rebuild := Callable()  # optional hook: re-create the world (same seed)
signal state_changed(prev: int, next: int)


func setup(p_loop: GameLoop, p_seed: int) -> void:
	loop = p_loop
	run_seed = p_seed
	loop.paused = frozen or state != State.PLAYING
	loop.ticked.connect(_on_ticked)


## Transition + side effects (sim pause). Emits state_changed even for
## same-state re-entry so listeners (UI, HUD) can resync.
func goto(next: int) -> void:
	var prev := state
	state = next
	loop.paused = frozen or next != State.PLAYING
	state_changed.emit(prev, next)


func start() -> void:
	if state == State.MENU:
		goto(State.PLAYING)


func restart() -> void:
	if state != State.WON and state != State.DEAD:
		return
	if rebuild.is_valid():
		rebuild.call()
	else:
		loop.setup(run_seed)
	goto(State.PLAYING)


## Shot-harness / test hook: jump to a state bypassing the transition rules.
func force_state(next: int) -> void:
	goto(next)


func _on_ticked(_tick: int) -> void:
	if state != State.PLAYING:
		return
	if loop.world.rescued != null:
		goto(State.WON)
	elif loop.world.dead != null:
		goto(State.DEAD)
