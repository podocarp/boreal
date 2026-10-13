extends SceneTree
# Regression (playtest 2026-10-12, web build): the player fell through the
# terrain a few steps after starting. Root cause: Godot 4.7 HeightMapShape3D
# names its depth property `map_depth`; the frozen-level builder set
# `map_height`, which fails at runtime (property does not exist), so
# _frozen_terrain_collision() died mid-build and the level shipped with NO
# terrain floor. Headless script errors only PRINT — no test asserted the
# collider exists, and screenshots render the visual mesh (no physics), so
# 18/18 stayed green on a floorless world.
#
# Gate: (1) the collider node exists with a valid HeightMapShape3D,
# (2) downward rays hit it within 0.3 m of Terrain.heightAt across the map,
# (3) the real mover settles ON the floor under gravity.

var _frames := 0
var _ready_frame := 0
var _main: Node
var fails := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  " + msg)


func _init():
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_frames += 1
	# staged _ready: the collider lands mid-build; wait for WORLD READY
	if not _main._world_ready:
		return false
	if _ready_frame == 0:
		_ready_frame = _frames
	if _frames == _ready_frame + 2:
		_collider_checks()
	if _frames == _ready_frame + 4:
		# enter PLAYING so the mover's physics enables (menu pauses it)
		_main._state.start()
	if _frames >= _ready_frame + 154:  # ~2.5 s of physics to settle
		_settle_checks()
		if fails == 0:
			print("PASS test_terrain_collider")
			quit(0)
		else:
			print("FAIL test_terrain_collider: %d checks failed" % fails)
			quit(1)
	return false


func _collider_checks() -> void:
	var body := _main.get_node_or_null("TerrainCollision")
	_check(body != null and body is StaticBody3D,
		"TerrainCollision StaticBody missing — collider build died " \
		+ "(HeightMapShape3D property typo regression: it's map_depth!)")
	if body == null:
		return
	# shape child is created unnamed in main.gd -> index, not name
	var cs: CollisionShape3D = body.get_child(0) as CollisionShape3D \
		if body.get_child_count() > 0 else null
	_check(cs != null, "TerrainCollision has no CollisionShape3D child")
	if cs == null:
		return
	var shape := cs.shape as HeightMapShape3D
	_check(shape != null, "collision shape is not a HeightMapShape3D")
	if shape == null:
		return
	_check(shape.map_width == 128 and shape.map_data.size() == 128 * 128,
		"heightmap shape invalid: map_width=%d map_data=%d (expected 128 / 16384)" \
		% [shape.map_width, shape.map_data.size()])
	# rays: collider surface must match the visual mesh everywhere but the
	# wreck footprint (the wreck's own StaticBody is on layer 1 too)
	var direct: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var props := _main.get_node_or_null("Scatter/PropColliders")
	var excl: Array = [props.get_rid()] if props != null else []
	for pt in [Vector2(60, -20), Vector2(-70, 30), Vector2(40, 80),
			Vector2(-100, -80), Vector2(110, -110), Vector2(0, 130)]:
		var p := Vector3(pt.x, 30.0, pt.y)
		var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -80, 0), 1 | 2)
		q.exclude = excl
		var hit := direct.intersect_ray(q)
		if hit.is_empty():
			_fail_ray(pt, "MISS")
		else:
			var want := Terrain.heightAt(pt.x, pt.y)
			if absf(float(hit.position.y) - want) > 0.3:
				_fail_ray(pt, "y=%.2f vs mesh %.2f" % [hit.position.y, want])


func _fail_ray(pt: Vector2, what: String) -> void:
	_check(false, "ray at (%0.0f,%0.0f): %s — collider does not match mesh" % [
		pt.x, pt.y, what])


func _settle_checks() -> void:
	var player: CharacterBody3D = _main.get_node("Player")
	var feet := player.global_position.y - 0.85
	var want := Terrain.heightAt(player.global_position.x, player.global_position.z)
	_check(absf(feet - want) < 0.6,
		"player did not settle on the terrain: feet y=%.2f, mesh %.2f " % [feet, want] \
		+ "(fell through or floated — mover gravity/collider regression)")
