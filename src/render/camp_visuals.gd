## Camp visuals built at a flat spot (CampSite.find_center): rock ring +
## fire light + emissive flame. Fire light: shadows OFF + small range +
## modest energy — the old shadowed 20-energy omni painted pink streaks
## down the slope (light leaking across the fall-off).
class_name CampVisuals


static func build(camp: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Camp"
	# trampled-snow pad: reads as "camp clearing" and hides small grade changes
	var pad := MeshInstance3D.new()
	pad.name = "CampPad"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 3.2
	pad_mesh.bottom_radius = 3.2
	pad_mesh.height = 0.06
	pad.mesh = pad_mesh
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.72, 0.70, 0.64)  # trodden snow, warmer than surroundings
	pad_mat.roughness = 0.95
	pad.material_override = pad_mat
	pad.position = Vector3(camp.x, camp.y + 0.02, camp.z)
	root.add_child(pad)
	var rock_mesh := ScatterRender.mesh_from_gltf("res://assets/nature/Rock_Medium_1.gltf")
	if rock_mesh != null:
		var xforms: Array = []
		for k in 9:
			var a := TAU * float(k) / 9.0
			var rx := camp.x + cos(a) * 1.5
			var rz := camp.z + sin(a) * 1.5
			var b := Basis(Vector3.UP, a * 2.3).scaled(Vector3.ONE * 0.5)
			xforms.append(Transform3D(b, Vector3(rx, camp.y - 0.25, rz)))
		root.add_child(ScatterRender.make_multimesh(rock_mesh, xforms, "CampRocks"))
	var fire := OmniLight3D.new()
	fire.name = "CampfireGlow"
	fire.position = Vector3(camp.x, camp.y + 1.0, camp.z)
	fire.light_color = Color(1.0, 0.55, 0.22)
	fire.light_energy = 1.4
	fire.omni_range = 6.0
	fire.shadow_enabled = false
	root.add_child(fire)
	# visible flame: small emissive cone (no flame asset in any pack)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 1.5
	flame.mesh = cone
	var fmat := StandardMaterial3D.new()
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.5, 0.15)
	fmat.emission_energy_multiplier = 1.6
	fmat.albedo_color = Color(1.0, 0.4, 0.12)
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fmat
	flame.position = Vector3(camp.x, camp.y + cone.height * 0.5 + 0.05, camp.z)
	root.add_child(flame)
	return root
