class_name ExtractTable
extends RefCounted
## Every map's extracts (DESIGN.md §5), from data/config/extracts.json: 1 to 3 per map, at least one
## always open for every side. Types: "always", "random" (open this raid with `chance`) and
## "conditional" (needs an item such as a key, roubles paid at the extract, the power on, a flare
## fired in it, gear left behind, or a finished quest). Map scenes place them as ExtractZones by id;
## the rules live here (ExtractZone.configure()).

const PATH := "res://data/config/extracts.json"
const TYPES := ["always", "random", "conditional"]
const SIDES := ["Both", "PMC", "Scav"]
## Fields that make an extract conditional.
const CONDITIONS := ["item", "price", "power", "flare", "no_gear", "quest"]
const FIELDS := ["id", "name", "type", "chance", "item", "consumes", "price", "power", "flare", "no_gear", "sides", "quest"]
const MIN_EXTRACTS := 1
const MAX_EXTRACTS := 3

static var _maps := {}


## {map id: [extract entries]}.
static func maps() -> Dictionary:
	if _maps.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and parsed.get("maps") is Dictionary:
			_maps = parsed.maps
			for problem in problems():
				push_warning("ExtractTable: %s" % problem)
		else:
			push_error("ExtractTable: %s isn't valid JSON with a \"maps\" object" % PATH)
	return _maps


## `map_id`'s extracts, in table order (quest-locked ones included).
static func for_map(map_id: String) -> Array:
	return maps().get(map_id, [])


static func find(map_id: String, id: String) -> Dictionary:
	for entry: Dictionary in for_map(map_id):
		if entry.get("id", "") == id:
			return entry
	return {}


## True when the extract exists for this profile: it needs no quest, or the quest is completed.
static func is_unlocked(entry: Dictionary) -> bool:
	var quest := str(entry.get("quest", ""))
	return quest == "" or GameState.quests.get(quest, {}).get("state", "") == "completed"


## The extracts `quest_id` unlocks: [{"map": map id, "entry": extract entry}].
static func unlocked_by(quest_id: String) -> Array:
	var found := []
	for map_id: String in maps():
		for entry: Dictionary in maps()[map_id]:
			if str(entry.get("quest", "")) == quest_id:
				found.append({"map": map_id, "entry": entry})
	return found


## What an extract takes, as short phrases: "Factory exit key", "power on", "pay 7,000 ₽", "fire a
## flare", "no backpack", "Scav only", "after Flare Path" (empty for none).
static func condition_texts(entry: Dictionary) -> PackedStringArray:
	var texts := PackedStringArray()
	var sides := str(entry.get("sides", "Both"))
	if sides != "Both":
		texts.append("%s only" % sides)
	if str(entry.get("item", "")) != "":
		texts.append(item_name(str(entry.item)) + (" (used up)" if entry.get("consumes", false) else ""))
	if int(entry.get("price", 0)) > 0:
		texts.append("pay %s" % UiFormat.money(int(entry.price)))
	if entry.get("power", false):
		texts.append("power on")
	if entry.get("flare", false):
		texts.append("fire a flare")
	for slot: String in entry.get("no_gear", []):
		texts.append("no %s" % slot_name(slot).to_lower())
	if str(entry.get("quest", "")) != "":
		var quest := QuestLog.find(str(entry.quest))
		texts.append("after %s" % quest.get("name", entry.quest))
	return texts


## "Always open", "Random (40%)" or "Conditional: Factory exit key, power on".
static func kind_text(entry: Dictionary) -> String:
	match str(entry.get("type", "always")):
		"random":
			return "Random (%d%%)" % roundi(float(entry.get("chance", 0.5)) * 100.0)
		"conditional":
			return "Conditional: %s" % ", ".join(condition_texts(entry))
	return "Always open"


