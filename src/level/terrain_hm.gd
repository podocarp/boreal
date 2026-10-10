## Heightmap adapter for baked terrain-gen worlds (levels/gen_001). Same query
## surface the render/game layer needs from Terrain (heightAt, zoneAt,
## speedMulAt) plus baked-only helpers (nearest water, biome cells, water
## distance field). Render uses bilinear interpolation on the height grid;
## gameplay uses nearest-cell. ADAPTER ONLY: the frozen sim is never modified
## — this is a duck-typed provider passed in from the level layer.
class_name TerrainHM

const WATER := 0
const GRASS := 1
const FOREST := 2
const ROCK := 3

var size := 0
var cell := 2.0
var water_level := 12.0
var heights := PackedFloat32Array()
var biomes := PackedInt32Array()
var spawn := {}
var meta := {}
var _water_dist := PackedInt32Array()  # cells to nearest water cell (-1 = none)


## Load a baked dir (must end with '/'): heights/biomes/meta/spawn JSONs.
static func load_baked(dir: String) -> TerrainHM:
	var hm := TerrainHM.new()
	hm.meta = _read_json(dir + "terrain_meta.json")
	hm.size = int(hm.meta["size"])
	hm.cell = float(hm.meta["cell_size_m"])
	hm.water_level = float(hm.meta["water_level"])
	var hs: Array = _read_json(dir + "terrain_heights.json")
	hm.heights = PackedFloat32Array()
	hm.heights.resize(hs.size())
	for i in hs.size():
		hm.heights[i] = float(hs[i])
	var bs: Array = _read_json(dir + "terrain_biomes.json")
	hm.biomes = PackedInt32Array()
	hm.biomes.resize(bs.size())
	for i in bs.size():
		hm.biomes[i] = int(bs[i])
	hm.spawn = _read_json(dir + "spawn.json")["spawn"]
	hm._build_water_dist()
	return hm


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "cannot open " + path)
	return JSON.parse_string(f.get_as_text())


## Bilinear sample (render path). Exact at cell centers (weights 0/1).
func heightAt(x: float, z: float) -> float:
	var gx := clampf(x / cell, 0.0, float(size - 1))
	var gz := clampf(z / cell, 0.0, float(size - 1))
	var x0 := int(floorf(gx))
	var z0 := int(floorf(gz))
	var x1 := mini(x0 + 1, size - 1)
	var z1 := mini(z0 + 1, size - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var h00 := heights[z0 * size + x0]
	var h10 := heights[z0 * size + x1]
	var h01 := heights[z1 * size + x0]
	var h11 := heights[z1 * size + x1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Nearest-cell sample (gameplay path): returns the baked grid value exactly.
func heightAtCell(x: float, z: float) -> float:
	return heights[_cell_index(x, z)]


func biome_at(x: float, z: float) -> int:
	return biomes[_cell_index(x, z)]


func _cell_index(x: float, z: float) -> int:
	var cx := clampi(int(round(x / cell)), 0, size - 1)
	var cy := clampi(int(round(z / cell)), 0, size - 1)
	return cy * size + cx


## Biome -> frozen-sim zone string (speed/shelter tables stay compatible).
func zoneAt(x: float, z: float) -> String:
	match biomes[_cell_index(x, z)]:
		WATER:
			return "lake"
		ROCK:
			return "ridge"
		_:
			return "forest"


## Same table as Terrain.speedMulAt (adapter surface, not a sim change).
func speedMulAt(zone: String) -> float:
	match zone:
		"bog":
			return 0.55
		"ridge":
			return 0.85
		"stream":
			return 0.7
		_:
			return 1.0


## World (x, z) of the nearest water cell (walks the BFS field downhill).
func nearest_water(x: float, z: float) -> Vector2:
	var cx := clampi(int(round(x / cell)), 0, size - 1)
	var cy := clampi(int(round(z / cell)), 0, size - 1)
	if _water_dist[cy * size + cx] < 0:
		return Vector2(x, z)  # no water on the map at all
	var guard := 0
	while _water_dist[cy * size + cx] > 0 and guard < 2 * size:
		var d := _water_dist[cy * size + cx]
		for n in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + n[0]
			var ny: int = cy + n[1]
			if nx >= 0 and ny >= 0 and nx < size and ny < size \
					and _water_dist[ny * size + nx] == d - 1:
				cx = nx
				cy = ny
				break
		guard += 1
	return Vector2(float(cx) * cell, float(cy) * cell)


## Channel/stream info derived from biome cells (adapter surface).
func stream_info(x: float, z: float) -> Dictionary:
	var d_cells := _water_dist[_cell_index(x, z)]
	return {
		"dist_m": float(d_cells) * cell if d_cells >= 0 else INF,
		"water": nearest_water(x, z),
		"edge": d_cells >= 0 and d_cells <= 1,
	}


## Multi-source BFS from all water cells (4-neighborhood distance field).
func _build_water_dist() -> void:
	_water_dist = PackedInt32Array()
	_water_dist.resize(size * size)
	_water_dist.fill(-1)
	var q: Array[int] = []
	for i in size * size:
		if biomes[i] == WATER:
			_water_dist[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % size
		var y := i / size
		var d := _water_dist[i]
		for n in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = x + n[0]
			var ny: int = y + n[1]
			var j := ny * size + nx
			if nx >= 0 and ny >= 0 and nx < size and ny < size \
					and _water_dist[j] < 0:
				_water_dist[j] = d + 1
				q.append(j)
