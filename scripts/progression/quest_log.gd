class_name QuestLog
extends RefCounted
## Quests (DESIGN.md §11): defined in data/quests/*.json, progress in GameState.quests. Hand-in
## objectives take items from the stash and your character; those marked found in raid only take items
## with the checkmark. You can hand over part of an objective and come back with the rest. Rewards go
## to the stash and are never found in raid.
##
## A quest is {"id", "name", "trader", "description", "requires": [quest ids], "level": the player
## level it needs (leave out for none), "objectives": [...], "rewards": {"roubles", "dollars", "xp",
## "reputation", "drip", "items": [{"item", "count"}]}}. Turning one in adds its experience through
## GameState.add_xp() and its reputation with the trader (loyalty is checked again).
## Objectives: {"type": "hand_in", "item", "count", "fir"}; {"type": "roubles", "count"}: money handed
## over, all at once or bit by bit; or {"type": "trick_kill", "count", "target": "pmc" / "scav" (leave
## out for anyone), "weapon_class": "bolt_action" / "dmr" (leave out for either)}: kills with a 360
## trick shot (DESIGN.md §13.4), counted at the end of each raid while the quest is active, whether you
## survive or not.

## What a trick-kill objective's filters are called.
const TARGET_NAMES := {"pmc": "PMCs", "scav": "Scavs"}
const CLASS_NAMES := {"bolt_action": "a bolt-action rifle", "dmr": "a DMR"}

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


static func for_trader(trader_id: String) -> Array[Dictionary]:
	return all().filter(func(quest: Dictionary) -> bool: return quest.get("trader", "") == trader_id)


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


## Why `quest` can't be accepted yet: "Needs player level 10 · finish Scrap Run first", or "".
static func lock_reason(quest: Dictionary) -> String:
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


## "hand_in", "roubles" or "trick_kill".
static func objective_type(quest: Dictionary, index: int) -> String:
	return str(quest.objectives[index].get("type", "hand_in"))


static func objective_count(quest: Dictionary, index: int) -> int:
	return maxi(int(quest.objectives[index].get("count", 1)), 1)


## What a trick-kill objective asks for, e.g. "360 trick-shot kills on PMCs with a bolt-action rifle".
static func objective_text(quest: Dictionary, index: int) -> String:
	var entry: Dictionary = quest.objectives[index]
	var text := "360 trick-shot kills"
	if TARGET_NAMES.has(entry.get("target", "")):
		text += " on " + TARGET_NAMES[entry.target]
	if CLASS_NAMES.has(entry.get("weapon_class", "")):
		text += " with " + CLASS_NAMES[entry.weapon_class]
	return text


## Counts `kills` (a raid's trick-shot kills: [{"side": "pmc" / "scav", "weapon_class"}]) toward every
## active quest's trick-kill objectives they match.
static func record_trick_kills(kills: Array) -> void:
	for quest in all():
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


## How many have been handed over for objective `index`.
static func progress(quest: Dictionary, index: int) -> int:
	var saved: Array = GameState.quests.get(quest.id, {}).get("progress", [])
	return int(saved[index]) if index < saved.size() else 0


static func accept(quest: Dictionary) -> bool:
	if state(quest) != "available":
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
