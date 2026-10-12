extends SceneTree
# Regression (web 0.1.0): PlayerMover._read_input fed Input.get_vector's raw
# output into a y=forward-positive contract, but get_vector returns NEGATIVE
# y for the forward action (it lives in the negative_y slot) — W walked
# backwards. Tests drove `test_input` (which bypasses _read_input), so the
# live-input sign was never exercised.
#
# Headless note: Input.parse_input_event does not update action state in a
# --script context; Input.action_press does, and get_vector reads exactly that
# state — so this pins the real action->get_vector->mover sign chain.

const PlayerMover = preload("res://vendor/sdk/player_mover.gd")


func _init():
	var mover: CharacterBody3D = PlayerMover.new()
	var pivot := Node3D.new()  # yaw 0 => camera forward is -Z
	root.add_child(pivot)
	root.add_child(mover)
	mover.camera_pivot = pivot
	mover.test_input = Vector2.ZERO
	_run(mover)


func _run(mover: CharacterBody3D) -> void:
	await process_frame  # SceneTree script: self is the tree; let nodes enter

	var fails := 0

	Input.action_press("move_forward")
	var v: Vector2 = mover._read_input()
	if v.y <= 0.0:
		print("  move_forward: _read_input y=%.2f (expected > 0 — forward)" % v.y)
		fails += 1
	var wish: Vector3 = mover._wish_direction(v)
	if wish.z >= 0.0:
		print("  move_forward at yaw 0: wish z=%.2f (expected < 0 — into the screen)" % wish.z)
		fails += 1
	Input.action_release("move_forward")

	Input.action_press("move_back")
	v = mover._read_input()
	if v.y >= 0.0:
		print("  move_back: _read_input y=%.2f (expected < 0 — backward)" % v.y)
		fails += 1
	Input.action_release("move_back")

	Input.action_press("move_right")
	v = mover._read_input()
	if v.x <= 0.0:
		print("  move_right: _read_input x=%.2f (expected > 0 — right)" % v.x)
		fails += 1
	Input.action_release("move_right")

	if fails == 0:
		print("PASS test_player_input")
		quit(0)
	else:
		print("FAIL test_player_input: %d failures" % fails)
		quit(1)
