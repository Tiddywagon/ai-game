class_name PoiTable
extends RefCounted
## Every map's points of interest (DESIGN.md §5.2), from data/config/pois.json: a named area with a
## loot tier (1-3), loot focus tags, an optional requirement (a key, the power on or a lever pulled)
## and whether it's hidden (not on the map item until you've found it). Map scenes place each one as a
## PointOfInterest by id (its boundary; the containers and loose loot spots inside it are its spawn
## points). Checked when it loads: problems().

const PATH := "res://data/config/pois.json"
const CONFIG: PoiConfig = preload("res://data/config/poi.tres")
const FIELDS := ["id", "name", "tier", "focus", "hidden", "requires", "spawn_chance", "description"]
const REQUIREMENTS := ["key", "power", "lever"]
## Fewest POIs a map may have.
const MIN_POIS := 6
## What each focus tag means in items: their categories, groups and tags (any of them).
const FOCUS := {
	"electronics": {"groups": ["Electronics", "Tech"], "tags": ["electronics", "computer", "battery", "radio"]},
	"medical": {"categories": [ItemData.Category.MEDS], "groups": ["Medical supply"], "tags": ["medical"]},
	"weapons": {"categories": [ItemData.Category.WEAPON, ItemData.Category.ATTACHMENT, ItemData.Category.THROWABLE, ItemData.Category.MELEE]},
	"ammo": {"categories": [ItemData.Category.AMMO]},
	"gear": {"categories": [ItemData.Category.ARMOR, ItemData.Category.HELMET, ItemData.Category.RIG, ItemData.Category.BACKPACK]},
	"food": {"categories": [ItemData.Category.FOOD]},
	"valuables": {"categories": [ItemData.Category.VALUABLE], "tags": ["valuable"]},
	"currency": {"groups": ["Currency", "Jewelry"], "tags": ["gold", "currency", "jewelry"]},
	"tools": {"groups": ["Hardware", "Tools", "Materials"], "tags": ["tool"]},
	"intel": {"groups": ["Intel"], "tags": ["intel", "data", "map"]},
	"keys": {"categories": [ItemData.Category.KEY]},
	"military": {"groups": ["Military"], "tags": ["military", "explosive", "ballistic"]},
	"fuel": {"groups": ["Fuel"], "tags": ["fuel", "flammable"]},
	"household": {"groups": ["Household"], "tags": ["hygiene", "kitchen", "cleaning"]},
}

static var _maps := {}
static var _focus_tables := {}


## {map id: [POI entries]}.
static func maps() -> Dictionary:
	if _maps.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and parsed.get("maps") is Dictionary:
			_maps = parsed.maps
			for problem in problems():
				push_warning("PoiTable: %s" % problem)
		else:
			push_error("PoiTable: %s isn't valid JSON with a \"maps\" object" % PATH)
	return _maps


## `map_id`'s POIs, in table order.
static func for_map(map_id: String) -> Array:
	return maps().get(map_id, [])


static func find(map_id: String, id: String) -> Dictionary:
	for entry: Dictionary in for_map(map_id):
		if entry.get("id", "") == id:
			return entry
	return {}


## The rarity multipliers for loot in `entry` (indexed by ItemData.Rarity): its tier's for Rare and up,
## and the locked bonus if a key opens it.
static func loot_boost(entry: Dictionary) -> PackedFloat32Array:
	var tier := clampi(int(entry.get("tier", 1)), 1, 3)
	var boost := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	for rarity in range(ItemData.Rarity.RARE, LootTable.RARITY_COUNT):
		boost[rarity] = CONFIG.tier_multipliers[tier - 1]
	if str(entry.get("requires", {}).get("key", "")) != "":
		for rarity in LootTable.RARITY_COUNT:
			boost[rarity] *= CONFIG.locked_bonus[rarity] if rarity < CONFIG.locked_bonus.size() else 1.0
	return boost


## Share of `entry`'s spawn points that are active in a raid.
static func spawn_chance(entry: Dictionary) -> float:
	if entry.has("spawn_chance"):
		return clampf(float(entry.spawn_chance), 0.0, 1.0)
	return CONFIG.spawn_chances[clampi(int(entry.get("tier", 1)), 1, 3) - 1]


## True if `item` matches any of the focus tags.
static func matches_focus(item: ItemData, focus: Array) -> bool:
	for tag: String in focus:
		var rule: Dictionary = FOCUS.get(tag, {})
		if item.category in rule.get("categories", []) or item.group in rule.get("groups", []):
			return true
		for item_tag: String in rule.get("tags", []):
			if item.has_tag(item_tag):
				return true
	return false


