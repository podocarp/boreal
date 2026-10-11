## Crafting recipes — port of craft.ts (survival-kit depth only).
## Recipes are plain dicts mirroring the TS Recipe interface:
##   {id, label, in: [{item, n}], out: [{item, n}], hours, requires?}
## `hours` is game-hours of work (TS keeps it declarative; the MVP action
## path crafts instantly — see actions.ts contextActions tier 6).
class_name CraftSim


const RECIPES: Array = [
	{
		"id": "kindling",
		"label": "Split kindling (×3)",
		"in": [{"item": "deadfall", "n": 1}],
		"out": [{"item": "kindling", "n": 3}],
		"hours": 0.2,
		"requires": "knife",
	},
	{
		"id": "tinderBundle",
		"label": "Tinder bundle",
		"in": [{"item": "bark", "n": 1}, {"item": "kindling", "n": 2}],
		"out": [{"item": "tinderBundle", "n": 1}],
		"hours": 0.15,
	},
	{
		"id": "barkContainer",
		"label": "Bark container",
		"in": [{"item": "bark", "n": 4}],
		"out": [{"item": "barkContainer", "n": 1}],
		"hours": 0.3,
		"requires": "knife",
	},
	{
		"id": "boughBundle",
		"label": "Bough bundle (bedding)",
		"in": [{"item": "boughs", "n": 6}],
		"out": [{"item": "boughBundle", "n": 1}],
		"hours": 0.25,
	},
	{
		"id": "cordage",
		"label": "Cordage (twisted bark)",
		"in": [{"item": "bark", "n": 4}],
		"out": [{"item": "cordage", "n": 1}],
		"hours": 0.25,
	},
	{
		"id": "torch",
		"label": "Torch",
		"in": [{"item": "bark", "n": 2}, {"item": "deadfall", "n": 1}],
		"out": [{"item": "torch", "n": 1}],
		"hours": 0.15,
	},
]


static func recipe_by_id(id: String) -> Variant:
	for r in RECIPES:
		if r.id == id:
			return r
	return null


## Can this recipe run right now? Requires-item, inputs, and output fit
## (stack limit + carry weight) must all hold.
static func can_craft(inv: Dictionary, r: Dictionary) -> bool:
	if r.has("requires") and not Items.inv_has(inv, r.requires, 1):
		return false
	for i in r.in:
		if not Items.inv_has(inv, i.item, i.n):
			return false
	# output must fit
	for o in r.out:
		if not Items.inv_can_add(inv, o.item, o.n):
			return false
	return true


## Craft against an inventory dict; returns true on success
## (atomic: all-or-nothing). Log line is pushed by the caller (actions.gd),
## mirroring the actions.ts run() closure.
static func craft(inv: Dictionary, r: Dictionary) -> bool:
	if not can_craft(inv, r):
		return false
	for i in r.in:
		Items.inv_remove(inv, i.item, i.n)
	for o in r.out:
		Items.inv_add(inv, o.item, o.n)
	return true
