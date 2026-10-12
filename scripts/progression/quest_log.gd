class_name QuestLog
extends RefCounted
## Quests (DESIGN.md §11): defined in data/quests/*.json, progress in GameState.quests. Hand-in
## objectives take items from the stash and your character; those marked found in raid only take items
## with the checkmark. You can hand over part of an objective and come back with the rest. Rewards go
## to the stash and are never found in raid.
##
## A quest is {"id", "name", "trader", "description", "requires": [quest ids], "objectives":
## [{"type": "hand_in", "item", "count", "fir"}], "rewards": {"roubles", "xp", "reputation",
## "items": [{"item", "count"}]}}.

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


## "locked" (an earlier quest isn't done), "available", "active", "ready" (everything handed over)
## or "completed".
static func state(quest: Dictionary) -> String:
	var saved: Dictionary = GameState.quests.get(quest.id, {})
	if saved.get("state", "") == "completed":
		return "completed"
	if saved.get("state", "") == "active":
		for i in quest.objectives.size():
			if progress(quest, i) < objective(quest, i).count:
				return "active"
		return "ready"
	for before: String in quest.get("requires", []):
		if GameState.quests.get(before, {}).get("state", "") != "completed":
			return "locked"
	return "available"


static func objective(quest: Dictionary, index: int) -> Requirement:
	return Requirement.from_dict(quest.objectives[index])


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


## Hands over as many items as you have (up to what's still needed) for objective `index`. Returns how
## many were handed over.
static func hand_in(quest: Dictionary, index: int) -> int:
	if state(quest) != "active":
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


## Turns `quest` in: money, experience, reputation with its trader, and reward items in the stash.
## Returns "" on success, else why not.
static func complete(quest: Dictionary) -> String:
	var reason := complete_block_reason(quest)
	if reason != "":
		return reason
	var rewards: Dictionary = quest.get("rewards", {})
	GameState.roubles += int(rewards.get("roubles", 0))
	GameState.xp += int(rewards.get("xp", 0))
	var trader: String = quest.get("trader", "")
	if GameState.trader_loyalty.has(trader):
		GameState.trader_loyalty[trader].reputation += float(rewards.get("reputation", 0.0))
	for reward in rewards.get("items", []):
		GameState.stash.add(FoundInRaid.make(str(reward.item), int(reward.get("count", 1)), FoundInRaid.Source.QUEST_REWARD))
	GameState.quests[quest.id].state = "completed"
	return ""
