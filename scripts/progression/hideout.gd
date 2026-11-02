class_name Hideout
extends RefCounted
## Hideout stations (DESIGN.md §9): defined in data/hideout/stations.json (checked when the items
## load: problems()), levels built in GameState.hideout. Upgrading costs roubles, items (often found in
## raid: only items with the checkmark count for those), sometimes other stations' levels and a
## trader's loyalty level (never met while that trader is locked: loyalty()). Each level can unlock
## crafts: inputs in, one item out, into the stash. Crafted items are found in raid. The Stash station
## sizes the stash (DESIGN.md §8): building a level grows GameState.stash at once. Upgrades and crafts
## are instant for now (build and craft timers are planned).
##
## A station is {"id", "name", "description", "start_level" (built that far for every profile; 0 if
## missing), "levels": [{"level", "roubles", "stations": {id: level}, "traders": {trader id: loyalty
## level}, "requires": [requirements], "crafts": [{"id", "inputs": [requirements], "output": {"item",
## "count"}}], "stash_size": [columns, rows] (the Stash only)}]}.

const STATIONS_PATH := "res://data/hideout/stations.json"
## The station whose level sizes the stash.
const STASH := "stash"
const STATION_KEYS := ["id", "name", "description", "start_level", "levels"]
const LEVEL_KEYS := ["level", "roubles", "stations", "traders", "requires", "crafts", "stash_size"]

static var _stations: Array[Dictionary] = []


static func stations() -> Array[Dictionary]:
	if _stations.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATIONS_PATH))
		if parsed is Array:
			for station: Dictionary in parsed:
				_stations.append(station)
		else:
			push_error("Hideout: %s isn't a JSON list of stations" % STATIONS_PATH)
	return _stations


static func find(id: String) -> Dictionary:
	for station in stations():
		if station.id == id:
			return station
	return {}


## The level built (the station's start level if the profile doesn't say).
static func level(station: Dictionary) -> int:
	return int(GameState.hideout.get(station.id, start_level(station)))


## How far `station` is built for every profile from the start (the Stash: level 1).
static func start_level(station: Dictionary) -> int:
	return int(station.get("start_level", 0))


## {station id: start level} for the stations built from the start (a new profile's hideout).
static func starting_levels() -> Dictionary:
	var result := {}
	for station in stations():
		if start_level(station) > 0:
			result[station.id] = start_level(station)
	return result


## The stash's size at Stash level `at_level` (the level built if -1): the size of the highest level up
## to it that sets one, else the size in data/config/inventory.tres.
static func stash_size(at_level := -1) -> Vector2i:
	var station := find(STASH)
	var result := (load("res://data/config/inventory.tres") as InventoryConfig).stash_size
	if station.is_empty():
		return result
	var top := level(station) if at_level < 0 else at_level
	for entry: Dictionary in station.levels:
		var cells: Variant = entry.get("stash_size")
		if int(entry.get("level", 0)) <= top and cells is Array and cells.size() == 2:
			result = Vector2i(int(cells[0]), int(cells[1]))
	return result


static func max_level(station: Dictionary) -> int:
	return station.levels.size()


## The next level's entry, or {} at the top.
static func next_level(station: Dictionary) -> Dictionary:
	var current := level(station)
	return station.levels[current] if current < station.levels.size() else {}


static func requirements(level_entry: Dictionary) -> Array[Requirement]:
	return Requirement.list(level_entry.get("requires", []))


## Why `station` can't be upgraded now, or "" if it can.
static func upgrade_block_reason(station: Dictionary) -> String:
	var next := next_level(station)
	if next.is_empty():
		return "Fully upgraded"
	var needed_stations: Dictionary = next.get("stations", {})
	for other: String in needed_stations:
		var other_station := find(other)
		if other_station.is_empty() or level(other_station) < int(needed_stations[other]):
			return "Needs %s level %d" % [find(other).get("name", other), int(needed_stations[other])]
	var needed_traders: Dictionary = next.get("traders", {})
	for trader: String in needed_traders:
		if loyalty(trader) < int(needed_traders[trader]):
			return "Needs %s LL%d%s" % [TraderTable.display_name(trader), int(needed_traders[trader]), TraderTable.locked_suffix(trader)]
	if GameState.roubles < int(next.get("roubles", 0)):
		return "Not enough roubles"
	if not ItemSearch.can_afford(requirements(next)):
		return "Missing items"
	return ""


