class_name SkinTable
extends RefCounted
## Cosmetic skins and the Drip slot machine as data (DESIGN.md §6.7). The skins: data/cosmetics/*.json,
## one collection a file ({"collection": {"id", "name", "about", "season" (true for a seasonal one)},
## "skins": [...]}), each skin {"id", "name", "rarity" (a ItemData.RARITY_IDS entry), "kind" (KINDS),
## what it fits ("weapon": a gun's item id, or "class": a weapon class, or "item": an armor, helmet,
## rig or backpack id, or "faction": "bear" / "usec" for an outfit; none of them: every item of its
## kind), "bound" (optional: true makes it bound whatever its rarity), "look": {"base", "accent" (colours,
## "#rrggbb"), "pattern" (PATTERNS), "scale" (optional, the pattern's size)}}. data/config/slots.json:
## the machine (price, odds, pity, duplicates, bound rarities, wear bands, seasons, near misses, the
## cosmetic slots each kind of item has). data/config/drip.json: the Drip earned. Read once, checked by
## problems() when the items load (ItemDB). What the profile does with them is Cosmetics.

const DIR := "res://data/cosmetics"
const SLOTS_PATH := "res://data/config/slots.json"
const DRIP_PATH := "res://data/config/drip.json"
## What a skin can be for: the item kinds (item_kind()), the character's outfit, stickers and charms.
const KINDS: Array[String] = ["weapon", "armor", "helmet", "backpack", "rig", "outfit", "knife", "sticker", "charm"]
const KIND_TITLES := {"weapon": "Weapon", "armor": "Body armor", "helmet": "Helmet", "backpack": "Backpack", "rig": "Rig",
	"outfit": "Outfit", "knife": "Knife", "sticker": "Sticker", "charm": "Charm"}
## How a skin's look is drawn (assets/shaders/skin.gdshaderinc, the same order).
const PATTERNS: Array[String] = ["solid", "camo", "stripes", "hex", "splatter", "gradient", "glow"]
## The cosmetic slots an item may have: a skin of its own kind, a sticker, a charm.
const SLOTS: Array[String] = ["skin", "sticker", "charm"]
const SKIN_KEYS := ["id", "name", "rarity", "kind", "weapon", "class", "item", "faction", "bound", "look"]
const FACTIONS := ["bear", "usec"]

## Where the files are (tests point them at broken copies).
static var dir := DIR
static var slots_path := SLOTS_PATH
static var drip_path := DRIP_PATH
static var _collections: Array[Dictionary] = []
static var _skins: Dictionary = {}
static var _slots := {}
static var _drip := {}
static var _file_problems: Array[String] = []


## Forgets what was loaded (tests that point the paths somewhere else).
static func reload() -> void:
	_collections = []
	_skins = {}
	_slots = {}
	_drip = {}
	_file_problems = []


static func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if parsed is Dictionary:
		return parsed
	_file_problems.append("%s isn't valid JSON" % path)
	return {}


## data/config/slots.json.
static func config() -> Dictionary:
	if _slots.is_empty():
		_slots = _read(slots_path)
	return _slots


## data/config/drip.json.
static func drip_config() -> Dictionary:
	if _drip.is_empty():
		_drip = _read(drip_path)
	return _drip


## The collections: core ones first, then the seasonal ones in the rotation's order. Each {"id", "name",
## "about", "season", "skins": [skin dictionaries]}.
static func collections() -> Array[Dictionary]:
	if _collections.is_empty():
		_load()
	return _collections


static func _load() -> void:
	var files := Array(DirAccess.get_files_at(dir)).filter(func(file: String) -> bool: return file.ends_with(".json"))
	files.sort()
	var loaded: Array[Dictionary] = []
	for file: String in files:
		var data := _read(dir.path_join(file))
		if data.is_empty():
			continue
		var collection: Dictionary = data.get("collection", {}).duplicate()
		collection.season = bool(collection.get("season", false))
		collection.skins = []
		for entry: Variant in data.get("skins", []):
			if entry is Dictionary:
				var skin: Dictionary = entry.duplicate(true)
				skin.collection = str(collection.get("id", ""))
				collection.skins.append(skin)
				if not _skins.has(str(skin.get("id", ""))):
					_skins[str(skin.get("id", ""))] = skin
		loaded.append(collection)
	var order: Array = config().get("seasons", {}).get("order", [])
	loaded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.season != b.season:
			return not a.season
		return order.find(a.get("id")) < order.find(b.get("id")))
	_collections = loaded


