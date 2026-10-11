extends SceneTree
## Monte-Carlo balance harness — GDScript port of boreal-src tests/sim/balance.ts
## (S8 tooling — no gameplay code). Runs full headless games (pure sim, no
## render) for scripted bot policies over N seeds and reports outcome
## distributions so Config.gd tuning can target a difficulty band.
##
## Usage (from repo root):
##   godot --headless --path games/boreal --script res://tools/balance.gd -- [seedsPerPolicy]
## Default 20 seeds/policy. Deterministic per seed (world roll() stream +
## per-bot xorshift-ish stream; no wall-clock, no randf()).
##
## Policies (card t_815d7713): idle (do-nothing floor), naive (loots, fire at
## the exposed wreck site, no shelter/food/signal), competent (TS 'optimal':
## scouted forest camp, fire loop, shelter, snares, fishing, wound care,
## signal smoke + open shore before day 7). Wolves are cut from the MVP
## (owner directive 2026-10-10), so the TS wolf-repel line is not ported and
## naive death rates sit below the TS band (TS naive deaths were mostly
## wolves).

const DT := Config.SIM_DT


# ---------------------------------------------------------------------------
# bot helpers
# ---------------------------------------------------------------------------

## Walk-toward helper with real stuck recovery: if the player stops
## progressing (collider), commit to a perpendicular strafe for a fixed number
## of ticks (sign chosen once — per-tick random flips just oscillate), then
## resume. One instance per bot; state resets on arrival. Port of Mover.
class Mover:
	var did_move := false
	var tx := INF
	var tz := INF
	var best_d := INF
	var stuck := 0
	var since_arrival := 0
	var strafe_ticks := 0
	var strafe_dir := 1

	func move(w: WorldSim, x: float, z: float, rng: Callable) -> bool:
		if x != tx or z != tz:
			tx = x
			tz = z
			best_d = INF  # new target -> fresh progress baseline
		var dx: float = x - w.player.x
		var dz: float = z - w.player.z
		var d := sqrt(dx * dx + dz * dz)
		if d < 2.5:
			# clear stale p.moving (only update_player resets it; tick_work
			# cancels tasks and sleep refuses while moving=true)
			PlayerSim.update_player(w, {"fwd": 0, "strafe": 0, "run": false, "camYaw": 0}, Config.SIM_DT)
			did_move = false
			reset()
			return true
		# progress-based stuck detection: sliding along a collider counts as
		# stuck (we move but never close the distance)
		if d < best_d - 0.15:
			best_d = d
			stuck = 0
		else:
			stuck += 1
			if d < best_d:
				best_d = d
		if stuck > 3 and strafe_ticks == 0:
			strafe_dir = 1 if rng.call() < 0.5 else -1
			strafe_ticks = 25  # ~commit to sidestepping the prop
		since_arrival += 1  # resets only on arrival; ping-pong retargeting must not reset it
		if since_arrival > 1500 or stuck > 40:
			# harness-only: bots are policy stand-ins, not pathfinding tests.
			# Skip the prop.
			w.player.x = x
			w.player.z = z
			PlayerSim.update_player(w, {"fwd": 0, "strafe": 0, "run": false, "camYaw": 0}, Config.SIM_DT)
			did_move = false
			reset()
			return true
		var cam_yaw := atan2(-dx / d, -dz / d)
		did_move = true
		if strafe_ticks > 0:
			strafe_ticks -= 1
			PlayerSim.update_player(w, {"fwd": 0.35, "strafe": strafe_dir, "run": false, "camYaw": cam_yaw}, Config.SIM_DT)
			return false
		PlayerSim.update_player(w, {"fwd": 1, "strafe": 0, "run": false, "camYaw": cam_yaw}, Config.SIM_DT)
		return false

	func reset() -> void:
		best_d = INF
		stuck = 0
		strafe_ticks = 0
		since_arrival = 0


# ---------------------------------------------------------------------------
# policies
# ---------------------------------------------------------------------------

