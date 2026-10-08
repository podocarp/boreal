## Builds the vendored SDK third-person rig for boreal: capsule body at the
## sim's CRASH site, gravity 0 (GameLoop snaps y to heightAt every tick).
class_name PlayerRig


static func make() -> CharacterBody3D:
	var PlayerMover: GDScript = load("res://vendor/sdk/player_mover.gd")
	var ThirdPersonCamera: GDScript = load("res://vendor/sdk/camera_third_person.gd")
	var p: CharacterBody3D = PlayerMover.new()
	p.name = "Player"
	p.walk_speed = Config.PLAYER.WALK_SPEED_MPS
	p.sprint_speed = Config.PLAYER.RUN_SPEED_MPS
	p.gravity = 0.0
	p.position = Vector3(Terrain.CRASH.x,
		Terrain.heightAt(Terrain.CRASH.x, Terrain.CRASH.z) + 0.85, Terrain.CRASH.z)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	col.shape = shape
	p.add_child(col)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.79, 0.25, 0.18)  # PALETTE.PARKA — red hero silhouette
	body.material_override = mat
	p.add_child(body)
	var arm: SpringArm3D = ThirdPersonCamera.new()
	arm.name = "CameraThirdPerson"
	arm.target = p
	arm.target_path = NodePath("..")
	arm.pitch = -0.12
	arm.yaw = -2.8  # face the starter grove (CRASH + (10, 28)) at spawn
	arm.apply_look(0.0, 0.0)
	p.add_child(arm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	arm.add_child(cam)
	p.camera_pivot = arm
	return p
