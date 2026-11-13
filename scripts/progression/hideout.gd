class_name Hideout
extends RefCounted
## Hideout stations (DESIGN.md §9): the 13 stations in data/hideout/stations.json, the rules in
## rules.json and the cosmetics in cosmetics.json (all checked when the items load: problems()), levels
## built in GameState.hideout. Upgrading costs roubles, items (found in raid from level 2: only items
## with the checkmark count for those), sometimes other stations' levels, a trader's loyalty level
## (never met while that trader is locked: loyalty()) and a player level. Each level can unlock crafts:
## inputs in, one item out, into the stash. Crafted items are found in raid. The Stash station sizes the
## stash (DESIGN.md §8): building a level grows GameState.stash at once.
##
## A station is {"id", "name", "description", "start_level" (built that far for every profile; 0 if
## missing), "room": [x, y, w, h] (its place on the hideout plan, rules.json "plan" cells), "needs_power"
## (its crafts and production slow down without power, its bonuses stop), "unpowered_rate" (how fast it
## works without power; rules.json's if missing), "fuel": {item id: minutes of power one gives} (the
## Generator), "cards": {"item", "bonus"} (the Bitcoin Farm), "levels": [{"level", "roubles",
## "stations": {id: level}, "traders": {trader id: loyalty level}, "player_level", "build_minutes",
## "requires": [requirements], "crafts": [{"id", "minutes", "inputs": [requirements], "output": {"item",
## "count"}}], and what the level gives: "stash_size": [columns, rows] (the Stash), "fuel_slots" and
## "fuel_efficiency" (the Generator), "card_slots" (the Bitcoin Farm), "produces": {"item", "minutes",
## "cap"} (the Water Collector and the Bitcoin Farm), "training": {"points", "hours"} (the Gym),
## "scav_cooldown", "insurance_price", "insurance_time" (the Intelligence Center: multipliers),
## "scouting" (Security) and "practice" (the Shooting Range): tiers 1-3}]}.

const STATIONS_PATH := "res://data/hideout/stations.json"
const RULES_PATH := "res://data/hideout/rules.json"
const COSMETICS_PATH := "res://data/hideout/cosmetics.json"
## Station ids the code names.
const GENERATOR := "generator"
## The station whose level sizes the stash.
const STASH := "stash"
## The station whose levels shorten the Scav run cooldown and make insurance cheaper and faster (a
## level's "scav_cooldown", "insurance_price" and "insurance_time": the multipliers from that level on).
const INTELLIGENCE_CENTER := "intelligence_center"
const BITCOIN_FARM := "bitcoin_farm"
const WATER_COLLECTOR := "water_collector"
const GYM := "gym"
const SECURITY := "security"
const SHOOTING_RANGE := "shooting_range"
## Where the Shooting Range's practice sessions are.
const PRACTICE_MAP := "test_yard"
## Every station the hideout has (DESIGN.md §9), in the order the data lists them.
const ALL_STATIONS := ["generator", "stash", "medstation", "nutrition_unit", "rest_space", "workbench", "water_collector",
	"lavatory", "shooting_range", "gym", "intelligence_center", "bitcoin_farm", "security"]
const STATION_KEYS := ["id", "name", "description", "start_level", "room", "needs_power", "unpowered_rate", "fuel", "cards", "levels"]
const LEVEL_KEYS := ["level", "roubles", "stations", "traders", "player_level", "build_minutes", "requires", "crafts", "stash_size",
	"fuel_slots", "fuel_efficiency", "card_slots", "produces", "training", "scav_cooldown", "insurance_price", "insurance_time",
	"scouting", "practice"]
## Level keys only one station may set.
const OWN_KEYS := {"stash_size": STASH, "fuel_slots": GENERATOR, "fuel_efficiency": GENERATOR, "card_slots": BITCOIN_FARM,
	"training": GYM, "scav_cooldown": INTELLIGENCE_CENTER, "insurance_price": INTELLIGENCE_CENTER,
	"insurance_time": INTELLIGENCE_CENTER, "scouting": SECURITY, "practice": SHOOTING_RANGE}