## Every skin, collection by collection.
static func skins() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for collection in collections():
		result.append_array(collection.skins)
	return result


## Skin `id` ({} if there's none).
static func find(id: String) -> Dictionary:
	collections()
	return _skins.get(id, {})


static func has(id: String) -> bool:
	return not find(id).is_empty()


## Collection `id` ({} if there's none).
static func collection(id: String) -> Dictionary:
	for entry in collections():
		if entry.get("id") == id:
			return entry
	return {}


## A skin's rarity as an ItemData.Rarity index (0 Common ... 5 Legendary).
static func rarity(skin: Dictionary) -> int:
	return maxi(ItemData.RARITY_IDS.find(str(skin.get("rarity", "common"))), 0)


static func rarity_name(skin: Dictionary) -> String:
	return Palette.RARITY_NAMES[rarity(skin)]


## Bound: an outfit, a skin marked "bound", or one of the bound rarities (Epic and Legendary). Lost with
## an item in a raid, a bound skin goes back to the collection.
static func is_bound(skin: Dictionary) -> bool:
	if skin.get("kind") == "outfit" or bool(skin.get("bound", false)):
		return true
	return str(skin.get("rarity", "")) in config().get("bound_rarities", [])


## The slot a skin goes on: "sticker", "charm", or "skin" (every other kind; an outfit goes on the
## character).
static func slot_of(skin: Dictionary) -> String:
	var kind := str(skin.get("kind", ""))
	return kind if kind in ["sticker", "charm"] else "skin"


## The kind of item `data` is for skins ("weapon", "armor", "helmet", "rig", "backpack", "knife"), "" for
## an item that takes none.
static func item_kind(data: ItemData) -> String:
	if data == null:
		return ""
	match data.category:
		ItemData.Category.WEAPON:
			return "weapon" if data.weapon else ""
		ItemData.Category.ARMOR:
			return "armor"
		ItemData.Category.HELMET:
			return "helmet"
		ItemData.Category.RIG:
			return "rig"
		ItemData.Category.BACKPACK:
			return "backpack"
		ItemData.Category.MELEE:
			return "knife"
	return ""


## The cosmetic slots item `data` has (slots.json "item_slots" by its kind): e.g. ["skin", "sticker",
## "charm"] for a gun; [] for an item that takes none.
static func item_slots(data: ItemData) -> Array:
	return config().get("item_slots", {}).get(item_kind(data), [])


## True when `skin` can go on item `data`: the item has the skin's slot, and a skin of its own kind fits
## it (the one gun, the weapon class, the one item, or every item of the kind). Never outfits.
static func fits(skin: Dictionary, data: ItemData) -> bool:
	var slot := slot_of(skin)
	if skin.get("kind") == "outfit" or not slot in item_slots(data):
		return false
	if slot != "skin":
		return true
	if skin.get("kind") != item_kind(data):
		return false
	if skin.has("weapon"):
		return data.id == str(skin.weapon)
	if skin.has("class"):
		return data.weapon != null and data.weapon.weapon_class == str(skin["class"])
	if skin.has("item"):
		return data.id == str(skin.item)
	return true


## What `skin` fits, in words: "Every gun", "Assault rifles", "AK-74N", "BEAR", "Any item with a sticker
## slot".
static func fits_text(skin: Dictionary) -> String:
	if skin.get("kind") == "outfit":
		return "%s outfit" % str(skin.get("faction", "")).to_upper()
	if skin.get("kind") in ["sticker", "charm"]:
		return "Any item with a %s slot" % skin.kind
	if skin.has("weapon") or skin.has("item"):
		var data := ItemDB.get_item(str(skin.get("weapon", skin.get("item", ""))))
		return data.display_name if data else "?"
	if skin.has("class"):
		return WeaponData.CLASS_NAMES.get(str(skin["class"]), str(skin["class"]).capitalize())
	return "Every %s" % {"weapon": "gun", "armor": "body armor", "helmet": "helmet", "rig": "rig", "backpack": "backpack", "knife": "knife"}.get(skin.get("kind"), "item")


