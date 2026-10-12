class_name LootTable
extends Resource
## Rolls loot (DESIGN.md §6.2): first a rarity by weight, then an item of that rarity from ItemDB.
## The base weights live here (data/loot_tables/default.tres); a LootContainer (the kind of spot: a
## jacket, a weapon box, a safe) and the MapInfo (Labs) multiply them, so high-tier spots drop rarer
## loot. Pass a RandomNumberGenerator to get repeatable results.

const RARITY_COUNT := 6

@export var display_name := "Default"
## Weight of each rarity, indexed by ItemData.Rarity. They don't have to add up to 100.
@export var rarity_weights: PackedFloat32Array = [55.0, 25.0, 12.0, 5.0, 2.5, 0.5]


## Weight of each rarity in `container` on `map` (either can be null): base × container × map.
## With `categories`, rarities that have no lootable item in them get 0.
func weights(container: LootContainer = null, map: MapInfo = null, categories: Array = []) -> PackedFloat32Array:
	var result := rarity_weights.duplicate()
	for rarity in RARITY_COUNT:
		if container:
			result[rarity] *= _multiplier(container.rarity_multipliers, rarity)
		if map:
			result[rarity] *= _multiplier(map.loot_multipliers, rarity)
		if not categories.is_empty() and ItemDB.lootable(rarity, categories).is_empty():
			result[rarity] = 0.0
	return result


## Chance of each rarity (0-1) for a single roll, as weights() but adding up to 1.
func chances(container: LootContainer = null, map: MapInfo = null, categories: Array = []) -> PackedFloat32Array:
	var result := weights(container, map, categories)
	var total := 0.0
	for weight in result:
		total += weight
	for rarity in RARITY_COUNT:
		result[rarity] = result[rarity] / total if total > 0.0 else 0.0
	return result


## Rolls a rarity (ItemData.Rarity) for `container` on `map`.
func roll_rarity(rng: RandomNumberGenerator, container: LootContainer = null, map: MapInfo = null, categories: Array = []) -> int:
	return _pick(rng, weights(container, map, categories))


## Rolls one item: a rarity, then an item of that rarity the container allows (weighted by each
## item's loot_weight). Null if nothing can drop.
func roll_item(rng: RandomNumberGenerator, container: LootContainer = null, map: MapInfo = null) -> ItemData:
	var categories: Array = container.categories if container else []
	var rarity := roll_rarity(rng, container, map, categories)
	if rarity < 0:
		return null
	var candidates := ItemDB.lootable(rarity, categories)
	var item_weights := PackedFloat32Array()
	for item in candidates:
		item_weights.append(item.loot_weight)
	var index := _pick(rng, item_weights)
	return candidates[index] if index >= 0 else null


## Fills one container: between its item_count.x and item_count.y items, each {"id", "count"}.
## Stackable items (ammo) come as a partial stack.
func roll_container(rng: RandomNumberGenerator, container: LootContainer, map: MapInfo = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in rng.randi_range(container.item_count.x, container.item_count.y):
		var item := roll_item(rng, container, map)
		if item:
			var count := 1
			if item.max_stack > 1:
				count = rng.randi_range(maxi(item.max_stack / 5, 1), maxi(item.max_stack / 2, 1))
			result.append({"id": item.id, "count": count})
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
	var roll := rng.randf() * total
	for index in weights.size():
		roll -= weights[index]
		if roll < 0.0:
			return index
	return weights.size() - 1