## shared "camp" routine: fire upkeep, water, eat, sleep. Port of BaseBot.
class BaseBot:
	var mover := Mover.new()
	var phase := "?"
	var rng: Callable
	var camp_x: float
	var camp_z: float
	var fire_built := false
	var camped := false
	var urgent_wood := false
	# Rebalance 2026-10-11 (calorie-model card): friction-light RETRY COOLDOWN.
	# A real player strikes the drill once every couple of minutes, not 40×
	# per second: the old bot burned its entire tinder reserve on failed
	# rolls (dexterity collapses in the cold → p ≈ 0.05) and froze beside a
	# pack of bundles it had already spent. Ticks are harness ticks (0.25 s).
	var light_cooldown := 0

	# helpers live here as statics (nested classes can't see script-level
	# functions; subclasses inherit these)
	static func dist(x1: float, z1: float, x2: float, z2: float) -> float:
		return sqrt((x1 - x2) * (x1 - x2) + (z1 - z2) * (z1 - z2))

	static func nearest_kind(w: WorldSim, kinds: Array, center := Vector3.INF, radius := INF) -> Variant:
		var best: Variant = null
		var bd := INF
		for it in w.interactables:
			if it.uses <= 0 or not (it.kind in kinds):
				continue
			if center != Vector3.INF and dist(it.x, it.z, center.x, center.z) > radius:
				continue
			var d := dist(it.x, it.z, w.player.x, w.player.z)
			if d < bd:
				bd = d
				best = it
		return best

	static func craft_first(w: WorldSim, id: String) -> bool:
		var r: Variant = CraftSim.recipe_by_id(id)
		return r != null and CraftSim.can_craft(w.inventory, r) and CraftSim.craft(w.inventory, r)

	static func is_night(h: float) -> bool:
		return h < 9.0 or h > 17.0

	# per-bot xorshift-ish deterministic stream (matches TS:
	# seed = (seed*1103515245 + 12345) & 0x7fffffff). A method, not a lambda:
	# GDScript lambdas capture locals BY VALUE, so a closure counter would
	# never advance (TS closures capture the mutable variable).
	var _rng_state: int

	func bot_rng() -> float:
		# JS semantics: `seed * 1103515245 + 12345` is float64 math (products
		# > 2^53 lose low bits) and `& 0x7fffffff` is ToInt32-then-mask.
		# GDScript int64 is exact, so round through float to match the TS
		# harness's per-bot stream bit-for-bit.
		var prod := float(_rng_state) * 1103515245.0 + 12345.0
		_rng_state = int(prod) & 0x7FFFFFFF
		return float(_rng_state) / float(0x7FFFFFFF)

	func _init(seed_: int, camp_x_: float, camp_z_: float) -> void:
		_rng_state = seed_
		rng = bot_rng
		camp_x = camp_x_
		camp_z = camp_z_

	## Scout a camp: near water (scarce), in forest (wind), with fuel within
	## reach — what a competent player does after looting the wreck.
	func scout_camp(w: WorldSim) -> void:
		var score_at := func(x: float, z: float) -> float:
			var zone := Terrain.zoneAt(x, z)
			var s := 2.0 if zone == "forest" else (0.5 if zone == "bog" else 0.0)
			for k in ["deadfall", "bark", "boughs", "berries"]:
				for o in w.interactables:
					if o.kind == k and o.uses > 0 and dist(o.x, o.z, x, z) < 30.0:
						s += 1.0
						break
			for h in w.fishHoles:
				if h.usesLeft > 0 and dist(h.x, h.z, x, z) < 30.0:
					s += 1.0
					break
			for o in w.interactables:
				if o.kind == "water" and o.uses > 0 and dist(o.x, o.z, x, z) < 30.0:
					s += 1.0
					break
			s -= dist(x, z, Terrain.CRASH.x, Terrain.CRASH.z) / 25.0  # strong: camp IS the crash area
			return s
		var bx: float = Terrain.CRASH.x
		var bz: float = Terrain.CRASH.z + 20.0
		var best_score: float = score_at.call(bx, bz)
		var x: float = Terrain.CRASH.x - 45.0
		while x <= Terrain.CRASH.x + 45.0:
			var z: float = Terrain.CRASH.z - 10.0
			while z <= Terrain.CRASH.z + 55.0:
				var s2: float = score_at.call(x, z)
				if s2 > best_score:
					bx = x
					bz = z
					best_score = s2
				z += 5.0
			x += 5.0
		camp_x = roundf(bx)
		camp_z = roundf(bz)
		camped = true

	func gather(w: WorldSim, kinds: Array, want: int) -> void:
		# if the pack can't take even one of what we're fetching, dump bulk
		# wood first (a full pack of deadfall must never deadlock the tinder chain)
		var all_blocked := true
		for k in kinds:
			if Items.inv_can_add(w.inventory, k, 1):
				all_blocked = false
				break
		if all_blocked:
			if int(w.inventory.get("deadfall", 0)) > 0:
				Items.inv_remove(w.inventory, "deadfall", 1)
				phase = "dump-wood"
				return
		var t: Variant = nearest_kind(w, kinds)
		if t == null:
			phase = "idle(no-target:" + ",".join(kinds) + ")"
			idle(w)
			return
		# Rebalance 2026-10-11: home range. A real survivor works within a
		# short haul of camp — a 70 m round trip in -18 °C for one bundle of
		# bark is how the old runs froze mid-errand. Prefer targets within
		# 60 m of camp; otherwise the nearest one, but only in daylight
		# (night errands are the #1 freeze-mid-walk death). EXCEPTION
		# (calorie-model card): urgent_wood — a fire that is OUT at night is
		# the one errand a real player makes in the dark; without this the
		# bot stripped its home range by day 4 and deadlocked in build-fire
		# with an empty tinder chain, freezing beside a pack of bark.
		var t2: Variant = nearest_kind(w, kinds, Vector3(camp_x, 0, camp_z), 60.0)
		if t2 == null:
			t2 = nearest_kind(w, kinds)
			if t2 != null and is_night(w.hourOfDay) and not urgent_wood \
					and dist(t2.x, t2.z, w.player.x, w.player.z) > 60.0:
				t2 = null
		if t2 == null:
			phase = "idle(far:" + ",".join(kinds) + ")"
			idle(w)
			return
		t = t2
		phase = "gather:" + t.kind
		if not mover.move(w, t.x, t.z, rng):
			return
		# start the task on THIS target — begin_work picks the nearest
		# interactable (or the snow fallback), so an exhausted prop mid-walk
		# turned gathering into an endless snow-scoop loop
		if w.task == null:
			w.task = Interact.start_task(t)

	func idle(w: WorldSim) -> void:
		# mill about camp slightly so "moving" debuff logic behaves
		phase = "idle"
		mover.move(w, camp_x + 1, camp_z + 1, rng)

	func camp_fire(w: WorldSim) -> void:
		# Rebalance 2026-10-11 (calorie-model card): a work task means STAND —
		# tick_work cancels any task the moment the player moves. The old loop
		# kept issuing fetch-fuel/gather movement while a thirst task ran, so
		# the task was cancelled and restarted every tick (emergency-snow
		# deadlock: bot scooped snow for 10 h, never drank, died of thirst
		# next to a lit fire).
		if w.task != null:
			phase = "stand(work)"
			PlayerSim.update_player(w, {"fwd": 0, "strafe": 0, "run": false, "camYaw": 0}, Config.SIM_DT)
			return
		# Thirst overrides ALL logistics: snow is everywhere, scoop at the
		# feet immediately.
		if w.needs.hydration < 30.0 \
				and not Items.inv_has(w.inventory, "snow", 1) \
				and not Items.inv_has(w.inventory, "waterClean", 1) \
				and not Items.inv_has(w.inventory, "waterRaw", 1) \
				and w.task == null:
			phase = "emergency-snow"
			# Rebalance 2026-10-11 (calorie-model card): start the snow task
			# DIRECTLY — begin_work picks the nearest prop within reach (or
			# fails on "no container"), and a prop whose yield doesn't fit
			# the pack completes with no yield, forever: the old bot re-scooped
			# the same bark prop for 10 h and died of thirst next to a fire.
			w.task = Interact.start_task({"id": -1, "kind": "snow",
				"x": w.player.x, "z": w.player.z, "uses": 99})
			# a foot task means STAND
			PlayerSim.update_player(w, {"fwd": 0, "strafe": 0, "run": false, "camYaw": 0}, Config.SIM_DT)
			return

		# Fire-first loop, ordered like a competent player: light what you can
		# carry NOW, then bulk fuel only once a fire burns.
		var camp_fire_obj: Variant = null
		for f in w.fires:
			if dist(f.x, f.z, camp_x, camp_z) < 6.0:
				if camp_fire_obj == null or f.fuel > camp_fire_obj.fuel:
					camp_fire_obj = f
		var lit: Variant = camp_fire_obj if (camp_fire_obj != null and camp_fire_obj.lit and camp_fire_obj.fuel > 0.0) else null
		if fire_built and (lit == null or lit.fuel < 20.0):
			fire_built = false

		var df: int = int(w.inventory.get("deadfall", 0))
		var kd: int = int(w.inventory.get("kindling", 0))
		var bk: int = int(w.inventory.get("bark", 0))
		var at_camp := dist(w.player.x, w.player.z, camp_x, camp_z) <= 3.0
		# Night rule: no chore trips after dark. A real player huddles by the
		# fire — wandering at −18 °C is the #1 harness death.
		var night := is_night(w.hourOfDay)

		if not fire_built:
			# Rebalance 2026-10-11: no fire at camp after dark is an emergency —
			# a real player gathers tinder chain even at night when the fire is
			# out (the old night-gate deadlocked the bot: build-fire needs a
			# bundle, crafting needs bark, bark-gather was night-gated).
			if night and lit == null:
				urgent_wood = true
			# Bulk-stock the tinder chain BEFORE crafting: a failed friction
			# light consumes the bundle, so retries must be craft-only.
			# Rebalance 2026-10-11 (calorie-model card): the reachability
			# pre-check is gone — gather() owns the night/home-range policy
			# (urgent_wood allows the dark errand; otherwise it falls back to
			# idle). The old pre-check deadlocked the bot in build-fire with
			# an empty chain once the home range was stripped.
			if (not night or urgent_wood) and df < 4 and Items.inv_can_add(w.inventory, "deadfall", 2):
				phase = "stock-deadfall"
				gather(w, ["deadfall"], 4)
				return
			if (not night or urgent_wood) and bk < 2 and Items.inv_can_add(w.inventory, "bark", 2):
				phase = "stock-bark"
				gather(w, ["bark"], 2)
				return
			if not at_camp:
				phase = "to-camp"
				mover.move(w, camp_x, camp_z, rng)
				return
			phase = "build-fire"
			if not Items.inv_has(w.inventory, "tinderBundle", 1):
				if kd < 2:
					craft_first(w, "kindling")
				craft_first(w, "tinderBundle")
			# Rebalance 2026-10-11 (calorie-model card): friction-light retry
			# cooldown — one strike every ~2 real minutes, not 40/s. The old bot
			# burned every bundle it owned on failed rolls (cold hands → p≈0.05)
			# and froze beside a pack of deadfall with no tinder left.
			if light_cooldown > 0:
				light_cooldown -= 1
				return
			var lit_res := Actions.light_fire(w, Needs.compute_debuffs(w.needs).dexterity)
			fire_built = lit_res == "lit"
			if lit_res == "failed":
				light_cooldown = 40  # ~1 game-hour between strikes (10 s real)
			if fire_built and Items.inv_has(w.inventory, "deadfall", 1):
				Actions.feed_fire(w)
			return

		# fire is lit: keep it fed (bulk fetch only with pack room), then camp chores
		var fire_critical: bool = lit == null or lit.fuel < 15.0
		# night fetches are allowed ONLY for a dying fire
		# Rebalance 2026-10-11: fetch threshold 50 -> 70. The burn cascade
		# (10/18/30 %/h by stage) empties a fuel-50 fire in ~2.5 h — a real
		# player keeps the fire in the big-flame stage through the evening,
		# not stoking embers at 21:00.
		if (not night or fire_critical) and (lit == null or lit.fuel < 70.0) and df < 6 and Items.inv_can_add(w.inventory, "deadfall", 2):
			phase = "fetch-fuel"
			if night:
				urgent_wood = true
			gather(w, ["deadfall"], 6)
			return
		# Rebalance 2026-10-11: tinder RESERVE. A competent player NEVER lets
		# the tinder chain run dry — friction lights fail, bark is scarce, and
		# a night with wood but no bundle is a hypothermia death (the old bot
		# burned bark on snares/shelter, then froze beside a pack of deadfall
		# it could not light). Daylight chore, ranked BELOW fetch-fuel.
		if not night:
			var has_bundle := Items.inv_has(w.inventory, "tinderBundle", 1)
			if not has_bundle:
				if int(w.inventory.get("kindling", 0)) >= 2 and bk >= 1:
					craft_first(w, "tinderBundle")
				elif bk < 1 or kd < 2:
					phase = "reserve-tinder"
					gather(w, ["bark", "deadfall"], 2)
					return
			if kd < 2 and df >= 2:
				craft_first(w, "kindling")

		if night and not at_camp and not urgent_wood:
			phase = "to-camp"
			mover.move(w, camp_x, camp_z, rng)
			return  # night: camp only
		if urgent_wood and df >= 2:
			urgent_wood = false  # got wood, head home
		if not at_camp:
			phase = "to-camp"
			mover.move(w, camp_x, camp_z, rng)
			return
		phase = "camp-fire"
		# evening reserve: after 15:00 feed only to ~70 and keep deadfall in
		# the pack for the night watch (stuffing the fire at bedtime = midnight death)
		var feed_cap := 70.0 if (is_night(w.hourOfDay) or w.hourOfDay > 15.0) else 90.0
		if Items.inv_has(w.inventory, "deadfall", 1) and lit != null and lit.fuel < feed_cap:
			Actions.feed_fire(w)
		elif Items.inv_has(w.inventory, "deadfall", 1) and lit == null:
			Actions.feed_fire(w)
		if Items.inv_has(w.inventory, "snow", 1) or Items.inv_has(w.inventory, "waterRaw", 1):
			Actions.boil_water(w)
		if Items.inv_has(w.inventory, "waterClean", 1):
			Actions.drink(w)
		if Items.inv_has(w.inventory, "meat", 1):
			Actions.cook(w)
		if Items.inv_has(w.inventory, "meatCooked", 1) and w.needs.hunger < 55.0:
			Actions.eat(w)
		# Rebalance 2026-10-11: eat berries too (Actions.eat prefers cooked
		# meat, berries are the fallback a real player uses between hunts).
		if Items.inv_has(w.inventory, "berries", 1) and w.needs.hunger < 45.0:
			Actions.eat(w)
		if w.task == null and w.needs.hydration < 60.0 and w.needs.carriedWaterL < 0.5 \
				and not Items.inv_has(w.inventory, "waterClean", 1) and not Items.inv_has(w.inventory, "snow", 1):
			# same direct-snow fix as emergency-snow (begin_work grabs props)
			w.task = Interact.start_task({"id": -1, "kind": "snow",
				"x": w.player.x, "z": w.player.z, "uses": 99})

	## true = went to sleep this tick (or already asleep). Only sleeps when
	## standing still at camp with a fire, or when collapsing from exhaustion.
	func sleep(w: WorldSim) -> bool:
		if w.needs.sleeping:
			phase = "sleeping"
			return true
		if w.player.moving:
			return false
		var at_camp := dist(w.player.x, w.player.z, camp_x, camp_z) < 3.0
		var fire_fuel: Variant = null
		for f in w.fires:
			if f.lit and dist(f.x, f.z, camp_x, camp_z) < 4.0:
				if fire_fuel == null or f.fuel > fire_fuel.fuel:
					fire_fuel = f
		# a stage-2 fire burns 18%/h — only a well-fed fire (>=70) survives to dawn
		var safe_night: bool = is_night(w.hourOfDay) and at_camp and fire_fuel != null and fire_fuel.fuel > 70.0
		# exhaustion-nap (voluntary policy, NOT a forced-sleep mechanic —
		# the sim never incapacitates) only at camp WITH a healthy fire, or
		# in daylight — an open-air or fireless nap at night is a
		# hypothermia death sentence. Rebalance 2026-10-11 (calorie-model
		# card): AND only while still warm (core > 35.5) — the old bot napped
		# at midday with the fire out and a 34 °C core, and slept straight
		# into hypothermia. A freezing player stays awake and builds a fire.
		var camp_fuel := 0.0
		for f in w.fires:
			if f.lit and dist(f.x, f.z, camp_x, camp_z) < 4.0:
				camp_fuel = maxf(camp_fuel, f.fuel)
		var exhausted_nap := w.needs.energy < 15.0 and w.needs.coreTemp > 35.5 \
				and (camp_fuel > 25.0 or not is_night(w.hourOfDay))
		if safe_night or exhausted_nap:
			phase = "sleep"
			Actions.toggle_sleep(w)
			return w.needs.sleeping
		return false

	## While asleep: wake just enough to feed the fire from the wood pile and
	## settle again — a fire that dies at midnight is the #1 harness death.
	func maintain(w: WorldSim) -> void:
		if not w.needs.sleeping:
			return
		var f: Variant = null
		for x in w.fires:
			if x.lit and dist(x.x, x.z, camp_x, camp_z) < 4.0:
				if f == null or x.fuel > f.fuel:
					f = x
		if f != null and f.fuel < 30.0 and Items.inv_has(w.inventory, "deadfall", 1):
			Actions.feed_fire(w)
			return
		# fire dying and no wood in the pack: get up and fetch
		if f != null and f.fuel < 12.0 and int(w.inventory.get("deadfall", 0)) == 0:
			Actions.toggle_sleep(w)
			urgent_wood = true
			return
		# fire fully out at camp: wake and relight
		if f == null:
			Actions.toggle_sleep(w)
			fire_built = false
			urgent_wood = true

	func tick(w: WorldSim) -> void:
		# default: camp + sleep; subclasses extend
		if sleep(w):
			return
		# night curfew: head for camp before dark (thirst is the only override)
		var at_camp := dist(w.player.x, w.player.z, camp_x, camp_z) < 8.0
		var thirsty := w.needs.hydration < 25.0
		if is_night(w.hourOfDay) and not at_camp and not thirsty and not urgent_wood and w.task == null:
			phase = "curfew"
			mover.move(w, camp_x, camp_z, rng)
			return
		camp_fire(w)


