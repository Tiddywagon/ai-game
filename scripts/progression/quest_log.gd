class_name QuestLog
extends RefCounted
## Quests (DESIGN.md §11): defined in data/quests/*.json, progress in GameState.quests. Hand-in
## objectives take items from the stash and your character; those marked found in raid only take items
## with the checkmark. You can hand over part of an objective and come back with the rest. Rewards go
## to the stash and are never found in raid.
##
## A quest is {"id", "name", "trader", "description", "requires": [quest ids], "level": the player
## level it needs (leave out for none), "faction": "bear" / "usec" (leave out for both: only that
## faction sees the quest, visible()), "objectives": [...], "rewards": {"roubles", "dollars", "xp",
## "reputation", "drip", "items": [{"item", "count"}]}}. Turning one in adds its experience through
## GameState.add_xp() and its reputation with the trader (loyalty is checked again). A quest of the other
## faction is never shown, accepted or counted (shown(), for_trader()); a barter waiting for one is hidden
## too (BarterTable.visible()). problems() checks the files, run by ItemDB once the items are loaded.
## Objectives: {"type": "hand_in", "item", "count", "fir"}; {"type": "roubles", "count"}: money handed
## over, all at once or bit by bit; {"type": "trick_kill", "count", "target": "pmc" / "scav" (leave
## out for anyone), "weapon_class": "bolt_action" / "dmr" (leave out for either)}: kills with a 360
## trick shot (DESIGN.md §13.4), counted at the end of each raid while the quest is active, whether you
## survive or not; {"type": "kill", "count", "target": "pmc" / "scav", "faction" (a PMC's, leave out for
## either), "map" (leave out for any)}: kills in your PMC raids, counted the same way; {"type":
## "extract", "count", "map" (leave out for any)}: PMC raids survived (extracted; a Run Through doesn't
## count); {"type": "explore", "count", "map"}: points of interest on the map explored, ever (GameState
## .explored, so points found before the quest count too).

## What a trick-kill objective's filters are called.
const TARGET_NAMES := {"pmc": "PMCs", "scav": "Scavs"}
const CLASS_NAMES := {"bolt_action": "a bolt-action rifle", "dmr": "a DMR"}
## The objective types (objective_type()); those counted in raids (by record_raid() and
## record_trick_kills(), or explore's from the explored points) have no HAND OVER button.
const OBJECTIVE_TYPES: Array[String] = ["hand_in", "roubles", "trick_kill", "kill", "extract", "explore"]
const RAID_TYPES: Array[String] = ["trick_kill", "kill", "extract", "explore"]
const QUEST_FIELDS := ["id", "name", "trader", "description", "objectives", "rewards"]

const QUESTS_DIR := "res://data/quests"

static var _quests: Array[Dictionary] = []


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


static func find(id: String) -> Dictionary:
	for quest in all():
		if quest.id == id:
			return quest
	return {}


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


## "locked" (an earlier quest isn't done, or your level is too low: lock_reason()), "available",
## "active", "ready" (everything handed over) or "completed".
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


## Why `quest` can't be accepted yet: "Needs player level 10 · finish Scrap Run first", "For BEAR
## only" (another faction's), or "".
static func lock_reason(quest: Dictionary) -> String:
	if not visible(quest):
		return "For %s only" % Factions.display_name(faction_of(quest))
	var reasons: Array[String] = []
	var level := int(quest.get("level", 1))
	if GameState.level < level:
		reasons.append("Needs player level %d" % level)
	var missing: Array = quest.get("requires", []).filter(func(before: String) -> bool:
		return GameState.quests.get(before, {}).get("state", "") != "completed")
	if not missing.is_empty():
		var names := ", ".join(missing.map(func(id: String) -> String: return str(find(id).get("name", id))))
		reasons.append(("finish %s first" if not reasons.is_empty() else "Finish %s first") % names)
	return "  ·  ".join(reasons)


## Objective `index` of `quest` as an item requirement (hand-in objectives).
static func objective(quest: Dictionary, index: int) -> Requirement:
	return Requirement.from_dict(quest.objectives[index])


## One of OBJECTIVE_TYPES: "hand_in", "roubles", "trick_kill", "kill", "extract" or "explore".
static func objective_type(quest: Dictionary, index: int) -> String:
	return str(quest.objectives[index].get("type", "hand_in"))


static func objective_count(quest: Dictionary, index: int) -> int:
	return maxi(int(quest.objectives[index].get("count", 1)), 1)


