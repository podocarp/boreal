## Interactables + work tasks — port of interact.ts.
class_name Interact

const INTERACT_LABEL := {
	"deadfall": "Break deadfall wood",
	"boughs": "Snap spruce boughs",
	"bark": "Peel birch bark",
	"rock": "Collect hand rocks",
	"snow": "Pack snow (container)",
	"water": "Scoop stream water (container)",
	"berries": "Pick berries",
	"wreck": "Scavenge the wreck",
}

## base work duration in GAME HOURS
const WORK_HOURS := {
	"deadfall": 0.35,
	"boughs": 0.2,
	"bark": 0.3,
	"rock": 0.25,
	"snow": 0.1,
	"water": 0.1,
	"berries": 0.2,
	"wreck": 0.5,
}

const YIELDS := {
	"deadfall": [{"item": "deadfall", "n": 2}],
	"boughs": [{"item": "boughs", "n": 3}],
	"bark": [{"item": "bark", "n": 2}],
	"rock": [{"item": "rock", "n": 1}],
	"snow": [{"item": "snow", "n": 1}],
	"water": [{"item": "waterRaw", "n": 1}],
	"berries": [{"item": "berries", "n": 2}],
}

const WRECK_LOOT := [
	{"item": "knife", "n": 1},
	{"item": "tinCup", "n": 1},
	{"item": "blanket", "n": 1},
	{"item": "flareGun", "n": 1},
	{"item": "flare", "n": 1},
	{"item": "ductTape", "n": 2},
	{"item": "kindling", "n": 2},
]

const INTERACT_RADIUS_M := 2.6


static func build_interactables(seed: int, props: Array) -> Array:
	var list: Array = []
	var id := 1
	for p in props:
		var r := NoiseSim.valueNoise2(p.x * 0.11, p.z * 0.11, seed + 31)
		if p.kind == "spruce":
			if r < 0.22:
				list.append({"id": id, "kind": "deadfall", "x": p.x, "z": p.z, "uses": 2}); id += 1
			elif r < 0.5:
				list.append({"id": id, "kind": "boughs", "x": p.x, "z": p.z, "uses": 3}); id += 1
		elif p.kind == "birch" and r < 0.45:
			list.append({"id": id, "kind": "bark", "x": p.x, "z": p.z, "uses": 2}); id += 1
		elif p.kind == "rock" and r < 0.6:
			list.append({"id": id, "kind": "rock", "x": p.x, "z": p.z, "uses": 2}); id += 1
		if p.kind == "birch" and r > 0.85:
			list.append({"id": id, "kind": "berries", "x": p.x, "z": p.z, "uses": 3}); id += 1
	# stream access points every ~45 m
	var z := 200.0
	while z > -150.0:
		list.append({"id": id, "kind": "water", "x": Terrain.streamX(z), "z": z, "uses": 99}); id += 1
		z -= 45.0
	# crash site
	list.append({"id": id, "kind": "wreck", "x": Terrain.CRASH.x, "z": Terrain.CRASH.z, "uses": 1})
	return list


## nearest interactable (or dynamic snow if none close and allowSnow)
static func find_target(px: float, pz: float, list: Array, allow_snow: bool) -> Variant:
	var best: Variant = null
	var bd := INTERACT_RADIUS_M
	for it in list:
		if it.uses <= 0:
			continue
		var d := sqrt((it.x - px) * (it.x - px) + (it.z - pz) * (it.z - pz))
		if d < bd:
			bd = d
			best = it
	if best == null and allow_snow:
		return {"id": -1, "kind": "snow", "x": px, "z": pz, "uses": 99}
	return best


## WorkTask dict {targetId, remaining, total, kind} — remaining in REAL seconds.
static func start_task(target: Dictionary) -> Dictionary:
	var hours: float = WORK_HOURS[target.kind]
	var secs: float = hours * Config.TIME.REAL_SECONDS_PER_GAME_HOUR
	return {"targetId": target.id, "remaining": secs, "total": secs, "kind": "gather"}
