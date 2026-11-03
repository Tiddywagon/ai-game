class_name InventoryGrid
extends RefCounted
## A grid of cells holding ItemInstances (DESIGN.md §7): the stash, pockets, or the inside of a rig,
## backpack or secure container. Items take their footprint (turned or not) and can't overlap. Pure
## data: the UI (InventoryGridView) draws it and asks it what's allowed.
##
## What may go in, besides fitting: the stash takes anything; a secure container takes nothing that
## has its own grid; any other container takes containers only when they're empty; nothing goes inside
## itself.
##
## Stacks stay within their max stack: add(), load_array() and sort() split a bigger one (rounds out of a
## magazine) into full stacks, so no round is ever cut off.
##
## The stash grows (resize(): only bigger, every item stays put) and repacks itself in an order (sort()).

## Something was added, moved, removed, restacked or the grid grew.
signal changed

## Orders sort() repacks in (DESIGN.md §8), with their names.
enum SortMode { TYPE, RARITY, VALUE, NAME, SIZE }
const SORT_NAMES: Array[String] = ["Type", "Rarity", "Value", "Name", "Size"]

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


## The grid holding `item`: this one, or one inside an item here (at any depth); null if none.
func find_holder(item: ItemInstance) -> InventoryGrid:
	if item in items:
		return self
	for each in items:
		if each.contents:
			var holder := each.contents.find_holder(item)
			if holder:
				return holder
	return null


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


## Adds `item` wherever it fits, topping up existing stacks of the same item first. A stack over its max
## stack goes in as full stacks (no stack in a grid is ever over). Returns true if it all went in;
## otherwise `item.count` is what's left over.
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
	while item.data.max_stack > 1 and item.count > item.data.max_stack:
		var free := find_space(item)
		if free.is_empty():
			break
		var full := item.copy_stack(item.data.max_stack)
		item.count -= full.count
		place(full, free.cell, free.rotated)
		merged = true
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


## Removes up to `amount` of item `id`. Returns how many were taken.
func take(id: String, amount: int) -> int:
	var taken := 0
	for piece in take_pieces(id, amount):
		taken += piece.count
	return taken


## Removes up to `amount` of item `id` and returns what was taken, one piece per stack it came from,
## each keeping its Found-in-Raid status. Uses stacks that aren't found in raid first (FIR items are
## worth keeping for quests), then the smallest.
func take_pieces(id: String, amount: int) -> Array[ItemInstance]:
	var stacks := items.filter(func(item: ItemInstance) -> bool: return item.data.id == id)
	stacks.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool:
		return a.count < b.count if a.fir == b.fir else not a.fir)
	var pieces: Array[ItemInstance] = []
	var taken := 0
	for stack: ItemInstance in stacks:
		if taken >= amount:
			break
		var used := mini(stack.count, amount - taken)
		taken += used
		if used == stack.count:
			items.erase(stack)
			pieces.append(stack)
		else:
			stack.count -= used
			pieces.append(stack.split_off(used))
	if taken > 0:
		changed.emit()
	return pieces


## True if all of `item` would fit: on top of matching stacks and in free space.
func has_room_for(item: ItemInstance) -> bool:
	if not accepts(item):
		return false
	var room := 0
	for other in items:
		if other.can_stack_with(item):
			room += other.data.max_stack - other.count
	return room >= item.count or not find_space(item).is_empty()


## True if all of `new_items` would fit together, the way add() would put them one after another: on
## top of matching stacks (theirs and each other's) first, then in free space, row by row, unturned
## first (a barter's several rewards). Items in `freed` count as gone (what the barter takes).
func has_room_for_all(new_items: Array[ItemInstance], freed: Array[ItemInstance] = []) -> bool:
	var taken: Array[Rect2i] = []
	var stacks: Array = []  # [ItemInstance like it, room left]
	for item in items:
		if not item in freed:
			taken.append(Rect2i(item.cell, item.footprint()))
			stacks.append([item, item.data.max_stack - item.count])
	for item in new_items:
		if not accepts(item):
			return false
		var left := item.count
		for stack: Array in stacks:
			if left > 0 and (stack[0] as ItemInstance).can_stack_with(item):
				var moved := mini(left, int(stack[1]))
				stack[1] = int(stack[1]) - moved
				left -= moved
		if left == 0:
			continue
		var spot := Rect2i()
		for turned in ([false, true] if item.data.size.x != item.data.size.y else [false]):
			spot = _free_area(taken, item.footprint_if(turned))
			if spot.size != Vector2i.ZERO:
				break
		if spot.size == Vector2i.ZERO:
			return false
		taken.append(spot)
		stacks.append([item, item.data.max_stack - left])
	return true


