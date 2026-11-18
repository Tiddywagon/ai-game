class_name QuestLog
extends RefCounted
## Quests (DESIGN.md §11): defined in data/quests/*.json, progress in GameState.quests. Hand-in
## objectives take items from the stash and your character; those marked found in raid only take items
## with the checkmark. You can hand over part of an objective and come back with the rest. Rewards go
## to the stash and are never found in raid.
##
## A quest is {"id", "name", "trader" (who gives it), "description" (the briefing), "success" (the
## trader's line when you turn it in; optional), "requires": [quest ids, every one completed], "level":
## the player level it needs, "loyalty": {trader id: loyalty level} it needs, "faction": "bear" / "usec"
## (leave out for both: only that faction sees the quest, visible()), "gives": [{"item", "count"}] (quest
## items put in the stash when you accept: a marker to place; one lost can be taken again for free,
## retake_marker()), "objectives": [...], "rewards": {"roubles", "dollars", "xp", "reputation" (with the
## giver), "reputation_with": {trader id: amount} (others), "drip", "items": [{"item", "count"}]}}.
## What a quest unlocks (barters, buy offers, crafts, extracts, quick-buy cards, a trader) is written on
## the thing it unlocks as "quest": id (cards: "unlock": {"quests": [...]}, a trader: "unlock": {"quest"});
## unlocks() gathers them all.
##
## Objectives (OBJECTIVE_KEYS lists each type's keys; every one also takes "text", shown instead of the
## generated line):
## - {"type": "hand_in", "item", "count", "fir"}; {"type": "figures", "count", "figures": {"rarity",
##   "set"}, "fir"} (spare figures, Figures.spares()); {"type": "roubles", "count"}: HAND OVER at the
##   trader, part now and the rest later.
## - {"type": "kill", "count", "target": any / scav / pmc / boss / guard (leave out for any), "faction",
##   "boss" (a boss id: that boss), "map", "weapon" (an item id), "weapon_class", "body_part" (where the
##   killing hit landed: head, thorax, stomach, arms, legs, left_arm, ...), "min_distance" (metres),
##   "survive"}; {"type": "trick_kill", "count", "target": scav / pmc, "weapon_class", "map", "survive"}:
##   a 360 trick-shot kill (DESIGN.md §13.4). A kill counts for every active objective it fits.
## - {"type": "visit", "map", "poi" or "spot", "survive"}: reach a location (a point of interest,
##   PoiTable, or a named quest spot, data/config/quest_spots.json).
## - {"type": "place", "item", "count", "map", "poi" or "spot", "seconds", "survive"}: hold the interact
##   key at the location (QuestSite) and the item leaves your inventory; {"type": "mark", ...}: the same
##   with the quest's marker (its first "gives" item unless "item" says otherwise).
## - {"type": "extract", "count", "map", "extract" (an extract id)}: survive and extract (a Run Through
##   doesn't count); {"type": "extract_with", "item", "count", "fir", "map"}: extract carrying the item
##   (each extract adds what you carry out, up to the count; you keep it).
## - {"type": "explore", "count", "map"}: points of interest explored on the map, ever.
## - {"type": "craft", "count", "recipe" / "item" / "station"}: crafts collected at the hideout (a craft
##   id, a craft's output item, or any craft at a station).
## - {"type": "upgrade", "station", "level"}; {"type": "level", "level"}; {"type": "loyalty", "trader",
##   "level"}: state checks, already true means already done (progress shows the level so far).
## Raid objectives count in PMC raids only (not Scav runs, not Shooting Range practice): QuestRaid counts
## kills, visits and placements the moment they happen, and they stay if you die; with "survive": true
## an objective's progress from a raid only counts if you extract (SURVIVED). problems() checks the files,
## run by ItemDB once the items are loaded.

## Kill targets and what the objective line calls them.
const TARGET_NAMES := {"any": "enemies", "pmc": "PMCs", "scav": "Scavs", "boss": "bosses", "guard": "boss guards"}
const CLASS_NAMES := {"bolt_action": "a bolt-action rifle", "dmr": "a DMR"}
## Body parts a kill objective can ask for, by name: the BodyHealth parts each covers.
const BODY_PARTS := {"head": [0], "thorax": [1], "stomach": [2], "left_arm": [3], "right_arm": [4], "left_leg": [5],
	"right_leg": [6], "arms": [3, 4], "legs": [5, 6], "torso": [1, 2]}
## Every objective type and the keys it takes ("type" and "text" are always allowed).
const OBJECTIVE_KEYS := {
	"hand_in": ["item", "count", "fir"],
	"figures": ["figures", "count", "fir"],
	"roubles": ["count"],
	"kill": ["count", "target", "faction", "boss", "map", "weapon", "weapon_class", "body_part", "min_distance", "survive"],
	"trick_kill": ["count", "target", "weapon_class", "map", "survive"],
	"visit": ["map", "poi", "spot", "survive"],
	"place": ["item", "count", "map", "poi", "spot", "seconds", "survive"],
	"mark": ["item", "count", "map", "poi", "spot", "seconds", "survive"],
	"extract": ["count", "map", "extract"],
	"extract_with": ["item", "count", "fir", "map"],
	"explore": ["count", "map"],
	"craft": ["count", "recipe", "item", "station"],
	"upgrade": ["station", "level"],
	"level": ["level"],
	"loyalty": ["trader", "level"],
}
## The objective types (objective_type()), in the order the docs list them.
const OBJECTIVE_TYPES: Array[String] = ["hand_in", "figures", "roubles", "kill", "trick_kill", "visit", "place", "mark",
	"extract", "extract_with", "explore", "craft", "upgrade", "level", "loyalty"]
