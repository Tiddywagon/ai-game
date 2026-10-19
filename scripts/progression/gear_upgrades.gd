class_name GearUpgrades
extends RefCounted
## Gear upgrades (DESIGN.md §12.2): a trader (Stitch) or the hideout Workbench raises a piece of gear's
## level (ItemInstance.upgrade_level, +1 to +5) for roubles and barter items. The highest level depends
## on the item's rarity; how far a source can take it on its loyalty level or the Workbench's level.
## Armor (vests, armored rigs, helmets, face shields) gets more durability, lets less blunt damage
## through and (helmets, face shields) deflects more; rigs and backpacks get lighter and roomier;
## headsets hear further. Everything is tuned in data/config/gear_upgrades.json.

const CONFIG_PATH := "res://data/config/gear_upgrades.json"
const WORKBENCH := "workbench"

static var _config := {}


static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {}
		if _config.is_empty():
			push_error("GearUpgrades: %s isn't valid JSON" % CONFIG_PATH)
	return _config


# --- What can be upgraded ----------------------------------------------------------------------

## The upgrade group of `data` ("armor", "carry", "electronics"), or "" if it can't be upgraded.
## Armored rigs are armor (their capacity grows too).
static func group_of(data: ItemData) -> String:
	if data == null:
		return ""
	var stats := data.stats
	if stats.has("class") and data.category in [ItemData.Category.ARMOR, ItemData.Category.HELMET, ItemData.Category.RIG,
			ItemData.Category.ATTACHMENT]:
		return "armor"
	if stats.has("grid") and data.category in [ItemData.Category.RIG, ItemData.Category.BACKPACK]:
		return "carry"
	if WeaponMods.kind_of(data) == "headset":
		return "electronics"
	return ""


static func is_upgradable(data: ItemData) -> bool:
	return group_of(data) != ""


## The highest level `data` can reach (0 if it can't be upgraded): by rarity.
static func max_level(data: ItemData) -> int:
	if not is_upgradable(data):
		return 0
	var levels: Array = config().get("max_level_by_rarity", [1, 2, 3, 4, 5, 5])
	return int(levels[clampi(data.rarity, 0, levels.size() - 1)])


static func _per_level(key: String) -> float:
	return float(config().get("per_level", {}).get(key, 0.0)) / 100.0


# --- Effects -------------------------------------------------------------------------------------

## Max durability of armor `data` at `level`.
static func max_durability(data: ItemData, level: int) -> float:
	return float(data.stats.get("durability", 100.0)) * (1.0 + _per_level("durability") * level)


## Share of a stopped round's damage that gets through `piece` as blunt damage.
static func blunt(piece: ItemInstance) -> float:
	return float(piece.data.stats.get("blunt", 0.3)) * maxf(1.0 + _per_level("blunt") * piece.upgrade_level, 0.1)


## `piece`'s ricochet factor (how likely a round it stops glances off).
static func ricochet(piece: ItemInstance) -> float:
	return minf(float(piece.data.stats.get("ricochet", 0.0)) * (1.0 + _per_level("ricochet") * piece.upgrade_level), 1.0)


## How much `piece` changes hearing (+0.25 = sounds heard 25% further): a headset's bonus grows with
## its level; helmets and face shields muffle.
static func hearing(piece: ItemInstance) -> float:
	var value := float(piece.data.stats.get("hearing", 0.0))
	if value > 0.0:
		value += _per_level("hearing") * piece.upgrade_level
	return value


## Weight multiplier of a rig or backpack at `piece`'s level (1 for anything else).
static func weight_multiplier(piece: ItemInstance) -> float:
	if piece.upgrade_level <= 0 or not piece.data.stats.has("grid"):
		return 1.0
	return maxf(1.0 + _per_level("weight") * piece.upgrade_level, 0.2)


## The grid of a rig or backpack `data` at `level`.
static func grid_size(data: ItemData, level: int) -> Vector2i:
	var grid: Array = data.stats.get("grid", [0, 0])
	var growth: Array = config().get("capacity", [])
	var extra: Array = growth[clampi(level, 0, growth.size() - 1)] if not growth.is_empty() else [0, 0]
	return Vector2i(int(grid[0]) + int(extra[0]), int(grid[1]) + int(extra[1]))


## Puts `item`'s level into effect: its max durability (current durability rises by as much) and its
## grid (only ever grows). Call after changing ItemInstance.upgrade_level.
static func apply(item: ItemInstance) -> void:
	if item.is_armor():
		var new_max := max_durability(item.data, item.upgrade_level)
		item.durability = clampf(item.durability + new_max - item.max_durability, 0.0, new_max)
		item.max_durability = new_max
	if item.contents and item.data.stats.has("grid"):
		var size := grid_size(item.data, item.upgrade_level)
		item.contents.size = Vector2i(maxi(item.contents.size.x, size.x), maxi(item.contents.size.y, size.y))
		item.contents.changed.emit()


