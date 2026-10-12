class_name InventoryDrag
extends RefCounted
## An item being dragged in the inventory UI (DESIGN.md §7): what it is, where it came from, how many
## are moving (a Shift-drag split takes half; the mouse wheel changes it) and whether it's been turned
## with R. It also decides what dropping it somewhere would do, and does it. Nothing moves until the
## drop succeeds, so letting go anywhere else simply cancels.

## The drag in progress, if any (for R and the mouse wheel).
static var current: InventoryDrag

## Turned or the amount changed: the preview redraws.
signal updated

var item: ItemInstance
## Where it came from: a grid, or an equipment slot of `inventory`.
var from_grid: InventoryGrid
var from_slot := ""
var inventory: Inventory
## How many are moving; less than item.count for a split.
var amount := 1
var rotated := false
var splitting := false


func _init(dragged: ItemInstance, source_grid: InventoryGrid, source_slot: String, owner: Inventory, split: bool) -> void:
	item = dragged
	from_grid = source_grid
	from_slot = source_slot
	inventory = owner
	rotated = dragged.rotated
	splitting = split and dragged.count > 1
	amount = ceili(dragged.count / 2.0) if splitting else dragged.count
	current = self


func footprint() -> Vector2i:
	return item.footprint_if(rotated)


func rotate() -> void:
	rotated = not rotated
	updated.emit()


## Mouse wheel during a split: more or fewer.
func change_amount(by: int) -> void:
	if splitting:
		amount = clampi(amount + by, 1, item.count - 1)
		updated.emit()


## Top-left cell when the item's centre is under the mouse (`mouse_cells` in fractional cells).
func target_cell(mouse_cells: Vector2) -> Vector2i:
	return Vector2i((mouse_cells - Vector2(footprint()) / 2.0 + Vector2(0.5, 0.5)).floor())


## What dropping on `grid` with the mouse over `mouse_cell` would do:
## {"action": "merge" (onto a stack), "insert" (into a container item), "place", "stay" (no change),
## "target": the item underneath, "cell": the top-left cell} or {} when it can't go there.
func plan_grid(grid: InventoryGrid, mouse_cell: Vector2i, top_left: Vector2i) -> Dictionary:
	var under := grid.item_at(mouse_cell)
	if under == item and not splitting and from_grid == grid and top_left == item.cell and rotated == item.rotated:
		return {"action": "stay"}
	if under and under != item:
		if under.data == item.data and item.data.max_stack > 1 and under.count < under.data.max_stack:
			return {"action": "merge", "target": under}
		if can_insert(under):
			return {"action": "insert", "target": under}
	var fits := grid.accepts(item) and grid.in_bounds(top_left, footprint())
	fits = fits and grid.is_free(top_left, footprint(), null if splitting else item)
	return {"action": "place", "cell": top_left} if fits else {}


## Carries out a plan_grid() result. Returns true if anything moved.
func drop_on_grid(grid: InventoryGrid, plan: Dictionary) -> bool:
	match plan.get("action", ""):
		"stay":
			return true
		"merge":
			var target: ItemInstance = plan.target
			var moved := mini(amount, target.data.max_stack - target.count)
			_take_from_source(moved)
			target.count += moved
			grid.changed.emit()
			return true
		"insert":
			return insert(plan.target)
		"place":
			if splitting:
				var piece := ItemInstance.create(item.data.id, amount)
				piece.fir = item.fir
				_take_from_source(amount)
				return grid.place(piece, plan.cell, rotated)
			if from_grid != grid:
				_remove_from_source()
			return grid.place(item, plan.cell, rotated)
	return false


## True if the dragged item (or split) can go inside `target`, a rig, backpack or container.
func can_insert(target: ItemInstance) -> bool:
	return target != item and target.contents != null and _fits_inside(target.contents)


## Puts the dragged item (or split) inside `target` wherever it fits. Returns true if any of it went in.
func insert(target: ItemInstance) -> bool:
	if not can_insert(target):
		return false
	var piece := _piece()
	var before := piece.count
	var whole := target.contents.add(piece)
	var moved := before if whole else before - piece.count
	if piece == item:
		if not whole:
			_put_back_rest(piece)  # Only part of the stack fitted.
	elif moved > 0:
		_take_from_source(moved)
	return moved > 0


## True if dropping on equipment `slot` would work (whole items only).
func can_equip(slot: String) -> bool:
	if splitting or inventory == null:
		return false
	if from_slot == slot:
		return true
	return inventory.equipment.get(slot) == null and inventory.accepts(slot, item)


func drop_on_slot(slot: String) -> bool:
	if not can_equip(slot):
		return false
	if from_slot == slot:
		return true
	_remove_from_source()
	item.rotated = false
	return inventory.equip(slot, item)


## True if `container` (a rig or backpack shown as an item) can take what's being dragged.
func _fits_inside(container: InventoryGrid) -> bool:
	if not container.accepts(item):
		return false
	var probe := ItemInstance.create(item.data.id, amount)
	return not container.find_space(probe).is_empty() or container.items.any(func(other: ItemInstance) -> bool:
		return other.data == item.data and other.count < other.data.max_stack and item.data.max_stack > 1)


## The item being moved, or a new stack split off it.
func _piece() -> ItemInstance:
	if not splitting:
		_remove_from_source()
		return item
	var piece := ItemInstance.create(item.data.id, amount)
	piece.fir = item.fir
	return piece


## After an insert that didn't take the whole stack, what's left goes back where it was.
func _put_back_rest(piece: ItemInstance) -> void:
	if piece.count == 0:
		return
	if from_grid:
		from_grid.place(piece, piece.cell, piece.rotated)
	elif inventory and from_slot != "":
		inventory.equip(from_slot, piece)


func _take_from_source(count: int) -> void:
	if count >= item.count:
		_remove_from_source()
		item.count = 0
		return
	item.count -= count
	if from_grid:
		from_grid.changed.emit()
	elif inventory:
		inventory.changed.emit()


func _remove_from_source() -> void:
	if from_grid:
		from_grid.remove(item)
	elif inventory and from_slot != "":
		inventory.unequip(from_slot)
