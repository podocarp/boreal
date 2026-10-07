extends SceneTree
# Golden tests: noise hash/valueNoise2/fbm2 (bit-exact — pure arithmetic path)
# and terrain heightAt/zoneAt/streamX (±1e-9 — sin/pow may drift ~1 ULP between
# V8 and Godot's libm; see docs/boreal-analysis.md risk 2).
# NOTE: goldens use plain float dicts, NOT Vector2 keys — Vector2 is float32
# and truncates golden input coordinates.

const Goldens = preload("res://tests/goldens.gd")

var fails := 0
const TRIG_EPS := 1e-9


func _init():
	for e in Goldens.HASH2:
		var got := NoiseSim.hash2(e.ix, e.iy, e.seed)
		if got != Goldens.f(e.v):
			fails += 1
			print("  hash2(%d,%d,%d): got %.17f want %.17f" % [e.ix, e.iy, e.seed, got, Goldens.f(e.v)])
	for e in Goldens.VALUE_NOISE2:
		var got := NoiseSim.valueNoise2(e.x, e.y, e.seed)
		if got != Goldens.f(e.v):
			fails += 1
			print("  valueNoise2(%s,%s,%d): got %.17f want %.17f" % [str(e.x), str(e.y), e.seed, got, Goldens.f(e.v)])
	for e in Goldens.FBM2:
		var got := NoiseSim.fbm2(e.x, e.y, e.seed, e.oct, e.freq)
		if got != Goldens.f(e.v):
			fails += 1
			print("  fbm2(%s,%s,%d,%d,%s): got %.17f want %.17f" % [str(e.x), str(e.y), e.seed, e.oct, str(e.freq), got, Goldens.f(e.v)])
	for e in Goldens.HEIGHT_AT:
		var got := Terrain.heightAt(e.x, e.z)
		if absf(got - Goldens.f(e.v)) > TRIG_EPS:
			fails += 1
			print("  heightAt(%s,%s): got %.17f want %.17f" % [str(e.x), str(e.z), got, Goldens.f(e.v)])
	for e in Goldens.ZONE_AT:
		var got := Terrain.zoneAt(e.x, e.z)
		if got != e.zone:
			fails += 1
			print("  zoneAt(%s,%s): got %s want %s" % [str(e.x), str(e.z), got, e.zone])
	for z in Goldens.STREAM_X:
		var got := Terrain.streamX(z)
		if absf(got - Goldens.f(Goldens.STREAM_X[z])) > TRIG_EPS:
			fails += 1
			print("  streamX(%s): got %.17f want %.17f" % [str(z), got, Goldens.f(Goldens.STREAM_X[z])])

	# structural checks from terrain.test.ts
	if absf(Terrain.heightAt(0.0, -150.0)) >= 0.5:
		fails += 1
		print("  lake center not flat at ice level")
	var sx := Terrain.streamX(0.0)
	if not Terrain.heightAt(sx, 0.0) < Terrain.heightAt(sx + 40.0, 0.0):
		fails += 1
		print("  stream does not carve below surroundings")
	if Terrain.speedMulAt("bog") >= 1.0:
		fails += 1
		print("  bog speed mul")

	if fails == 0:
		print("PASS terrain: noise + height/zone goldens match TS")
		quit(0)
	else:
		print("FAIL terrain: %d mismatches" % fails)
		quit(1)
