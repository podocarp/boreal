extends SceneTree
# Balance harness (tools/balance.gd) regression: the floor policy must die,
# and runs must be deterministic per seed (same seed -> identical outcome).
# NOTE: the competent-rescued gate is NOT asserted here — the frozen TS sim
# itself rescues 0% (Sprint-8 open item in boreal-src AGENTS.md: "harness bot
# policies regressed after the crash-site move... needs re-tuning toward the
# rescue band"). See docs/balance-report.md.
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
	var a := Balance.run_game("competent", 3)
	var b := Balance.run_game("competent", 3)
	if a.outcome != b.outcome or a.cause != b.cause or a.day != b.day or a.hour != b.hour:
		print("  competent seed 3 not deterministic: %s/%s/d%dh%d vs %s/%s/d%dh%d" % [
			a.outcome, a.cause, a.day, a.hour, b.outcome, b.cause, b.day, b.hour])
		fails += 1

	# 3) naive must not be rescued either (no signal policy in a 0%-rescue sim)
	var naive := Balance.run_game("naive", 2)
	if naive.outcome != "dead":
		print("  naive seed 2: expected dead, got %s" % naive.outcome)
		fails += 1

	if fails == 0:
		print("PASS balance: idle floor dies, per-seed determinism, naive dies")
		quit(0)
	else:
		print("FAIL balance: %d failures" % fails)
		quit(1)
