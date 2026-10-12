class_name InventoryGrid
extends RefCounted
## A grid of cells holding ItemInstances (DESIGN.md §7): the stash, pockets, or the inside of a rig,
## backpack or secure container. Items take their footprint (turned or not) and can't overlap. Pure
## data: the UI (InventoryGridView) draws it and asks it what's allowed.
##
## What may go in, besides fitting: the stash takes anything; a secure container takes nothing that
## has its own grid; any other container takes containers only when they're empty; nothing goes inside
## itself.

## Something was added, moved, removed or restacked.
signal changed

var size: Vector2i
## &"stash", &"pockets", &"rig", &"backpack", &"secure" or &"case".
var kind: StringName
var items: Array[ItemInstance] = []

var _owner: WeakRef


func _init(grid_size: Vector2i, grid_kind := &"stash", owner_item: ItemInstance = null) -> void:
	size = grid_size
	kind = grid_kind
	_owner = weakref(owner_item) if owner_item else null


## The rig, backpack or container this grid is inside of, if any.
func owner_item() -> ItemInstance:
	return _owner.get_ref() if _owner else null


## True if `item` may go in this grid at all (ignoring space).
func accepts(item: ItemInstance) -> bool:
	if item.contents and (item.contents == self or item.contents.holds_grid(self)):
		return false  # Not inside itself.
	match kind:
		&"stash":
			return true
		&"secure":
			return not item.has_grid()
	return item.is_empty_container()


## True if `grid` is this grid or inside one of its items, at any depth.
func holds_grid(grid: InventoryGrid) -> bool:
	for item in items:
		if item.contents and (item.contents == grid or item.contents.holds_grid(grid)):
			return true
	return false


func in_bounds(cell: Vector2i, footprint: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x + footprint.x <= size.x and cell.y + footprint.y <= size.y


## True if no item (other than `ignore`) overlaps that area.
func is_free(cell: Vector2i, footprint: Vector2i, ignore: ItemInstance = null) -> bool:
	var area := Rect2i(cell, footprint)
	for item in items:
		if item != ignore and Rect2i(item.cell, item.footprint()).intersects(area):
			return false
	return true


## True if `item` can go at `cell`, turned or not (it may already be in this grid: it doesn't block itself).
func can_place(item: ItemInstance, cell: Vector2i, turned: bool) -> bool:
	var footprint := item.footprint_if(turned)
	return accepts(item) and in_bounds(cell, footprint) and is_free(cell, footprint, item)


## Puts `item` at `cell` (moving it if it's already here). Returns false if it can't go there.
func place(item: ItemInstance, cell: Vector2i, turned: bool) -> bool:
	if not can_place(item, cell, turned):
		return false
	item.cell = cell
	item.rotated = turned
	if item not in items:
		items.append(item)
	changed.emit()
	return true


func remove(item: ItemInstance) -> void:
	if item in items:
		items.erase(item)
		changed.emit()


func item_at(cell: Vector2i) -> ItemInstance:
	for item in items:
		if Rect2i(item.cell, item.footprint()).has_point(cell):
			return item
	return null


## First free spot for `item`, row by row, unturned first: {"cell": Vector2i, "rotated": bool}, or {}.
func find_space(item: ItemInstance) -> Dictionary:
	if not accepts(item):
		return {}
	for turned in ([false, true] if item.data.size.x != item.data.size.y else [false]):
		var footprint := item.footprint_if(turned)
		for y in size.y - footprint.y + 1:
			for x in size.x - footprint.x + 1:
				if is_free(Vector2i(x, y), footprint, item):
					return {"cell": Vector2i(x, y), "rotated": turned}
	return {}


## Adds `item` wherever it fits, topping up existing stacks of the same item first. Returns true if it
## all went in; otherwise `item.count` is what's left over.
func add(item: ItemInstance) -> bool:
	if not accepts(item):
		return false
	var merged := false
	for other in items:
		if other.can_stack_with(item):
			var moved := mini(item.count, other.data.max_stack - other.count)
			other.count += moved
			item.count -= moved
			merged = merged or moved > 0
			if item.count == 0:
				changed.emit()
				return true
	var spot := find_space(item)
	if spot.is_empty():
		if merged:
			changed.emit()
		return false
	return place(item, spot.cell, spot.rotated)


## How many of item `id` this grid holds (not counting inside containers).
func count_of(id: String) -> int:
	var total := 0
	for item in items:
		if item.data.id == id:
			total += item.count
	return total


## Removes up to `amount` of item `id`, smallest stacks first. Returns how many were taken.
func take(id: String, amount: int) -> int:
	var stacks := items.filter(func(item: ItemInstance) -> bool: return item.data.id == id)
	stacks.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.count < b.count)
	var taken := 0
	for stack: ItemInstance in stacks:
		if taken >= amount:
			break
		var used := mini(stack.count, amount - taken)
		stack.count -= used
		taken += used
		if stack.count == 0:
			items.erase(stack)
	if taken > 0:
		changed.emit()
	return taken


func weight() -> float:
	var total := 0.0
	for item in items:
		total += item.weight()
	return total


func value() -> int:
	var total := 0
	for item in items:
		total += item.value()
	return total


func to_array() -> Array:
	return items.map(func(item: ItemInstance) -> Dictionary: return item.to_dict())


## Fills the grid from to_array() data. Items whose saved spot is taken go wherever they fit.
func load_array(entries: Array) -> void:
	for entry in entries:
		if not entry is Dictionary:
			continue
		var item := ItemInstance.from_dict(entry)
		if item == null:
			continue
		if not place(item, item.cell, item.rotated) and not add(item):
			push_warning("InventoryGrid: no room for %s, dropped" % item.data.id)