## The look's colours.
static func base_color(skin: Dictionary) -> Color:
	return Color.from_string(str(skin.get("look", {}).get("base", "#808080")), Color.GRAY)


static func accent_color(skin: Dictionary) -> Color:
	return Color.from_string(str(skin.get("look", {}).get("accent", "#404040")), Color.DIM_GRAY)


static func pattern(skin: Dictionary) -> int:
	return maxi(PATTERNS.find(str(skin.get("look", {}).get("pattern", "solid"))), 0)


# --- The machine --------------------------------------------------------------------------------

## Drip for `count` spins: one at the single price, ten at the ten-spin price.
static func price(count: int) -> int:
	return int(config().get("ten_price", 900)) if count == 10 else int(config().get("price", 100)) * count


## The chance of each rarity (by ItemData.Rarity index).
static func odds() -> Array[float]:
	var result: Array[float] = []
	var table: Dictionary = config().get("odds", {})
	for id in ItemData.RARITY_IDS:
		result.append(float(table.get(id, 0.0)))
	return result


## Spins in a row without an Epic or better that the next one is sure to give one on (80).
static func pity_spins() -> int:
	return int(config().get("pity", {}).get("spins", 80))


## The rarity the pity counter guarantees (an index: Epic).
static func pity_rarity() -> int:
	return maxi(ItemData.RARITY_IDS.find(str(config().get("pity", {}).get("rarity", "epic"))), 0)


## Drip a duplicate of rarity `index` pays back.
static func duplicate_drip(index: int) -> int:
	return int(config().get("duplicate_drip", {}).get(ItemData.RARITY_IDS[clampi(index, 0, 5)], 0))


static func season_weight() -> float:
	return float(config().get("season_weight", 1.0))


## The wear bands, best first: [{"name", "min", "max", "chance"}].
static func wear_bands() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var low := 0.0
	for entry: Variant in config().get("wear", []):
		if entry is Dictionary:
			result.append({"name": str(entry.get("name", "")), "min": low, "max": float(entry.get("max", 1.0)), "chance": float(entry.get("chance", 0.0))})
			low = float(entry.get("max", 1.0))
	return result


## The band `wear` is in (an index into wear_bands(): 0 Factory New ... 4 Battle-Scarred).
static func wear_band(wear: float) -> int:
	var bands := wear_bands()
	for i in bands.size():
		if wear < bands[i].max or i == bands.size() - 1:
			return i
	return 0


## "Field-Tested".
static func wear_name(wear: float) -> String:
	var bands := wear_bands()
	return str(bands[wear_band(wear)].name) if not bands.is_empty() else ""


## "Field-Tested 0.214".
static func wear_text(wear: float) -> String:
	return "%s %.3f" % [wear_name(wear), wear]


## The near-miss rule: {"chance", "below" (a rarity index: results below it may tease)}.
static func near_miss() -> Dictionary:
	var rule: Dictionary = config().get("near_miss", {})
	return {"chance": float(rule.get("chance", 0.0)), "below": maxi(ItemData.RARITY_IDS.find(str(rule.get("below", "ultra_rare"))), 0)}


# --- Seasons ------------------------------------------------------------------------------------

## The rotation's first day (unix time, UTC midnight) and its length in seconds.
static func _season_clock() -> Vector2:
	var rule: Dictionary = config().get("seasons", {})
	var start := Time.get_unix_time_from_datetime_string("%sT00:00:00" % str(rule.get("start", "2026-01-05")))
	return Vector2(start, maxf(float(rule.get("days", 28)), 1.0) * 86400.0)


