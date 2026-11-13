class_name QuickBuyTable
extends RefCounted
## The quick-buy cards (DESIGN.md §16.6): one per file in data/quick_buy/<id>.json, the rules in
## data/config/quick_buy.json. QuickBuy prices and buys them; this reads and checks them (problems(),
## run by ItemDB once the items are loaded).
##
## A card: {"id" (its file name), "name", "description", "faction" (optional: "bear" or "usec", only that
## faction sees it), "unlock": {"loyalty": {trader: level}, "tasks": completed quests, "quests": [ids]},
## "gear": {slot: {"item", "trader"}} (the LoadoutPresets slots), "parts": {gun slot: [{"path", "item",
## "trader"}]} (fitted in order, by slot path), "rounds": [{"for": gun slot, "item", "trader", "count"}],
## "carried": [{"item", "trader", "count"}] (meds and anything else for the pockets, rig and backpack)}.
## Each line names the trader it's bought from. The ten cards were designed for the game: the table the
## request named never arrived (DESIGN.md says so).

const CARDS_DIR := "res://data/quick_buy"
const CONFIG_PATH := "res://data/config/quick_buy.json"
const FACTIONS: Array[String] = ["bear", "usec"]
const FIELDS: Array[String] = ["id", "name", "description", "unlock", "gear"]
const GUN_SLOTS: Array[String] = ["primary", "secondary", "pistol"]

static var _cards: Array[Dictionary] = []
static var _config := {}


## Every card, in the order the QUICK BUY tab shows them: the lowest unlock first (the highest loyalty
## level it needs, then its task count), then by name.
static func all() -> Array[Dictionary]:
	if _cards.is_empty():
		for file in DirAccess.get_files_at(CARDS_DIR):
			if not file.ends_with(".json"):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARDS_DIR.path_join(file)))
			if parsed is Dictionary:
				var card: Dictionary = parsed
				card["_file"] = file
				_cards.append(card)
			else:
				push_error("QuickBuyTable: %s isn't a JSON object" % file)
		_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var key_a := [top_level(a), int(a.get("unlock", {}).get("tasks", 0)), str(a.get("name", ""))]
			var key_b := [top_level(b), int(b.get("unlock", {}).get("tasks", 0)), str(b.get("name", ""))]
			return key_a < key_b)
	return _cards


## Forgets the loaded cards and rules (tests that edit them).
static func reload() -> void:
	_cards.clear()
	_config = {}


static func find(id: String) -> Dictionary:
	for card in all():
		if str(card.get("id", "")) == id:
			return card
	return {}


## The highest loyalty level `card`'s unlock asks of any trader (1 for none).
static func top_level(card: Dictionary) -> int:
	var top := 1
	var unlock: Variant = card.get("unlock", {})
	if unlock is Dictionary and unlock.get("loyalty") is Dictionary:
		for trader: String in unlock.loyalty:
			top = maxi(top, int(unlock.loyalty[trader]))
	return top


## The cards a player of `faction` ("bear" or "usec") sees: every card without a faction, and their own.
static func for_faction(faction: String) -> Array[Dictionary]:
	return all().filter(func(card: Dictionary) -> bool: return str(card.get("faction", "")) in ["", faction])


static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {}
		if _config.is_empty():
			push_error("QuickBuyTable: %s isn't valid JSON" % CONFIG_PATH)
	return _config


## The share a card takes off the sum of its lines (0.1).
static func bundle_discount() -> float:
	return float(config().get("bundle_discount", 0.0))


static func min_magazines() -> int:
	return int(config().get("min_magazines", 2))


static func max_custom() -> int:
	return int(config().get("max_custom", 5))


static func name_length() -> int:
	return int(config().get("name_length", 24))


static func penetration_drop() -> float:
	return float(config().get("penetration_drop", 0.0))


## The weight of `key` in how far an alternative is from what it replaces (config "similarity").
static func weight(key: String) -> float:
	return float(config().get("similarity", {}).get(key, 0.0))


# --- Checks -------------------------------------------------------------------------------------

