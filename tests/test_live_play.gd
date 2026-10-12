extends SceneTree
# Regression (web 0.1.0): main.gd's screenshot-shot block ran
# `get_tree().quit()` even when SHOT_OUT was unset, so LIVE PLAY killed its own
# scene tree on frame 2 — frozen title screen, dead input, wasm shell spinning
# on a dead engine. Screenshot tests always set SHOT_OUT, so only interactive
# play exposed it.
#
# Headless note: the shot path awaits RenderingServer.frame_post_draw, which
# never fires headless, so the quit() itself is unobservable here. We assert on
# the state the buggy code set BEFORE the await: _shot_saved flips true on
# frame 2 even with SHOT_OUT unset. Live play must never enter the shot path.

var _frames := 0
var _main: Node
var fails := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  " + msg)


func _init():
	# SHOT_OUT deliberately NOT set: this is the live-play path.
	assert(OS.get_environment("SHOT_OUT") == "")
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames >= 10:
		_check(is_instance_valid(_main), "main scene was freed (tree quit early?)")
		_check(_main != null and _main._shot_saved == false,
			"live play entered the screenshot-shot path (SHOT_OUT unset but " \
			+ "_shot_saved=true) — the frame-2 quit() regression is back")
		if fails == 0:
			print("PASS test_live_play")
			quit(0)
		else:
			print("FAIL test_live_play: %d checks failed" % fails)
			quit(1)
	return false