## The map select line: "3: Gate 3 (always open), Office window (random, 40%), Cellars (Factory exit
## key, power on)".
static func summary(map_id: String) -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in for_map(map_id):
		var kind := "always open"
		match str(entry.get("type", "always")):
			"random":
				kind = "random, %d%%" % roundi(float(entry.get("chance", 0.5)) * 100.0)
			"conditional":
				kind = ", ".join(condition_texts(entry))
		parts.append("%s (%s)" % [entry.get("name", "?"), kind])
	return "%d: %s" % [parts.size(), ", ".join(parts)] if not parts.is_empty() else "none"


static func item_name(item_id: String) -> String:
	return ItemDB.get_item(item_id).display_name if ItemDB.has_item(item_id) else item_id


## "Backpack", "Body armor"... (Inventory.SLOTS).
static func slot_name(slot: String) -> String:
	for entry: Array in Inventory.SLOTS:
		if entry[0] == slot:
			return entry[1]
	return slot


## Everything wrong with the table, as messages: a map with too few or too many extracts or no
## always-open one for a side, unknown types, fields, items, quests or slots, a random extract with
## conditions...
static func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var map_ids := MapInfo.load_all().map(func(map: MapInfo) -> String: return map.id)
	for map_id: String in map_ids:
		if not maps().has(map_id):
			found.append("%s has no extracts" % map_id)
	var slots := Inventory.SLOTS.map(func(slot: Array) -> String: return slot[0])
	for map_id: String in maps():
		var entries: Array = maps()[map_id]
		if not map_id in map_ids:
			found.append("%s isn't a map (data/maps/)" % map_id)
		if entries.size() < MIN_EXTRACTS or entries.size() > MAX_EXTRACTS:
			found.append("%s has %d extracts (%d to %d)" % [map_id, entries.size(), MIN_EXTRACTS, MAX_EXTRACTS])
		for side in ["PMC", "Scav"]:
			if not entries.any(func(entry: Dictionary) -> bool:
					return entry.get("type", "") == "always" and str(entry.get("sides", "Both")) in ["Both", side]):
				found.append("%s has no always-open extract for %ss" % [map_id, side])
		var ids := {}
		for entry: Dictionary in entries:
			var where := "%s/%s" % [map_id, entry.get("id", "?")]
			if str(entry.get("id", "")) == "" or str(entry.get("name", "")) == "":
				found.append("%s: needs an id and a name" % where)
			if ids.has(entry.get("id", "")):
				found.append("%s: id used twice" % where)
			ids[entry.get("id", "")] = true
			for key: String in entry:
				if not key in FIELDS:
					found.append("%s: unknown field \"%s\"" % [where, key])
			var type := str(entry.get("type", ""))
			var conditions := CONDITIONS.filter(func(key: String) -> bool: return entry.has(key) and entry[key])
			if not type in TYPES:
				found.append("%s: type \"%s\" (use one of %s)" % [where, type, ", ".join(TYPES)])
			elif type == "always" and (not conditions.is_empty() or entry.has("chance")):
				found.append("%s: an always-open extract can't have a chance or conditions" % where)
			elif type == "random":
				var chance := float(entry.get("chance", -1.0))
				if chance <= 0.0 or chance >= 1.0:
					found.append("%s: a random extract needs a chance between 0 and 1" % where)
				if not conditions.is_empty():
					found.append("%s: a random extract can't have conditions" % where)
			elif type == "conditional":
				if conditions.is_empty() and str(entry.get("sides", "Both")) == "Both":
					found.append("%s: a conditional extract needs a condition" % where)
				if entry.has("chance"):
					found.append("%s: a conditional extract can't have a chance" % where)
			if not str(entry.get("sides", "Both")) in SIDES:
				found.append("%s: sides \"%s\" (use Both, PMC or Scav)" % [where, entry.sides])
			if str(entry.get("item", "")) != "" and not ItemDB.has_item(str(entry.item)):
				found.append("%s: unknown item \"%s\"" % [where, entry.item])
			if str(entry.get("quest", "")) != "" and QuestLog.find(str(entry.quest)).is_empty():
				found.append("%s: unknown quest \"%s\"" % [where, entry.quest])
			for slot: String in entry.get("no_gear", []):
				if not slot in slots:
					found.append("%s: unknown slot \"%s\" in no_gear" % [where, slot])
	return found
