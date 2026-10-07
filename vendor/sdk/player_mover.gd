class_name PlayerMover
extends CharacterBody3D
# WASD + sprint movement for FPS/TPS players. Movement is camera-relative
# (yaw of `camera_pivot`) so controls match what the player sees.
#
# Headless-testable: tests set `test_input` instead of faking the Input
# singleton; _physics_process consumes whichever is present.

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var gravity: float = 9.8
## Path to the node whose yaw defines "forward" (NodePath export so it
## survives PackedScene; resolved in _ready).
@export var camera_pivot_path: NodePath
var camera_pivot: Node3D
## Test hook: Vector2(x=right, y=forward). Nonzero overrides live input.
var test_input := Vector2.ZERO

func _ready() -> void:
	if camera_pivot == null and camera_pivot_path:
		camera_pivot = get_node_or_null(camera_pivot_path) as Node3D

func _physics_process(delta: float) -> void:
	var dir := _read_input()
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	var wish := _wish_direction(dir)
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	move_and_slide()

func _read_input() -> Vector2:
	if test_input != Vector2.ZERO:
		return test_input
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")

## Horizontal world-space wish vector from input, rotated by camera yaw.
## Yaw-only basis: camera pitch must not change ground speed.
func _wish_direction(dir: Vector2) -> Vector3:
	if dir == Vector2.ZERO:
		return Vector3.ZERO
	var y := camera_pivot.global_rotation.y if camera_pivot else 0.0
	var fwd := Vector3(-sin(y), 0, -cos(y))
	var right := fwd.cross(Vector3.UP)
	var w := fwd * dir.y + right * dir.x
	return w.normalized() if w.length_squared() > 1e-6 else Vector3.ZERO
