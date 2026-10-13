class_name Hideout
extends RefCounted
## Hideout stations (DESIGN.md §9): defined in data/hideout/stations.json, levels built in
## GameState.hideout. Upgrading costs roubles, items (often found in raid: only items with the
## checkmark count for those) and sometimes other stations' levels. Each level can unlock crafts:
## inputs in, one item out, into the stash. Crafted items are found in raid. Upgrades and crafts are
## instant for now (build and craft timers are planned).
##
## A station is {"id", "name", "description", "levels": [{"level", "roubles", "stations": {id: level},
## "requires": [requirements], "crafts": [{"id", "inputs": [requirements], "output": {"item",
## "count"}}]}]}.

const STATIONS_PATH := "res://data/hideout/stations.json"

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


static func level(station: Dictionary) -> int:
	return int(GameState.hideout.get(station.id, 0))


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
		if int(GameState.hideout.get(other, 0)) < int(needed_stations[other]):
			return "Needs %s level %d" % [find(other).get("name", other), int(needed_stations[other])]
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
	return ""


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