## What an objective counted in raids asks for: "360 trick-shot kills on PMCs with a bolt-action
## rifle", "Kill USEC operators on Woodland", "Survive and extract from Customs Yard", "Explore points of
## interest on Shoreline".
static func objective_text(quest: Dictionary, index: int) -> String:
	var entry: Dictionary = quest.objectives[index]
	var map := MapInfo.find(str(entry.get("map", ""))) if str(entry.get("map", "")) != "" else null
	var on := " on %s" % map.display_name if map else ""
	match objective_type(quest, index):
		"kill":
			var faction := StringName(str(entry.get("faction", "")))
			var who := Factions.member_name(faction) + "s" if Factions.has(faction) else str(TARGET_NAMES.get(entry.get("target", ""), "enemies"))
			return "Kill %s%s" % [who, on]
		"extract":
			return "Survive and extract%s" % (" from %s" % map.display_name if map else "")
		"explore":
			return "Explore points of interest%s" % on
	var text := "360 trick-shot kills"
	if TARGET_NAMES.has(entry.get("target", "")):
		text += " on " + TARGET_NAMES[entry.target]
	if CLASS_NAMES.has(entry.get("weapon_class", "")):
		text += " with " + CLASS_NAMES[entry.weapon_class]
	return text


## Counts `kills` (a raid's trick-shot kills: [{"side": "pmc" / "scav", "weapon_class"}]) toward every
## active quest's trick-kill objectives they match.
static func record_trick_kills(kills: Array) -> void:
	for quest in shown():
		if state(quest) != "active":
			continue
		for i in quest.objectives.size():
			if objective_type(quest, i) != "trick_kill":
				continue
			var entry: Dictionary = quest.objectives[i]
			var matching := kills.filter(func(kill: Dictionary) -> bool:
				return str(entry.get("target", kill.side)) == kill.side \
					and str(entry.get("weapon_class", kill.weapon_class)) == kill.weapon_class).size()
			if matching > 0:
				GameState.quests[quest.id].progress[i] = mini(progress(quest, i) + matching, objective_count(quest, i))


## Counts a PMC raid toward every active quest you can see: `kills` (the raid's kill list: [{"side",
## "faction"}]) toward kill objectives they match, and, when you `extracted` (survived, not a Run
## Through), one toward each extract objective for `map_id` or any map.
static func record_raid(kills: Array, extracted: bool, map_id: String) -> void:
	for quest in shown():
		if state(quest) != "active":
			continue
		for i in quest.objectives.size():
			var entry: Dictionary = quest.objectives[i]
			if str(entry.get("map", map_id)) != map_id:
				continue
			var gained := 0
			if objective_type(quest, i) == "kill":
				gained = kills.filter(func(kill: Dictionary) -> bool:
					return str(entry.get("target", kill.get("side", ""))) == str(kill.get("side", "")) \
						and str(entry.get("faction", kill.get("faction", ""))) == str(kill.get("faction", ""))).size()
			elif objective_type(quest, i) == "extract" and extracted:
				gained = 1
			if gained > 0:
				GameState.quests[quest.id].progress[i] = mini(progress(quest, i) + gained, objective_count(quest, i))


## How much of objective `index` is done: handed over, counted in raids, or for an explore objective the
## map's points of interest explored so far (up to its count).
static func progress(quest: Dictionary, index: int) -> int:
	if objective_type(quest, index) == "explore":
		return mini(GameState.explored_count(str(quest.objectives[index].get("map", ""))), objective_count(quest, index))
	var saved: Array = GameState.quests.get(quest.id, {}).get("progress", [])
	return int(saved[index]) if index < saved.size() else 0


static func accept(quest: Dictionary) -> bool:
	if state(quest) != "available" or not visible(quest):
		return false
	var counts: Array = []
	counts.resize(quest.objectives.size())
	counts.fill(0)
	GameState.quests[quest.id] = {"state": "active", "progress": counts}
	return true


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
	if objective_type(quest, index) != "hand_in":
		return 0
	var wanted := objective(quest, index)
	var handed := ItemSearch.take(wanted.item_id, wanted.count - progress(quest, index), wanted.fir)
	GameState.quests[quest.id].progress[index] = progress(quest, index) + handed
	return handed


