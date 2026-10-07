## Deterministic RNG (mulberry32) — bit-exact port of boreal-src/src/sim/rng.ts.
## GDScript ints are 64-bit; JS ops are emulated: |0 -> i32(), >>> -> u32()>>n,
## Math.imul -> imul32 (product of two i32 fits in 64 bits, then mask).
class_name Rng

static func i32(v: int) -> int:
	var u := v & 0xFFFFFFFF
	return u - 4294967296 if u >= 2147483648 else u


static func u32(v: int) -> int:
	return v & 0xFFFFFFFF


static func imul32(a: int, b: int) -> int:
	return i32(i32(a) * i32(b))


## One mulberry32 stream; call next() for each roll.
class Stream extends RefCounted:
	var _a: int

	func _init(seed: int) -> void:
		_a = Rng.u32(seed)

	func next() -> float:
		var a := Rng.i32(_a)
		a = Rng.i32(a + 0x6D2B79F5)
		var t := Rng.imul32(a ^ (Rng.u32(a) >> 15), 1 | a)
		t = Rng.i32(t + Rng.imul32(t ^ (Rng.u32(t) >> 7), 61 | t)) ^ t
		_a = a
		return float(Rng.u32(t ^ (Rng.u32(t) >> 14))) / 4294967296.0


static func make_rng(seed: int) -> Stream:
	return Stream.new(seed)