## A loot table of everything matching `focus` (loose loot in a POI rolls from it), with the loose loot
## table's rarity weights. Cached per tag set.
static func focus_table(focus: Array) -> LootTable:
	var key := ",".join(focus)
	if _focus_tables.has(key):
		return _focus_tables[key]
	var table := LootTable.new()
	var base: LootTable = load("res://data/loot_tables/loose_loot.tres")
	table.display_name = "Focus: %s" % key
	table.rarity_weights = base.rarity_weights.duplicate()
	for tag: String in focus:
		var rule: Dictionary = FOCUS.get(tag, {})
		for category: int in rule.get("categories", []):
			if not category in table.categories:
				table.categories.append(category)
		for group: String in rule.get("groups", []):
			if not group in table.groups:
				table.groups.append(group)
		for item_tag: String in rule.get("tags", []):
			if not item_tag in table.tags:
				table.tags.append(item_tag)
	_focus_tables[key] = table
	return table


## What a POI takes, as a phrase: "Needs the Factory office key", "Needs power", "Needs the bunker
## lever pulled" ("" for none).
static func requirement_text(entry: Dictionary) -> String:
	var requires: Dictionary = entry.get("requires", {})
	if str(requires.get("key", "")) != "":
		return "Needs the %s" % ExtractTable.item_name(str(requires.key))
	if requires.get("power", false):
		return "Needs power"
	if str(requires.get("lever", "")) != "":
		return "Needs a lever pulled"
	return ""


## "Tier 2 · electronics, valuables".
static func summary(entry: Dictionary) -> String:
	return "Tier %d  ·  %s" % [int(entry.get("tier", 1)), ", ".join(entry.get("focus", []))]


## What's wrong with the table (empty if nothing): every map has at least MIN_POIS, ids unique per
## map, tiers 1-3, known focus tags, at most one requirement (a key item, the power, or a lever id), at
## least one hidden POI per map.
static func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var table: Dictionary = _maps if not _maps.is_empty() else maps()
	for map in MapInfo.load_all():
		if not table.has(map.id):
			found.append("%s has no POIs" % map.id)
	for map_id: String in table:
		var entries: Array = table[map_id]
		if MapInfo.find(map_id) == null:
			found.append("%s isn't a map in data/maps" % map_id)
		if entries.size() < MIN_POIS:
			found.append("%s has %d POIs (at least %d)" % [map_id, entries.size(), MIN_POIS])
		var ids := {}
		var hidden := 0
		for entry: Dictionary in entries:
			var id := str(entry.get("id", ""))
			var where := "%s/%s" % [map_id, id]
			if id == "" or str(entry.get("name", "")) == "":
				found.append("%s: a POI needs an id and a name" % map_id)
			if ids.has(id):
				found.append("%s: duplicate id" % where)
			ids[id] = true
			for field: String in entry:
				if not field in FIELDS:
					found.append("%s: unknown field \"%s\"" % [where, field])
			var tier := int(entry.get("tier", 0))
			if tier < 1 or tier > 3:
				found.append("%s: tier %d (1 to 3)" % [where, tier])
			var focus: Array = entry.get("focus", [])
			if focus.is_empty():
				found.append("%s: no focus tags" % where)
			for tag in focus:
				if not FOCUS.has(tag):
					found.append("%s: unknown focus tag \"%s\"" % [where, tag])
			var requires: Dictionary = entry.get("requires", {})
			if requires.size() > 1:
				found.append("%s: more than one requirement" % where)
			for kind: String in requires:
				if not kind in REQUIREMENTS:
					found.append("%s: unknown requirement \"%s\"" % [where, kind])
			var key := str(requires.get("key", ""))
			if key != "" and (not ItemDB.has_item(key) or ItemDB.get_item(key).category != ItemData.Category.KEY):
				found.append("%s: \"%s\" isn't a key" % [where, key])
			if requires.has("lever") and str(requires.lever) == "":
				found.append("%s: a lever requirement needs the lever's id" % where)
			if entry.has("spawn_chance") and (float(entry.spawn_chance) <= 0.0 or float(entry.spawn_chance) > 1.0):
				found.append("%s: spawn_chance must be over 0 and at most 1" % where)
			if entry.get("hidden", false):
				hidden += 1
		if hidden == 0:
			found.append("%s has no hidden POI" % map_id)
	return found