## idle: do nothing at the wreck. The floor policy — must die.
class IdleBot extends BaseBot:
	func _init(seed_: int) -> void:
		super(seed_, Terrain.CRASH.x, Terrain.CRASH.z)

	func tick(_w: WorldSim) -> void:
		phase = "idle(do-nothing)"

	func maintain(_w: WorldSim) -> void:
		pass


## naive: loots, fire at the exposed wreck site, no shelter, no food loop, no
## signal. Port of NaiveBot (camp = open lake shore at the wreck — windy).
class NaiveBot extends BaseBot:
	var looted := false

	func _init(seed_: int) -> void:
		super(seed_, 0.0, -137.0)

	func tick(w: WorldSim) -> void:
		if not looted:
			phase = "to-wreck"
			if not mover.move(w, Terrain.CRASH.x, Terrain.CRASH.z, rng):
				return
			# check completion BEFORE starting another task (else snow-loops)
			if w.task == null and Items.inv_has(w.inventory, "knife", 1):
				looted = true
				return
			phase = "loot"
			if w.task == null:
				Actions.begin_work(w)
			return
		super.tick(w)


## competent: scouted forest camp, shelter, snares, eats properly, dawn
## fishing, wound care, signal fire + open shore by day 7. Port of
## AverageBot + OptimalBot (TS "optimal"). The TS wolf-repel line is not
## ported (wolves cut from the MVP).
class CompetentBot extends BaseBot:
	var looted := false
	var shelter_done := false
	var snares_set := 0
	var snare_fails := 0
	var signalling := false

	func _init(seed_: int) -> void:
		super(seed_, -40.0, -60.0)  # forest near lake shore (pre-scout default)

	## one committed shelter step; returns true when shelter complete
	func shelter_tick(w: WorldSim) -> bool:
		var s: Variant = null
		for sh in w.shelters:
			if dist(sh.x, sh.z, camp_x, camp_z) < 4.0:
				s = sh
				break
		if s != null and s.complete:
			return true
		var step: int = s.step if s != null else 0
		# step costs mirror Build.SHELTER_STEP_COST: 1,2 = deadfall×2; 3,5 = boughs×6
		var need: String = "deadfall" if (step == 1 or step == 2) else ("boughs" if (step == 3 or step == 5) else "")
		var want := 6 if need == "boughs" else 2
		if need != "" and int(w.inventory.get(need, 0)) < want:
			# COMMIT to gathering — do not re-check camp distance mid-fetch
			gather(w, [need], want)
			return false
		if dist(w.player.x, w.player.z, camp_x, camp_z) > 2.0:
			phase = "to-camp-shelter"
			mover.move(w, camp_x, camp_z, rng)
			return false
		phase = "shelter"
		var r := Build.build_shelter(w)
		return r == "complete"

	func tick(w: WorldSim) -> void:
		# --- OptimalBot extensions (minus wolves) ---
		# treat wounds at fire when tape available
		for i in w.injuries:
			if (i.infected or i.severity > 30.0) and Items.inv_has(w.inventory, "ductTape", 1):
				Actions.treat_wound(w)
				break
		# fish at dawn when idle and near a hole. Rebalance 2026-10-11:
		# daylight-gated (a real player doesn't fish at 03:00 in the wind)
		# and moved BELOW the critical-needs check below, so a starving/hyp-
		# othermic bot tends the emergency first instead of ping-ponging.
		if w.task == null and not is_night(w.hourOfDay) and w.hourOfDay < 10.0 \
				and w.needs.hydration > 45.0 \
				and Items.inv_has(w.inventory, "cordage", 1) \
				and dist(w.player.x, w.player.z, camp_x, camp_z) < 40.0:
			var hole: Variant = null
			for h in w.fishHoles:
				if h.usesLeft > 0:
					hole = h
					break
			if hole != null:
				phase = "fish"
				if not mover.move(w, hole.x, hole.z, rng):
					return
				Actions.fish(w)
				return
		# Rebalance 2026-10-11 (calorie-model card): the FLARE is the win
		# button and it never leaves the pack — the old flare line lived
		# inside the vitals-gated shore move, so a camp-bound bot reached
		# day 10 with a full flare gun and died of 'the search gave up'.
		# A competent player fires it at the day-7 dawn pass from wherever
		# they stand (0.95 detection even from forest).
		if w.day >= 7 and not signalling and w.rescued == null and w.dead == null \
				and w.hourOfDay >= 8.5 and w.hourOfDay < 16.0 \
				and Items.inv_has(w.inventory, "flare", 1) \
				and Items.inv_has(w.inventory, "flareGun", 1):
			if Actions.fire_flare(w):
				signalling = true
			# day 7 dawn pass is 09:00; keep the flare hot through it
		# day 6+: move to open shore, big fire, signal smoke, stay for dawn pass
		# Rebalance 2026-10-11 (calorie-model card): the signal run must never
		# outrank the vitals — the old branch walked to shore starving and
		# dehydrated (died d6 'water ran out' mid-march), and it spammed
		# light_fire every tick, burning its tinder reserve on failed rolls.
		# A competent player only breaks camp for the signal when stable.
		if w.day >= 6 and not signalling \
				and w.needs.hydration > 55.0 and w.needs.hunger > 45.0 \
				and w.needs.energy > 25.0:
			phase = "signal-move"
			camp_x = 0.0
			camp_z = -137.0
			fire_built = false
			for f in w.fires:
				if f.lit and dist(f.x, f.z, Terrain.CRASH.x, Terrain.CRASH.z) < 6.0:
					fire_built = true
					break
			if not mover.move(w, 0.0, -137.0, rng):
				return
			if not fire_built:
				# Rebalance 2026-10-11 (calorie-model card): same retry
				# cooldown as camp — the old branch burned a bundle per tick.
				if light_cooldown > 0:
					light_cooldown -= 1
					return
				if Items.inv_has(w.inventory, "tinderBundle", 1):
					var lit_res2 := Actions.light_fire(w, 1.0)
					fire_built = lit_res2 == "lit"
					if lit_res2 == "failed":
						light_cooldown = 40
				elif Items.inv_has(w.inventory, "kindling", 2) and Items.inv_has(w.inventory, "bark", 1):
					craft_first(w, "tinderBundle")
				elif Items.inv_has(w.inventory, "deadfall", 1):
					craft_first(w, "kindling")
				else:
					gather(w, ["deadfall", "bark"], 6)
				return
			if Items.inv_has(w.inventory, "deadfall", 1):
				Actions.feed_fire(w)
			if w.signalFireId == null and Items.inv_has(w.inventory, "boughs", 2):
				Actions.signal_smoke(w)
			if w.signalFireId != null:
				signalling = true
			# flare as insurance once the pass is imminent and smoke isn't up
			if not signalling and w.day == 7 and w.hourOfDay > 8.0 and Items.inv_has(w.inventory, "flare", 1):
				Actions.fire_flare(w)

		# --- AverageBot body ---
		if not looted:
			phase = "to-wreck"
			if not mover.move(w, Terrain.CRASH.x, Terrain.CRASH.z, rng):
				return
			if w.task == null and Items.inv_has(w.inventory, "knife", 1):
				looted = true
				scout_camp(w)
				return
			phase = "loot"
			if w.task == null:
				Actions.begin_work(w)
			return
		if not camped:
			scout_camp(w)

		# Rebalance 2026-10-11: active foraging — a competent player doesn't
		# starve next to berry bushes. This runs BEFORE the critical check:
		# when the pack has no food, hunger IS the emergency (the old bot
		# routed hunger<30 into the camp loop, which never forages — a
		# starvation trap). Daylight only; short haul; never while the camp
		# fire is sinking (fire first — a cold camp kills faster than hunger).
		var lit_at_camp := false
		var camp_fuel_now := 0.0
		for f in w.fires:
			if f.lit and dist(f.x, f.z, camp_x, camp_z) < 4.0:
				lit_at_camp = true
				camp_fuel_now = maxf(camp_fuel_now, f.fuel)
				break
		# Rebalance 2026-10-11: a camp fire about to die IS critical — a
		# competent player notices the flames sinking and refuels before
		# chasing snares/shelter (the old bot ping-ponged on side chores
		# while its fire burned to embers, then froze).
		var fire_sinking := lit_at_camp and camp_fuel_now < 40.0
		# Rebalance 2026-10-11: a sinking camp fire outranks EVERY side chore —
		# drop the snare run, drop the bark run, go tend it (stage-2 burn is
		# 18%/h: fuel 40 is barely 2 h of flame, and the old bot let it die
		# mid-errand and then froze trying to relight at midnight).
		if fire_sinking:
			if dist(w.player.x, w.player.z, camp_x, camp_z) > 8.0:
				phase = "to-camp"
				mover.move(w, camp_x, camp_z, rng)
				return
			if Items.inv_has(w.inventory, "deadfall", 1):
				phase = "stoke"
				Actions.feed_fire(w)
				return
		var has_food := Items.inv_has(w.inventory, "meat", 1) \
				or Items.inv_has(w.inventory, "meatCooked", 1) \
				or Items.inv_has(w.inventory, "berries", 1)
		if not has_food and w.needs.hunger < 45.0 and not is_night(w.hourOfDay) \
				and w.task == null and Items.inv_can_add(w.inventory, "berries", 1) \
				and lit_at_camp and not fire_sinking \
				and w.needs.coreTemp > Config.THERMO.COLD_C:
			phase = "forage-berries"
			gather(w, ["berries"], 4)
			return
		# Rebalance 2026-10-11: check the snares on the day's rounds — but
		# only when one has sprung (the bot "hears" it the way the TS bot
		# "sees" fire fuel: world state as perception). Walking to an empty
		# line every tick starved the fire loop.
		if snares_set > 0 and not is_night(w.hourOfDay) and w.task == null and not fire_sinking \
				and w.needs.coreTemp > Config.THERMO.COLD_C:
			var sprung: Variant = null
			for s in w.snares:
				if s.set and s.pending != null and s.pending > 0 \
						and dist(s.x, s.z, camp_x, camp_z) < 60.0:
					sprung = s
					break
			if sprung != null and dist(sprung.x, sprung.z, w.player.x, w.player.z) > 3.0:
				phase = "snare-check"
				mover.move(w, sprung.x, sprung.z, rng)
				return
			Actions.check_snares(w)
		# 1) base survival loop whenever critical or the camp fire needs tending
		# (lit_at_camp / camp_fuel_now / fire_sinking computed above)
		var critical := w.needs.hydration < 40.0 or w.needs.energy < 30.0 \
				or w.needs.coreTemp < Config.THERMO.COLD_C or w.needs.hunger < 30.0 \
				or fire_sinking
		var fire_needs_topup := not lit_at_camp or camp_fuel_now < 70.0
		var at_camp_now := dist(w.player.x, w.player.z, camp_x, camp_z) < 8.0
		if critical or fire_needs_topup or (is_night(w.hourOfDay) and not at_camp_now):
			super.tick(w)  # includes the night curfew
			return

		# 2) snares FIRST (passive food beats comfort; sets are cheap and catch
		#    while you do everything else). Rebalance 2026-10-11: daylight only
		#    — a real player sets snares on the day's rounds, not after dark
		#    (the old night snare branch ping-ponged the bot off camp) — and
		#    only with the fire already fed to 70+ (the old bot chased bark for
		#    cordage while its fire sank from 60 to 0).
		if snares_set < 2 and not is_night(w.hourOfDay) and lit_at_camp and camp_fuel_now >= 70.0:
			phase = "snare"
			if not Items.inv_has(w.inventory, "cordage", 1):
				if Items.inv_has(w.inventory, "bark", 4):
					craft_first(w, "cordage")
				else:
					gather(w, ["bark"], 4)
					return
			if Items.inv_has(w.inventory, "cordage", 1):
				# Rebalance 2026-10-11: snare within the camp home range only
				var t: Variant = nearest_kind(w, ["water"], Vector3(camp_x, 0, camp_z), 60.0)
				if t == null:
					snares_set = 2  # no hare sign near camp; move on
				elif dist(w.player.x, w.player.z, t.x, t.z) > 3.0:
					mover.move(w, t.x, t.z + 4, rng)
					return
				if Actions.set_snare(w) == "set":
					snares_set += 1
				elif snare_fails + 1 > 20:
					snares_set = 2  # no hare sign here; move on
				else:
					snare_fails += 1
				return
		Actions.check_snares(w)

		# 3) shelter when calm
		if not shelter_done:
			if shelter_tick(w):
				shelter_done = true
			super.tick(w)
			return
		super.tick(w)


# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------

class RunResult:
	var policy: String
	var seed: int
	var outcome: String  # "rescued" | "dead"
	var cause := ""
	var day := 0
	var hour := 0


static func make_bot(policy: String, seed_: int) -> BaseBot:
	match policy:
		"idle":
			return IdleBot.new(seed_)
		"naive":
			return NaiveBot.new(seed_)
		_:
			return CompetentBot.new(seed_)


static func run_game(policy: String, seed_: int) -> RunResult:
	var w := WorldSim.new(seed_)
	var bot: BaseBot = make_bot(policy, seed_)
	var max_ticks := int(11.0 * 24.0 * (Config.TIME.REAL_SECONDS_PER_GAME_HOUR / DT))
	for i in max_ticks:
		if w.dead != null or w.rescued != null:
			break
		bot.mover.did_move = false
		if w.needs.sleeping:
			bot.maintain(w)
		elif w.task == null:
			bot.tick(w)
		# if the bot chose a non-movement action while p.moving was still
		# true, settle it — stale movement blocks sleep, auto-sip, and drains energy
		if w.player.moving and not bot.mover.did_move:
			PlayerSim.update_player(w, {"fwd": 0, "strafe": 0, "run": false, "camYaw": 0}, DT)
		# a bot that starts a task intends to stand
		if w.task != null and w.player.moving:
			PlayerSim.update_player(w, {"fwd": 0, "strafe": 0, "run": false, "camYaw": 0}, DT)
		w.step(DT, false)
		Actions.tick_work(w, DT, Needs.compute_debuffs(w.needs).dexterity)
	var r := RunResult.new()
	r.policy = policy
	r.seed = seed_
	r.outcome = "rescued" if w.rescued != null else "dead"
	r.cause = w.dead.cause if w.dead != null else ""
	r.day = w.day
	r.hour = int(floor(w.hourOfDay))
	return r


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