## What's wrong with the rules and every card (empty if nothing). Needs the items loaded: ItemDB runs it.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var where := CONFIG_PATH.get_file()
	var rules := config()
	if not (bundle_discount() > 0.0 and bundle_discount() < 0.5):
		found.append("%s: bundle_discount must be above 0 and below 0.5" % where)
	if min_magazines() < 1 or max_custom() < 1 or name_length() < 1:
		found.append("%s: min_magazines, max_custom and name_length must be 1 or more" % where)
	if not (penetration_drop() >= 0.0 and penetration_drop() < 1.0):
		found.append("%s: penetration_drop must be a share from 0 up to below 1" % where)
	var weights: Variant = rules.get("similarity")
	if not weights is Dictionary or (weights as Dictionary).is_empty() or (weights as Dictionary).values().any(func(value: Variant) -> bool:
			return not (value is float or value is int) or float(value) < 0.0):
		found.append("%s: similarity needs weights of 0 or more" % where)
	var ids := {}
	for card in all():
		var id := str(card.get("id", ""))
		if id == "" or ids.has(id) or str(card.get("_file", id + ".json")) != id + ".json":
			found.append("%s: the id is missing, taken or not the file's name" % str(card.get("_file", id)))
		ids[id] = true
		found.append_array(card_problems(card))
	return found


