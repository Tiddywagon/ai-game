class_name ItemSearch
extends RefCounted
## Finds and takes items you own out of raid, for quest hand-ins, hideout upgrades, crafts and
## barters (DESIGN.md §9–11): everything in the stash and on your character (equipment, pockets and
## inside containers at any depth). With `barter` (barters are stricter): only the stash and the
## containers in it, and only whole items, never food, drink, meds or a key with some of it used up.
## Containers with something in them never count, so nothing inside is lost. Requirements marked found
## in raid only take items with the FIR checkmark; the others take items without it first, so FIR items
## are kept for whatever needs them.


## How many of item `id` you have (only found-in-raid ones if `fir_only`; only whole ones in the stash
## if `barter`).
static func count(id: String, fir_only: bool, barter := false) -> int:
	var total := 0
	for found in _matches(id, fir_only, barter):
		total += (found.item as ItemInstance).count
	return total


## True if you have everything in `requirements` (whole, in the stash if `barter`). Requirements for the
## same item add up (found-in-raid ones first).
static func can_afford(requirements: Array[Requirement], barter := false) -> bool:
	var needed := {}
	for requirement in requirements:
		var entry: Dictionary = needed.get_or_add(requirement.item_id, {"fir": 0, "any": 0})
		entry["fir" if requirement.fir else "any"] += requirement.count
	for id: String in needed:
		var entry: Dictionary = needed[id]
		if count(id, true, barter) < entry.fir or count(id, false, barter) < entry.fir + entry.any:
			return false
	return true


## Takes everything in `requirements` (whole ones from the stash if `barter`). Takes nothing and returns
## false if something is missing.
static func pay(requirements: Array[Requirement], barter := false) -> bool:
	if not can_afford(requirements, barter):
		return false
	var ordered := requirements.duplicate()
	ordered.sort_custom(func(a: Requirement, b: Requirement) -> bool: return a.fir and not b.fir)
	for requirement: Requirement in ordered:
		take(requirement.item_id, requirement.count, requirement.fir, barter)
	return true


## The stacks pay() would use up completely taking `requirements` (whole ones from the stash if
## `barter`): what a barter frees room by (Trading). Partly used stacks aren't in it.
static func used_up(requirements: Array[Requirement], barter := false) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	var left := {}
	var ordered := requirements.duplicate()
	ordered.sort_custom(func(a: Requirement, b: Requirement) -> bool: return a.fir and not b.fir)
	for requirement: Requirement in ordered:
		var found := _matches(requirement.item_id, requirement.fir, barter)
		found.sort_custom(_taken_first)
		var amount := requirement.count
		for entry in found:
			var item: ItemInstance = entry.item
			var have := int(left.get(item, item.count))
			if amount <= 0 or have <= 0:
				continue
			var used := mini(have, amount)
			amount -= used
			left[item] = have - used
			if have == used:
				result.append(item)
	return result


## Takes up to `amount` of item `id` (only found-in-raid ones if `fir_only`; only whole ones from the
## stash if `barter`). Returns how many.
static func take(id: String, amount: int, fir_only: bool, barter := false) -> int:
	var found := _matches(id, fir_only, barter)
	found.sort_custom(_taken_first)
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


## The order take() uses stacks in: not found in raid first, then the smallest.
static func _taken_first(a: Dictionary, b: Dictionary) -> bool:
	var first: ItemInstance = a.item
	var second: ItemInstance = b.item
	return first.count < second.count if first.fir == second.fir else not first.fir


## [{"item": ItemInstance, "grid": InventoryGrid or null, "slot": equipment slot or ""}] for every
## stack of `id` that counts.
static func _matches(id: String, fir_only: bool, barter := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var wanted := func(item: ItemInstance) -> bool:
		return item.data.id == id and item.is_empty_container() and (item.fir or not fir_only) and not (barter and item.is_part_used())
	var grids: Array[InventoryGrid] = [GameState.stash]
	var inventory := GameState.inventory
	if not barter:
		grids.append(inventory.pockets)
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
