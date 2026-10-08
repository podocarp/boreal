extends SceneTree
# Camp placement tests (headless): the camp center found by grid-sampling the
# frozen Terrain.heightAt must be genuinely flat under its footprint, near the
# (frozen) CRASH site, and deterministic. Water ribbon rides the frozen
# channel-floor formula — checked here too (no new height math allowed).

var fails := 0


func _init():
	_camp_flat()
	_camp_near_crash()
	_camp_deterministic()
	_water_follows_stream()
	if fails == 0:
		print("PASS test_camp_water")
		quit(0)
	else:
		print("FAIL test_camp_water: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


func _camp_flat() -> void:
	var c := CampSite.find_center()
	var f := CampSite.flatness(c.x, c.z)
	if f >= 0.15:
		_fail("camp spot (%.1f, %.1f) not flat: max-min %.3f m >= 0.15 m" % [c.x, c.z, f])
	# CRASH itself should be worse (that's the whole point of moving the camp)
	var crash_f := CampSite.flatness(Terrain.CRASH.x, Terrain.CRASH.z)
	if f > crash_f:
		_fail("chosen spot flatter-check: %.3f > CRASH %.3f" % [f, crash_f])


func _camp_near_crash() -> void:
	var c := CampSite.find_center()
	var d := sqrt(pow(c.x - Terrain.CRASH.x, 2) + pow(c.z - Terrain.CRASH.z, 2))
	if d > CampSite.RADIUS + 0.001:
		_fail("camp center %.1f m from CRASH (max %.1f)" % [d, CampSite.RADIUS])
	if absf(c.y - Terrain.heightAt(c.x, c.z)) > 1e-6:
		_fail("camp center y not on heightAt")


func _camp_deterministic() -> void:
	var a := CampSite.find_center()
	var b := CampSite.find_center()
	if a != b:
		_fail("find_center not deterministic: %s vs %s" % [a, b])


func _water_follows_stream() -> void:
	var mesh := WaterRender.build_mesh()
	if mesh == null:
		_fail("water mesh null")
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(verts.size() > 100, "too few water verts (%d) — stream regressed?" % verts.size())
	# every vert sits within the channel band (streamX ± HALF_W, tapering to a
	# point where the channel ends) and on the frozen channel-floor formula
	var rows := 0
	for i in range(0, verts.size(), 2):
		var v := verts[i]
		var z := v.z
		var sx := Terrain.streamX(z)
		var half := absf(v.x - sx)
		if half > WaterRender.HALF_W + 1e-3:
			_fail("water vert x=%.2f off streamX=%.2f at z=%.1f" % [v.x, sx, z])
			break
		if absf(half - absf(verts[i + 1].x - sx)) > 1e-3:
			_fail("water row not symmetric at z=%.1f" % z)
			break
		var want := maxf(-1.5, Terrain._heightAtLakeApproach(z)) + 0.12
		if absf(v.y - want) > 1e-3:
			_fail("water vert y=%.3f != channel floor formula %.3f" % [v.y, want])
			break
		# the ribbon may only draw where the frozen channel exists: outside the
		# lake-flatten region (lakeT >= LAKE_T at the centerline) and strictly
		# below the bank (heightAt at streamX ± BANK_D) by BANK_MARGIN
		if half > 1e-6:
			rows += 1
			var lt := Terrain.lakeT(sx, z)
			if lt < WaterRender.LAKE_T - 1e-6:
				_fail("water drawn inside lake-flatten region at z=%.1f (lakeT=%.3f)" % [z, lt])
				break
			var bank := WaterRender.bank_y(z)
			if not v.y <= bank - WaterRender.BANK_MARGIN + 1e-9:
				_fail("water surface %.3f not below bank %.3f at z=%.1f" % [v.y, bank, z])
				break
	_check(rows > 20, "only %d full-width rows — stream no longer reads as a stream" % rows)
	# the camp must not sit under the ribbon: no drawn row within the camp
	# footprint (±FOOTPRINT of CampSite.find_center())
	var c := CampSite.find_center()
	for i in range(0, verts.size(), 2):
		var v := verts[i]
		if absf(v.x - c.x) <= WaterRender.HALF_W + CampSite.FOOTPRINT \
				and absf(v.z - c.z) <= CampSite.FOOTPRINT:
			_fail("water ribbon crosses camp footprint at (%.2f, %.2f)" % [v.x, v.z])
			break
	# water must sit below the banks: the channel is carved flat to ±5 m, the
	# bank rises from 6 m (heightAt at streamX ± 6 m is strictly higher)
	var z0 := -30.0
	var bank := Terrain.heightAt(Terrain.streamX(z0) + 6.0, z0)
	if not WaterRender.water_y(z0) < bank:
		_fail("water surface %.2f not below bank %.2f" % [WaterRender.water_y(z0), bank])
	# the lake-approach rows (where the camp sits) must be fully clipped
	if WaterRender.channel_taper(c.z) > 0.0:
		_fail("channel_taper at camp z=%.1f is %.3f, expected 0" % [c.z, WaterRender.channel_taper(c.z)])


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)