## Level keys every level of their station sets.
const EVERY_LEVEL_KEYS := {GENERATOR: ["fuel_slots", "fuel_efficiency"], BITCOIN_FARM: ["card_slots", "produces"],
	WATER_COLLECTOR: ["produces"], GYM: ["training"], SECURITY: ["scouting"], SHOOTING_RANGE: ["practice"],
	INTELLIGENCE_CENTER: ["scav_cooldown", "insurance_price", "insurance_time"]}
const RECIPE_KEYS := ["id", "minutes", "inputs", "output"]
const COSMETIC_KEYS := ["id", "name", "slot", "color", "roubles", "description", "requires"]
## Cosmetic slots: one cosmetic each, drawn on the hideout plan (HideoutMap).
const COSMETIC_SLOTS := ["lighting", "walls", "floor", "posters"]

static var _stations: Array[Dictionary] = []
static var _rules: Dictionary = {}
static var _cosmetics: Array[Dictionary] = []


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


## rules.json: {"plan": [columns, rows] of the hideout plan, "unpowered_rate" (how fast a station that
## needs power works without it), "craft_queue" (crafts one station can have queued, the running one
## included)}.
static func rules() -> Dictionary:
	if _rules.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		_rules = parsed if parsed is Dictionary else {"plan": [32, 20], "unpowered_rate": 0.5, "craft_queue": 3}
	return _rules


static func plan_size() -> Vector2i:
	var cells: Array = rules().get("plan", [32, 20])
	return Vector2i(int(cells[0]), int(cells[1]))


static func craft_queue_size() -> int:
	return maxi(int(rules().get("craft_queue", 3)), 1)


## Every cosmetic: [{"id", "name", "slot" (COSMETIC_SLOTS), "color": [r, g, b], "roubles", "description",
## "requires": [requirements]}].
static func cosmetics() -> Array[Dictionary]:
	if _cosmetics.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COSMETICS_PATH))
		if parsed is Array:
			for entry: Dictionary in parsed:
				_cosmetics.append(entry)
	return _cosmetics


static func find_cosmetic(id: String) -> Dictionary:
	for entry in cosmetics():
		if entry.id == id:
			return entry
	return {}


## The room `station` takes on the plan, in plan cells.
static func room(station: Dictionary) -> Rect2i:
	var cells: Array = station.get("room", [0, 0, 1, 1])
	return Rect2i(int(cells[0]), int(cells[1]), int(cells[2]), int(cells[3]))


static func needs_power(station: Dictionary) -> bool:
	return bool(station.get("needs_power", false))


## How fast `station` works without power (1 if it doesn't need any).
static func unpowered_rate(station: Dictionary) -> float:
	if not needs_power(station):
		return 1.0
	return clampf(float(station.get("unpowered_rate", rules().get("unpowered_rate", 0.5))), 0.0, 1.0)


## Level `number`'s entry of `station` ({} if there's no such level).
static func level_entry(station: Dictionary, number: int) -> Dictionary:
	var levels: Array = station.get("levels", [])
	return levels[number - 1] if number >= 1 and number <= levels.size() else {}


## A value the levels built so far set: the highest built level's `key` (`fallback` below the first one
## that sets it).
static func built_value(station_id: String, key: String, fallback: Variant) -> Variant:
	var station := find(station_id)
	var result: Variant = fallback
	if station.is_empty():
		return result
	var built := level(station)
	for entry: Dictionary in station.get("levels", []):
		if int(entry.get("level", 0)) <= built and entry.has(key):
			result = entry[key]
	return result


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


## What the Scav run cooldown is multiplied by (ScavRuns.cooldown_seconds(), DESIGN.md §2): the
## "scav_cooldown" of the highest Intelligence Center level built (0.9: 10% shorter) while it has power,
## else 1.
static func scav_cooldown_multiplier() -> float:
	return _intel_multiplier("scav_cooldown")


## What insurance prices are multiplied by (Insurance.price()): the Intelligence Center's
## "insurance_price" while it has power, else 1.
static func insurance_price_multiplier() -> float:
	return _intel_multiplier("insurance_price")


## What insurance return times are multiplied by (Insurance.schedule()): the Intelligence Center's
## "insurance_time" while it has power, else 1.
static func insurance_time_multiplier() -> float:
	return _intel_multiplier("insurance_time")