static func median_days(rs: Array) -> String:
	var days: Array = []
	for r in rs:
		days.append(r.day)
	days.sort()
	if days.is_empty():
		return "—"
	var n: int = days.size()
	if n % 2 == 1:
		return str(days[n / 2])
	return "%.1f" % ((days[n / 2 - 1] + days[n / 2]) / 2.0)


static func histogram(rs: Array, key: String) -> String:
	# key: "cause" -> deaths by cause; "day" -> deaths by day; "rescue" -> rescues by day
	var counts := {}
	for r in rs:
		var k: String
		match key:
			"cause":
				if r.outcome != "dead":
					continue
				k = r.cause if r.cause != "" else "?"
			"day":
				if r.outcome != "dead":
					continue
				k = "d%d" % r.day
			_:
				if r.outcome != "rescued":
					continue
				k = "d%d" % r.day
		counts[k] = int(counts.get(k, 0)) + 1
	var keys: Array = counts.keys()
	if key == "day" or key == "rescue":
		keys.sort_custom(func(a, b): return int(a.substr(1)) < int(b.substr(1)))
	else:
		keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d" % [k, counts[k]])
	return ", ".join(parts) if not parts.is_empty() else "none"


static func summarize(results: Array) -> String:
	var by_policy := {}
	var order: Array[String] = []
	for r in results:
		if not by_policy.has(r.policy):
			by_policy[r.policy] = []
			order.append(r.policy)
		by_policy[r.policy].append(r)
	var lines: Array[String] = []
	for policy in order:
		var rs: Array = by_policy[policy]
		var n: int = rs.size()
		var rescued: Array = rs.filter(func(r): return r.outcome == "rescued")
		var deaths: Array = rs.filter(func(r): return r.outcome == "dead")
		var avg_rescue := "—"
		if not rescued.is_empty():
			var s := 0.0
			for r in rescued:
				s += r.day
			avg_rescue = "%.1f" % (s / rescued.size())
		lines.push_back("%-10s n=%d  rescued %3.0f%% (avg day %s)  died %3.0f%%  days-survived median %s" % [
			policy, n, 100.0 * rescued.size() / n, avg_rescue, 100.0 * deaths.size() / n, median_days(rs)])
		lines.push_back("  causes:      %s" % histogram(rs, "cause"))
		lines.push_back("  death days:  %s" % histogram(rs, "day"))
		lines.push_back("  rescue days: %s" % histogram(rs, "rescue"))
	return "\n".join(lines)


func _init() -> void:
	var seeds := 20
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = int(args[0])
	if seeds <= 0:
		seeds = 20
	var t0 := Time.get_ticks_msec()
	var results: Array = []
	for policy in ["idle", "naive", "competent"]:
		for s in range(1, seeds + 1):
			results.append(run_game(policy, s))
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	print("# boreal balance: %d seeds/policy, %.1fs (GDScript harness)" % [seeds, secs])
	print(summarize(results))
	quit(0)
