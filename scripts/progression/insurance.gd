class_name Insurance
extends RefCounted
## Insurance (DESIGN.md §2): before a raid, insure your gear for a share of its value
## (RaidConfig.insurance_rate, at least insurance_min_price each). If you die or go missing, insured
## items you lost come back to the stash after the raid: a gun or helmet with the parts fitted to it,
## a rig or backpack empty (insure what's inside separately), no rounds. Returned items aren't found in
## raid and aren't insured any more. What doesn't fit in the stash waits in GameState.insurance_pending
## and is delivered when there's room (deliver_pending()).
##
## Insurable: guns, weapon parts, armor, helmets, rigs, backpacks and melee weapons. Not ammo, meds,
## food, barter goods, valuables, keys or the secure container (always kept anyway).

const CONFIG: RaidConfig = preload("res://data/config/raid.tres")
const INSURABLE: Array[ItemData.Category] = [ItemData.Category.WEAPON, ItemData.Category.ATTACHMENT,
	ItemData.Category.ARMOR, ItemData.Category.HELMET, ItemData.Category.RIG, ItemData.Category.BACKPACK,
	ItemData.Category.MELEE]


static func is_insurable(item: ItemInstance) -> bool:
	return item.data.category in INSURABLE and not item.data.stats.get("secure", false)


## What insuring `item` costs: its value with its parts fitted (not what's inside it or loaded in it).
static func price(item: ItemInstance) -> int:
	var value := item.data.base_value * item.count
	for part in WeaponMods.installed(item):
		value += part.data.base_value
	return maxi(ceili(value * CONFIG.insurance_rate / 100.0) * 100, CONFIG.insurance_min_price)


## Items on `inventory` that could be insured and aren't: equipment (but the secure container) and
## anything in the pockets, rig and backpack, at any depth; parts fitted to a gun or helmet go with it.
static func uninsured(inventory: Inventory) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for slot: String in inventory.equipment:
		if slot != "secure" and inventory.equipment[slot]:
			_collect(inventory.equipment[slot], result)
	for item in inventory.pockets.items:
		_collect(item, result)
	return result


static func _collect(item: ItemInstance, into: Array[ItemInstance]) -> void:
	if is_insurable(item) and not item.insured:
		into.append(item)
	if item.contents and item.contents.kind != &"secure":
		for inside in item.contents.items:
			_collect(inside, into)


static func total_price(items: Array) -> int:
	var total := 0
	for item: ItemInstance in items:
		total += price(item)
	return total


## Insures `items`, paying from GameState.roubles. "" on success, else why not.
static func insure(items: Array) -> String:
	var cost := total_price(items)
	if items.is_empty():
		return "Nothing to insure"
	if GameState.roubles < cost:
		return "Not enough roubles: %s needed" % UiFormat.money(cost)
	GameState.roubles -= cost
	for item: ItemInstance in items:
		item.insured = true
	return ""


## What comes back for insured items among `lost` (everything the character lost, at any depth, as
## from Inventory.all_items()): a copy of each insured item, emptied, its rounds gone, with its parts
## but not insured any more and not found in raid. Parts fitted to a returned item come with it.
static func returns_for(lost: Array[ItemInstance]) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	var covered := {}
	for item in lost:
		if not item.insured or covered.has(item):
			continue
		for part in WeaponMods.installed(item):
			covered[part] = true
		var copy := ItemInstance.from_dict(item.to_dict())
		if copy == null:
			continue
		copy.magazine.clear()
		if copy.contents:
			for inside in copy.contents.items.duplicate():
				copy.contents.remove(inside)
		FoundInRaid.set_found(copy, false)
		for each in copy.all_items():
			each.insured = false
		result.append(copy)
	return result


## Puts returned items in the stash; what doesn't fit waits in GameState.insurance_pending. Returns
## how many went into the stash.
static func deliver(items: Array[ItemInstance]) -> int:
	var delivered := 0
	for item in items:
		if GameState.stash.add(item):
			delivered += 1
		else:
			GameState.insurance_pending.append(item.to_dict())
	return delivered


## Delivers what's waiting in GameState.insurance_pending, as far as the stash has room. Returns how
## many items arrived.
static func deliver_pending() -> int:
	var waiting := GameState.insurance_pending.duplicate()
	GameState.insurance_pending.clear()
	var items: Array[ItemInstance] = []
	for entry: Dictionary in waiting:
		var item := ItemInstance.from_dict(entry)
		if item:
			items.append(item)
	return deliver(items)
