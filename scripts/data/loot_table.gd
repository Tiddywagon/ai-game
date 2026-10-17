class_name LootTable
extends Resource
## Rolls loot for one kind of spot (DESIGN.md §6.2). Every container type has its own table in
## data/loot_tables/ (crate.tres, medical_bag.tres, safe.tres...), plus loose_loot.tres for items on
## the ground and default.tres, the plain base table.
##
## A roll picks a rarity by weight: the base weights × this table's rarity multipliers × the map's (Lab Zero
## doubles Epic and Legendary). Then it picks an item of that rarity the table allows, weighted by each
## item's loot_weight × the table's item_weights. A table allows every item in its item list, of its
## categories, of its groups, with any of its tags or of its types (all of them together; anything if
## it has none of these): a toolbox rolls the Hardware and Tools groups, a safe anything tagged
## "valuable" (DESIGN.md §6.5). Rarities with nothing allowed in them get no weight, so the others
## share their chance. Pass a RandomNumberGenerator for repeatable results. Rolled inside a point of
## interest (DESIGN.md §5.2), items matching its focus tags weigh PoiConfig.focus_weight times more.

const RARITY_COUNT := 6

@export var display_name := "Default"
## Base weight of each rarity, indexed by ItemData.Rarity. They don't have to add up to 100.
@export var rarity_weights: PackedFloat32Array = [55.0, 25.0, 12.0, 5.0, 2.5, 0.5]
## This table's boost (or cut) per rarity: a safe drops rarer loot than a crate. Missing entries are 1.
@export var rarity_multipliers: PackedFloat32Array = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
## Item categories it can roll (ItemData.Category).
@export var categories: Array[ItemData.Category] = []
## These item ids: a medical bag holds bandages, medkits...
@export var items: PackedStringArray = []
## Items of these groups (ItemData.group, DESIGN.md §6.5): a toolbox rolls "Hardware" and "Tools".
@export var groups: PackedStringArray = []
## Items with any of these tags (ItemData.tags): a safe rolls anything "valuable".
@export var tags: PackedStringArray = []
## Weight × for the items only `groups` or `tags` bring in (a weapon box's valuables are a side line).
@export_range(0.0, 10.0, 0.05) var tag_weight := 1.0
## Items of these types (their "type" stat): a safe also holds stims ("stim").
@export var types: PackedStringArray = []
## Weight × for the items only `types` brings in (a safe's stims are a side line: 0.3).
@export_range(0.0, 10.0, 0.05) var type_weight := 1.0
## Extra weight for some items among their rarity, by id (default 1): {"intel_folder": 2.0}.
@export var item_weights: Dictionary = {}
## How many items one roll() gives: a random number from x to y.
@export var item_count := Vector2i(1, 1)


## Items of `rarity` this table can roll (loot_weight above 0).
func candidates(rarity: int) -> Array[ItemData]:
	var anything := categories.is_empty() and items.is_empty() and groups.is_empty() and tags.is_empty() and types.is_empty()
	return ItemDB.lootable(rarity, []).filter(func(item: ItemData) -> bool: return anything or _source(item) != "")


## Why this table holds `item`: "list" (its item list or categories), "tag" (only its groups or tags),
## "type" (only its types) or "" (it doesn't).
func _source(item: ItemData) -> String:
	if item.id in items or item.category in categories:
		return "list"
	if item.group in groups:
		return "tag"
	for tag in tags:
		if item.has_tag(tag):
			return "tag"
	if str(item.stats.get("type", "")) in types:
		return "type"
	return ""


## Weight of each rarity on `map` (null for no map): base × table × map × `boost` (a LootZone's: a
## locked office, a lab), 0 where nothing can drop.
func weights(map: MapInfo = null, boost := PackedFloat32Array()) -> PackedFloat32Array:
	var result := rarity_weights.duplicate()
	for rarity in RARITY_COUNT:
		result[rarity] *= _multiplier(rarity_multipliers, rarity)
		if map:
			result[rarity] *= _multiplier(map.loot_multipliers, rarity)
		result[rarity] *= _multiplier(boost, rarity)
		if candidates(rarity).is_empty():
			result[rarity] = 0.0
	return result


## Chance of each rarity (0-1) for a single roll, as weights() but adding up to 1.
func chances(map: MapInfo = null, boost := PackedFloat32Array()) -> PackedFloat32Array:
	var result := weights(map, boost)
	var total := 0.0
	for weight in result:
		total += weight
	for rarity in RARITY_COUNT:
		result[rarity] = result[rarity] / total if total > 0.0 else 0.0
	return result


## Rolls a rarity (ItemData.Rarity), or -1 if nothing can drop.
func roll_rarity(rng: RandomNumberGenerator, map: MapInfo = null, boost := PackedFloat32Array()) -> int:
	return _pick(rng, weights(map, boost))


## Rolls one item: a rarity, then an item of that rarity (those matching `focus`, a POI's focus tags,
## weigh more). Null if nothing can drop.
func roll_item(rng: RandomNumberGenerator, map: MapInfo = null, boost := PackedFloat32Array(), focus: Array = []) -> ItemData:
	var rarity := roll_rarity(rng, map, boost)
	if rarity < 0:
		return null
	var pool := candidates(rarity)
	var pool_weights := PackedFloat32Array()
	for item in pool:
		var source := _source(item)
		var side_line := tag_weight if source == "tag" else type_weight if source == "type" else 1.0
		if not focus.is_empty() and PoiTable.matches_focus(item, focus):
			side_line *= PoiTable.CONFIG.focus_weight
		pool_weights.append(item.loot_weight * float(item_weights.get(item.id, 1.0)) * side_line)
	var index := _pick(rng, pool_weights)
	return pool[index] if index >= 0 else null


## Fills one container: item_count.x to item_count.y items, each {"id", "count"}. Stackable items
## (ammo) come as a partial stack: a fifth to a half of a full one.
func roll(rng: RandomNumberGenerator, map: MapInfo = null, boost := PackedFloat32Array(), focus: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in rng.randi_range(item_count.x, item_count.y):
		var item := roll_item(rng, map, boost, focus)
		if item:
			var count := 1
			if item.max_stack > 1:
				count = rng.randi_range(maxi(item.max_stack / 5, 1), maxi(item.max_stack / 2, 1))
			result.append({"id": item.id, "count": count})
	return result


## roll() as ready-made items: guns come loaded with a matching round, somewhat worn (60-95
## durability). Null entries are skipped.
func roll_items(rng: RandomNumberGenerator, map: MapInfo = null, boost := PackedFloat32Array(), focus: Array = []) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for entry in roll(rng, map, boost, focus):
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


## Two sets of rarity multipliers multiplied together (an empty set counts as all 1).
static func combine_boosts(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	if a.is_empty():
		return b.duplicate()
	if b.is_empty():
		return a.duplicate()
	var result := PackedFloat32Array()
	for rarity in RARITY_COUNT:
		result.append(_multiplier(a, rarity) * _multiplier(b, rarity))
	return result


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
