## AudioDirector — consumes GameLoop/GameState each sim tick and drives the
## audio graph. Buses: Master / Ambience / SFX (created at runtime, code-
## authored per FACTORY rule 1). Loops (fire crackle, wind) are two dedicated
## AudioStreamPlayers whose volume comes from AudioMap.map_state — SIM STATE
## ONLY, no wall-clock. Footsteps fire on a sim-tick accumulator (cadence from
## player speed, volume from surface zone). One-shots (UI confirm, rescue
## plane flyby on WON, death sting on DEAD) are event-driven.
##
## Headless guard: under --headless there is no audio driver worth talking to,
## so bus/player setup is skipped; the mapping still runs (tests assert on
## AudioMap directly and on this node's `last_mapping`).
class_name AudioDirector
extends Node

const TICK := Config.SIM_DT  # sim tick length (real s) — the cadence clock

var loop: GameLoop
var state: GameState

var last_mapping: Dictionary = {}

var _fire_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _streams := {}          # name -> AudioStream (loops + one-shots)
var _step_acc := 0.0        # sim-seconds accumulator for footstep cadence
var _step_variant := 0      # rotating footstep variant index (no randf)
var _live := false          # false under headless: compute, never play

const POOL_SIZE := 6
const SMOOTH := 6.0         # loop volume approach rate (per second)


func _ready() -> void:
	_streams = _load_streams()
	_live = not OS.has_feature("headless")
	if _live:
		_setup_buses()
		_fire_player = _make_loop_player(AudioMap.LOOP_FIRE, "Ambience")
		_wind_player = _make_loop_player(AudioMap.LOOP_WIND, "Ambience")
		# Pre-decode the beds behind the title screen (playtest 2026-10-12:
		# first play() on web decodes the OGG on the main thread — a visible
		# lag spike the moment PLAYING starts). Silent at -80 dB; the tick
		# ramp takes over the volume. Beds keep playing; _ramp fades them.
		for p in [_fire_player, _wind_player]:
			if p != null and p.stream != null:
				p.play()
		for i in POOL_SIZE:
			var p := AudioStreamPlayer.new()
			p.bus = "SFX"
			add_child(p)
			_pool.append(p)
	# signal wiring runs headless too: the mapping must still consume ticks
	if loop != null:
		loop.ticked.connect(_on_ticked)
		loop.action_performed.connect(_on_action)
	if state != null:
		state.state_changed.connect(_on_state_changed)


## Buses Master(0)/Ambience(1)/SFX(2), created once, idempotent.
func _setup_buses() -> void:
	if AudioServer.get_bus_index("Ambience") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Ambience")
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")


func _load_streams() -> Dictionary:
	var out := {}
	for name in AudioMap.LOOP_NAMES:
		var s: AudioStream = load("res://assets/audio/%s.ogg" % name)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true  # seamless ambience beds
		if s != null:
			out[name] = s
	for name in AudioMap.EVENT_STREAMS:
		var s: AudioStream = load("res://assets/audio/%s.ogg" % name)
		if s != null:
			out[name] = s
	for i in AudioMap.FOOTSTEP_VARIANTS:
		var s: AudioStream = load("res://assets/audio/footstep_%02d.ogg" % i)
		if s != null:
			out["%s_%d" % [AudioMap.EVENT_FOOTSTEP, i]] = s
	return out


func _make_loop_player(stream_name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = stream_name.capitalize().replace(" ", "") + "Loop"
	p.bus = bus
	p.volume_db = -80.0
	if _streams.has(stream_name):
		p.stream = _streams[stream_name]
	add_child(p)
	return p


## One sim tick: recompute the mapping and apply it (loop volumes, cadence).
func _on_ticked(_tick: int) -> void:
	if loop == null or state == null:
		return
	last_mapping = AudioMap.map_state(AudioMap.from_world(loop.world, state.state))
	_apply_loops(last_mapping["loops"])
	_tick_footsteps(last_mapping)


func _apply_loops(loops: Dictionary) -> void:
	if not _live:
		return
	_ramp(_fire_player, float(loops.get(AudioMap.LOOP_FIRE, 0.0)))
	_ramp(_wind_player, float(loops.get(AudioMap.LOOP_WIND, 0.0)))


## Frame-rate smoothing toward the target linear volume (attack/release).
func _process(delta: float) -> void:
	if not _live:
		return
	for p in [_fire_player, _wind_player]:
		if p == null or not p.has_meta("cur_lin"):
			continue
		var cur: float = p.get_meta("cur_lin")
		var tgt: float = p.get_meta("target_lin")
		cur = lerpf(cur, tgt, clampf(delta * SMOOTH, 0.0, 1.0))
		p.set_meta("cur_lin", cur)
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		# release finished: stop a bed that faded to silence
		if p.get_meta("pending_stop") and cur <= 0.001 and p.playing:
			p.stop()
			p.set_meta("pending_stop", false)


func _ramp(p: AudioStreamPlayer, target_lin: float) -> void:
	if p == null or p.stream == null:
		return
	p.set_meta("target_lin", maxf(target_lin, 0.0001))
	if not p.has_meta("cur_lin"):
		p.set_meta("cur_lin", 0.0001)
	# beds run only while audible: start immediately, stop after the fade-out
	if target_lin > 0.0:
		p.set_meta("pending_stop", false)
		if not p.playing:
			p.play()
	else:
		p.set_meta("pending_stop", true)


## Footstep cadence on the sim clock: each tick adds TICK seconds; when the
## accumulator passes the interval, fire one step (rotating variants — no
## randf, deterministic).
func _tick_footsteps(m: Dictionary) -> void:
	var interval: float = m["step_interval"]
	if interval <= 0.0:
		_step_acc = 0.0
		return
	_step_acc += TICK
	while _step_acc >= interval:
		_step_acc -= interval
		_play_step(float(m["step_vol"]))


func _play_step(vol: float) -> void:
	if not _live or vol <= 0.0:
		return
	var name := "%s_%d" % [AudioMap.EVENT_FOOTSTEP, _step_variant]
	_step_variant = (_step_variant + 1) % AudioMap.FOOTSTEP_VARIANTS
	if not _streams.has(name):
		return
	var p := _free_player()
	if p == null:
		return
	p.stream = _streams[name]
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.play()


## Event one-shots: UI confirm on every player action.
func _on_action(_name: String) -> void:
	_play_one_shot(AudioMap.EVENT_CONFIRM, 0.7, "SFX")


## Event one-shots: rescue flyby on WON, death sting on DEAD.
func _on_state_changed(_prev: int, next: int) -> void:
	# the sim pauses outside PLAYING (no more ticks): fade the beds out now
	if next != GameState.State.PLAYING:
		last_mapping = AudioMap.map_state({})
		_apply_loops({})
	match next:
		GameState.State.WON:
			_play_one_shot(AudioMap.EVENT_FLYBY, 1.0, "SFX")
		GameState.State.DEAD:
			_play_one_shot(AudioMap.EVENT_DEATH, 0.9, "SFX")


func _play_one_shot(stream_name: String, vol: float, bus: String) -> void:
	if not _live or not _streams.has(stream_name):
		return
	var p := _free_player()
	if p == null:
		return
	p.bus = bus
	p.stream = _streams[stream_name]
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.play()


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return null
