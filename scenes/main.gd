extends Node3D
## Placeholder 3D scene for the phase-1 screenshot pipeline: samples the ported
## analytic terrain into a flat-shaded mesh around the crash site, adds a low
## sun + camera. Reads $SHOT_OUT and saves one frame (render_shot.sh contract).

var _shot_saved := false


func _ready() -> void:
	# dark cool environment so the ground reads "snow under overcast"
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.68, 0.74)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.88)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-28.0, 35.0, 0.0)  # low subarctic sun
	sun.light_color = Color(1.0, 0.87, 0.72)
	sun.light_energy = 1.2
	add_child(sun)

	add_child(_make_terrain_mesh())
	add_child(_make_props())

	var cam := Camera3D.new()
	cam.name = "Camera"
	# stand on the shore north-east of the wreck, look into the starter grove
	var cx := Terrain.CRASH.x + 12.0
	var cz := Terrain.CRASH.z + 18.0
	cam.position = Vector3(cx, Terrain.heightAt(cx, cz) + 2.2, cz)
	cam.look_at(Vector3(Terrain.CRASH.x + 10.0, Terrain.heightAt(Terrain.CRASH.x + 10.0, Terrain.CRASH.z + 30.0) + 2.0, Terrain.CRASH.z + 30.0), Vector3.UP)
	cam.current = true
	add_child(cam)


## 64x64 grid over a 160 m box around CRASH, sampled from the SAME heightAt
## the sim uses (docs/boreal-analysis.md risk 5).
func _make_terrain_mesh() -> MeshInstance3D:
	var n := 64
	var half := 80.0
	var cx: float = Terrain.CRASH.x
	var cz: float = Terrain.CRASH.z + 10.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var x0 := cx - half + 2.0 * half * float(i) / float(n)
			var z0 := cz - half + 2.0 * half * float(j) / float(n)
			var x1 := cx - half + 2.0 * half * float(i + 1) / float(n)
			var z1 := cz - half + 2.0 * half * float(j + 1) / float(n)
			var p00 := Vector3(x0, Terrain.heightAt(x0, z0), z0)
			var p10 := Vector3(x1, Terrain.heightAt(x1, z0), z0)
			var p01 := Vector3(x0, Terrain.heightAt(x0, z1), z1)
			var p11 := Vector3(x1, Terrain.heightAt(x1, z1), z1)
			# snow white on ice/low ground, cool grey on slopes
			var c := Color(0.92, 0.94, 0.97).lerp(Color(0.72, 0.76, 0.82),
				clampf(p00.y / 25.0, 0.0, 1.0))
			for p in [p00, p10, p11, p00, p11, p01]:
				st.set_color(c)
				st.add_vertex(p)
	var arrays := st.commit_to_arrays()
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = arr_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


## A few dark spruce cones from the deterministic scatter (proves scatter+terrain
## agreement in the shot; kept tiny for lavapipe).
func _make_props() -> Node3D:
	var root := Node3D.new()
	root.name = "Props"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.24, 0.16)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.9
	mesh.height = 7.0
	mesh.material = mat
	var placed := 0
	for p in Scatter.scatter(1):
		if p.kind != "spruce":
			continue
		var d := sqrt(pow(p.x - Terrain.CRASH.x, 2) + pow(p.z - (Terrain.CRASH.z + 10.0), 2))
		if d > 70.0:
			continue
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mat
		m.position = Vector3(p.x, Terrain.heightAt(p.x, p.z) + 3.0 * p.scale, p.z)
		m.scale = Vector3.ONE * p.scale
		root.add_child(m)
		placed += 1
		if placed >= 40:
			break
	return root


func _process(_d: float) -> void:
	if _shot_saved:
		return
	_shot_saved = true
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("SHOT_OUT")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit.call_deferred()
