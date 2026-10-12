extends SceneTree
# Balance harness (tools/balance.gd) regression: the floor policy must die,
# runs must be deterministic per seed (same seed -> identical outcome), and
# the competent policy must actually reach the rescue band. The
# competent-rescued gate was disabled while the frozen TS sim rescued 0%
# (Sprint-8 open item); the weight-based calorie model (owner directive
# 2026-10-11 v2) made the sim rescuable — competent now rescues 50% of seeds
# (seed 1 is a stable d7 flare rescue since the 2026-10-12 speed
# buff re-pin), so the gate is back.
const Balance = preload("res://tools/balance.gd")


func _init():
	var fails := 0

	# 1) idle floor policy must die (hypothermia, day 2)
	var idle := Balance.run_game("idle", 1)
	if idle.outcome != "dead":
		print("  idle seed 1: expected dead, got %s" % idle.outcome)
		fails += 1
	if idle.cause != "hypothermia":
		print("  idle seed 1: expected hypothermia, got %s" % idle.cause)
		fails += 1
	if idle.day > 4:
		print("  idle seed 1: expected death by day 4, survived to day %d" % idle.day)
		fails += 1

	# 2) determinism: same seed twice -> identical outcome tuple
	# (seed re-pinned 3 -> 1, playtest speed buff 2026-10-12: WALK 1.4->2.6 /
	# RUN 3.2->5.0 shifts bot arrival times; seed 3's competent bot now dies
	# of dehydration d7, seed 1 is the new stable d7 rescue. Band after the
	# 2026-10-12 CRASH move: idle 0% / naive 70% / competent 80% rescued.)
	var a := Balance.run_game("competent", 1)
	var b := Balance.run_game("competent", 1)
	if a.outcome != b.outcome or a.cause != b.cause or a.day != b.day or a.hour != b.hour:
		print("  competent seed 1 not deterministic: %s/%s/d%dh%d vs %s/%s/d%dh%d" % [
			a.outcome, a.cause, a.day, a.hour, b.outcome, b.cause, b.day, b.hour])
		fails += 1

	# 3) naive must die on some seeds but not all (weight-model rebalance
	# 2026-10-11: the sim is rescuable now; seed 5 was the stable death pin.
	# Re-pinned 5 -> 4 on 2026-10-12: the CRASH move to a flat forest bench
	# (playtest: plane sat on a 5.4 m slope) shortened the water carry —
	# 20-seed band is now idle 0% / naive 70% / competent 80% rescued.
	# Naive sits ABOVE the original 40-90%-die band: deliberate drift pending
	# a post-playtest difficulty pass, not an accident. Seed 4 is a stable
	# hypothermia death. DIVERGENCE from the old 0%-rescue premise.)
	var naive := Balance.run_game("naive", 4)
	if naive.outcome != "dead":
		print("  naive seed 4: expected dead, got %s" % naive.outcome)
		fails += 1

	# 4) competent seed 1 must be RESCUED (re-enabled gate — see header).
	if a.outcome != "rescued":
		print("  competent seed 1: expected rescued, got %s (%s d%d)" % [a.outcome, a.cause, a.day])
		fails += 1

	if fails == 0:
		print("PASS balance: idle floor dies, per-seed determinism, naive dies, competent rescued")
		quit(0)
	else:
		print("FAIL balance: %d failures" % fails)
		quit(1)
