class_name ScatterRender
## Instances the FROZEN sim's deterministic Scatter.scatter() props as
## MultiMeshInstance3D groups using the copied Stylized Nature glTF models.
## Variant choice per prop is a pure function of the prop index (deterministic).

const MODELS := {
	"spruce": [
		"res://assets/nature/Pine_1.gltf",
		"res://assets/nature/Pine_2.gltf",
		"res://assets/nature/Pine_3.gltf",
	],
	"birch": [
		"res://assets/nature/CommonTree_1.gltf",
		"res://assets/nature/CommonTree_2.gltf",
	],
	"rock": [
		"res://assets/nature/Rock_Medium_1.gltf",
		"res://assets/nature/Rock_Medium_2.gltf",
	],
}


## Deterministic variant index for prop `i` of kind `kind`.
static func variant_index(i: int, kind: String) -> int:
	var k: int = (MODELS[kind] as Array).size()
	return int((i * 2654435761) % k)


## props -> {model_path: Array[Transform3D]}. Y from the sim's heightAt.
## Optional distance cull around `center`/`radius` (lavapipe budget).
static func build_instances(props: Array, center := Vector2.INF,
		radius := 1e9) -> Dictionary:
	var out := {}
	for path_list in MODELS.values():
		for p in path_list:
			out[p] = []
	for i in props.size():
		var p: Dictionary = props[i]
		if center != Vector2.INF:
			if ((p.x - center.x) * (p.x - center.x)
					+ (p.z - center.y) * (p.z - center.y)) > radius * radius:
				continue
		var path: String = MODELS[p.kind][variant_index(i, p.kind)]
		var pos := Vector3(p.x, Terrain.heightAt(p.x, p.z), p.z)
		var basis := Basis(Vector3.UP, p.rot).scaled(Vector3.ONE * p.scale)
		out[path].append(Transform3D(basis, pos))
	return out


## One MultiMeshInstance3D per model path (mesh may be a PackedScene or Mesh).
static func make_multimesh(mesh: Resource, xforms: Array,
		name_: String, mat_override: Material = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.mesh = mesh  # MultiMeshInstance3D.mesh is setter-only; set it on the MultiMesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	if mat_override:
		mmi.material_overlay = mat_override
	return mmi


## Extract the first Mesh from an imported glTF (PackedScene) for MultiMesh use.
static func mesh_from_gltf(path: String) -> Mesh:
	var res: Resource = load(path)
	if res == null:
		return null
	if res is Mesh:
		return res
	var inst := (res as PackedScene).instantiate()
	var mesh: Mesh = null
	var stack: Array[Node] = [inst]
	while not stack.is_empty() and mesh == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		else:
			for c in n.get_children():
				stack.append(c)
	inst.free()
	return mesh


## Subtle snow-blue tint overlaid on the Quaternius materials so the flora
## reads arctic (asset-inventory: shift toward desaturated blue-white).
static func snow_tint() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.86, 0.9, 0.96, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