## How many seasons have started by `time` (unix seconds; may be negative before the start).
static func season_number(time: float) -> int:
	var clock := _season_clock()
	return floori((time - clock.x) / clock.y)


## The seasonal collection in the machine at `time` (its id; "" with none).
static func season_at(time: float) -> String:
	var order: Array = config().get("seasons", {}).get("order", [])
	return str(order[posmod(season_number(time), order.size())]) if not order.is_empty() else ""


## Unix time the season in the machine at `time` ends.
static func season_ends(time: float) -> float:
	var clock := _season_clock()
	return clock.x + (season_number(time) + 1) * clock.y


## When seasonal collection `id` is next in the machine after `time` (its start; `time` itself while it's
## in), -1 if it never is.
static func season_next(id: String, time: float) -> float:
	var order: Array = config().get("seasons", {}).get("order", [])
	if not id in order:
		return -1.0
	if season_at(time) == id:
		return time
	var clock := _season_clock()
	var number := season_number(time) + 1
	while str(order[posmod(number, order.size())]) != id:
		number += 1
	return clock.x + number * clock.y


# --- Drip earned --------------------------------------------------------------------------------

## Drip for getting out with loot worth `loot_value` roubles: the base plus the highest bracket reached.
static func extract_drip(loot_value: int) -> Vector2i:
	var rule: Dictionary = drip_config().get("extract", {})
	var bonus := 0
	for bracket: Variant in rule.get("loot", []):
		if bracket is Dictionary and loot_value >= int(bracket.get("value", 0)):
			bonus = maxi(bonus, int(bracket.get("drip", 0)))
	return Vector2i(int(rule.get("base", 0)), bonus)


## Drip for a kill of `who` ("scav", "guard", "pmc", "boss").
static func kill_drip(who: String) -> int:
	return int(drip_config().get("kills", {}).get(who, 0))


static func quest_drip() -> int:
	return int(drip_config().get("quest", 0))


static func level_drip() -> int:
	return int(drip_config().get("level", 0))


# --- Checks -------------------------------------------------------------------------------------

