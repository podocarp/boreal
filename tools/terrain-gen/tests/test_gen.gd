## Determinism + sanity tests for the fBm/erosion generator.
extends SceneTree


func _init() -> void:
	_test_determinism()
	_test_seed_divergence()
	_test_height_range()
	_test_erosion_determinism()
	quit(0)


func _test_determinism() -> void:
	var a := Gen.heightmap(64, 42, 5)
	var b := Gen.heightmap(64, 42, 5)
	var ha := Gen.hash_heights(a)
	var hb := Gen.hash_heights(b)
	if ha == hb and a.size() == 64 * 64:
		print("PASS gen_determinism seed=42 hash=%s" % ha)
	else:
		print("FAIL gen_determinism: %s != %s" % [ha, hb])
		quit(1)


func _test_seed_divergence() -> void:
	var a := Gen.heightmap(64, 42, 5)
	var b := Gen.heightmap(64, 43, 5)
	if Gen.hash_heights(a) != Gen.hash_heights(b):
		print("PASS gen_seed_divergence")
	else:
		print("FAIL gen_seed_divergence: seeds 42/43 produced identical maps")
		quit(1)


func _test_height_range() -> void:
	var world := Gen.bake(64, 7, 5, 2000, 2, 2.0)
	var h: PackedFloat32Array = world["heights"]
	var mn: float = world["stats"]["min_height"]
	var mx: float = world["stats"]["max_height"]
	# sane: finite, within [-20, 80] m for AMPLITUDE=55 with erosion
	var ok := is_finite(mn) and is_finite(mx) and mn >= -20.0 and mx <= 80.0 and mx > mn
	# and stats match a manual scan
	var smn := INF
	var smx := -INF
	for v in h:
		smn = minf(smn, v)
		smx = maxf(smx, v)
	ok = ok and absf(smn - mn) < 1e-4 and absf(smx - mx) < 1e-4
	if ok:
		print("PASS gen_height_range min=%.2f max=%.2f" % [mn, mx])
	else:
		print("FAIL gen_height_range min=%.3f max=%.3f" % [mn, mx])
		quit(1)


func _test_erosion_determinism() -> void:
	var a := Gen.bake(64, 99, 5, 3000, 2, 2.0)
	var b := Gen.bake(64, 99, 5, 3000, 2, 2.0)
	if a["stats"]["height_hash"] == b["stats"]["height_hash"]:
		print("PASS gen_erosion_determinism hash=%s" % a["stats"]["height_hash"])
	else:
		print("FAIL gen_erosion_determinism: %s != %s" % [
			a["stats"]["height_hash"], b["stats"]["height_hash"]])
		quit(1)
