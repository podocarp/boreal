class_name ThirdPersonCamera
extends SpringArm3D
# Collision-avoiding spring-arm follow rig. The arm shortens toward obstacles
# (SpringArm3D's built-in ray) so the camera never clips through walls.

## Path to the node to follow (NodePath export so it survives PackedScene).
@export var target_path: NodePath
var target: Node3D
@export var sensitivity: float = 0.0025
@export var pitch_limit_deg: float = 70.0
## Rest distance from target to camera.
@export var distance: float = 4.0
## How fast the arm retracts/extends around obstacles (0..1 per frame).
@export var spring_length_speed: float = 10.0

var pitch: float = -0.25
var yaw: float = 0.0

func _ready() -> void:
	spring_length = distance
	if target == null and target_path:
		target = get_node_or_null(target_path) as Node3D

func _process(delta: float) -> void:
	if target:
		global_position = target.global_position + Vector3(0, 1.5, 0)
	# Smoothly restore rest length when clear (retraction is handled by the arm).
	var want := distance
	if spring_length < want:
		spring_length = minf(want, spring_length + spring_length_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative.x, event.relative.y)

func apply_look(dx: float, dy: float) -> void:
	yaw -= dx * sensitivity
	pitch = clampf(pitch - dy * sensitivity,
		deg_to_rad(-pitch_limit_deg), deg_to_rad(pitch_limit_deg))
	rotation = Vector3(pitch, yaw, 0.0)

## Camera-relative horizontal move basis (unit vectors), used by TPS players.
func move_basis() -> Array[Vector3]:
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 1e-6:
		f = -Vector3(0, 0, 1)
	f = f.normalized()
	return [f, f.cross(Vector3.UP)]
