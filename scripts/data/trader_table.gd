class_name TraderTable
extends RefCounted
## The traders (DESIGN.md §10), from data/traders/traders.json: id, name, role, specialty, personality,
## three greetings (one picked each visit), currency, what sets them apart, how they unlock (null: from
## the start; {"quest": id}: once that quest is done, so "unlocked" follows the quest's state and needs
## no saved flag), what a locked trader says instead of a greeting, and the highest loyalty level they
## go to (Mole, the fence: 1), how often they restock (TraderStock) and what they buy when you sell
## (their "sell" block: Selling). Everything that lists traders or shows a trader's name asks here; where
## a trader is named as a source of something, a locked one says so (locked_suffix()). Checked when it
## loads: problems() (also against offers.json, the quests, the insurers, the gear upgrade sources, the
## faction bonus and the sell blocks; the offers' items and rarity rule, and the barters
## (BarterTable), are checked by Trading.problems() once the items are loaded).

const PATH := "res://data/traders/traders.json"
const FIELDS := ["id", "name", "role", "specialty", "personality", "greetings", "currency", "unique", "unlock", "sell"]
const CURRENCIES := {"RUB": "Roubles", "USD": "Dollars"}
const GREETINGS := 3

## The file read (tests point it at a broken copy, then reload()).
static var path := PATH
static var _traders: Array[Dictionary] = []
static var _loaded := false


## Every trader, in screen order.
static func all() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true  # Before problems(), which lists the traders again.
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("traders") is Array:
			for entry: Variant in parsed.traders:
				if entry is Dictionary:
					_traders.append(entry)
			for problem in problems():
				push_warning("TraderTable: %s" % problem)
		else:
			push_error("TraderTable: %s isn't valid JSON with a \"traders\" list" % path)
	return _traders


## Reads the file again on next use.
static func reload() -> void:
	_traders = []
	_loaded = false


## Every trader id, in screen order.
static func ids() -> Array[String]:
	var result: Array[String] = []
	for entry in all():
		result.append(str(entry.get("id", "")))
	return result


## Trader `id`'s entry ({} if there's no such trader).
static func find(id: String) -> Dictionary:
	for entry in all():
		if entry.get("id", "") == id:
			return entry
	return {}


static func has(id: String) -> bool:
	return not find(id).is_empty()


## "Auntie Zoya" (the id itself, capitalized, for an unknown trader).
static func display_name(id: String) -> String:
	return str(find(id).get("name", id.capitalize()))


## "Roubles" or "Dollars": what `id`'s prices are in.
static func currency_name(id: String) -> String:
	return str(CURRENCIES.get(find(id).get("currency", "RUB"), "Roubles"))


## One of `id`'s greetings, picked with `rng` (else at random).
static func greeting(id: String, rng: RandomNumberGenerator = null) -> String:
	var lines: Array = find(id).get("greetings", [])
	if lines.is_empty():
		return ""
	return str(lines[rng.randi_range(0, lines.size() - 1) if rng else randi() % lines.size()])


## What `id` says while they don't trade with you yet ("" if nothing).
static func locked_greeting(id: String) -> String:
	return str(find(id).get("locked_greeting", ""))


## The highest loyalty level `id` goes to.
static func max_loyalty(id: String) -> int:
	return clampi(int(find(id).get("max_loyalty", Progression.max_loyalty())), 1, Progression.max_loyalty())


## Real minutes between `id`'s restocks (their "restock_minutes", else data/config/trading.json's).
static func restock_minutes(id: String) -> float:
	return float(find(id).get("restock_minutes", Trading.config().get("restock_minutes", 60.0)))


## The quest that unlocks `id` ("" if they trade from the start).
static func unlock_quest(id: String) -> String:
	var unlock: Variant = find(id).get("unlock")
	return str(unlock.get("quest", "")) if unlock is Dictionary else ""


## True once `id` trades with you: from the start, or once their unlock quest is completed.
static func is_unlocked(id: String) -> bool:
	var quest_id := unlock_quest(id)
	if quest_id == "":
		return true
	var quest := QuestLog.find(quest_id)
	return not quest.is_empty() and QuestLog.state(quest) == "completed"


