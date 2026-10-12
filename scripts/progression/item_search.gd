class_name ItemSearch
extends RefCounted
## Finds and takes items you own out of raid, for quest hand-ins, hideout upgrades, crafts and
## barters (DESIGN.md §9–11): everything in the stash and on your character (equipment, pockets and
## inside containers at any depth). Containers with something in them never count, so nothing inside
## is lost. Requirements marked found in raid only take items with the FIR checkmark; the others take
## items without it first, so FIR items are kept for whatever needs them.


## How many of item `id` you have (only found-in-raid ones if `fir_only`).
static func count(id: String, fir_only: bool) -> int:
	var total := 0
	for found in _matches(id, fir_only):
		total += (found.item as ItemInstance).count
	return total


## True if you have everything in `requirements`. Requirements for the same item add up (found-in-raid
## ones first).
static func can_afford(requirements: Array[Requirement]) -> bool:
	var needed := {}
	for requirement in requirements:
		var entry: Dictionary = needed.get_or_add(requirement.item_id, {"fir": 0, "any": 0})
		entry["fir" if requirement.fir else "any"] += requirement.count
	for id: String in needed:
		var entry: Dictionary = needed[id]
		if count(id, true) < entry.fir or count(id, false) < entry.fir + entry.any:
			return false
	return true


## Takes everything in `requirements`. Takes nothing and returns false if something is missing.
static func pay(requirements: Array[Requirement]) -> bool:
	if not can_afford(requirements):
		return false
	var ordered := requirements.duplicate()
	ordered.sort_custom(func(a: Requirement, b: Requirement) -> bool: return a.fir and not b.fir)
	for requirement: Requirement in ordered:
		take(requirement.item_id, requirement.count, requirement.fir)
	return true


## Takes up to `amount` of item `id` (only found-in-raid ones if `fir_only`). Returns how many.
static func take(id: String, amount: int, fir_only: bool) -> int:
	var found := _matches(id, fir_only)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first: ItemInstance = a.item
		var second: ItemInstance = b.item
		return first.count < second.count if first.fir == second.fir else not first.fir)
	var taken := 0
	for entry in found:
		if taken >= amount:
			break
		var item: ItemInstance = entry.item
		var used := mini(item.count, amount - taken)
		taken += used
		if used < item.count:
			item.count -= used
			if entry.grid:
				(entry.grid as InventoryGrid).changed.emit()
			else:
				GameState.inventory.changed.emit()
		elif entry.grid:
			(entry.grid as InventoryGrid).remove(item)
		else:
			GameState.inventory.unequip(entry.slot)
	return taken


## [{"item": ItemInstance, "grid": InventoryGrid or null, "slot": equipment slot or ""}] for every
## stack of `id` that counts.
static func _matches(id: String, fir_only: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var wanted := func(item: ItemInstance) -> bool:
		return item.data.id == id and item.is_empty_container() and (item.fir or not fir_only)
	var grids: Array[InventoryGrid] = [GameState.stash, GameState.inventory.pockets]
	var inventory := GameState.inventory
	for slot: String in inventory.equipment:
		var equipped: ItemInstance = inventory.equipment[slot]
		if equipped == null:
			continue
		if wanted.call(equipped):
			result.append({"item": equipped, "grid": null, "slot": slot})
		if equipped.contents:
			grids.append(equipped.contents)
	while not grids.is_empty():
		var grid: InventoryGrid = grids.pop_back()
		for item in grid.items:
			if wanted.call(item):
				result.append({"item": item, "grid": grid, "slot": ""})
			if item.contents:
				grids.append(item.contents)
	return result