## What's wrong with the files: bad JSON, unknown keys, rarities, kinds, patterns, colours or fits,
## duplicate ids, the odds and wear chances not adding up to 1, prices, the pity rule, the seasons (each
## one a seasonal collection), the drip brackets. Empty when all is well.
static func problems() -> Array[String]:
	reload()
	collections()
	var found: Array[String] = _file_problems.duplicate()
	var ids := {}
	var by_rarity := {}
	for collection in collections():
		var where := "collection %s" % str(collection.get("id", "?"))
		if str(collection.get("id", "")) == "" or str(collection.get("name", "")) == "":
			found.append("%s: needs an id and a name" % where)
		for skin: Dictionary in collection.skins:
			var id := str(skin.get("id", ""))
			if id == "" or str(skin.get("name", "")) == "":
				found.append("%s: a skin needs an id and a name" % where)
			if ids.has(id):
				found.append("skin %s: the id is used twice" % id)
			ids[id] = true
			for key: String in skin:
				if not key in SKIN_KEYS and key != "collection":
					found.append("skin %s: unknown key %s" % [id, key])
			if not str(skin.get("rarity", "")) in ItemData.RARITY_IDS:
				found.append("skin %s: rarity %s isn't one of %s" % [id, skin.get("rarity", ""), ItemData.RARITY_IDS])
			if not collection.season:
				by_rarity[str(skin.get("rarity", ""))] = true
			var kind := str(skin.get("kind", ""))
			if not kind in KINDS:
				found.append("skin %s: kind %s isn't one of %s" % [id, kind, KINDS])
			var look: Variant = skin.get("look")
			if not look is Dictionary or not str(look.get("pattern", "")) in PATTERNS:
				found.append("skin %s: look needs a pattern (%s)" % [id, PATTERNS])
			elif not Color.html_is_valid(str(look.get("base", ""))) or not Color.html_is_valid(str(look.get("accent", ""))):
				found.append("skin %s: look needs base and accent colours (#rrggbb)" % id)
			var fits_keys := ["weapon", "class", "item", "faction"].filter(func(key: String) -> bool: return skin.has(key))
			if fits_keys.size() > 1:
				found.append("skin %s: fits one thing (%s)" % [id, fits_keys])
			if kind == "outfit" and not str(skin.get("faction", "")) in FACTIONS:
				found.append("skin %s: an outfit fits a faction (%s)" % [id, FACTIONS])
			if kind != "outfit" and skin.has("faction"):
				found.append("skin %s: only outfits fit a faction" % id)
			if skin.has("weapon"):
				var gun := ItemDB.get_item(str(skin.weapon)) if ItemDB.has_item(str(skin.weapon)) else null
				if kind != "weapon" or gun == null or gun.weapon == null:
					found.append("skin %s: weapon %s isn't a gun" % [id, skin.weapon])
			if skin.has("class") and (kind != "weapon" or not WeaponData.CLASS_NAMES.has(str(skin["class"]))):
				found.append("skin %s: class %s isn't a weapon class" % [id, skin["class"]])
			if skin.has("item"):
				var data := ItemDB.get_item(str(skin.item)) if ItemDB.has_item(str(skin.item)) else null
				if data == null or item_kind(data) != kind:
					found.append("skin %s: item %s isn't a %s" % [id, skin.item, kind])
			if kind in ["sticker", "charm", "knife"] and not fits_keys.is_empty():
				found.append("skin %s: a %s fits every item with its slot" % [id, kind])
	for rarity_id in ItemData.RARITY_IDS:
		if not by_rarity.has(rarity_id):
			found.append("the core collections have no %s skin" % rarity_id)
	var total := 0.0
	for chance in odds():
		if chance < 0.0:
			found.append("slots.json: odds can't be below 0")
		total += chance
	if absf(total - 1.0) > 0.0005:
		found.append("slots.json: the odds add up to %.4f, not 1" % total)
	if price(1) <= 0 or price(10) <= 0 or price(10) > price(1) * 10:
		found.append("slots.json: price above 0, and ten_price above 0 and no more than ten single spins")
	if pity_spins() < 1 or not str(config().get("pity", {}).get("rarity", "")) in ItemData.RARITY_IDS:
		found.append("slots.json: pity needs spins 1+ and a rarity")
	for index in 6:
		if duplicate_drip(index) < 0:
			found.append("slots.json: duplicate_drip can't be below 0")
	var bands := wear_bands()
	var wear_total := 0.0
	for i in bands.size():
		wear_total += float(bands[i].chance)
		if bands[i].max <= bands[i].min or (i == bands.size() - 1 and absf(bands[i].max - 1.0) > 0.0001):
			found.append("slots.json: wear bands go up from 0 and the last ends at 1")
	if bands.size() != 5 or absf(wear_total - 1.0) > 0.0005:
		found.append("slots.json: five wear bands whose chances add up to 1 (%d, %.4f)" % [bands.size(), wear_total])
	var order: Array = config().get("seasons", {}).get("order", [])
	for id: Variant in order:
		if not collection(str(id)).get("season", false):
			found.append("slots.json: season %s isn't a seasonal collection" % id)
	for entry in collections():
		if entry.season and not entry.id in order:
			found.append("collection %s: a seasonal collection that's never in the rotation" % entry.id)
	for kind: String in config().get("item_slots", {}):
		for slot: Variant in config().item_slots[kind]:
			if not str(slot) in SLOTS:
				found.append("slots.json: item_slots %s has %s (%s)" % [kind, slot, SLOTS])
	var extract: Dictionary = drip_config().get("extract", {})
	if int(extract.get("base", -1)) < 0 or not extract.get("loot") is Array:
		found.append("drip.json: extract needs a base 0+ and loot brackets")
	for who in ["scav", "guard", "pmc", "boss"]:
		if kill_drip(who) < 0 or not drip_config().get("kills", {}).has(who):
			found.append("drip.json: kills needs %s (0+)" % who)
	if quest_drip() < 0 or level_drip() < 0:
		found.append("drip.json: quest and level can't be below 0")
	return found
