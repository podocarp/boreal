## Stream water stopgap: a ribbon MeshInstance3D following the frozen
## Terrain.streamX path, riding the sim's own channel-floor formula
## (Terrain._heightAtLakeApproach — no new height math), with an animated
## wave + fresnel-ish shader. SHOT_FROZEN=1 pins u_time so screenshots are
## deterministic (no wall-clock anywhere: u_time comes from sim seconds).
class_name WaterRender

const HALF_W := 3.4          # channel is fully carved (flat) within ±5 m of streamX
const Z_MIN := -150.0        # lake shore
const Z_MAX := 138.0         # terrain mesh edge (CRASH.z + 200)
const STEP := 3.0
const FROZEN_TIME := 4.0     # fixed shader time for deterministic shots
const LAKE_T := 1.15         # Terrain's lakeMix ends at lakeT=1.15: inside that
                             # radius the frozen heightAt flattens the channel
                             # floor down to lake ice (y≈0), so the channel-floor
                             # formula no longer describes the ground and the
                             # ribbon would float as a sheet over the lake shelf.
                             # The stream only draws OUTSIDE this region.
const BANK_D := 6.0          # bank sample distance across the channel (m); the
                             # frozen carve rises from ±5 m, so ±6 m is bank.
const BANK_MARGIN := 0.10    # water surface (incl. ±0.09 shader waves) must
                             # stay this far below the bank
const TAPER := 0.10          # ramp width over this margin (lakeT units / meters)
                             # so the ribbon tapers to a point where the channel
                             # ends instead of showing a vertical cut edge.

const SHADER := """
shader_type spatial;
uniform vec3 u_deep = vec3(0.04, 0.22, 0.42);
uniform vec3 u_shallow = vec3(0.45, 0.78, 0.95);
uniform float u_time = 0.0;
uniform float u_wave_amp = 0.09;
varying vec3 v_wp;
void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(v_wp.x * 0.9 + u_time * 1.6) * cos(v_wp.z * 0.7 - u_time * 1.1);
	VERTEX.y += w * u_wave_amp;
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(-VIEW), NORMAL), 0.0, 1.0), 2.0);
	// scrolling ripple bands: bright crests on deep blue
	float band = sin(v_wp.z * 1.7 - u_time * 2.4 + sin(v_wp.x * 1.3) * 1.2);
	float crest = smoothstep(0.35, 0.95, band);
	vec3 col = mix(u_deep, u_shallow, clamp(crest * 0.65 + fres * 0.5, 0.0, 1.0));
	// darker edges where water meets bank (UV.x = 0/1 across the channel)
	float across = abs(UV.x * 2.0 - 1.0);
	float edge = smoothstep(0.62, 1.0, across);
	col = mix(col, u_deep * 0.55, edge * 0.7);
	// foam line at the bank, flickering with the ripples
	float foam = smoothstep(0.86, 1.0, across) * (0.55 + 0.45 * sin(v_wp.z * 3.1 - u_time * 3.0));
	col = mix(col, vec3(0.92, 0.96, 1.0), foam * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.08 + 0.2 * (1.0 - fres);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = u_shallow * (fres * 0.14 + crest * 0.08);
}
"""


## Water surface height: channel floor (exactly what heightAt yields within
## ±5 m of streamX) plus a small freeboard so it reads as a surface.
static func water_y(z: float) -> float:
	return maxf(-1.5, Terrain._heightAtLakeApproach(z)) + 0.12


## Bank height across the channel at row z (frozen heightAt sampled at ±BANK_D).
static func bank_y(z: float) -> float:
	var sx := Terrain.streamX(z)
	return minf(Terrain.heightAt(sx - BANK_D, z), Terrain.heightAt(sx + BANK_D, z))


## 0..1 width ramp: where the frozen channel actually exists. The
## channel-floor formula only describes the ground OUTSIDE the lake-flatten
## region (Terrain.heightAt mixes everything inside lakeT<1.15 down to lake
## ice, so the ribbon would float there as a sheet over the shelf — this is
## what put the camp "in water") and only while the bank stays above the
## surface by BANK_MARGIN. Ramps to 0 at both limits so the ribbon tapers to
## a point where the channel ends instead of showing a vertical cut edge.
static func channel_taper(z: float) -> float:
	var y := water_y(z)
	var t_lake := clampf((Terrain.lakeT(Terrain.streamX(z), z) - LAKE_T) / TAPER, 0.0, 1.0)
	var t_bank := clampf((bank_y(z) - BANK_MARGIN - y) / TAPER, 0.0, 1.0)
	return minf(t_lake, t_bank)


static func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var prev_base := -1
	var z := Z_MIN
	while z <= Z_MAX + 0.001:
		var sx := Terrain.streamX(z)
		var y := water_y(z)
		var t := channel_taper(z)
		if t <= 0.0:
			if prev_base >= 0:
				# channel ended: close the strip at a point on the centerline
				var base := verts.size()
				_append_pair(verts, norms, uvs, sx, y, z, 0.0)
				var a := prev_base
				idx.append_array(PackedInt32Array([a, a + 1, base, a + 1, base + 1, base]))
				prev_base = -1
			z += STEP
			continue
		var base := verts.size()
		_append_pair(verts, norms, uvs, sx, y, z, HALF_W * t)
		if prev_base >= 0:
			var a := prev_base
			idx.append_array(PackedInt32Array([a, a + 1, base, a + 1, base + 1, base]))
		prev_base = base
		z += STEP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_pair(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, sx: float, y: float, z: float, half: float) -> void:
	verts.append(Vector3(sx - half, y, z))
	verts.append(Vector3(sx + half, y, z))
	norms.append(Vector3.UP)
	norms.append(Vector3.UP)
	uvs.append(Vector2(0.0, z * 0.05))
	uvs.append(Vector2(1.0, z * 0.05))


static func build_material(frozen: bool) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("u_time", FROZEN_TIME if frozen else 0.0)
	return mat


static func build(frozen: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "StreamWater"
	mi.mesh = build_mesh()
	mi.material_override = build_material(frozen)
	return mi