## Counted in raids (no HAND OVER button): QuestRaid.
const RAID_TYPES: Array[String] = ["kill", "trick_kill", "visit", "place", "mark", "extract", "extract_with", "explore"]
## Handed over at the trader (HAND OVER).
const HAND_TYPES: Array[String] = ["hand_in", "figures", "roubles"]
## Worked out from the profile each time (progress() reads the state, nothing is saved).
const STATE_TYPES: Array[String] = ["explore", "upgrade", "level", "loyalty"]
## Raid objectives at a location (a point of interest or a quest spot), and those that may be "survive".
const LOCATION_TYPES: Array[String] = ["visit", "place", "mark"]
const SURVIVE_TYPES: Array[String] = ["kill", "trick_kill", "visit", "place", "mark"]
## Objectives that name an item you need to bring (the needed-for icon, ItemUses).
const ITEM_TYPES: Array[String] = ["hand_in", "place", "extract_with"]
const QUEST_FIELDS := ["id", "name", "trader", "description", "objectives", "rewards"]
const QUEST_KEYS := ["id", "name", "trader", "description", "success", "requires", "level", "loyalty", "faction", "gives",
	"objectives", "rewards"]
const REWARD_KEYS := ["roubles", "dollars", "xp", "reputation", "reputation_with", "drip", "items"]
## Up to this many quests are tracked on the HUD (track()).
const MAX_TRACKED := 3

const QUESTS_DIR := "res://data/quests"
const SPOTS_PATH := "res://data/config/quest_spots.json"
## Seconds a placement takes when the objective doesn't say.
const PLACE_SECONDS := 4.0

static var _quests: Array[Dictionary] = []
static var _spots: Dictionary = {}


static func all() -> Array[Dictionary]:
	if _quests.is_empty():
		for file in DirAccess.get_files_at(QUESTS_DIR):
			if not file.ends_with(".json"):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_DIR.path_join(file)))
			if parsed is Array:
				for quest: Dictionary in parsed:
					_quests.append(quest)
			else:
				push_error("QuestLog: %s isn't a JSON list of quests" % file)
	return _quests


## Reads the quest files again (tests that edit a copy).
static func reload() -> void:
	_quests.clear()
	_spots.clear()


static func find(id: String) -> Dictionary:
	for quest in all():
		if quest.id == id:
			return quest
	return {}


## Named quest spots by map: {map id: {spot id: {"name", "position": [x, y, z], "radius"}}}
## (data/config/quest_spots.json): places in a map that aren't points of interest.
static func spots() -> Dictionary:
	if _spots.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPOTS_PATH))
		_spots = parsed.get("maps", {}) if parsed is Dictionary else {}
	return _spots


static func spot(map_id: String, spot_id: String) -> Dictionary:
	return spots().get(map_id, {}).get(spot_id, {})


## `trader_id`'s quests you can see (visible()), in file order.
static func for_trader(trader_id: String) -> Array[Dictionary]:
	return shown().filter(func(quest: Dictionary) -> bool: return quest.get("trader", "") == trader_id)


## The faction `quest` is for (&"bear", &"usec"), &"" for every faction.
static func faction_of(quest: Dictionary) -> StringName:
	return StringName(str(quest.get("faction", "")))


## True when `quest` is for everyone or for `faction` (your profile's faction when &"none").
static func visible(quest: Dictionary, faction: StringName = &"none") -> bool:
	if faction == &"none":
		faction = Factions.of_profile(GameState.faction)
	return faction_of(quest) == &"" or faction_of(quest) == faction


## The quests you can see (visible()): what the TASKS tabs show and every quest count goes by (quick-buy
## unlocks, the items still needed). `faction` as in visible().
static func shown(faction: StringName = &"none") -> Array[Dictionary]:
	return all().filter(func(quest: Dictionary) -> bool: return visible(quest, faction))


# --- States ----------------------------------------------------------------------------------------

## "locked" (lock_reason()), "available", "active", "ready" (every objective done) or "completed".
static func state(quest: Dictionary) -> String:
	var saved: Dictionary = GameState.quests.get(quest.id, {})
	if saved.get("state", "") == "completed":
		return "completed"
	if saved.get("state", "") == "active":
		for i in quest.objectives.size():
			if progress(quest, i) < objective_count(quest, i):
				return "active"
		return "ready"
	return "locked" if lock_reason(quest) != "" else "available"


## True once `quest_id` is completed (a quest id the files no longer have counts too, from the save).
static func is_completed(quest_id: String) -> bool:
	return str(GameState.quests.get(quest_id, {}).get("state", "")) == "completed"


## Why `quest` can't be accepted yet: "Needs player level 10 · Bulat LL2 · finish Scrap Run first",
## "For BEAR only" (another faction's), or "".
static func lock_reason(quest: Dictionary) -> String:
	if not visible(quest):
		return "For %s only" % Factions.display_name(faction_of(quest))
	var reasons: Array[String] = []
	var level := int(quest.get("level", 1))
	if GameState.level < level:
		reasons.append("Needs player level %d" % level)
	var loyalty: Dictionary = quest.get("loyalty", {})
	for trader: String in loyalty:
		if Hideout.loyalty(trader) < int(loyalty[trader]):
			reasons.append(("needs %s LL%d" if not reasons.is_empty() else "Needs %s LL%d") % [TraderTable.display_name(trader), int(loyalty[trader])])
	var missing: Array = quest.get("requires", []).filter(func(before: String) -> bool: return not is_completed(before))
	if not missing.is_empty():
		var names := ", ".join(missing.map(func(id: String) -> String: return str(find(id).get("name", id))))
		reasons.append(("finish %s first" if not reasons.is_empty() else "Finish %s first") % names)
	return "  ·  ".join(reasons)