## What the next level changes, as [label, now, next] rows (empty at the max level).
static func next_changes(item: ItemInstance) -> Array:
	var rows := []
	if item.upgrade_level >= max_level(item.data):
		return rows
	var next := item.upgrade_level + 1
	var after := ItemInstance.create(item.data.id)
	after.upgrade_level = next
	if item.is_armor():
		rows.append(["Max durability", "%.1f" % item.max_durability, "%.1f" % max_durability(item.data, next)])
		rows.append(["Blunt damage", "%d%%" % roundi(blunt(item) * 100.0), "%d%%" % roundi(blunt(after) * 100.0)])
		if float(item.data.stats.get("ricochet", 0.0)) > 0.0:
			rows.append(["Ricochet", "×%.3f" % ricochet(item), "×%.3f" % ricochet(after)])
	if item.data.stats.has("grid"):
		var now := grid_size(item.data, item.upgrade_level)
		var later := grid_size(item.data, next)
		if later != now:
			rows.append(["Capacity", "%d × %d" % [now.x, now.y], "%d × %d" % [later.x, later.y]])
		rows.append(["Weight", Settings.format_weight(item.data.weight_kg * weight_multiplier(item)),
			Settings.format_weight(item.data.weight_kg * weight_multiplier(after))])
	if group_of(item.data) == "electronics":
		rows.append(["Hearing", "+%d%%" % roundi(hearing(item) * 100.0), "+%d%%" % roundi(hearing(after) * 100.0)])
	return rows


# --- Who upgrades, and what it costs -------------------------------------------------------------

## Upgrade sources by id: "workbench" and the traders that upgrade gear.
static func sources() -> Array[String]:
	var result: Array[String] = []
	for id: String in config().get("sources", {}):
		result.append(id)
	return result


## "Workbench", or the trader's name (TraderTable).
static func source_name(source: String) -> String:
	if TraderTable.has(source):
		return TraderTable.display_name(source)
	return str(config().get("sources", {}).get(source, {}).get("name", source.capitalize()))


## The highest level `source` can upgrade to right now: by the Workbench's level, or your loyalty
## level with the trader.
static func source_max_level(source: String) -> int:
	var entry: Dictionary = config().get("sources", {}).get(source, {})
	if entry.is_empty():
		return 0
	if source == WORKBENCH:
		var levels: Array = entry.get("max_level_by_station_level", [0])
		return int(levels[clampi(int(GameState.hideout.get(WORKBENCH, 0)), 0, levels.size() - 1)])
	if not GameState.trader_loyalty.has(source):
		return 0
	var by_loyalty: Array = entry.get("max_level_by_loyalty", [0])
	return int(by_loyalty[clampi(int(GameState.trader_loyalty[source].level), 0, by_loyalty.size() - 1)])


## What taking `item` one level higher at `source` costs: {"roubles", "requirements": Array[Requirement]}.
static func cost(item: ItemInstance, source: String) -> Dictionary:
	var next := item.upgrade_level + 1
	var entry: Dictionary = config().get("sources", {}).get(source, {})
	var shares: Array = config().get("money_share", [])
	var share := float(shares[clampi(next, 0, shares.size() - 1)]) if not shares.is_empty() else 0.0
	var roubles := maxi(roundi(item.data.base_value * share * float(entry.get("money", 1.0)) / 100.0) * 100,
		int(config().get("min_roubles", 0)))
	var by_level: Array = config().get("items", {}).get(group_of(item.data), [])
	var wanted: Array = (by_level[next] if next < by_level.size() else []).duplicate()
	wanted.append_array(entry.get("extra_items", []))
	# The same item twice (the level's and the source's extra) is one requirement.
	var merged := {}
	var order: Array[String] = []
	for need: Dictionary in wanted:
		var key := "%s|%s" % [need.item, need.get("fir", false)]
		if merged.has(key):
			merged[key].count = int(merged[key].count) + int(need.get("count", 1))
		else:
			merged[key] = need.duplicate()
			order.append(key)
	return {"roubles": roubles, "requirements": Requirement.list(order.map(func(key: String) -> Dictionary: return merged[key]))}


## Why `item` can't go up a level at `source` now, or "" if it can.
static func block_reason(item: ItemInstance, source: String) -> String:
	if not is_upgradable(item.data):
		return "Can't be upgraded"
	if item.upgrade_level >= max_level(item.data):
		return "Already at its highest level (+%d)" % max_level(item.data)
	var limit := source_max_level(source)
	if limit <= 0:
		return "Build the Workbench first" if source == WORKBENCH else "%s doesn't upgrade gear" % source_name(source)
	if item.upgrade_level >= limit:
		if source == WORKBENCH:
			return "Upgrade the Workbench for +%d" % (item.upgrade_level + 1)
		return "Needs a higher loyalty level with %s" % source_name(source)
	var price := cost(item, source)
	if GameState.roubles < int(price.roubles):
		return "Not enough roubles"
	if not ItemSearch.can_afford(price.requirements):
		return "Missing items"
	return ""


## Raises `item` one level at `source`, paying the roubles and items. Returns "" or why it couldn't.
static func upgrade(item: ItemInstance, source: String) -> String:
	var reason := block_reason(item, source)
	if reason != "":
		return reason
	var price := cost(item, source)
	if not ItemSearch.pay(price.requirements):
		return "Missing items"
	GameState.roubles -= int(price.roubles)
	if GameState.trader_loyalty.has(source):
		GameState.trader_loyalty[source].spent += int(price.roubles)
		Trading.update_loyalty(source)
	item.upgrade_level += 1
	apply(item)
	return ""


## Every upgradable item you own out of raid (equipped, in your containers and the stash, and parts on
## your gear), for the upgrade lists.
static func owned() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	var everything: Array[ItemInstance] = []
	if GameState.inventory:
		everything.append_array(GameState.inventory.all_items())
	if GameState.stash:
		everything.append_array(GameState.stash.all_items())
	for item in everything:
		if is_upgradable(item.data) and item not in result:
			result.append(item)
	return result