## Builds the next level. Returns "" on success, else why not.
static func upgrade(station: Dictionary) -> String:
	var reason := upgrade_block_reason(station)
	if reason != "":
		return reason
	var next := next_level(station)
	ItemSearch.pay(requirements(next))
	GameState.roubles -= int(next.get("roubles", 0))
	GameState.hideout[station.id] = level(station) + 1
	if station.id == STASH:
		GameState.stash.resize(stash_size())
	return ""


## Your loyalty level with `trader_id`, as far as an upgrade's "traders" requirement goes: 0 if there's
## no such trader or they don't trade with you yet (The Broker before his unlock quest), so a locked
## trader never meets one.
static func loyalty(trader_id: String) -> int:
	if not TraderTable.is_unlocked(trader_id):
		return 0
	return int(GameState.trader_loyalty.get(trader_id, {}).get("level", 0))


## Crafts unlocked at the station's current level and below.
static func crafts(station: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in station.levels.slice(0, level(station)):
		for recipe: Dictionary in entry.get("crafts", []):
			result.append(recipe)
	return result


## Every craft of `station`, with the level that unlocks it: [[level, recipe], ...].
static func all_crafts(station: Dictionary) -> Array:
	var result := []
	for entry: Dictionary in station.levels:
		for recipe: Dictionary in entry.get("crafts", []):
			result.append([int(entry.level), recipe])
	return result


## Why `recipe` can't be crafted now, or "" if it can.
static func craft_block_reason(station: Dictionary, recipe: Dictionary) -> String:
	if recipe not in crafts(station):
		return "Upgrade the station first"
	if not ItemSearch.can_afford(Requirement.list(recipe.inputs)):
		return "Missing items"
	var outputs := _outputs(recipe)
	if outputs.is_empty():
		return "No room in the stash"
	# Everything it makes has to fit: try it on a copy of the stash.
	var copy := InventoryGrid.new(GameState.stash.size, &"stash")
	copy.load_array(GameState.stash.to_array())
	for piece in outputs:
		if not copy.add(piece):
			return "No room in the stash"
	return ""


## Crafts `recipe`: takes the inputs, puts the output (found in raid) in the stash. "" on success. An
## output of several items that don't stack (2 energy drinks) comes as that many items.
static func craft(station: Dictionary, recipe: Dictionary) -> String:
	var reason := craft_block_reason(station, recipe)
	if reason != "":
		return reason
	ItemSearch.pay(Requirement.list(recipe.inputs))
	for piece in _outputs(recipe):
		GameState.stash.add(FoundInRaid.make(piece.data.id, piece.count, FoundInRaid.Source.CRAFT))
	return ""


## What `recipe` makes, as stacks no bigger than the item's max stack (none if the item is missing).
static func _outputs(recipe: Dictionary) -> Array[ItemInstance]:
	var pieces: Array[ItemInstance] = []
	var data := ItemDB.get_item(str(recipe.output.item))
	if data == null:
		return pieces
	var left := int(recipe.output.get("count", 1))
	while left > 0:
		var piece := ItemInstance.create(data.id, mini(left, data.max_stack))
		pieces.append(piece)
		left -= piece.count
	return pieces


# --- Checks -------------------------------------------------------------------------------------

## What's wrong with stations.json (empty if nothing): the shape, levels numbered 1 up, stations and
## traders that exist at levels they have, items that exist, and the Stash station: built at level 1
## from the start at inventory.tres's size, and growing every level. Needs the items loaded: ItemDB runs
## it once it has them.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var all := stations()
	if all.is_empty():
		return ["%s: no stations" % STATIONS_PATH]
	var ids := {}
	for station in all:
		ids[str(station.get("id", ""))] = station
	if ids.size() != all.size() or ids.has(""):
		found.append("%s: every station needs an id of its own" % STATIONS_PATH)
	for station in all:
		var where := "station %s" % station.get("id", "?")
		for key: String in station:
			if not key in STATION_KEYS:
				found.append("%s: unknown key \"%s\"" % [where, key])
		if str(station.get("name", "")).strip_edges() == "":
			found.append("%s: no name" % where)
		var levels: Variant = station.get("levels")
		if not levels is Array or levels.is_empty():
			found.append("%s: no levels" % where)
			continue
		if start_level(station) < 0 or start_level(station) > levels.size():
			found.append("%s: start_level %d isn't 0-%d" % [where, start_level(station), levels.size()])
		for i in levels.size():
			found.append_array(_level_problems(station, levels[i], i + 1, ids))
	found.append_array(_stash_problems(ids.get(STASH, {})))
	return found


static func _level_problems(station: Dictionary, entry: Variant, number: int, stations_by_id: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var where := "station %s level %d" % [station.get("id", "?"), number]
	if not entry is Dictionary:
		return ["%s isn't an object" % where]
	for key: String in entry:
		if not key in LEVEL_KEYS:
			found.append("%s: unknown key \"%s\"" % [where, key])
	if int(entry.get("level", 0)) != number:
		found.append("%s: says level %s (levels go 1, 2, 3...)" % [where, entry.get("level")])
	if int(entry.get("roubles", 0)) < 0:
		found.append("%s: roubles below 0" % where)
	var needed_stations: Variant = entry.get("stations", {})
	if not needed_stations is Dictionary:
		found.append("%s: \"stations\" isn't {id: level}" % where)
	else:
		for other: String in needed_stations:
			var other_station: Dictionary = stations_by_id.get(other, {})
			if other == station.get("id") or other_station.is_empty() or int(needed_stations[other]) < 1 \
					or int(needed_stations[other]) > other_station.get("levels", []).size():
				found.append("%s: needs %s level %s, which doesn't exist" % [where, other, needed_stations[other]])
	var needed_traders: Variant = entry.get("traders", {})
	if not needed_traders is Dictionary:
		found.append("%s: \"traders\" isn't {trader id: loyalty level}" % where)
	else:
		for trader: String in needed_traders:
			if not TraderTable.has(trader) or int(needed_traders[trader]) < 1 or int(needed_traders[trader]) > TraderTable.max_loyalty(trader):
				found.append("%s: needs %s LL%s, which doesn't exist" % [where, trader, needed_traders[trader]])
	var named := []
	for wanted: Variant in entry.get("requires", []):
		named.append(wanted)
	for recipe: Variant in entry.get("crafts", []):
		if not (recipe is Dictionary and recipe.get("inputs") is Array and recipe.get("output") is Dictionary):
			found.append("%s: a craft needs \"inputs\" and an \"output\"" % where)
			continue
		named.append_array(recipe.inputs)
		named.append(recipe.output)
	for wanted: Variant in named:
		if not (wanted is Dictionary and ItemDB.has_item(str(wanted.get("item", ""))) and int(wanted.get("count", 1)) >= 1):
			found.append("%s: %s isn't an item that exists with a count of 1 or more" % [where, wanted])
	if entry.has("stash_size") and station.get("id") != STASH:
		found.append("%s: only the %s station sets stash_size" % [where, STASH])
	return found


static func _stash_problems(station: Dictionary) -> Array[String]:
	if station.is_empty():
		return ["no %s station (it sizes the stash)" % STASH]
	var found: Array[String] = []
	var start := (load("res://data/config/inventory.tres") as InventoryConfig).stash_size
	if start_level(station) != 1:
		found.append("station %s: start_level must be 1 (every profile starts with level 1)" % STASH)
	var last := Vector2i.ZERO
	for entry: Variant in station.levels:
		if not entry is Dictionary:
			continue
		var cells: Variant = entry.get("stash_size")
		var where := "station %s level %s" % [STASH, entry.get("level")]
		if not (cells is Array and cells.size() == 2 and int(cells[0]) > 0 and int(cells[1]) > 0):
			found.append("%s: needs stash_size [columns, rows]" % where)
			continue
		var size := Vector2i(int(cells[0]), int(cells[1]))
		if last == Vector2i.ZERO and size != start:
			found.append("%s: stash_size %s isn't inventory.tres's stash_size %s" % [where, size, start])
		elif last != Vector2i.ZERO and (size.x < last.x or size.y < last.y or size == last):
			found.append("%s: stash_size %s doesn't grow from %s" % [where, size, last])
		last = size
	return found
