class_name ItemInstance
extends RefCounted
## One actual item or stack the player owns (DESIGN.md §7, §15): which ItemData it is, how many,
## where it sits in a grid and whether it's turned. Rigs, backpacks and secure containers carry their
## own InventoryGrid (`contents`, sized by the item's "grid" stat). Guns carry the rounds loaded, as
## ammo instances, so each round keeps its Found-in-Raid status. Saved as plain data through
## to_dict() / from_dict().

var data: ItemData
var count := 1
## Top-left cell in the grid that holds it.
var cell := Vector2i.ZERO
## Turned a quarter: width and height swap.
var rotated := false
## Found in Raid (DESIGN.md §2, §7): looted in a raid you survived and extracted from, or crafted.
## Never set on anything bought, bartered, insured or given as a reward. See FoundInRaid.
var fir := false
## In a raid only: looted this raid. Becomes `fir` if you extract with it (a faded checkmark until
## then); cleared if you die or the raid is a Run Through. Not saved.
var fir_pending := false
## In a raid only: part of the kit you brought in, so taking it back from a container never makes it
## found in raid. Not saved.
var brought_in := false
## In a raid only: in a container or on a body you haven't searched yet. Drawn as an unknown item; can't
## be moved or examined until a search reveals it (LootSearch). Not saved.
var hidden := false
## Rigs, backpacks, secure containers: what's inside. Null for everything else.
var contents: InventoryGrid
## Guns: the round type a reload uses, and the rounds in the magazine, bottom first. Each entry is an
## ammo ItemInstance (a run of rounds with the same status); the last one is fired first.
var loaded_ammo := ""
var magazine: Array[ItemInstance] = []


## A new instance of item `id` (null if there's no such item), `count` of it (capped to a stack).
## Not found in raid: use FoundInRaid.make() to say where an item came from.
static func create(id: String, amount := 1) -> ItemInstance:
	var item_data := ItemDB.get_item(id)
	if item_data == null:
		return null
	var instance := ItemInstance.new()
	instance.data = item_data
	instance.count = clampi(amount, 1, item_data.max_stack)
	var grid: Array = item_data.stats.get("grid", [])
	if grid.size() == 2:
		instance.contents = InventoryGrid.new(Vector2i(int(grid[0]), int(grid[1])), _grid_kind(item_data), instance)
	return instance


## Cells taken as placed (turned or not).
func footprint() -> Vector2i:
	return Vector2i(data.size.y, data.size.x) if rotated else data.size


func footprint_if(turned: bool) -> Vector2i:
	return Vector2i(data.size.y, data.size.x) if turned else data.size


func has_grid() -> bool:
	return contents != null


func is_empty_container() -> bool:
	return contents == null or contents.items.is_empty()


## Same Found-in-Raid status (found, looted this raid, brought in): only such stacks merge.
func same_status(other: ItemInstance) -> bool:
	return fir == other.fir and fir_pending == other.fir_pending and brought_in == other.brought_in


## Same item type that stacks, with room to spare, and the same Found-in-Raid status.
func can_stack_with(other: ItemInstance) -> bool:
	return other != self and other.data == data and data.max_stack > 1 and count < data.max_stack and same_status(other) \
		and not hidden and not other.hidden


## A new stack of `amount` taken off this one's status (the caller takes the count off this one).
func split_off(amount: int) -> ItemInstance:
	var piece := ItemInstance.create(data.id, amount)
	piece.copy_status(self)
	return piece


func copy_status(from: ItemInstance) -> void:
	fir = from.fir
	fir_pending = from.fir_pending
	brought_in = from.brought_in


## This item and everything in it: grid contents (at any depth) and the rounds in its magazine.
func all_items() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = [self]
	result.append_array(magazine)
	if contents:
		result.append_array(contents.all_items())
	return result


## Weight of the stack, plus whatever is inside and the rounds loaded.
func weight() -> float:
	var total := data.weight_kg * count + (contents.weight() if contents else 0.0)
	for rounds in magazine:
		total += rounds.weight()
	return total


## Base value of the stack, plus whatever is inside and the rounds loaded.
func value() -> int:
	var total := data.base_value * count + (contents.value() if contents else 0)
	for rounds in magazine:
		total += rounds.value()
	return total


# --- Magazine ---------------------------------------------------------------------------------