## " (locked)" while `id` doesn't trade with you yet, else "": after a trader named as where something
## comes from ("The Broker LL1 (locked)": AmmoChart.sources(), ItemUses.of()).
static func locked_suffix(id: String) -> String:
	return "" if is_unlocked(id) else " (locked)"


## Why `id` doesn't trade with you yet ("" once they do): "Finish Auntie Zoya's task A Word in His
## Ear (from player level 10) to trade with The Broker."
static func lock_text(id: String) -> String:
	if is_unlocked(id):
		return ""
	var quest := QuestLog.find(unlock_quest(id))
	if quest.is_empty():
		return "%s doesn't trade with you yet." % display_name(id)
	var level := int(quest.get("level", 1))
	return "Finish %s's task %s%s to trade with %s." % [display_name(str(quest.get("trader", ""))), quest.get("name", quest.id),
		" (from player level %d)" % level if level > 1 else "", display_name(id)]


## What's wrong with traders.json and the files that name traders (empty if nothing).
static func problems() -> Array[String]:
	var found: Array[String] = []
	var traders := all()
	if traders.is_empty():
		return ["%s: no traders" % path]
	var seen: Array[String] = []
	var names: Array[String] = []
	for entry in traders:
		var id := str(entry.get("id", ""))
		var where := "trader %s" % (id if id != "" else str(entry))
		for field in FIELDS:
			if not entry.has(field):
				found.append("%s: no %s" % [where, field])
		if id == "" or id in seen:
			found.append("%s: the id is missing or taken" % where)
		seen.append(id)
		var name := str(entry.get("name", ""))
		if name == "" or name in names:
			found.append("%s: the name is missing or taken" % where)
		names.append(name)
		for field in ["role", "specialty", "personality", "unique"]:
			if str(entry.get(field, "")).strip_edges() == "":
				found.append("%s: %s is empty" % [where, field])
		var greetings: Variant = entry.get("greetings", [])
		if not greetings is Array or greetings.size() < GREETINGS or greetings.any(func(line: Variant) -> bool: return str(line).strip_edges() == ""):
			found.append("%s: needs %d greetings" % [where, GREETINGS])
		if not CURRENCIES.has(str(entry.get("currency", ""))):
			found.append("%s: currency %s isn't RUB or USD" % [where, entry.get("currency", "")])
		var unlock: Variant = entry.get("unlock")
		if unlock != null and not (unlock is Dictionary and QuestLog.find(str(unlock.get("quest", ""))).size() > 0):
			found.append("%s: unlock %s isn't null or a quest that exists" % [where, unlock])
		if unlock != null and str(entry.get("locked_greeting", "")).strip_edges() == "":
			found.append("%s: needs a locked_greeting (it has an unlock)" % where)
		if entry.has("restock_minutes") and float(entry.restock_minutes) <= 0.0:
			found.append("%s: restock_minutes must be above 0" % where)
		var top := int(entry.get("max_loyalty", Progression.max_loyalty()))
		if top < 1 or top > Progression.max_loyalty():
			found.append("%s: max_loyalty %d isn't 1-%d" % [where, top, Progression.max_loyalty()])
		var offers: Dictionary = Trading.all_offers().get(id, {})
		if not offers.get("buy") is Array:
			found.append("%s: no \"buy\" list in %s" % [where, Trading.OFFERS_PATH])
	for key: String in Trading.all_offers():
		if not key.begins_with("_") and not key in seen:
			found.append("%s: %s isn't a trader" % [Trading.OFFERS_PATH, key])
	for quest in QuestLog.all():
		if not str(quest.get("trader", "")) in seen:
			found.append("quest %s: trader %s doesn't exist" % [quest.get("id", ""), quest.get("trader", "")])
	for insurer: Dictionary in Insurance.insurers():
		if not str(insurer.get("id", "")) in seen:
			found.append("insurer %s isn't a trader" % insurer.get("id", ""))
	for source in GearUpgrades.sources():
		if source != GearUpgrades.WORKBENCH and not source in seen:
			found.append("gear upgrade source %s isn't a trader" % source)
	for faction: int in GameState.FACTION_TRADER:
		if not GameState.FACTION_TRADER[faction] in seen:
			found.append("faction trader %s isn't a trader" % GameState.FACTION_TRADER[faction])
	found.append_array(Selling.problems())
	return found