## The first area of `footprint` that overlaps none of `taken`, row by row (zero-sized if none).
func _free_area(taken: Array[Rect2i], footprint: Vector2i) -> Rect2i:
	for y in size.y - footprint.y + 1:
		for x in size.x - footprint.x + 1:
			var area := Rect2i(Vector2i(x, y), footprint)
			if not taken.any(func(other: Rect2i) -> bool: return other.intersects(area)):
				return area
	return Rect2i()


## Grows the grid to `new_size` (the stash, when the hideout's Stash station goes up a level). Only
## grows: every item stays where it is. False (nothing changes) if `new_size` is smaller either way.
func resize(new_size: Vector2i) -> bool:
	if new_size.x < size.x or new_size.y < size.y:
		return false
	if new_size != size:
		size = new_size
		changed.emit()
	return true


## Repacks the grid in `mode` order (SortMode): Type (category in ItemData.CATEGORY_ORDER, then rarity,
## rarest first, then name), Rarity (rarest first), Value (ItemInstance.value(), dearest first), Name,
## or Size (biggest first). Stacks of the same item with the same found-in-raid status merge first into
## full stacks (_restack(): never fewer rounds than before); then each item goes in the first free spot,
## row by row, turned if that puts it sooner. It's worked out on a copy of the layout and only applied
## when everything fits: false, and nothing changed, if it doesn't. Items keep what's inside them.
func sort(mode: int) -> bool:
	var restack := _restack()
	var counts: Dictionary = restack.counts
	var pieces: Array[ItemInstance] = []
	for item in items:
		if int(counts.get(item, item.count)) > 0:
			pieces.append(item)
	pieces.append_array(restack.extra)
	var keys := {}
	for i in pieces.size():
		keys[pieces[i]] = _sort_key(pieces[i], mode, int(counts.get(pieces[i], pieces[i].count))) + [i]
	pieces.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return _key_less(keys[a], keys[b]))
	var spots := _pack(pieces)
	if spots.size() != pieces.size():
		return false
	for item: ItemInstance in counts:
		item.count = int(counts[item])
	for i in pieces.size():
		pieces[i].cell = spots[i][0]
		pieces[i].rotated = spots[i][1]
	items.assign(pieces)
	changed.emit()
	return true


## How sort() restacks: {"counts": {item: new count}, "extra": [new stacks, not in the grid yet]}. Each
## group of stacks that can go together (same item, same status and uses left) fills up to full stacks,
## fullest first (0 for one that's emptied). A group holding more than its stacks can carry (one over its
## max stack: rounds out of a magazine, or a save from an older build) gets new full stacks for the rest,
## so its total never changes.
func _restack() -> Dictionary:
	var groups := {}
	for item in items:
		if item.data.max_stack > 1 and not item.hidden:
			var key := "%s|%s|%s|%s|%.3f" % [item.data.id, item.fir, item.fir_pending, item.brought_in, item.charges]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(item)
	var counts := {}
	var extra: Array[ItemInstance] = []
	for group: Array in groups.values():
		var full: int = (group[0] as ItemInstance).data.max_stack
		var left := 0
		for item: ItemInstance in group:
			left += item.count
		if group.size() < 2 and left <= full:
			continue
		group.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.count > b.count)
		for item: ItemInstance in group:
			var kept := mini(left, full)
			counts[item] = kept
			left -= kept
		while left > 0:
			var piece := (group[0] as ItemInstance).copy_stack(mini(left, full))
			extra.append(piece)
			left -= piece.count
	return {"counts": counts, "extra": extra}