## Rounds in the magazine.
func rounds_loaded() -> int:
	var total := 0
	for rounds in magazine:
		total += rounds.count
	return total


## How many of the loaded rounds are found in raid (`pending`: looted this raid instead).
func rounds_with_status(found: bool, pending := false) -> int:
	var total := 0
	for rounds in magazine:
		if rounds.fir == found and rounds.fir_pending == pending:
			total += rounds.count
	return total


## Puts `rounds` (an ammo instance) on top of the magazine, keeping its status.
func load_rounds(rounds: ItemInstance) -> void:
	if rounds == null or rounds.count <= 0:
		return
	var top: ItemInstance = magazine.back() if not magazine.is_empty() else null
	if top and top.data == rounds.data and top.same_status(rounds):
		top.count += rounds.count
	else:
		magazine.append(rounds)
	loaded_ammo = rounds.data.id


## Fires (removes) the top round.
func fire_round() -> void:
	if magazine.is_empty():
		return
	var top: ItemInstance = magazine.back()
	top.count -= 1
	if top.count <= 0:
		magazine.pop_back()


## Empties the magazine and returns its rounds, merged into stacks by status.
func unload() -> Array[ItemInstance]:
	var stacks: Array[ItemInstance] = []
	for rounds in magazine:
		var merged := false
		for stack in stacks:
			if stack.data == rounds.data and stack.same_status(rounds):
				stack.count += rounds.count
				merged = true
				break
		if not merged:
			stacks.append(rounds)
	magazine.clear()
	return stacks


## Debug: the loaded rounds become `ammo_id` rounds, keeping counts and status.
func convert_magazine(ammo_id: String) -> void:
	var ammo := ItemDB.get_item(ammo_id)
	for rounds in magazine:
		rounds.data = ammo
	loaded_ammo = ammo_id


func to_dict() -> Dictionary:
	var result := {"id": data.id, "count": count, "x": cell.x, "y": cell.y, "rotated": rotated, "fir": fir}
	if contents:
		result.contents = contents.to_array()
	if loaded_ammo != "":
		result.loaded_ammo = loaded_ammo
	if not magazine.is_empty():
		result.magazine = magazine.map(func(rounds: ItemInstance) -> Dictionary:
			return {"id": rounds.data.id, "count": rounds.count, "fir": rounds.fir})
	return result


## Rebuilds an instance from to_dict() data (also reads older entries: version 3 guns saved
## "loaded_rounds", -1 for a full magazine). Null if the item no longer exists.
static func from_dict(entry: Dictionary) -> ItemInstance:
	var instance := create(str(entry.get("id", "")), int(entry.get("count", 1)))
	if instance == null:
		return null
	instance.cell = Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	instance.rotated = bool(entry.get("rotated", false))
	instance.fir = bool(entry.get("fir", false))
	instance.loaded_ammo = str(entry.get("loaded_ammo", ""))
	for saved in entry.get("magazine", []):
		var rounds := ItemInstance.new()
		rounds.data = ItemDB.get_item(str(saved.get("id", "")))
		if rounds.data:
			rounds.count = int(saved.get("count", 0))
			rounds.fir = bool(saved.get("fir", false))
			instance.load_rounds(rounds)
	if entry.has("loaded_rounds") and not entry.has("magazine") and instance.loaded_ammo != "" and instance.data.weapon:
		var loaded := int(entry.loaded_rounds)
		instance.load_rounds(full_rounds(instance.loaded_ammo, instance.data.weapon.magazine_size if loaded < 0 else loaded))
	if instance.contents:
		instance.contents.load_array(entry.get("contents", []))
	return instance


## `amount` rounds of `ammo_id` as one magazine entry (not capped to a stack), or null.
static func full_rounds(ammo_id: String, amount: int) -> ItemInstance:
	var ammo := ItemDB.get_item(ammo_id)
	if ammo == null or amount <= 0:
		return null
	var rounds := ItemInstance.new()
	rounds.data = ammo
	rounds.count = amount
	return rounds


func duplicate_deep() -> ItemInstance:
	return from_dict(to_dict())


static func _grid_kind(item_data: ItemData) -> StringName:
	if item_data.stats.get("secure", false):
		return &"secure"
	match item_data.category:
		ItemData.Category.RIG:
			return &"rig"
		ItemData.Category.BACKPACK:
			return &"backpack"
	return &"case"