## Why `quest` can't be turned in yet, or "".
static func complete_block_reason(quest: Dictionary) -> String:
	if state(quest) != "ready":
		return "Hand over everything first"
	for reward in quest.get("rewards", {}).get("items", []):
		var item := ItemInstance.create(str(reward.item), int(reward.get("count", 1)))
		if item and not GameState.stash.has_room_for(item):
			return "No room in the stash for the rewards"
	return ""


## Turns `quest` in: money, reputation with its trader, reward items in the stash, then the experience
## (GameState.add_xp(): the level may go up) and the trader's loyalty checked again. Returns "" on
## success, else why not.
static func complete(quest: Dictionary) -> String:
	var reason := complete_block_reason(quest)
	if reason != "":
		return reason
	var rewards: Dictionary = quest.get("rewards", {})
	GameState.roubles += int(rewards.get("roubles", 0))
	GameState.dollars += int(rewards.get("dollars", 0))
	GameState.drip += int(rewards.get("drip", 0))
	var trader: String = quest.get("trader", "")
	if GameState.trader_loyalty.has(trader):
		GameState.trader_loyalty[trader].reputation = Progression.add_reputation(float(GameState.trader_loyalty[trader].reputation),
			float(rewards.get("reputation", 0.0)))
	for reward in rewards.get("items", []):
		GameState.stash.add(FoundInRaid.make(str(reward.item), int(reward.get("count", 1)), FoundInRaid.Source.QUEST_REWARD))
	GameState.quests[quest.id].state = "completed"
	GameState.add_xp(int(rewards.get("xp", 0)))
	Trading.update_loyalty(trader)
	return ""


## What's wrong with the quest files (empty if nothing): missing fields, ids used twice, a trader,
## item, map or faction that doesn't exist, objectives of an unknown type or without what they need
## (an explore count above the map's points of interest), and the chain: a required quest must exist,
## come earlier in the files (so the chain has no loops) and be for the same faction or everyone (a quest
## for everyone never waits for a faction's).
static func problems() -> Array[String]:
	var found: Array[String] = []
	var seen := {}
	for quest in all():
		var id := str(quest.get("id", ""))
		var where := "quest %s" % id
		for field in QUEST_FIELDS:
			if not quest.has(field):
				found.append("%s: no %s" % [where, field])
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
		var objectives: Variant = quest.get("objectives", [])
		if not objectives is Array or objectives.is_empty():
			found.append("%s: no objectives" % where)
		else:
			for entry: Variant in objectives:
				found.append_array(_objective_problems(where, entry))
		for reward: Variant in quest.get("rewards", {}).get("items", []):
			if not reward is Dictionary or not ItemDB.has_item(str(reward.get("item", ""))) or int(reward.get("count", 1)) < 1:
				found.append("%s: reward %s isn't an item and a count" % [where, reward])
		seen[id] = quest
	return found


static func _objective_problems(where: String, entry: Variant) -> Array[String]:
	if not entry is Dictionary or not str(entry.get("type", "hand_in")) in OBJECTIVE_TYPES:
		return ["%s: objective %s isn't one of %s" % [where, entry, ", ".join(OBJECTIVE_TYPES)]]
	var found: Array[String] = []
	var type := str(entry.get("type", "hand_in"))
	if int(entry.get("count", 1)) < 1:
		found.append("%s: a %s objective needs a count of 1 or more" % [where, type])
	if type == "hand_in" and not ItemDB.has_item(str(entry.get("item", ""))):
		found.append("%s: hand-in item %s doesn't exist" % [where, entry.get("item", "")])
	var map_id := str(entry.get("map", ""))
	if (map_id != "" or type == "explore") and MapInfo.find(map_id) == null:
		found.append("%s: map %s doesn't exist" % [where, map_id])
	if type == "explore" and MapInfo.find(map_id) != null and int(entry.get("count", 1)) > PoiTable.for_map(map_id).size():
		found.append("%s: %d points to explore on %s, which has %d" % [where, int(entry.get("count", 1)), map_id, PoiTable.for_map(map_id).size()])
	if type in ["kill", "trick_kill"] and entry.has("target") and not TARGET_NAMES.has(str(entry.target)):
		found.append("%s: kill target %s isn't pmc or scav" % [where, entry.target])
	if type == "kill" and entry.has("faction") and (not Factions.has(StringName(str(entry.faction))) or str(entry.get("target", "pmc")) != "pmc"):
		found.append("%s: kill faction %s isn't bear or usec, on PMCs" % [where, entry.faction])
	return found
