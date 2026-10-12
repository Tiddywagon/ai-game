class_name ItemInstance
extends RefCounted
## One actual item or stack the player owns (DESIGN.md §7, §15): which ItemData it is, how many,
## where it sits in a grid and whether it's turned. Rigs, backpacks and secure containers carry their
## own InventoryGrid (`contents`, sized by the item's "grid" stat). Guns remember the rounds loaded.
## Saved as plain data through to_dict() / from_dict().

var data: ItemData
var count := 1
## Top-left cell in the grid that holds it.
var cell := Vector2i.ZERO
## Turned a quarter: width and height swap.
var rotated := false
## Found in Raid (DESIGN.md §2).
var fir := false
## Rigs, backpacks, secure containers: what's inside. Null for everything else.
var contents: InventoryGrid
## Guns: round type in the magazine, and how many (-1 = a full magazine).
var loaded_ammo := ""
var loaded_rounds := -1


## A new instance of item `id` (null if there's no such item), `count` of it (capped to a stack).
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


## Same item type that stacks, with room to spare.
func can_stack_with(other: ItemInstance) -> bool:
	return other != self and other.data == data and data.max_stack > 1 and count < data.max_stack


## Weight of the stack, plus whatever is inside.
func weight() -> float:
	return data.weight_kg * count + (contents.weight() if contents else 0.0)


## Base value of the stack, plus whatever is inside.
func value() -> int:
	return data.base_value * count + (contents.value() if contents else 0)


func to_dict() -> Dictionary:
	var result := {"id": data.id, "count": count, "x": cell.x, "y": cell.y, "rotated": rotated, "fir": fir}
	if contents:
		result.contents = contents.to_array()
	if loaded_ammo != "":
		result.loaded_ammo = loaded_ammo
		result.loaded_rounds = loaded_rounds
	return result


## Rebuilds an instance from to_dict() data (also reads older stash entries: id, x, y, rotated, count).
## Null if the item no longer exists.
static func from_dict(entry: Dictionary) -> ItemInstance:
	var instance := create(str(entry.get("id", "")), int(entry.get("count", 1)))
	if instance == null:
		return null
	instance.cell = Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	instance.rotated = bool(entry.get("rotated", false))
	instance.fir = bool(entry.get("fir", false))
	instance.loaded_ammo = str(entry.get("loaded_ammo", ""))
	instance.loaded_rounds = int(entry.get("loaded_rounds", -1))
	if instance.contents:
		instance.contents.load_array(entry.get("contents", []))
	return instance


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
