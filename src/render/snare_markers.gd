## Snare markers: a small stake + cord loop at each set snare, built in code
## (FACTORY rule 1 — no new assets). One shared box/torus mesh pair, one
## StandardMaterial3D per state (set = pale wood, sprung = snare-line red),
## so N snares cost 2 meshes + 2 materials regardless of count.
## Sprung snares (pending game) stay visible in red: that IS the pickup marker.
class_name SnareMarkers


## Build the marker node tree for one snare dict at terrain height `y`.
static func make_marker(s: Dictionary, y: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Snare_%d" % int(s.id)
	root.position = Vector3(s.x, y, s.z)

	var stake := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.06, 0.7, 0.06)
	stake.mesh = sm
	stake.position = Vector3(0.0, 0.35, 0.0)
	stake.material_override = _mat(false)
	root.add_child(stake)

	var loop := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.14
	loop.mesh = tm
	loop.position = Vector3(0.12, 0.55, 0.0)
	loop.rotation_degrees = Vector3(90.0, 0.0, 0.0)  # vertical loop, like a noose
	loop.material_override = _mat(false)
	root.add_child(loop)

	# game-in-the-snare indicator: a small pale bundle at the base
	var game := MeshInstance3D.new()
	game.name = "Game"
	var gm := SphereMesh.new()
	gm.radius = 0.12
	gm.height = 0.24
	game.mesh = gm
	game.position = Vector3(0.0, 0.12, 0.18)
	game.material_override = _mat(true)
	game.visible = s.pending != null and s.pending > 0
	root.add_child(game)
	return root


## Refresh a marker subtree for a snare whose state changed (sprung/pending).
static func update_marker(marker: Node3D, s: Dictionary) -> void:
	var game: MeshInstance3D = marker.get_node_or_null("Game")
	if game != null:
		game.visible = s.pending != null and s.pending > 0


static func _mat(sprung: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.35, 0.28) if sprung else Color(0.62, 0.48, 0.30)
	m.roughness = 0.9
	return m
