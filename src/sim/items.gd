## Items + inventory — port of items.ts (MVP set).
class_name Items

const CARRY_LIMIT_KG := 18.0

## id -> {label, stack, weight}
const ITEMS := {
	"deadfall": {"label": "Deadfall wood", "stack": 6, "weight": 1.2},
	"kindling": {"label": "Kindling", "stack": 12, "weight": 0.3},
	"bark": {"label": "Birch bark", "stack": 10, "weight": 0.2},
	"boughs": {"label": "Spruce boughs", "stack": 12, "weight": 0.4},
	"rock": {"label": "Rock", "stack": 3, "weight": 2.5},
	"snow": {"label": "Packed snow", "stack": 2, "weight": 0.5},
	"waterRaw": {"label": "Water (raw)", "stack": 2, "weight": 1.0},
	"waterClean": {"label": "Water (boiled)", "stack": 2, "weight": 1.0},
	"tinderBundle": {"label": "Tinder bundle", "stack": 4, "weight": 0.3},
	"barkContainer": {"label": "Bark container", "stack": 2, "weight": 0.4},
	"torch": {"label": "Torch", "stack": 2, "weight": 0.6},
	"boughBundle": {"label": "Bough bundle", "stack": 4, "weight": 2.0},
	"knife": {"label": "Knife", "stack": 1, "weight": 0.2},
	"tinCup": {"label": "Tin cup", "stack": 1, "weight": 0.2},
	"blanket": {"label": "Emergency blanket", "stack": 1, "weight": 0.15},
	"flareGun": {"label": "Flare gun", "stack": 1, "weight": 0.8},
	"flare": {"label": "Flare", "stack": 2, "weight": 0.15},
	"ductTape": {"label": "Duct tape", "stack": 2, "weight": 0.25},
	"berries": {"label": "Berries", "stack": 8, "weight": 0.15},
	"meat": {"label": "Small game (raw)", "stack": 4, "weight": 0.8},
	"meatCooked": {"label": "Cooked meat", "stack": 4, "weight": 0.6},
	"cordage": {"label": "Cordage", "stack": 4, "weight": 0.2},
}


static func inv_weight(inv: Dictionary) -> float:
	var w := 0.0
	for id in inv:
		w += inv[id] * ITEMS[id].weight
	return w


## Add up to n; returns how many were actually added (stack + carry limit).
static func inv_add(inv: Dictionary, id: String, n := 1) -> int:
	var cur: int = inv.get(id, 0)
	var room: int = minf(ITEMS[id].stack - cur, n)
	var kg_room := CARRY_LIMIT_KG - inv_weight(inv)
	var by_weight := int(floor(kg_room / ITEMS[id].weight))
	room = mini(room, maxi(0, by_weight))
	var added := maxi(0, room)
	if added > 0:
		inv[id] = cur + added
	return added


static func inv_remove(inv: Dictionary, id: String, n := 1) -> bool:
	var cur: int = inv.get(id, 0)
	if cur < n:
		return false
	if cur == n:
		inv.erase(id)
	else:
		inv[id] = cur - n
	return true


static func inv_has(inv: Dictionary, id: String, n := 1) -> bool:
	return inv.get(id, 0) >= n


static func inv_can_add(inv: Dictionary, id: String, n := 1) -> bool:
	var room: int = ITEMS[id].stack - inv.get(id, 0)
	return room >= n and inv_weight(inv) + n * ITEMS[id].weight <= CARRY_LIMIT_KG
