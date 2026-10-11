## terrain-gen CLI: bake a seeded world and write baked artifacts.
## Usage:
##   godot --headless --path tools/terrain-gen --script res://terrain_gen.gd -- \
##     --seed 1337 [--size 256] [--octaves 5] [--particles 12000] [--thermal 3] \
##     [--cell 2.0] [--out baked/] [--no-mesh]
## Outputs into --out dir: terrain_heights.json, terrain_meta.json,
## terrain_biomes.json, spawn.json, terrain_mesh.tres, terrain_collision.tres.
extends SceneTree

var _timings := {}


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var seed_v := int(args.get("seed", 1337))
	var size := int(args.get("size", 256))
	var octaves := int(args.get("octaves", 5))
	var particles := int(args.get("particles", 12000))
	var thermal := int(args.get("thermal", 3))
	var cell := float(args.get("cell", 2.0))
	var out_dir := _abs(String(args.get("out", "baked/")))
	print("terrain-gen: seed=%d size=%d octaves=%d particles=%d thermal=%d cell=%.1f out=%s" % [
		seed_v, size, octaves, particles, thermal, cell, out_dir])

	var t0 := Time.get_ticks_msec()
	var world := Gen.bake(size, seed_v, octaves, particles, thermal, cell)
	world["size"] = size
	var t_bake := Time.get_ticks_msec() - t0

	t0 = Time.get_ticks_msec()
	var spawn := SpawnSelect.select(world)
	var t_spawn := Time.get_ticks_msec() - t0

	t0 = Time.get_ticks_msec()
	var mesh_files := {}
	if not bool(args.get("no-mesh", false)):
		var mesh := MeshOut.build_mesh(world["heights"], world["biomes"], size, cell)
		var shape := MeshOut.build_collision(world["heights"], size, cell)
		mesh_files = MeshOut.save(mesh, shape, out_dir)
	var t_mesh := Time.get_ticks_msec() - t0

	t0 = Time.get_ticks_msec()
	_write(out_dir, "terrain_heights.json", JSON.stringify(Array(world["heights"])))
	_write(out_dir, "terrain_biomes.json", JSON.stringify(Array(world["biomes"])))
	var meta: Dictionary = world["stats"]
	meta["cell_size_m"] = cell
	meta["octaves"] = octaves
	meta["hydraulic_particles"] = particles
	meta["thermal_passes"] = thermal
	_write(out_dir, "terrain_meta.json", JSON.stringify(meta, "\t"))
	_write(out_dir, "spawn.json", JSON.stringify(spawn, "\t"))
	var t_write := Time.get_ticks_msec() - t0

	print("bake: %.0f ms | spawn: %.0f ms | mesh: %.0f ms | write: %.0f ms" % [
		t_bake, t_spawn, t_mesh, t_write])
	print("meta: " + JSON.stringify(meta))
	print("spawn: " + JSON.stringify(spawn))
	if not mesh_files.is_empty():
		print("mesh: " + JSON.stringify(mesh_files))
	# cost guard (docs/terrain-gen-design.md §5): fail loudly rather than hang CI
	var total_ms := t_bake + t_spawn + t_mesh + t_write
	if total_ms > 120000:
		print("BAKE FAIL: %.0f ms exceeds 120 s cost guard" % total_ms)
		quit(1)
	print("BAKE OK " + out_dir)
	quit(0)


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var key := a.trim_prefix("--")
			if key == "no-mesh":
				out[key] = true
			elif i + 1 < argv.size():
				i += 1
				out[key] = argv[i]
		i += 1
	return out


func _abs(p: String) -> String:
	if p.begins_with("/"):
		return p
	return ProjectSettings.globalize_path("res://").path_join(p)


func _write(dir: String, name: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(content)
	f.close()
