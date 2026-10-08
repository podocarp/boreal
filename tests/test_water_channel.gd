extends SceneTree
# Water ribbon channel-constraint tests (headless): every drawn vertex must
# lie inside the frozen channel band (streamX ± HALF_W), outside the
# lake-flatten region (lakeT >= LAKE_T at the centerline — inside it the
# frozen heightAt mixes the ground down to lake ice, so the channel-floor
# formula no longer describes the terrain and the ribbon would float as a
# translucent sheet over the shelf), and below the bank (heightAt at
# streamX ± BANK_D) by BANK_MARGIN. The relocated camp must be clear of the
# ribbon. All checks sample the frozen Terrain functions — no new height math.

var fails := 0


func _init():
	_verts_in_channel_band()
	_verts_below_bank()
	_no_water_in_lake_flatten_region()
	_camp_clear_of_ribbon()
	_taper_endpoints()
	if fails == 0:
		print("PASS test_water_channel")
		quit(0)
	else:
		print("FAIL test_water_channel: %d failures" % fails)
		quit(1)


func _fail(msg: String) -> void:
	fails += 1
	print("  " + msg)


func _rows() -> Array:
	var mesh := WaterRender.build_mesh()
	if mesh == null:
		_fail("water mesh null")
		return []
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var out := []
	for i in range(0, verts.size(), 2):
		out.append([verts[i], verts[i + 1]])
	return out


## Full-width rows only (tapered tip rows have half < HALF_W by design).
func _full_rows(rows: Array) -> Array:
	var out := []
	for r in rows:
		var v: Vector3 = r[0]
		if absf(absf(v.x - Terrain.streamX(v.z)) - WaterRender.HALF_W) < 1e-3:
			out.append(r)
	return out


func _verts_in_channel_band() -> void:
	var rows := _rows()
	if rows.is_empty():
		return
	_check(rows.size() > 20, "too few water rows (%d) — stream regressed?" % rows.size())
	for r in rows:
		var v: Vector3 = r[0]
		var w: Vector3 = r[1]
		var sx := Terrain.streamX(v.z)
		if absf(v.x - sx) > WaterRender.HALF_W + 1e-3:
			_fail("vert x=%.2f outside channel band (streamX=%.2f ± %.1f) at z=%.1f"
				% [v.x, sx, WaterRender.HALF_W, v.z])
		if absf(w.x - sx) > WaterRender.HALF_W + 1e-3:
			_fail("vert x=%.2f outside channel band at z=%.1f" % [w.x, v.z])
		if absf(absf(v.x - sx) - absf(w.x - sx)) > 1e-3:
			_fail("row not symmetric about streamX at z=%.1f" % v.z)


func _verts_below_bank() -> void:
	for r in _rows():
		var v: Vector3 = r[0]
		if absf(v.x - Terrain.streamX(v.z)) < 1e-6:
			continue  # zero-width tip vertex
		var bank := WaterRender.bank_y(v.z)
		if v.y > bank - WaterRender.BANK_MARGIN + 1e-9:
			_fail("water y=%.3f not below bank y=%.3f - margin at z=%.1f" % [v.y, bank, v.z])


func _no_water_in_lake_flatten_region() -> void:
	for r in _rows():
		var v: Vector3 = r[0]
		if absf(v.x - Terrain.streamX(v.z)) < 1e-6:
			continue  # zero-width tip vertex
		var lt := Terrain.lakeT(Terrain.streamX(v.z), v.z)
		if lt < WaterRender.LAKE_T - 1e-6:
			_fail("water drawn inside lake-flatten region at z=%.1f (lakeT=%.3f < %.2f)"
				% [v.z, lt, WaterRender.LAKE_T])


func _camp_clear_of_ribbon() -> void:
	var c := CampSite.find_center()
	for r in _rows():
		var v: Vector3 = r[0]
		var w: Vector3 = r[1]
		var lo := minf(v.x, w.x) - 1e-3
		var hi := maxf(v.x, w.x) + 1e-3
		if hi >= c.x - CampSite.FOOTPRINT and lo <= c.x + CampSite.FOOTPRINT \
				and absf(v.z - c.z) <= CampSite.FOOTPRINT:
			_fail("water ribbon crosses camp footprint at z=%.1f (x %.2f..%.2f, camp x=%.2f)"
				% [v.z, lo, hi, c.x])
	if WaterRender.channel_taper(c.z) > 0.0:
		_fail("channel_taper at camp z=%.1f is %.3f, expected 0" % [c.z, WaterRender.channel_taper(c.z)])


## The ribbon must terminate cleanly: taper hits 0 at the lake end AND at the
## far (bog/edge) end where the bank drops to the water level — no open sheet.
func _taper_endpoints() -> void:
	if WaterRender.channel_taper(-60.0) > 0.0:
		_fail("taper at lake-approach z=-60 is %.3f, expected 0" % WaterRender.channel_taper(-60.0))
	if WaterRender.channel_taper(138.0) > 0.0:
		_fail("taper at map-edge z=138 is %.3f, expected 0" % WaterRender.channel_taper(138.0))
	if WaterRender.channel_taper(-30.0) < 0.999:
		_fail("taper mid-stream z=-30 is %.3f, expected 1 (stream regressed?)"
			% WaterRender.channel_taper(-30.0))
	# stream must still span a long stretch (waves/fresnel/foam stay visible)
	var z := -150.0
	var span_lo := INF
	var span_hi := -INF
	while z <= 138.001:
		if WaterRender.channel_taper(z) > 0.999:
			span_lo = minf(span_lo, z)
			span_hi = maxf(span_hi, z)
		z += 3.0
	if span_hi - span_lo < 100.0:
		_fail("full-width stream span only %.1f m (< 100)" % (span_hi - span_lo))


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)