static func _intel_multiplier(key: String) -> float:
	var station := find(INTELLIGENCE_CENTER)
	if station.is_empty() or level(station) == 0 or not HideoutWork.has_power():
		return 1.0
	return clampf(float(built_value(INTELLIGENCE_CENTER, key, 1.0)), 0.01, 1.0)


## Security's scouting tier (0: not built; 1: whether the map's boss is in, 2: and how many AI PMCs,
## 3: and how many guards the boss has).
static func scouting() -> int:
	return int(built_value(SECURITY, "scouting", 0))


## The Shooting Range's practice tier (0: not built; 1: Scavs only, 2: AI PMCs too, 3: the boss too).
static func practice() -> int:
	return int(built_value(SHOOTING_RANGE, "practice", 0))


## Security's scouting for a raid on `map_id` about to start (DESIGN.md §16.3): {} without Security, else
## {"map", "tier", "boss" (true if the map's boss is in: rolled now with the boss's chance, and the
## raid is then held to it: apply_scouting()), "guards" (tier 3, with the boss in: how many), "pmcs"
## (tier 2+: AI PMCs on the map)}. A map without a boss has no "boss".
static func scout(map_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var tier := scouting()
	if tier == 0:
		return {}
	var result := {"map": map_id, "tier": tier}
	var boss := BossTable.for_map(map_id)
	if not boss.is_empty():
		result.boss = rng.randf() < float(boss.chance)
		if tier >= 3 and result.boss:
			result.guards = rng.randi_range(int(boss.guards[0]), int(boss.guards[1]))
	if tier >= 2:
		result.pmcs = PmcAi.budget(map_id)
	return result


## What the raid setup says about `scouting` (scout()), one line each.
static func scouting_lines(scouting_result: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if scouting_result.is_empty():
		return lines
	var boss := BossTable.for_map(str(scouting_result.map))
	if not scouting_result.has("boss"):
		lines.append("Security: no boss on this map.")
	elif scouting_result.boss:
		lines.append("Security: %s is in this raid%s." % [BossTable.full_name(boss),
			" with %d %s" % [int(scouting_result.guards), BossTable.guard_plural(boss)] if scouting_result.has("guards") else ""])
	else:
		lines.append("Security: %s isn't in this raid." % BossTable.full_name(boss))
	if scouting_result.has("pmcs"):
		lines.append("Security: %d AI PMCs on the map." % int(scouting_result.pmcs))
	return lines


## Holds the raid (GameState.raid) to what Security scouted: the boss in or not, its guards, the AI PMCs.
static func apply_scouting(raid: Dictionary, scouting_result: Dictionary) -> void:
	for key: String in ["boss", "guards", "pmcs"]:
		if scouting_result.has(key) and scouting_result.get("map") == raid.get("map"):
			raid[key] = scouting_result[key]


## The Shooting Range's practice session (DESIGN.md §9): a PMC raid on the Test Yard with a copy of your
## gear, flagged "practice" (RaidController.is_practice()): nothing is lost or gained and no experience.
## Tier 1 has Scavs only, 2 the map's AI PMCs too, 3 its boss too. {} without the Shooting Range.
static func practice_raid() -> Dictionary:
	var tier := practice()
	if tier == 0:
		return {}
	var raid := {"map": PRACTICE_MAP, "side": "pmc", "loadout": GameState.pmc_loadout(), "practice": true, "boss": tier >= 3}
	if tier < 2:
		raid.pmcs = 0
	return raid


static func max_level(station: Dictionary) -> int:
	return station.levels.size()


## The next level's entry, or {} at the top.
static func next_level(station: Dictionary) -> Dictionary:
	var current := level(station)
	return station.levels[current] if current < station.levels.size() else {}


static func requirements(level_entry: Dictionary) -> Array[Requirement]:
	return Requirement.list(level_entry.get("requires", []))


# --- Handing over and building ------------------------------------------------------------------

## How many of `item_id` are handed over toward `station`'s next level (kept on the station).
static func handed(station: Dictionary, item_id: String) -> int:
	return int(GameState.hideout_state.get("handed", {}).get(station.id, {}).get(item_id, 0))


## How many more of `wanted` (a requirement of the next level) still have to be handed over.
static func still_needed(station: Dictionary, wanted: Requirement) -> int:
	return maxi(wanted.count - handed(station, wanted.item_id), 0)


## The next level's items still to be handed over, as requirements for what's left.
static func outstanding(station: Dictionary) -> Array[Requirement]:
	var result: Array[Requirement] = []
	for wanted in requirements(next_level(station)):
		var more := still_needed(station, wanted)
		if more > 0:
			result.append(Requirement.from_dict({"item": wanted.item_id, "count": more, "fir": wanted.fir}))
	return result


## Why `wanted` can't be handed over to `station` now ("" if it can): the station is building or fully
## upgraded, it's all in, or you have none that count.
static func hand_over_block_reason(station: Dictionary, wanted: Requirement) -> String:
	if next_level(station).is_empty():
		return "Fully upgraded"
	if is_building(station):
		return "Building"
	if still_needed(station, wanted) == 0:
		return "All handed over"
	if ItemSearch.count(wanted.item_id, wanted.fir) == 0:
		return "You have none found in raid" if wanted.fir else "You have none"
	return ""


## Hands over as many of `wanted` as the next level still needs and you have (found in raid ones only
## if it says so; ItemSearch takes from the stash and your character). "" on success.
static func hand_over(station: Dictionary, wanted: Requirement) -> String:
	var reason := hand_over_block_reason(station, wanted)
	if reason != "":
		return reason
	var taken := ItemSearch.take(wanted.item_id, still_needed(station, wanted), wanted.fir)
	var state := GameState.hideout_state
	if not state.handed.has(station.id):
		state.handed[station.id] = {}
	state.handed[station.id][wanted.item_id] = handed(station, wanted.item_id) + taken
	return ""


## The build running on `station` ({"level", "ends"}), or {}.
static func building(station: Dictionary) -> Dictionary:
	return GameState.hideout_state.get("builds", {}).get(station.id, {})


static func is_building(station: Dictionary) -> bool:
	return not building(station).is_empty()


## Seconds until `station`'s build is done (0 if none).
static func build_seconds_left(station: Dictionary) -> float:
	var build := building(station)
	return maxf(float(build.ends) - HideoutWork.now(), 0.0) if not build.is_empty() else 0.0


## Real seconds level `entry` takes to build.
static func build_seconds(entry: Dictionary) -> float:
	return float(entry.get("build_minutes", 0.0)) * 60.0


## Why `station`'s next level can't be built now, or "" if it can: fully upgraded, building, other
## stations' levels, trader loyalty levels, your level, the money, and the items not handed over yet
## that you don't have.
static func upgrade_block_reason(station: Dictionary) -> String:
	var next := next_level(station)
	if next.is_empty():
		return "Fully upgraded"
	if is_building(station):
		return "Building: %s left" % UiFormat.duration(build_seconds_left(station))
	var needed_stations: Dictionary = next.get("stations", {})
	for other: String in needed_stations:
		var other_station := find(other)
		if other_station.is_empty() or level(other_station) < int(needed_stations[other]):
			return "Needs %s level %d" % [find(other).get("name", other), int(needed_stations[other])]
	var needed_traders: Dictionary = next.get("traders", {})
	for trader: String in needed_traders:
		if loyalty(trader) < int(needed_traders[trader]):
			return "Needs %s LL%d%s" % [TraderTable.display_name(trader), int(needed_traders[trader]), TraderTable.locked_suffix(trader)]
	if GameState.level < int(next.get("player_level", 1)):
		return "Needs player level %d" % int(next.player_level)
	if GameState.roubles < int(next.get("roubles", 0)):
		return "Not enough roubles"
	if not ItemSearch.can_afford(outstanding(station)):
		return "Missing items"
	return ""


## Starts building the next level: hands over whatever is still missing (you have it all: see
## upgrade_block_reason()), pays the roubles and starts the clock; the level is built once its build time
## has passed (HideoutWork.update()), at once for a build time of 0. Returns "" on success, else why not.
static func upgrade(station: Dictionary) -> String:
	HideoutWork.update()
	var reason := upgrade_block_reason(station)
	if reason != "":
		return reason
	var next := next_level(station)
	ItemSearch.pay(outstanding(station))
	GameState.roubles -= int(next.get("roubles", 0))
	GameState.hideout_state.handed.erase(station.id)
	GameState.hideout_state.builds[station.id] = {"level": int(next.level), "ends": snappedf(HideoutWork.now() + build_seconds(next), 1.0)}
	HideoutWork.update()
	return ""


## Finishes `station`'s build: the level is built (the Stash grows the stash at once).
static func finish_build(station: Dictionary) -> void:
	var build := building(station)
	if build.is_empty():
		return
	GameState.hideout_state.builds.erase(station.id)
	GameState.hideout[station.id] = maxi(level(station), int(build.level))
	if station.id == STASH:
		GameState.stash.resize(stash_size())


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


## What the level `entry` of `station` gives, one line each ("Grows the stash to 10 × 40", "Unlocks 4
## crafts", "2 fuel slots, fuel lasts ×1.25"): what the HIDEOUT screen and DESIGN.md §9's table say.
static func gives(station: Dictionary, entry: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if entry.has("stash_size"):
		lines.append("Stash %d × %d" % [int(entry.stash_size[0]), int(entry.stash_size[1])])
	if entry.has("fuel_slots"):
		lines.append("%d fuel slots, fuel lasts ×%s" % [int(entry.fuel_slots), str(snappedf(float(entry.fuel_efficiency), 0.01))])
	if entry.has("card_slots"):
		lines.append("%d graphics card slots" % int(entry.card_slots))
	if entry.has("produces"):
		var made := ItemDB.get_item(str(entry.produces.item))
		lines.append("%s every %s%s, holds %d" % [made.display_name if made else entry.produces.item, UiFormat.duration(float(entry.produces.minutes) * 60.0),
			" with one card" if entry.has("card_slots") else "", int(entry.produces.cap)])
	if entry.has("training"):
		lines.append("Train Strength or Endurance: %d points every %d h" % [int(entry.training.points), int(entry.training.hours)])
	if entry.has("scav_cooldown"):
		lines.append("Scav cooldown −%d%%, insurance −%d%%, returns −%d%%" % [roundi((1.0 - float(entry.scav_cooldown)) * 100.0),
			roundi((1.0 - float(entry.insurance_price)) * 100.0), roundi((1.0 - float(entry.insurance_time)) * 100.0)])
	if entry.has("scouting"):
		lines.append(["", "Scouting: is the boss in", "Scouting: the boss and the AI PMCs", "Scouting: the boss, its guards and the AI PMCs"][int(entry.scouting)])
	if entry.has("practice"):
		lines.append(["", "Practice: Scavs only", "Practice: AI PMCs too", "Practice: the boss too"][int(entry.practice)])
	if station.id == "nutrition_unit" or station.id == "rest_space":
		var bonus := Consumables.CONFIG.nutrition_unit_bonus if station.id == "nutrition_unit" else Consumables.CONFIG.rest_space_bonus
		lines.append("Energy and hydration refill +%d%%" % roundi(bonus * 100.0))
	var count := (entry.get("crafts", []) as Array).size()
	if count > 0:
		lines.append("%d craft%s" % [count, "" if count == 1 else "s"])
	return lines


# --- Cosmetics ----------------------------------------------------------------------------------

static func has_cosmetic(id: String) -> bool:
	return id in GameState.hideout_state.get("cosmetics", [])


## Why cosmetic `id` can't be bought now ("" if it can).
static func cosmetic_block_reason(id: String) -> String:
	var entry := find_cosmetic(id)
	if entry.is_empty():
		return "No such cosmetic"
	if has_cosmetic(id):
		return "Already done"
	if GameState.roubles < int(entry.get("roubles", 0)):
		return "Not enough roubles"
	if not ItemSearch.can_afford(Requirement.list(entry.get("requires", []))):
		return "Missing items"
	return ""


## Buys cosmetic `id`: roubles and items paid, saved with the hideout, drawn on the plan. "" on success.
static func buy_cosmetic(id: String) -> String:
	var reason := cosmetic_block_reason(id)
	if reason != "":
		return reason
	var entry := find_cosmetic(id)
	ItemSearch.pay(Requirement.list(entry.get("requires", [])))
	GameState.roubles -= int(entry.get("roubles", 0))
	GameState.hideout_state.cosmetics.append(id)
	return ""


## The cosmetic bought for `slot` ({} if none).
static func cosmetic_in(slot: String) -> Dictionary:
	for entry in cosmetics():
		if entry.get("slot") == slot and has_cosmetic(str(entry.id)):
			return entry
	return {}


# --- Checks -------------------------------------------------------------------------------------

## What's wrong with the hideout data (empty if nothing): every station of ALL_STATIONS once, the shape,
## levels numbered 1 up with a build time, stations, traders and player levels that exist, items that
## exist (named once a level; found in raid from level 2), crafts with ids of their own and a time, rooms
## inside the plan that don't overlap, what each level gives on the station it belongs to (and on every
## level of it), the Stash station (built at level 1 from the start at inventory.tres's size, growing
## every level), rules.json and the cosmetics. Needs the items loaded: ItemDB runs it once it has them.
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
	for wanted: String in ALL_STATIONS:
		if not ids.has(wanted):
			found.append("%s: no %s station" % [STATIONS_PATH, wanted])
	var recipes := {}
	var rooms: Array[Rect2i] = []
	var plan := Rect2i(Vector2i.ZERO, plan_size())
	for station in all:
		var where := "station %s" % station.get("id", "?")
		for key: String in station:
			if not key in STATION_KEYS:
				found.append("%s: unknown key \"%s\"" % [where, key])
		if str(station.get("name", "")).strip_edges() == "":
			found.append("%s: no name" % where)
		found.append_array(_station_problems(station, where))
		var cells: Variant = station.get("room")
		if not (cells is Array and cells.size() == 4 and int(cells[2]) > 0 and int(cells[3]) > 0):
			found.append("%s: needs a room [x, y, w, h]" % where)
		else:
			var rect := room(station)
			if not plan.encloses(rect):
				found.append("%s: room %s isn't inside the %s plan" % [where, rect, plan.size])
			for other in rooms:
				if other.intersects(rect):
					found.append("%s: room %s overlaps another station's" % [where, rect])
			rooms.append(rect)
		var levels: Variant = station.get("levels")
		if not levels is Array or levels.is_empty():
			found.append("%s: no levels" % where)
			continue
		if start_level(station) < 0 or start_level(station) > levels.size():
			found.append("%s: start_level %d isn't 0-%d" % [where, start_level(station), levels.size()])
		for i in levels.size():
			found.append_array(_level_problems(station, levels[i], i + 1, ids))
			if not levels[i] is Dictionary:
				continue
			for key: String in EVERY_LEVEL_KEYS.get(station.get("id"), []):
				if not levels[i].has(key):
					found.append("%s level %d: needs \"%s\"" % [where, i + 1, key])
			for recipe: Variant in levels[i].get("crafts", []):
				var id := str(recipe.get("id", "")) if recipe is Dictionary else ""
				if id == "" or recipes.has(id):
					found.append("%s level %d: a craft needs an id no other craft has (%s)" % [where, i + 1, id])
				recipes[id] = true
	found.append_array(_stash_problems(ids.get(STASH, {})))
	found.append_array(_generator_problems(ids.get(GENERATOR, {})))
	found.append_array(_rules_problems())
	found.append_array(_cosmetic_problems())
	return found


## The station-wide keys: needs_power, unpowered_rate, fuel (the Generator) and cards (the Bitcoin Farm).
static func _station_problems(station: Dictionary, where: String) -> Array[String]:
	var found: Array[String] = []
	if station.has("needs_power") and not station.needs_power is bool:
		found.append("%s: needs_power isn't true or false" % where)
	if station.has("unpowered_rate") and (not _is_number(station.unpowered_rate) or float(station.unpowered_rate) < 0.0
			or float(station.unpowered_rate) > 1.0 or not needs_power(station)):
		found.append("%s: unpowered_rate is a rate from 0 to 1, on a station that needs power" % where)
	if station.has("fuel") and (station.get("id") != GENERATOR or not station.fuel is Dictionary or station.fuel.is_empty()):
		found.append("%s: only the %s has fuel: {item id: minutes}" % [where, GENERATOR])
	elif station.has("fuel"):
		for id: String in station.fuel:
			if not ItemDB.has_item(id) or not _is_number(station.fuel[id]) or float(station.fuel[id]) <= 0.0:
				found.append("%s: fuel %s isn't an item that exists with minutes above 0" % [where, id])
	if station.has("cards") != (station.get("id") == BITCOIN_FARM):
		found.append("station %s needs \"cards\": {\"item\", \"bonus\"}, and only it" % BITCOIN_FARM)
	elif station.has("cards"):
		var cards: Variant = station.cards
		if not (cards is Dictionary and ItemDB.has_item(str(cards.get("item", ""))) and _is_number(cards.get("bonus")) and float(cards.bonus) >= 0.0):
			found.append("%s: cards needs an item that exists and a bonus of 0 or more" % where)
	return found


static func _level_problems(station: Dictionary, entry: Variant, number: int, stations_by_id: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var where := "station %s level %d" % [station.get("id", "?"), number]
	if not entry is Dictionary:
		return ["%s isn't an object" % where]
	for key: String in entry:
		if not key in LEVEL_KEYS:
			found.append("%s: unknown key \"%s\"" % [where, key])
		elif OWN_KEYS.has(key) and OWN_KEYS[key] != station.get("id"):
			found.append("%s: only the %s station sets %s" % [where, OWN_KEYS[key], key])
	if int(entry.get("level", 0)) != number:
		found.append("%s: says level %s (levels go 1, 2, 3...)" % [where, entry.get("level")])
	if int(entry.get("roubles", 0)) < 0:
		found.append("%s: roubles below 0" % where)
	if not _is_number(entry.get("build_minutes")) or float(entry.build_minutes) < 0.0 \
			or (float(entry.build_minutes) == 0.0 and number > start_level(station)):
		found.append("%s: needs build_minutes above 0 (0 only for a level every profile starts with)" % where)
	if entry.has("player_level") and (not _is_number(entry.player_level) or int(entry.player_level) < 1 or int(entry.player_level) > Progression.max_level()):
		found.append("%s: player_level %s isn't a level that exists" % [where, entry.player_level])
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
	var once := {}
	for wanted: Variant in entry.get("requires", []):
		named.append(wanted)
		if wanted is Dictionary:
			if once.has(str(wanted.get("item", ""))):
				found.append("%s: names %s twice (handing over counts each item once)" % [where, wanted.get("item")])
			once[str(wanted.get("item", ""))] = true
			if number >= 2 and not bool(wanted.get("fir", false)):
				found.append("%s: %s must be found in raid (every level from 2 takes found-in-raid items)" % [where, wanted.get("item")])
	for recipe: Variant in entry.get("crafts", []):
		if not (recipe is Dictionary and recipe.get("inputs") is Array and recipe.get("output") is Dictionary):
			found.append("%s: a craft needs \"inputs\" and an \"output\"" % where)
			continue
		for key: String in recipe:
			if not key in RECIPE_KEYS:
				found.append("%s: craft %s: unknown key \"%s\"" % [where, recipe.get("id", "?"), key])
		if not _is_number(recipe.get("minutes")) or float(recipe.minutes) <= 0.0:
			found.append("%s: craft %s needs minutes above 0" % [where, recipe.get("id", "?")])
		named.append_array(recipe.inputs)
		named.append(recipe.output)
	var produces: Variant = entry.get("produces")
	if entry.has("produces"):
		if not EVERY_LEVEL_KEYS.get(station.get("id"), []).has("produces"):
			found.append("%s: only the %s and the %s produce" % [where, WATER_COLLECTOR, BITCOIN_FARM])
		if not (produces is Dictionary and _is_number(produces.get("minutes")) and float(produces.minutes) > 0.0
				and _is_number(produces.get("cap")) and int(produces.cap) >= 1):
			found.append("%s: produces needs an item, minutes above 0 and a cap of 1 or more" % where)
		elif produces is Dictionary:
			named.append({"item": produces.get("item", ""), "count": 1})
	for wanted: Variant in named:
		if not (wanted is Dictionary and ItemDB.has_item(str(wanted.get("item", ""))) and int(wanted.get("count", 1)) >= 1):
			found.append("%s: %s isn't an item that exists with a count of 1 or more" % [where, wanted])
	for key: String in ["scav_cooldown", "insurance_price", "insurance_time"]:
		if entry.has(key) and (not _is_number(entry[key]) or float(entry[key]) <= 0.0 or float(entry[key]) > 1.0):
			found.append("%s: %s is a multiplier above 0, at most 1" % [where, key])
	for key: String in ["scouting", "practice"]:
		if entry.has(key) and (not _is_number(entry[key]) or int(entry[key]) < 1 or int(entry[key]) > 3):
			found.append("%s: %s is a tier from 1 to 3" % [where, key])
	if entry.has("card_slots") and (not _is_number(entry.card_slots) or int(entry.card_slots) < 1):
		found.append("%s: card_slots below 1" % where)
	var training: Variant = entry.get("training")
	if entry.has("training") and not (training is Dictionary and _is_number(training.get("points")) and float(training.points) > 0.0
			and _is_number(training.get("hours")) and float(training.hours) > 0.0):
		found.append("%s: training needs points and hours above 0" % where)
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


## The Generator: some fuel, and fuel slots and efficiency that never go down from level to level.
static func _generator_problems(station: Dictionary) -> Array[String]:
	if station.is_empty():
		return []
	var found: Array[String] = []
	if not station.get("fuel") is Dictionary:
		found.append("station %s: needs \"fuel\": {item id: minutes}" % GENERATOR)
	var last := [0, 0.0]
	for entry: Variant in station.get("levels", []):
		if not (entry is Dictionary and _is_number(entry.get("fuel_slots")) and _is_number(entry.get("fuel_efficiency"))):
			continue
		if int(entry.fuel_slots) < 1 or float(entry.fuel_efficiency) <= 0.0 or int(entry.fuel_slots) < last[0] or float(entry.fuel_efficiency) < last[1]:
			found.append("station %s level %s: fuel slots (1+) and efficiency (above 0) never go down" % [GENERATOR, entry.get("level")])
		last = [int(entry.fuel_slots), float(entry.fuel_efficiency)]
	return found


static func _rules_problems() -> Array[String]:
	var found: Array[String] = []
	var plan: Variant = rules().get("plan")
	if not (plan is Array and plan.size() == 2 and int(plan[0]) > 0 and int(plan[1]) > 0):
		found.append("%s: plan needs [columns, rows]" % RULES_PATH)
	var rate: Variant = rules().get("unpowered_rate")
	if not _is_number(rate) or float(rate) < 0.0 or float(rate) > 1.0:
		found.append("%s: unpowered_rate is a rate from 0 to 1" % RULES_PATH)
	if not _is_number(rules().get("craft_queue")) or int(rules().craft_queue) < 1:
		found.append("%s: craft_queue is 1 or more" % RULES_PATH)
	return found


## Cosmetics: ids of their own, a name, a slot of COSMETIC_SLOTS no other cosmetic takes, a colour,
## a price of 0 or more and items that exist.
static func _cosmetic_problems() -> Array[String]:
	var found: Array[String] = []
	var ids := {}
	var slots := {}
	for entry in cosmetics():
		var id := str(entry.get("id", ""))
		var where := "%s: cosmetic %s" % [COSMETICS_PATH, id]
		for key: String in entry:
			if not key in COSMETIC_KEYS:
				found.append("%s: unknown key \"%s\"" % [where, key])
		if id == "" or ids.has(id):
			found.append("%s: needs an id of its own" % where)
		ids[id] = true
		if str(entry.get("name", "")).strip_edges() == "":
			found.append("%s: no name" % where)
		var slot := str(entry.get("slot", ""))
		if not slot in COSMETIC_SLOTS or slots.has(slot):
			found.append("%s: slot \"%s\" isn't one of %s, or another cosmetic has it" % [where, slot, COSMETIC_SLOTS])
		slots[slot] = true
		var color: Variant = entry.get("color")
		if not (color is Array and color.size() == 3):
			found.append("%s: needs a colour [r, g, b]" % where)
		if not _is_number(entry.get("roubles", 0)) or int(entry.get("roubles", 0)) < 0:
			found.append("%s: roubles below 0" % where)
		for wanted: Variant in entry.get("requires", []):
			if not (wanted is Dictionary and ItemDB.has_item(str(wanted.get("item", ""))) and int(wanted.get("count", 1)) >= 1):
				found.append("%s: %s isn't an item that exists with a count of 1 or more" % [where, wanted])
	return found


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