## The chain before `quest`, for the quest log: [{"name", "done"}] for each required quest, then the
## level and loyalty it needs ("after Old Unit ✓").
static func prerequisites(quest: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for before: String in quest.get("requires", []):
		result.append({"name": "after %s" % str(find(before).get("name", before)), "done": is_completed(before)})
	if int(quest.get("level", 1)) > 1:
		result.append({"name": "level %d" % int(quest.level), "done": GameState.level >= int(quest.level)})
	var loyalty: Dictionary = quest.get("loyalty", {})
	for trader: String in loyalty:
		result.append({"name": "%s LL%d" % [TraderTable.display_name(trader), int(loyalty[trader])], "done": Hideout.loyalty(trader) >= int(loyalty[trader])})
	return result


## The quests that need `quest` done (the next links of its chain), in file order.
static func followers(quest: Dictionary) -> Array[Dictionary]:
	return shown().filter(func(other: Dictionary) -> bool: return quest.id in other.get("requires", []))


# --- Objectives ----------------------------------------------------------------------------------

## Objective `index` of `quest` as an item requirement (hand-in objectives).
static func objective(quest: Dictionary, index: int) -> Requirement:
	return Requirement.from_dict(quest.objectives[index])


## One of OBJECTIVE_TYPES.
static func objective_type(quest: Dictionary, index: int) -> String:
	return str(quest.objectives[index].get("type", "hand_in"))


## How much an objective asks for: its count, or for upgrade / level / loyalty the level.
static func objective_count(quest: Dictionary, index: int) -> int:
	var entry: Dictionary = quest.objectives[index]
	if str(entry.get("type", "")) in ["upgrade", "level", "loyalty"]:
		return maxi(int(entry.get("level", 1)), 1)
	if str(entry.get("type", "")) == "visit":
		return 1
	return maxi(int(entry.get("count", 1)), 1)


## The marker item a mark objective places (its "item", else the quest's first "gives" item), or a place
## objective's item.
static func place_item(quest: Dictionary, index: int) -> String:
	var entry: Dictionary = quest.objectives[index]
	if entry.has("item"):
		return str(entry.item)
	var gives: Array = quest.get("gives", [])
	return str(gives[0].get("item", "")) if not gives.is_empty() else ""


## The location of a visit, place or mark objective: {"map", "poi" or "spot", "name"}, {} for others.
static func location(quest: Dictionary, index: int) -> Dictionary:
	var entry: Dictionary = quest.objectives[index]
	if not str(entry.get("type", "")) in LOCATION_TYPES:
		return {}
	var map_id := str(entry.get("map", ""))
	if entry.has("spot"):
		return {"map": map_id, "spot": str(entry.spot), "name": str(spot(map_id, str(entry.spot)).get("name", entry.spot))}
	return {"map": map_id, "poi": str(entry.get("poi", "")), "name": str(PoiTable.find(map_id, str(entry.get("poi", ""))).get("name", entry.get("poi", "")))}


## What an objective asks for, as the log and the TASKS tab show it: "Kill Scavs on Test Yard with a
## headshot", "Place a quest marker at Signal hut", "Survive and extract from Factory through Gate 3".
static func objective_text(quest: Dictionary, index: int) -> String:
	var entry: Dictionary = quest.objectives[index]
	if entry.has("text"):
		return str(entry.text)
	var map := MapInfo.find(str(entry.get("map", ""))) if str(entry.get("map", "")) != "" else null
	var on := " on %s" % map.display_name if map else ""
	var type := str(entry.get("type", "hand_in"))
	match type:
		"hand_in", "extract_with":
			var item_name := ExtractTable.item_name(str(entry.get("item", "")))
			if type == "hand_in":
				return "Hand over %s%s" % [item_name, " (found in raid)" if entry.get("fir", false) else ""]
			return "Extract%s carrying %s%s" % [" from %s" % map.display_name if map else "", item_name, " (found in raid)" if entry.get("fir", false) else ""]
		"figures":
			return "Hand over spare figures"
		"roubles":
			return "Hand over roubles"
		"kill":
			return "Kill %s%s%s" % [_kill_who(entry), on, _kill_conditions(entry)]
		"extract":
			var text := "Survive and extract%s" % (" from %s" % map.display_name if map else "")
			if str(entry.get("extract", "")) != "" and map:
				text += " through %s" % str(ExtractTable.find(map.id, str(entry.extract)).get("name", entry.extract))
			return text
		"explore":
			return "Explore points of interest%s" % on
		"visit", "place", "mark":
			var where := location(quest, index)
			var at := "%s%s" % [where.name, on]
			if type == "visit":
				return "Reach %s" % at
			return "Place %s at %s" % [ExtractTable.item_name(place_item(quest, index)), at]
		"craft":
			if entry.has("recipe"):
				return "Craft %s" % _recipe_name(str(entry.recipe))
			if entry.has("item"):
				return "Craft %s" % ExtractTable.item_name(str(entry.item))
			return "Craft anything at the %s" % str(Hideout.find(str(entry.get("station", ""))).get("name", entry.get("station", "")))
		"upgrade":
			return "Build the %s to level %d" % [str(Hideout.find(str(entry.get("station", ""))).get("name", entry.get("station", ""))), int(entry.get("level", 1))]
		"level":
			return "Reach player level %d" % int(entry.get("level", 1))
		"loyalty":
			return "Reach loyalty level %d with %s" % [int(entry.get("level", 1)), TraderTable.display_name(str(entry.get("trader", "")))]
	var trick := "360 trick-shot kills"
	if TARGET_NAMES.has(entry.get("target", "")) and entry.target != "any":
		trick += " on " + TARGET_NAMES[entry.target]
	if CLASS_NAMES.has(entry.get("weapon_class", "")):
		trick += " with " + CLASS_NAMES[entry.weapon_class]
	return trick + on


static func _kill_who(entry: Dictionary) -> String:
	if entry.has("boss"):
		return str(_boss_entry(str(entry.boss)).get("name", entry.boss))
	var faction := StringName(str(entry.get("faction", "")))
	if Factions.has(faction):
		return Factions.member_name(faction) + "s"
	return str(TARGET_NAMES.get(str(entry.get("target", "any")), "enemies"))


static func _kill_conditions(entry: Dictionary) -> String:
	var parts: Array[String] = []
	if entry.has("weapon"):
		parts.append("with %s" % ExtractTable.item_name(str(entry.weapon)))
	elif entry.has("weapon_class"):
		parts.append("with %s" % str(CLASS_NAMES.get(str(entry.weapon_class), "a " + str(entry.weapon_class).replace("_", " "))))
	if entry.has("body_part"):
		parts.append("a headshot" if entry.body_part == "head" else "hits to the %s" % str(entry.body_part).replace("_", " "))
	if entry.has("min_distance"):
		parts.append("from %d m or more" % int(entry.min_distance))
	return (", " + ", ".join(parts)) if not parts.is_empty() else ""


## The boss entry (data/config/bosses.json) with id `boss_id`, and its map as "map".
static func _boss_entry(boss_id: String) -> Dictionary:
	for map_id: String in BossTable.maps():
		var entry: Dictionary = BossTable.maps()[map_id]
		if str(entry.get("id", "")) == boss_id:
			var result := entry.duplicate()
			result.map = map_id
			return result
	return {}


static func _recipe_name(recipe_id: String) -> String:
	var found := find_recipe(recipe_id)
	return ExtractTable.item_name(str(found.get("recipe", {}).get("output", {}).get("item", recipe_id))) if not found.is_empty() else recipe_id


## The hideout craft with id `recipe_id`: {"station": station id, "level", "recipe"}, {} if none.
static func find_recipe(recipe_id: String) -> Dictionary:
	for station in Hideout.stations():
		for pair: Array in Hideout.all_crafts(station):
			if str(pair[1].get("id", "")) == recipe_id:
				return {"station": str(station.id), "level": int(pair[0]), "recipe": pair[1]}
	return {}


## How much of objective `index` is done: handed over or counted in raids (saved), or for the state
## types worked out now: points explored, the station's level, your level or loyalty (up to the count).
static func progress(quest: Dictionary, index: int) -> int:
	var entry: Dictionary = quest.objectives[index]
	var count := objective_count(quest, index)
	match str(entry.get("type", "hand_in")):
		"explore":
			return mini(GameState.explored_count(str(entry.get("map", ""))), count)
		"upgrade":
			var station := Hideout.find(str(entry.get("station", "")))
			return mini(Hideout.level(station), count) if not station.is_empty() else 0
		"level":
			return mini(GameState.level, count)
		"loyalty":
			return mini(Hideout.loyalty(str(entry.get("trader", ""))), count)
	var saved: Array = GameState.quests.get(quest.id, {}).get("progress", [])
	return int(saved[index]) if index < saved.size() else 0


## Adds `amount` to objective `index` of an active `quest` (up to its count). Returns how much it moved.
static func add_progress(quest: Dictionary, index: int, amount: int) -> int:
	if amount <= 0 or str(GameState.quests.get(quest.id, {}).get("state", "")) != "active":
		return 0
	var saved: Array = GameState.quests[quest.id].progress
	while saved.size() < quest.objectives.size():
		saved.append(0)
	var before := progress(quest, index)
	saved[index] = mini(before + amount, objective_count(quest, index))
	return int(saved[index]) - before


## The active quests you can see.
static func active() -> Array[Dictionary]:
	return shown().filter(func(quest: Dictionary) -> bool: return state(quest) == "active")


## True when objective `entry` fits `kill`: {"side": "pmc" / "scav", "faction", "role": "boss" /
## "guard", "boss" (the boss's id), "weapon" (item id), "weapon_class", "part" (BodyHealth.Part, -1
## unknown), "distance" (metres), "trick" (a 360 trick shot)} on `map_id`.
static func kill_fits(entry: Dictionary, kill: Dictionary, map_id: String) -> bool:
	if str(entry.get("map", map_id)) != map_id:
		return false
	var type := str(entry.get("type", ""))
	if type == "trick_kill" and not bool(kill.get("trick", false)):
		return false
	if type != "kill" and type != "trick_kill":
		return false
	match str(entry.get("target", "any")):
		"pmc", "scav":
			if str(kill.get("side", "")) != str(entry.target):
				return false
		"boss", "guard":
			if str(kill.get("role", "")) != str(entry.target):
				return false
	if entry.has("faction") and str(kill.get("faction", "")) != str(entry.faction):
		return false
	if entry.has("boss") and (str(kill.get("role", "")) != "boss" or str(kill.get("boss", "")) != str(entry.boss)):
		return false
	if entry.has("weapon") and str(kill.get("weapon", "")) != str(entry.weapon):
		return false
	if entry.has("weapon_class") and str(kill.get("weapon_class", "")) != str(entry.weapon_class):
		return false
	if entry.has("body_part") and not int(kill.get("part", -1)) in BODY_PARTS.get(str(entry.body_part), []):
		return false
	if entry.has("min_distance") and float(kill.get("distance", 0.0)) < float(entry.min_distance):
		return false
	return true


## Counts `kills` (trick-shot kills: [{"side", "weapon_class"}]) toward active trick-kill objectives,
## as one PMC raid on any map (QuestRaid does this live; kept for callers with a list).
static func record_trick_kills(kills: Array) -> void:
	var raid := QuestRaid.new("", true)
	raid.any_map = true
	for kill: Dictionary in kills:
		var entry := kill.duplicate()
		entry.trick = true
		raid.on_kill(entry)
	raid.settle(false, "", null)


## Counts a PMC raid on `map_id` all at once: `kills` (the kill list: [{"side", "faction", "role"}])
## toward the kill objectives they fit and, when you `extracted` (SURVIVED), one toward each extract
## objective for that map or any (QuestRaid does it live in a raid).
static func record_raid(kills: Array, extracted: bool, map_id: String) -> void:
	var raid := QuestRaid.new(map_id, true)
	for kill: Dictionary in kills:
		raid.on_kill(kill)
	raid.settle(extracted, "", null)


## A craft collected at the hideout (HideoutWork.collect()): one toward every active craft objective
## it fits (`recipe_id` at `station_id`, making `item_id`). Returns the objectives that moved.
static func record_craft(station_id: String, recipe_id: String, item_id: String) -> int:
	var moved := 0
	for quest in active():
		for i in quest.objectives.size():
			var entry: Dictionary = quest.objectives[i]
			if objective_type(quest, i) != "craft":
				continue
			if (entry.has("recipe") and str(entry.recipe) != recipe_id) or (entry.has("item") and str(entry.item) != item_id) \
					or (entry.has("station") and str(entry.station) != station_id):
				continue
			moved += signi(add_progress(quest, i, 1))
	return moved


# --- Accepting, handing over, turning in -----------------------------------------------------------

## Why `quest` can't be accepted, or "".
static func accept_block_reason(quest: Dictionary) -> String:
	if not visible(quest):
		return "For %s only" % Factions.display_name(faction_of(quest))
	if state(quest) != "available":
		return lock_reason(quest) if state(quest) == "locked" else "Already taken"
	for given in gives(quest):
		if not GameState.stash.has_room_for(given):
			return "No room in the stash for %s" % given.data.display_name
	return ""


## The quest items `quest` hands out on accept (new instances, never found in raid).
static func gives(quest: Dictionary) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for entry: Dictionary in quest.get("gives", []):
		result.append_array(pieces(str(entry.get("item", "")), int(entry.get("count", 1))))
	return result


## `count` of item `id` as stacks no bigger than its max stack (one each for an item that doesn't
## stack), from a quest: never found in raid.
static func pieces(id: String, count: int) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	var first := FoundInRaid.make(id, count, FoundInRaid.Source.QUEST_REWARD)
	if first == null:
		return result
	if first.data.max_stack <= 1:
		first.count = 1
		result.append(first)
		for i in count - 1:
			result.append(FoundInRaid.make(id, 1, FoundInRaid.Source.QUEST_REWARD))
		return result
	result.append(first)
	result.append_array(first.split_excess())
	return result


## The reward items of `quest` as stacks (pieces()).
static func reward_items(quest: Dictionary) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for reward: Dictionary in quest.get("rewards", {}).get("items", []):
		result.append_array(pieces(str(reward.get("item", "")), int(reward.get("count", 1))))
	return result


static func accept(quest: Dictionary) -> bool:
	if accept_block_reason(quest) != "":
		return false
	var counts: Array = []
	counts.resize(quest.objectives.size())
	counts.fill(0)
	GameState.quests[quest.id] = {"state": "active", "progress": counts}
	for given in gives(quest):
		GameState.stash.add(given)
	if not quest.get("gives", []).is_empty():
		GameState.quests[quest.id].given = 1
	return true


## True when an active `quest` still has a mark / place objective for its marker and you have none of
## it left (stash or character): retake_marker() hands one over again for free.
static func can_retake_marker(quest: Dictionary) -> bool:
	if state(quest) != "active" or quest.get("gives", []).is_empty():
		return false
	for i in quest.objectives.size():
		if objective_type(quest, i) in ["mark", "place"] and progress(quest, i) < objective_count(quest, i):
			var item_id := place_item(quest, i)
			if item_id == str(quest.gives[0].get("item", "")) and ItemSearch.count(item_id, false) == 0:
				return true
	return false


## Hands the quest's items out again ("" on success).
static func retake_marker(quest: Dictionary) -> String:
	if not can_retake_marker(quest):
		return "You still have it"
	for given in gives(quest):
		if not GameState.stash.add(given):
			return "No room in the stash"
	GameState.quests[quest.id].given = int(GameState.quests[quest.id].get("given", 0)) + 1
	return ""


## Hands over as many items as you have (up to what's still needed) for objective `index`, or for a
## roubles objective as much money as you have. Returns how many (items or roubles) were handed over.
static func hand_in(quest: Dictionary, index: int) -> int:
	if state(quest) != "active":
		return 0
	if objective_type(quest, index) == "roubles":
		var paid := mini(GameState.roubles, objective_count(quest, index) - progress(quest, index))
		if paid <= 0:
			return 0
		GameState.roubles -= paid
		GameState.quests[quest.id].progress[index] = progress(quest, index) + paid
		return paid
	if not objective_type(quest, index) in ["hand_in", "figures"]:
		return 0
	var wanted := objective(quest, index)
	var handed := Figures.take_spares(wanted.figures, wanted.count - progress(quest, index), wanted.fir) if wanted.is_generic() \
		else ItemSearch.take(wanted.item_id, wanted.count - progress(quest, index), wanted.fir)
	GameState.quests[quest.id].progress[index] = progress(quest, index) + handed
	return handed


## Why `quest` can't be turned in yet, or "".
static func complete_block_reason(quest: Dictionary) -> String:
	if state(quest) != "ready":
		return "Finish every objective first"
	for item in reward_items(quest):
		if not GameState.stash.has_room_for(item):
			return "No room in the stash for the rewards"
	return ""


## Turns `quest` in: money, reputation with its trader (and any others it names), reward items in the
## stash, the quest items it gave that are left are taken back, then the experience (GameState.add_xp():
## the level may go up) and the traders' loyalty checked again. Returns "" on success, else why not.
static func complete(quest: Dictionary) -> String:
	var reason := complete_block_reason(quest)
	if reason != "":
		return reason
	var rewards: Dictionary = quest.get("rewards", {})
	GameState.roubles += int(rewards.get("roubles", 0))
	GameState.dollars += int(rewards.get("dollars", 0))
	GameState.drip += int(rewards.get("drip", 0))
	var trader: String = quest.get("trader", "")
	var reputation := {trader: float(rewards.get("reputation", 0.0))}
	var others: Dictionary = rewards.get("reputation_with", {})
	for other: String in others:
		reputation[other] = float(reputation.get(other, 0.0)) + float(others[other])
	for id: String in reputation:
		if GameState.trader_loyalty.has(id):
			GameState.trader_loyalty[id].reputation = Progression.add_reputation(float(GameState.trader_loyalty[id].reputation), reputation[id])
	for item in reward_items(quest):
		GameState.stash.add(item)
	for given: Dictionary in quest.get("gives", []):
		var id := str(given.get("item", ""))
		if ItemDB.has_item(id) and ItemDB.get_item(id).base_value == 0:
			ItemSearch.take(id, ItemSearch.count(id, false), false)
	GameState.quests[quest.id].state = "completed"
	GameState.add_xp(int(rewards.get("xp", 0)))
	for id: String in reputation:
		Trading.update_loyalty(id)
	return ""


## The reward lines of `quest`: "25,000 ₽", "1,500 XP", "+0.05 Bulat", "60× 5.45x39 BS", "25 Drip".
static func reward_lines(quest: Dictionary) -> Array[String]:
	var rewards: Dictionary = quest.get("rewards", {})
	var lines: Array[String] = []
	if int(rewards.get("roubles", 0)) > 0:
		lines.append("%s ₽" % UiFormat.thousands(int(rewards.roubles)))
	if int(rewards.get("dollars", 0)) > 0:
		lines.append("$%s" % UiFormat.thousands(int(rewards.dollars)))
	if int(rewards.get("xp", 0)) > 0:
		lines.append("%s XP" % UiFormat.thousands(int(rewards.xp)))
	if float(rewards.get("reputation", 0.0)) > 0.0:
		lines.append("+%.2f %s" % [float(rewards.reputation), TraderTable.display_name(str(quest.get("trader", "")))])
	var others: Dictionary = rewards.get("reputation_with", {})
	for other: String in others:
		lines.append("%+.2f %s" % [float(others[other]), TraderTable.display_name(other)])
	if int(rewards.get("drip", 0)) > 0:
		lines.append("%d Drip" % int(rewards.drip))
	for reward: Dictionary in rewards.get("items", []):
		var count := int(reward.get("count", 1))
		lines.append(("%d× %s" % [count, ExtractTable.item_name(str(reward.item))]) if count > 1 else ExtractTable.item_name(str(reward.item)))
	return lines


## Everything finishing `quest` unlocks, from the things that name it: [{"kind": "barter" / "offer" /
## "craft" / "extract" / "quick_buy" / "trader", "id", "text"}].
static func unlocks(quest: Dictionary) -> Array[Dictionary]:
	var id := str(quest.get("id", ""))
	var result: Array[Dictionary] = []
	for barter in BarterTable.all():
		if BarterTable.quest(barter) == id:
			result.append({"kind": "barter", "id": str(barter.get("id", "")), "text": "A barter with %s: %s" % [
				TraderTable.display_name(str(barter.get("trader", ""))), BarterTable.reward_text(barter)]})
	for trader_id in TraderTable.ids():
		for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
			if str(offer.get("quest", "")) == id:
				result.append({"kind": "offer", "id": str(offer.get("id", "")), "text": "%s sells %s (LL%d)" % [TraderTable.display_name(trader_id),
					ExtractTable.item_name(str(offer.get("item", ""))), Trading.offer_level(offer)]})
		if TraderTable.unlock_quest(trader_id) == id:
			result.append({"kind": "trader", "id": trader_id, "text": "Trading with %s" % TraderTable.display_name(trader_id)})
	for station in Hideout.stations():
		for pair: Array in Hideout.all_crafts(station):
			if str(pair[1].get("quest", "")) == id:
				result.append({"kind": "craft", "id": str(pair[1].get("id", "")), "text": "A craft at the %s: %s" % [station.name,
					ExtractTable.item_name(str(pair[1].get("output", {}).get("item", "")))]})
	for found: Dictionary in ExtractTable.unlocked_by(id):
		var map := MapInfo.find(str(found.map))
		result.append({"kind": "extract", "id": str(found.entry.get("id", "")), "text": "An extract on %s: %s" % [
			map.display_name if map else found.map, found.entry.get("name", "")]})
	for card in QuickBuyTable.all():
		var unlock: Variant = card.get("unlock", {})
		if unlock is Dictionary and id in unlock.get("quests", []):
			result.append({"kind": "quick_buy", "id": str(card.get("id", "")), "text": "Quick-buy loadout %s" % card.get("name", "")})
	return result


# --- Tracking ------------------------------------------------------------------------------------

## The quests tracked on the HUD (ids, at most MAX_TRACKED, active ones only).
static func tracked() -> Array[String]:
	var result: Array[String] = []
	for id: String in GameState.quest_tracked:
		var quest := find(id)
		if not quest.is_empty() and state(quest) in ["active", "ready"]:
			result.append(id)
	return result


static func is_tracked(quest: Dictionary) -> bool:
	return str(quest.get("id", "")) in tracked()


## Tracks or stops tracking `quest`. "" on success, else why not (only active quests, MAX_TRACKED at once).
static func set_tracked(quest: Dictionary, on: bool) -> String:
	var id := str(quest.get("id", ""))
	GameState.quest_tracked = tracked()
	if not on:
		GameState.quest_tracked.erase(id)
		return ""
	if not state(quest) in ["active", "ready"]:
		return "Only active quests can be tracked"
	if id in GameState.quest_tracked:
		return ""
	if GameState.quest_tracked.size() >= MAX_TRACKED:
		return "Up to %d quests can be tracked" % MAX_TRACKED
	GameState.quest_tracked.append(id)
	return ""


# --- Checking the files --------------------------------------------------------------------------

## What's wrong with the quest files (empty if nothing): missing or unknown fields, ids used twice, a
## trader, item, map, boss, location, station, craft, extract or faction that doesn't exist, objectives
## of an unknown type or without what they need, rewards and quest items that aren't items, and the
## chain: a required quest must exist, come earlier in the files (so the chain has no loops) and be for
## the same faction or everyone (a quest for everyone never waits for a faction's). Then the quest
## spots and every unlock that names a quest (barters, buy offers, crafts, extracts, cards, traders).
static func problems() -> Array[String]:
	var found: Array[String] = []
	var seen := {}
	for quest in all():
		var id := str(quest.get("id", ""))
		var where := "quest %s" % id
		for field in QUEST_FIELDS:
			if not quest.has(field):
				found.append("%s: no %s" % [where, field])
		for key: String in quest:
			if not key in QUEST_KEYS:
				found.append("%s: unknown key \"%s\"" % [where, key])
		if seen.has(id):
			found.append("%s: the id is used twice" % where)
		if not TraderTable.has(str(quest.get("trader", ""))):
			found.append("%s: trader %s doesn't exist" % [where, quest.get("trader", "")])
		var faction := faction_of(quest)
		if faction != &"" and not Factions.has(faction):
			found.append("%s: faction %s isn't bear or usec" % [where, faction])
		for before: Variant in quest.get("requires", []):
			var earlier: Dictionary = seen.get(str(before), {})
			if earlier.is_empty():
				found.append("%s: requires %s, which isn't a quest listed before it" % [where, before])
			elif faction_of(earlier) != &"" and faction_of(earlier) != faction:
				found.append("%s: requires %s, a quest for %s only" % [where, before, faction_of(earlier)])
		var loyalty: Variant = quest.get("loyalty", {})
		if not loyalty is Dictionary:
			found.append("%s: loyalty must be {trader id: level}" % where)
		else:
			for trader: Variant in loyalty:
				if not TraderTable.has(str(trader)) or int(loyalty[trader]) < 1 or int(loyalty[trader]) > TraderTable.max_loyalty(str(trader)):
					found.append("%s: loyalty %s LL%s isn't a trader's level" % [where, trader, loyalty[trader]])
		for given: Variant in quest.get("gives", []):
			if not given is Dictionary or not ItemDB.has_item(str(given.get("item", ""))) or int(given.get("count", 1)) < 1:
				found.append("%s: quest item %s isn't an item and a count" % [where, given])
		var objectives: Variant = quest.get("objectives", [])
		if not objectives is Array or objectives.is_empty():
			found.append("%s: no objectives" % where)
		else:
			for i in objectives.size():
				found.append_array(_objective_problems(where, quest, i))
		found.append_array(_reward_problems(where, quest.get("rewards", {})))
		seen[id] = quest
	found.append_array(_spot_problems())
	return found


static func _reward_problems(where: String, rewards: Variant) -> Array[String]:
	if not rewards is Dictionary:
		return ["%s: rewards must be an object" % where]
	var found: Array[String] = []
	for key: String in rewards:
		if not key in REWARD_KEYS:
			found.append("%s: unknown reward \"%s\"" % [where, key])
	for key in ["roubles", "dollars", "xp", "drip", "reputation"]:
		if rewards.has(key) and not ((rewards[key] is int or rewards[key] is float) and float(rewards[key]) >= 0.0):
			found.append("%s: reward %s must be a number, 0 or more" % [where, key])
	var others: Variant = rewards.get("reputation_with", {})
	if not others is Dictionary or (others as Dictionary).keys().any(func(trader: Variant) -> bool: return not TraderTable.has(str(trader))):
		found.append("%s: reputation_with must be {trader id: amount}" % where)
	for reward: Variant in rewards.get("items", []):
		if not reward is Dictionary or not ItemDB.has_item(str(reward.get("item", ""))) or int(reward.get("count", 1)) < 1:
			found.append("%s: reward %s isn't an item and a count" % [where, reward])
	return found


static func _objective_problems(where: String, quest: Dictionary, index: int) -> Array[String]:
	var entry: Variant = quest.objectives[index]
	if not entry is Dictionary or not str(entry.get("type", "hand_in")) in OBJECTIVE_TYPES:
		return ["%s: objective %s isn't one of %s" % [where, entry, ", ".join(OBJECTIVE_TYPES)]]
	var found: Array[String] = []
	var type := str(entry.get("type", "hand_in"))
	for key: String in entry:
		if not key in OBJECTIVE_KEYS[type] and key != "type" and key != "text":
			found.append("%s: a %s objective has no \"%s\"" % [where, type, key])
	if int(entry.get("count", 1)) < 1:
		found.append("%s: a %s objective needs a count of 1 or more" % [where, type])
	if type in ["hand_in", "place", "extract_with"] and not ItemDB.has_item(str(entry.get("item", ""))):
		found.append("%s: %s item %s doesn't exist" % [where, type, entry.get("item", "")])
	if type == "mark" and not ItemDB.has_item(place_item(quest, index)):
		found.append("%s: a mark objective needs the quest to give a marker (gives) or an item" % where)
	if type == "figures" and Figures.filter_problem(entry.get("figures")) != "":
		found.append("%s: %s" % [where, Figures.filter_problem(entry.get("figures"))])
	var map_id := str(entry.get("map", ""))
	if (map_id != "" or type in ["explore", "visit", "place", "mark"]) and MapInfo.find(map_id) == null:
		found.append("%s: map %s doesn't exist" % [where, map_id])
	if type == "explore" and MapInfo.find(map_id) != null and int(entry.get("count", 1)) > PoiTable.for_map(map_id).size():
		found.append("%s: %d points to explore on %s, which has %d" % [where, int(entry.get("count", 1)), map_id, PoiTable.for_map(map_id).size()])
	if type in LOCATION_TYPES and MapInfo.find(map_id) != null:
		if entry.has("poi") == entry.has("spot"):
			found.append("%s: a %s objective needs a poi or a spot (one of them)" % [where, type])
		elif entry.has("poi") and PoiTable.find(map_id, str(entry.poi)).is_empty():
			found.append("%s: point of interest %s isn't on %s" % [where, entry.poi, map_id])
		elif entry.has("spot") and spot(map_id, str(entry.spot)).is_empty():
			found.append("%s: quest spot %s isn't on %s (%s)" % [where, entry.spot, map_id, SPOTS_PATH.get_file()])
	if entry.has("seconds") and float(entry.seconds) <= 0.0:
		found.append("%s: seconds must be above 0" % where)
	if entry.has("survive") and not entry.survive is bool:
		found.append("%s: survive must be true or false" % where)
	if type in ["kill", "trick_kill"]:
		if entry.has("target") and not TARGET_NAMES.has(str(entry.target)):
			found.append("%s: kill target %s isn't one of %s" % [where, entry.target, ", ".join(TARGET_NAMES.keys())])
		if type == "trick_kill" and str(entry.get("target", "any")) in ["boss", "guard"]:
			found.append("%s: a trick-kill target is pmc or scav" % where)
		if entry.has("faction") and (not Factions.has(StringName(str(entry.faction))) or str(entry.get("target", "pmc")) != "pmc"):
			found.append("%s: kill faction %s isn't bear or usec, on PMCs" % [where, entry.faction])
		if entry.has("boss"):
			var boss := _boss_entry(str(entry.boss))
			if boss.is_empty():
				found.append("%s: boss %s doesn't exist" % [where, entry.boss])
			elif map_id != "" and str(boss.map) != map_id:
				found.append("%s: boss %s isn't on %s" % [where, entry.boss, map_id])
			if str(entry.get("target", "boss")) != "boss":
				found.append("%s: a boss kill's target is boss" % where)
		if entry.has("weapon") and not (ItemDB.has_item(str(entry.weapon)) and ItemDB.get_item(str(entry.weapon)).weapon != null):
			found.append("%s: weapon %s isn't a gun" % [where, entry.weapon])
		if entry.has("weapon_class") and not str(entry.weapon_class) in ["assault_rifle", "pistol", "bolt_action", "dmr", "smg", "shotgun", "lmg"]:
			found.append("%s: weapon class %s doesn't exist" % [where, entry.weapon_class])
		if entry.has("body_part") and not BODY_PARTS.has(str(entry.body_part)):
			found.append("%s: body part %s isn't one of %s" % [where, entry.body_part, ", ".join(BODY_PARTS.keys())])
		if entry.has("min_distance") and float(entry.min_distance) <= 0.0:
			found.append("%s: min_distance must be above 0" % where)
	if type == "extract" and entry.has("extract") and (map_id == "" or ExtractTable.find(map_id, str(entry.extract)).is_empty()):
		found.append("%s: extract %s isn't on map %s" % [where, entry.extract, map_id])
	if type == "craft":
		var kinds := ["recipe", "item", "station"].filter(func(key: String) -> bool: return entry.has(key))
		if kinds.size() != 1:
			found.append("%s: a craft objective names one of recipe, item or station" % where)
		elif entry.has("recipe") and find_recipe(str(entry.recipe)).is_empty():
			found.append("%s: craft %s doesn't exist" % [where, entry.recipe])
		elif entry.has("item") and not _crafted(str(entry.item)):
			found.append("%s: no craft makes %s" % [where, entry.item])
		elif entry.has("station") and Hideout.all_crafts(Hideout.find(str(entry.station))).is_empty():
			found.append("%s: station %s has no crafts" % [where, entry.station])
	if type == "upgrade":
		var station := Hideout.find(str(entry.get("station", "")))
		if station.is_empty() or int(entry.get("level", 0)) < 1 or int(entry.get("level", 0)) > Hideout.max_level(station):
			found.append("%s: station %s level %s doesn't exist" % [where, entry.get("station", ""), entry.get("level", "")])
	if type == "level" and int(entry.get("level", 0)) < 2:
		found.append("%s: a level objective needs a level of 2 or more" % where)
	if type == "loyalty" and (not TraderTable.has(str(entry.get("trader", ""))) or int(entry.get("level", 0)) < 2
			or int(entry.get("level", 0)) > TraderTable.max_loyalty(str(entry.get("trader", "")))):
		found.append("%s: loyalty %s LL%s isn't a level to reach" % [where, entry.get("trader", ""), entry.get("level", "")])
	if type in ["upgrade", "level", "loyalty", "visit"] and entry.has("count"):
		found.append("%s: a %s objective has no count" % [where, type])
	return found


static func _crafted(item_id: String) -> bool:
	for station in Hideout.stations():
		for pair: Array in Hideout.all_crafts(station):
			if str(pair[1].get("output", {}).get("item", "")) == item_id:
				return true
	return false


## The quest spots file: every spot on a map that exists, with a name, a position [x, y, z] and a radius
## above 0; and every quest named by a craft or a buy offer exists.
static func _spot_problems() -> Array[String]:
	var found: Array[String] = []
	for map_id: String in spots():
		if MapInfo.find(map_id) == null:
			found.append("%s: map %s doesn't exist" % [SPOTS_PATH.get_file(), map_id])
		for spot_id: String in spots()[map_id]:
			var entry: Variant = spots()[map_id][spot_id]
			if not (entry is Dictionary and entry.get("name") is String and entry.get("position") is Array and (entry.position as Array).size() == 3
					and float(entry.get("radius", 0.0)) > 0.0):
				found.append("%s: spot %s on %s needs a name, a position [x, y, z] and a radius" % [SPOTS_PATH.get_file(), spot_id, map_id])
	for station in Hideout.stations():
		for pair: Array in Hideout.all_crafts(station):
			if pair[1].has("quest") and find(str(pair[1].quest)).is_empty():
				found.append("craft %s: quest %s doesn't exist" % [pair[1].get("id", ""), pair[1].quest])
	for trader_id in TraderTable.ids():
		for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
			if offer.has("quest") and find(str(offer.quest)).is_empty():
				found.append("offer %s: quest %s doesn't exist" % [offer.get("id", ""), offer.quest])
	return found
