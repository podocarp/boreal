## Biome classifier tests: coverage, purity, elevation rule.
extends SceneTree


func _init() -> void:
	_test_coverage()
	_test_pure_stability()
	_test_snow_elevation()
	_test_water_rule()
	quit(0)


func _test_coverage() -> void:
	var world := Gen.bake(64, 5, 5, 2000, 2, 2.0)
	var cov := Biome.coverage(world["biomes"])
	var sum := 0.0
	var ok: bool = cov["fractions"].size() == 5
	for k in cov["fractions"]:
		var f: float = cov["fractions"][k]
		ok = ok and f >= 0.0 and f <= 1.0
		sum += f
	ok = ok and absf(sum - 1.0) < 1e-5
	if ok:
		print("PASS biome_coverage sum=%.6f" % sum)
	else:
		print("FAIL biome_coverage sum=%f fractions=%s" % [sum, cov["fractions"]])
		quit(1)


func _test_pure_stability() -> void:
	# same inputs -> same output, 100x
	var first := Biome.biome(20.0, 0.3, 0.7, 12.0)
	var stable := true
	for i in 100:
		stable = stable and Biome.biome(20.0, 0.3, 0.7, 12.0) == first
	# and moisture map is deterministic
	var m1 := Biome.moisture_map(32, 11)
	var m2 := Biome.moisture_map(32, 11)
	for i in m1.size():
		stable = stable and m1[i] == m2[i]
	if stable:
		print("PASS biome_pure_stability")
	else:
		print("FAIL biome_pure_stability")
		quit(1)


func _test_snow_elevation() -> void:
	# snow ONLY at/above SNOW_LINE, across a baked map and synthetic probes
	var world := Gen.bake(64, 5, 5, 2000, 2, 2.0)
	var h: PackedFloat32Array = world["heights"]
	var b: PackedInt32Array = world["biomes"]
	var ok := true
	for i in h.size():
		if b[i] == Biome.SNOW and h[i] < Biome.SNOW_LINE:
			ok = false
	# synthetic: low + steep + wet must never be snow
	for probe in [[0.0, 0.0, 0.0], [11.9, 5.0, 1.0], [33.9, 0.0, 1.0]]:
		if Biome.biome(probe[0], probe[1], probe[2], 12.0) == Biome.SNOW:
			ok = false
	# high must be snow
	if Biome.biome(40.0, 0.0, 0.0, 12.0) != Biome.SNOW:
		ok = false
	if ok:
		print("PASS biome_snow_elevation")
	else:
		print("FAIL biome_snow_elevation")
		quit(1)


func _test_water_rule() -> void:
	var ok := Biome.biome(11.99, 0.0, 0.0, 12.0) == Biome.WATER \
			and Biome.biome(12.01, 0.0, 0.0, 12.0) != Biome.WATER
	if ok:
		print("PASS biome_water_rule")
	else:
		print("FAIL biome_water_rule")
		quit(1)
