extends SceneTree
# Golden tests: mulberry32 RNG must be bit-exact vs the TS implementation.
# Goldens store IEEE-754 bit patterns (see goldens.gd header for why).

const Goldens = preload("res://tests/goldens.gd")

var fails := 0


func _init():
	_check_rng_streams()
	_check_roll_seeds()
	if fails == 0:
		print("PASS rng: mulberry32 bit-exact vs TS goldens")
		quit(0)
	else:
		print("FAIL rng: %d mismatches" % fails)
		quit(1)


func _check_rng_streams() -> void:
	for key in Goldens.RNG:
		var seed: int = int(key)
		var expected_bits: Array = Goldens.RNG[key]
		var expected_u32: Array = Goldens.RNG_U32[key]
		var s := Rng.make_rng(seed)
		for i in expected_bits.size():
			var got := s.next()
			if got != Goldens.f(expected_bits[i]):
				fails += 1
				print("  seed %d out[%d]: got bits %d want %d" % [seed, i, _bits(got), expected_bits[i]])
		# raw u32 path: next() == u/2^32 exactly, so *2^32 recovers u exactly
		var s2 := Rng.make_rng(seed)
		for i in expected_u32.size():
			var u := int(s2.next() * 4294967296.0)
			if u != expected_u32[i]:
				fails += 1
				print("  seed %d u32[%d]: got %d want %d" % [seed, i, u, expected_u32[i]])


func _check_roll_seeds() -> void:
	# roll(w) seed mix: (seed*0x9e3779b9) ^ (rngN*0x85ebca6b), seed=1
	for e in Goldens.ROLL_SEEDS:
		var got := Rng.make_rng(e.seed).next()
		if got != Goldens.f(e.v):
			fails += 1
			print("  roll seed %d: got bits %d want %d" % [e.seed, _bits(got), e.v])
	# and the mix itself, through WorldSim.roll()
	var w := WorldSim.new(1)
	for i in Goldens.ROLL_SEEDS.size():
		var got := w.roll()
		if got != Goldens.f(Goldens.ROLL_SEEDS[i].v):
			fails += 1
			print("  WorldSim.roll #%d: got bits %d want %d" % [i, _bits(got), Goldens.ROLL_SEEDS[i].v])


func _bits(f: float) -> int:
	var b := PackedFloat64Array([f]).to_byte_array()
	var v := 0
	for i in 8:
		v |= int(b[7 - i]) << (8 * (7 - i))
	if v >= (1 << 63):
		v -= (1 << 64)
	return v
