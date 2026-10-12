class_name LootTable
extends Resource
## Rolls loot for one kind of spot (DESIGN.md §6.2). Every container type has its own table in
## data/loot_tables/ (crate.tres, medical_bag.tres, safe.tres...), plus loose_loot.tres for items on
## the ground and default.tres, the plain base table.
##
## A roll picks a rarity by weight: the base weights × this table's rarity multipliers × the map's (Labs
## doubles Epic and Legendary). Then it picks an item of that rarity the table allows (its item list, or
## its categories, or anything), weighted by each item's loot_weight × the table's item_weights.
## Rarities with nothing allowed in them get no weight, so the others share their chance. Pass a
## RandomNumberGenerator for repeatable results.

const RARITY_COUNT := 6

@export var display_name := "Default"
## Base weight of each rarity, indexed by ItemData.Rarity. They don't have to add up to 100.
@export var rarity_weights: PackedFloat32Array = [55.0, 25.0, 12.0, 5.0, 2.5, 0.5]
## This table's boost (or cut) per rarity: a safe drops rarer loot than a crate. Missing entries are 1.
@export var rarity_multipliers: PackedFloat32Array = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
## Item categories it can roll (ItemData.Category). Empty: any category.
@export var categories: Array[ItemData.Category] = []
## Only these item ids, when not empty (instead of the categories): a toolbox holds tools.
@export var items: PackedStringArray = []
## Extra weight for some items among their rarity, by id (default 1): {"intel_folder": 2.0}.
@export var item_weights: Dictionary = {}
## How many items one roll() gives: a random number from x to y.
@export var item_count := Vector2i(1, 1)


## Items of `rarity` this table can roll (loot_weight above 0).
func candidates(rarity: int) -> Array[ItemData]:
	var result := ItemDB.lootable(rarity, categories if items.is_empty() else [])
	if not items.is_empty():
		result = result.filter(func(item: ItemData) -> bool: return item.id in items)
	return result


## Weight of each rarity on `map` (null for no map): base × table × map, 0 where nothing can drop.
func weights(map: MapInfo = null) -> PackedFloat32Array:
	var result := rarity_weights.duplicate()
	for rarity in RARITY_COUNT:
		result[rarity] *= _multiplier(rarity_multipliers, rarity)
		if map:
			result[rarity] *= _multiplier(map.loot_multipliers, rarity)
		if candidates(rarity).is_empty():
			result[rarity] = 0.0
	return result


## Chance of each rarity (0-1) for a single roll, as weights() but adding up to 1.
func chances(map: MapInfo = null) -> PackedFloat32Array:
	var result := weights(map)
	var total := 0.0
	for weight in result:
		total += weight
	for rarity in RARITY_COUNT:
		result[rarity] = result[rarity] / total if total > 0.0 else 0.0
	return result


## Rolls a rarity (ItemData.Rarity), or -1 if nothing can drop.
func roll_rarity(rng: RandomNumberGenerator, map: MapInfo = null) -> int:
	return _pick(rng, weights(map))


## Rolls one item: a rarity, then an item of that rarity. Null if nothing can drop.
func roll_item(rng: RandomNumberGenerator, map: MapInfo = null) -> ItemData:
	var rarity := roll_rarity(rng, map)
	if rarity < 0:
		return null
	var pool := candidates(rarity)
	var pool_weights := PackedFloat32Array()
	for item in pool:
		pool_weights.append(item.loot_weight * float(item_weights.get(item.id, 1.0)))
	var index := _pick(rng, pool_weights)
	return pool[index] if index >= 0 else null


## Fills one container: item_count.x to item_count.y items, each {"id", "count"}. Stackable items
## (ammo) come as a partial stack: a fifth to a half of a full one.
func roll(rng: RandomNumberGenerator, map: MapInfo = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in rng.randi_range(item_count.x, item_count.y):
		var item := roll_item(rng, map)
		if item:
			var count := 1
			if item.max_stack > 1:
				count = rng.randi_range(maxi(item.max_stack / 5, 1), maxi(item.max_stack / 2, 1))
			result.append({"id": item.id, "count": count})
	return result


## roll() as ready-made items: guns come loaded with a matching round, somewhat worn (60-95
## durability). Null entries are skipped.
func roll_items(rng: RandomNumberGenerator, map: MapInfo = null) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for entry in roll(rng, map):
		var item := ItemInstance.create(entry.id, entry.count)
		if item and item.data.weapon:
			item = Inventory.loaded_gun(entry.id, ammo_for(item.data.weapon.caliber), rng.randf_range(60.0, 95.0))
		if item:
			result.append(item)
	return result


## The everyday round for `caliber` (the commonest, least penetrating), or "" if there's none.
static func ammo_for(caliber: String) -> String:
	var rounds := ItemDB.ammo_of(caliber)
	return rounds[0].id if not rounds.is_empty() else ""


static func _multiplier(multipliers: PackedFloat32Array, rarity: int) -> float:
	return multipliers[rarity] if rarity < multipliers.size() else 1.0


## Index picked at random in proportion to `weights`, or -1 if they're all 0.
static func _pick(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return -1
	var roll_at := rng.randf() * total
	for index in weights.size():
		roll_at -= weights[index]
		if roll_at < 0.0:
			return index
	return weights.size() - 1
