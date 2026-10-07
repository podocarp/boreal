## Deterministic resource scatter — port of scatter.ts.
class_name Scatter

## Returns Array[Dictionary{kind,x,z,scale,rot}]
static func scatter(seed: int) -> Array:
	var props: Array = []
	var n := 1400
	var r := 380.0
	for i in n:
		# deterministic jittered grid-ish placement
		var gx := float((i * 977) % 53) / 53.0
		var gz := float((i * 1699) % 71) / 71.0
		var x := (NoiseSim.valueNoise2(i * 0.71, 3.3, seed) * 2.0 - 1.0) * r + gx * 7.0
		var z := (NoiseSim.valueNoise2(5.1, i * 0.53, seed) * 2.0 - 1.0) * r + gz * 7.0
		var zone := Terrain.zoneAt(x, z)
		if zone == "lake" or zone == "stream":
			continue
		if Terrain.lakeT(x, z) < 1.12:
			continue
		if absf(x - Terrain.streamX(z)) < 8.0:
			continue

		var v := NoiseSim.valueNoise2(x * 0.05, z * 0.05, seed + 5)
		var kind := ""
		if zone == "ridge":
			kind = "rock" if v < 0.62 else ("birch" if v < 0.72 else "")
		elif zone == "bog":
			kind = "spruce" if v < 0.3 else ("rock" if v > 0.92 else "")
		else:
			kind = "spruce" if v < 0.55 else ("birch" if v < 0.64 else ("rock" if v > 0.97 else ""))
		if kind == "":
			continue

		var scale := 0.0
		if kind == "spruce":
			scale = 0.7 + NoiseSim.valueNoise2(x, z, seed + 9) * 1.1
		elif kind == "birch":
			scale = 0.6 + NoiseSim.valueNoise2(x, z, seed + 13) * 0.7
		else:
			scale = 0.5 + NoiseSim.valueNoise2(x, z, seed + 17) * 1.4
		var rot := NoiseSim.valueNoise2(x + 40.0, z - 40.0, seed + 23) * TAU
		props.append({"kind": kind, "x": x, "z": z, "scale": scale, "rot": rot})

	# Guaranteed starter grove: tight spruce stand 15-45 m from the crash site.
	for i in 90:
		var a := NoiseSim.valueNoise2(i * 1.7, 9.1, seed + 31) * TAU
		var rad := 15.0 + NoiseSim.valueNoise2(i * 2.3, 4.4, seed + 37) * 30.0
		var x := Terrain.CRASH.x + 10.0 + cos(a) * rad
		var z := Terrain.CRASH.z + 28.0 + sin(a) * rad * 0.7
		if Terrain.lakeT(x, z) < 1.12:
			continue
		if absf(x - Terrain.streamX(z)) < 8.5:
			continue
		if Terrain.heightAt(x, z) <= 0.2:
			continue
		if sqrt((x - Terrain.CRASH.x) * (x - Terrain.CRASH.x) + (z - Terrain.CRASH.z) * (z - Terrain.CRASH.z)) < 8.0:
			continue
		var scale := 0.8 + NoiseSim.valueNoise2(x, z, seed + 41) * 1.0
		var rot := NoiseSim.valueNoise2(x + 40.0, z - 40.0, seed + 43) * TAU
		var kind := "spruce" if NoiseSim.valueNoise2(x, z, seed + 47) < 0.85 else "birch"
		props.append({"kind": kind, "x": x, "z": z, "scale": scale, "rot": rot})

	# sanity: nothing embedded below terrain
	var kept: Array = []
	for p in props:
		if Terrain.heightAt(p.x, p.z) > 0.2 or p.kind == "rock":
			kept.append(p)
	return kept


## Sim colliders (trunk/rock circles) derived from the same scatter.
static func colliders_from(props: Array) -> Array:
	var out: Array = []
	for p in props:
		if p.kind == "birch" and p.scale <= 0.9:
			continue  # thin birches are push-through
		var r: float = 0.5 + p.scale * 0.7 if p.kind == "rock" else 0.35 + p.scale * 0.25
		out.append({"x": p.x, "z": p.z, "r": r})
	return out