## What sort() orders `item` by in `mode` (smallest first), with `count` the stack after merging.
static func _sort_key(item: ItemInstance, mode: int, count: int) -> Array:
	var data := item.data
	var type := ItemData.CATEGORY_ORDER.find(data.category)
	var name := data.display_name.to_lower()
	match mode:
		SortMode.RARITY:
			return [-data.rarity, type, name, -count]
		SortMode.VALUE:
			var value := roundi(float(item.value()) / maxi(item.count, 1) * count) if count != item.count else item.value()
			return [-value, type, name, -count]
		SortMode.NAME:
			return [name, -data.rarity, -count]
		SortMode.SIZE:
			return [-data.size.x * data.size.y, -maxi(data.size.x, data.size.y), type, name, -count]
	return [type, -data.rarity, name, -count]


static func _key_less(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()


## Where `pieces` go, in order, packed into an empty grid this size: [[cell, turned], ...], each in the
## first free spot row by row, turned when that spot comes sooner. Stops short if one doesn't fit.
func _pack(pieces: Array[ItemInstance]) -> Array:
	var taken := PackedByteArray()
	taken.resize(size.x * size.y)
	var first_free := 0
	var spots := []
	for item in pieces:
		var best := -1
		var best_turned := false
		for turned in ([false, true] if item.data.size.x != item.data.size.y else [false]):
			var at := _first_fit(taken, first_free, item.footprint_if(turned), best)
			if at >= 0 and (best < 0 or at < best):
				best = at
				best_turned = turned
		if best < 0:
			return spots
		var footprint := item.footprint_if(best_turned)
		var cell := Vector2i(best % size.x, floori(float(best) / size.x))
		for y in footprint.y:
			for x in footprint.x:
				taken[(cell.y + y) * size.x + cell.x + x] = 1
		spots.append([cell, best_turned])
		while first_free < taken.size() and taken[first_free]:
			first_free += 1
	return spots


## The first cell index from `start` where `footprint` fits in `taken` (before `before`, if that's 0 or
## more), or -1.
func _first_fit(taken: PackedByteArray, start: int, footprint: Vector2i, before: int) -> int:
	var end := taken.size() if before < 0 else before
	for index in range(start, end):
		if taken[index]:
			continue
		var x := index % size.x
		var y := floori(float(index) / size.x)
		if y + footprint.y > size.y:
			return -1
		if x + footprint.x > size.x:
			continue
		var free := true
		for dy in footprint.y:
			for dx in footprint.x:
				if taken[(y + dy) * size.x + x + dx]:
					free = false
					break
			if not free:
				break
		if free:
			return index
	return -1


## Everything in the grid, including what's inside containers and loaded in guns, at any depth.
func all_items() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for item in items:
		result.append_array(item.all_items())
	return result


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


## Cells in the grid.
func cell_count() -> int:
	return size.x * size.y


## Cells its items cover (what's inside a container in it doesn't count again).
func used_cells() -> int:
	var total := 0
	for item in items:
		var footprint := item.footprint()
		total += footprint.x * footprint.y
	return total


func to_array() -> Array:
	return items.map(func(item: ItemInstance) -> Dictionary: return item.to_dict())


## Fills the grid from to_array() data. Items whose saved spot is taken go wherever they fit. A stack
## saved over its max stack (rounds an older build unloaded as one stack) comes back as full stacks: a
## full one in its saved spot, the rest wherever they fit once everything else is back; what still has
## no room stays on the saved stack (over its max, but never lost).
func load_array(entries: Array) -> void:
	var rests := []  # [the saved stack, a stack split off it]
	for entry in entries:
		if not entry is Dictionary:
			continue
		var item := ItemInstance.from_dict(entry)
		if item == null:
			continue
		for rest in item.split_excess():
			rests.append([item, rest])
		if not place(item, item.cell, item.rotated) and not add(item):
			push_warning("InventoryGrid: no room for %s, dropped" % item.data.id)
	for pair: Array in rests:
		var saved: ItemInstance = pair[0]
		var rest: ItemInstance = pair[1]
		if add(rest):
			continue
		if saved in items:
			saved.count += rest.count
		else:
			push_warning("InventoryGrid: no room for %s, dropped" % rest.data.id)