## What's wrong with one card (crafted ones too: tests), each problem starting with its id.
static func card_problems(card: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var where := "quick buy %s" % str(card.get("id", "?"))
	for field in FIELDS:
		if not card.has(field):
			found.append("%s: no %s" % [where, field])
	if not found.is_empty():
		return found
	if str(card.get("name", "")).strip_edges() == "" or str(card.get("description", "")).strip_edges() == "":
		found.append("%s: needs a name and a description" % where)
	if card.has("faction") and not str(card.faction) in FACTIONS:
		found.append("%s: faction %s isn't bear or usec" % [where, card.faction])
	found.append_array(_unlock_problems(card, where))
	found.append_array(_line_problems(card, where))
	if found.is_empty():
		found.append_array(_kit_problems(card, where))
	return found


static func _unlock_problems(card: Dictionary, where: String) -> Array[String]:
	var found: Array[String] = []
	var unlock: Variant = card.get("unlock")
	if not unlock is Dictionary:
		return ["%s: unlock must be {\"loyalty\", \"tasks\", \"quests\"}" % where]
	var loyalty: Variant = unlock.get("loyalty", {})
	if not loyalty is Dictionary:
		found.append("%s: unlock loyalty must be {trader: level}" % where)
	else:
		for trader: String in loyalty:
			if not TraderTable.has(trader) or int(loyalty[trader]) < 1 or int(loyalty[trader]) > TraderTable.max_loyalty(trader):
				found.append("%s: unlock asks %s for LL%s, not a trader's level" % [where, trader, loyalty[trader]])
	var quests: Variant = unlock.get("quests", [])
	if not quests is Array or quests.any(func(quest: Variant) -> bool: return QuestLog.find(str(quest)).is_empty()):
		found.append("%s: unlock quests must be quests that exist" % where)
	elif quests.any(func(quest: Variant) -> bool:
			return QuestLog.faction_of(QuestLog.find(str(quest))) not in [&"", StringName(str(card.get("faction", "")))]):
		found.append("%s: unlock quests must be quests everyone who sees the card can do (the card's faction or none)" % where)
	var tasks := int(unlock.get("tasks", 0))
	for faction: StringName in ([StringName(str(card.faction))] if Factions.has(StringName(str(card.get("faction", "")))) else Factions.ids()):
		if tasks < 0 or tasks > QuestLog.shown(faction).size():
			found.append("%s: %d tasks completed can't be reached: there are %d quests for %s" % [where, tasks, QuestLog.shown(faction).size(), faction])
	return found


## The lines: items exist, fit their slot or gun, are sold by their trader at a level the unlock reaches,
## counts are right, rounds match a gun and are at least min_magazines() of its magazines, and the packs
## fit within limited stock.
static func _line_problems(card: Dictionary, where: String) -> Array[String]:
	var found: Array[String] = []
	var lines := QuickBuy.lines(card)
	if lines.is_empty():
		return ["%s: the kit is empty" % where]
	var unlock: Dictionary = card.get("unlock", {})
	var reach: Dictionary = unlock.get("loyalty", {}) if unlock.get("loyalty") is Dictionary else {}
	var packs := {}
	var gear: Dictionary = card.get("gear", {}) if card.get("gear") is Dictionary else {}
	var empty := Inventory.new()
	for slot: String in gear:
		if not slot in LoadoutPresets.SLOTS:
			found.append("%s: %s isn't a slot a card fills" % [where, slot])
	for line in lines:
		var name := "%s %s" % [line.kind, line.item]
		var data := ItemDB.get_item(str(line.item)) if ItemDB.has_item(str(line.item)) else null
		if data == null:
			found.append("%s: %s doesn't exist" % [where, name])
			continue
		var offer := QuickBuy.offer_for(str(line.trader), str(line.item))
		if offer.is_empty():
			found.append("%s: %s isn't sold for money by %s" % [where, name, line.trader])
			continue
		if Trading.offer_level(offer) > int(reach.get(line.trader, 1)):
			found.append("%s: %s needs %s LL%d, above the unlock's LL%d" % [where, name, line.trader, Trading.offer_level(offer), int(reach.get(line.trader, 1))])
		var quest := TraderTable.unlock_quest(str(line.trader))
		if quest != "" and not quest in unlock.get("quests", []):
			found.append("%s: %s is %s's, so the unlock must list the quest %s" % [where, name, line.trader, quest])
		match str(line.kind):
			"gear":
				if line.has("count") and int(line.count) != 1:
					found.append("%s: %s must have a count of 1" % [where, name])
				if line.slot in LoadoutPresets.SLOTS and not empty.accepts(str(line.slot), ItemInstance.create(str(line.item))):
					found.append("%s: %s doesn't go in the %s slot" % [where, name, line.slot])
			"part":
				if line.has("count") and int(line.count) != 1:
					found.append("%s: %s must have a count of 1" % [where, name])
				if not WeaponMods.is_mod(data) or WeaponMods.is_gear_mod(data):
					found.append("%s: %s isn't a gun part" % [where, name])
			"rounds", "carried":
				if int(line.get("count", 0)) < 1 or (line.kind == "rounds" and int(line.count) % maxi(int(offer.get("count", 1)), 1) != 0):
					found.append("%s: %s needs a count of 1 or more%s" % [where, name, " in whole packs of %d" % int(offer.get("count", 1)) if line.kind == "rounds" else ""])
				if line.kind == "rounds" and data.category != ItemData.Category.AMMO:
					found.append("%s: %s isn't rounds" % [where, name])
		packs[offer.id] = int(packs.get(offer.id, 0)) + QuickBuy.packs_for(line, offer)
	for trader_id in TraderTable.ids():
		for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
			var stock := TraderStock.stock_of(offer)
			if stock >= 0 and int(packs.get(offer.id, 0)) > stock:
				found.append("%s: takes %d of %s, which sells %d each restock" % [where, int(packs[offer.id]), offer.id, stock])
	return found


## The kit put together on an empty character: parts fit in order, rounds match their gun (enough for
## min_magazines() magazines), and everything fits on you with nothing left over.
static func _kit_problems(card: Dictionary, where: String) -> Array[String]:
	var found: Array[String] = []
	var resolved: Array[Dictionary] = []
	for line in QuickBuy.lines(card):
		var offer := QuickBuy.offer_for(str(line.trader), str(line.item))
		var entry := line.duplicate()
		entry.offer = offer
		entry.packs = QuickBuy.packs_for(line, offer)
		resolved.append(entry)
	var kit := QuickBuy.dress(resolved, null)
	for problem: String in kit.problems:
		found.append("%s: %s" % [where, problem])
	if not kit.overflow.is_empty():
		found.append("%s: doesn't fit on an empty character: %s" % [where, ", ".join(QuickBuy.names(kit.overflow))])
	for line in resolved:
		if line.kind != "rounds":
			continue
		var gun: ItemInstance = kit.inventory.equipment.get(str(line.get("for", "")))
		var ammo := ItemDB.get_item(str(line.item))
		if gun == null or not gun.is_gun() or str(ammo.stats.get("caliber", "")) != gun.data.weapon.caliber:
			found.append("%s: %s don't match a gun on the card (for %s)" % [where, line.item, line.get("for", "")])
		elif int(line.count) < min_magazines() * WeaponMods.capacity(gun):
			found.append("%s: %d × %s is less than %d magazines of the %s (%d)" % [where, int(line.count), line.item, min_magazines(),
				gun.data.display_name, min_magazines() * WeaponMods.capacity(gun)])
	return found
