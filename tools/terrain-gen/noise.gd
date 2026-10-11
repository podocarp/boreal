## Deterministic value noise / fBm for terrain-gen.
## Same hash pattern as games/boreal/src/sim/noise.gd (standalone copy so the
## tool does not depend on a game's vendor tree).
class_name TNoise

static func _i32(v: int) -> int:
	var u := v & 0xFFFFFFFF
	return u - 4294967296 if u >= 2147483648 else u


static func _u32(v: int) -> int:
	return v & 0xFFFFFFFF


static func _imul(a: int, b: int) -> int:
	return _i32(_i32(a) * _i32(b))


static func hash2(ix: int, iy: int, seed: int) -> float:
	var h := _i32(ix * 374761393 + iy * 668265263 + seed * 2147483647)
	h = _i32(h ^ (_u32(h) >> 13))
	h = _imul(h, 1274126177)
	h = _u32(h ^ (_u32(h) >> 16))
	return float(h) / 4294967296.0


static func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## 2D value noise in [0,1], lattice cell size = 1.
static func value2(x: float, y: float, seed: int) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := smooth(x - float(x0))
	var fy := smooth(y - float(y0))
	var n00 := hash2(x0, y0, seed)
	var n10 := hash2(x0 + 1, y0, seed)
	var n01 := hash2(x0, y0 + 1, seed)
	var n11 := hash2(x0 + 1, y0 + 1, seed)
	var nx0 := n00 + (n10 - n00) * fx
	var nx1 := n01 + (n11 - n01) * fx
	return nx0 + (nx1 - nx0) * fy


## Fractal Brownian motion in [0,1]. freq = base frequency (cycles per unit).
static func fbm2(x: float, y: float, seed: int, octaves := 4, freq := 1.0) -> float:
	var sum := 0.0
	var amp := 1.0
	var total := 0.0
	var f := freq
	for i in octaves:
		sum += value2(x * f, y * f, seed + i * 101) * amp
		total += amp
		amp *= 0.5
		f *= 2.0
	return sum / total


static func clampf(v: float, lo: float, hi: float) -> float:
	return minf(hi, maxf(lo, v))
