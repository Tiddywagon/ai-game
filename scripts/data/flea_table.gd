class_name FleaTable
extends RefCounted
## The flea market's rules (DESIGN.md §10, Flea market), from data/config/flea.json: when it opens, how
## many listings go up each refresh and what they look like, how market prices drift and how your trades
## push them, the listing fee, listing slots, how fast your listings sell and what's banned. FleaMarket
## runs the market on them; this reads and checks them (problems(), run by ItemDB once the items are
## loaded) and says what may never be listed (is_banned()).

const CONFIG_PATH := "res://data/config/flea.json"

## The file config() reads (tests point it at a broken copy).
static var source := CONFIG_PATH
static var _config := {}
## The item ids the market may list, by rarity index (pool()); and the banned ones (is_banned()).
static var _pools: Array = []
static var _banned := {}


static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source)) if FileAccess.file_exists(source) else null
		_config = parsed if parsed is Dictionary else {}
		if _config.is_empty():
			push_error("FleaTable: %s isn't valid JSON" % source)
	return _config


## Forgets the loaded rules and pools (tests that edit them).
static func forget() -> void:
	_config = {}
	_pools = []
	_banned = {}


## The player level the flea market opens at (15).
static func unlock_level() -> int:
	return int(config().get("unlock_level", 15))


## Seconds between refreshes, when a new batch of listings goes up.
static func refresh_seconds() -> float:
	return maxf(float(config().get("refresh_minutes", 30.0)), 1.0) * 60.0


static func listings() -> Dictionary:
	return config().get("listings", {})


static func drift() -> Dictionary:
	return config().get("drift", {})


static func pressure() -> Dictionary:
	return config().get("pressure", {})


static func fee() -> Dictionary:
	return config().get("fee", {})


static func sale() -> Dictionary:
	return config().get("sale", {})


## [from, to] of a listings / sale rule `key` as a Vector2 (`fallback` when it's missing).
static func span(rules: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var pair: Variant = rules.get(key)
	if pair is Array and pair.size() == 2:
		return Vector2(float(pair[0]), float(pair[1]))
	return fallback


## How many listing slots a player of `level` has: none below unlock_level(), "base" at it and one more
## every "every" levels (3 at 15, 4 at 20, 5 at 25).
static func slots(level: int) -> int:
	if level < unlock_level():
		return 0
	var rules: Dictionary = config().get("slots", {})
	return int(rules.get("base", 3)) + (level - unlock_level()) / maxi(int(rules.get("every", 5)), 1)


# --- Banned items -------------------------------------------------------------------------------

## True if `data` may never be listed or put up: the banned ids, categories and tags, secure containers,
## the boss uniques (bosses.json) and rounds of min_penetration or more.
static func is_banned(data: ItemData) -> bool:
	return ban_reason(data) != ""


## Why `data` is banned from the flea market ("" if it isn't): "Keys can't go on the flea market".
static func ban_reason(data: ItemData) -> String:
	if data == null:
		return "Unknown item"
	if _banned.is_empty():
		_banned[""] = ""
		var rules: Dictionary = config().get("banned", {})
		for id: Variant in rules.get("ids", []):
			_banned[str(id)] = "Banned from the flea market"
		for entry: Dictionary in BossTable.maps().values():
			_banned[str(entry.get("unique", ""))] = "Boss uniques can't go on the flea market"
		for item in ItemDB.all_items():
			if _banned.has(item.id):
				continue
			if item.stats.get("secure", false):
				_banned[item.id] = "Secure containers can't go on the flea market"
			elif item.category_name() in rules.get("categories", []):
				_banned[item.id] = "%s can't go on the flea market" % ItemData.CATEGORY_TITLES[item.category]
			elif Array(item.tags).any(func(tag: String) -> bool: return tag in rules.get("tags", [])):
				_banned[item.id] = "Banned from the flea market"
			elif item.category == ItemData.Category.AMMO and float(item.stats.get("penetration", 0.0)) >= float(rules.get("min_penetration", INF)):
				_banned[item.id] = "Top armor-piercing rounds can't go on the flea market"
		_banned.erase("")
	return str(_banned.get(data.id, ""))


## The ids of every item the market may list, by rarity: worth something, not banned, sorted.
static func pool(rarity: int) -> Array[String]:
	if _pools.is_empty():
		for each in ItemData.RARITY_IDS:
			var list: Array[String] = []
			_pools.append(list)
		for item in ItemDB.all_items():
			if item.base_value > 0 and not is_banned(item):
				(_pools[item.rarity] as Array[String]).append(item.id)
		for list: Array[String] in _pools:
			list.sort()
	return _pools[rarity]


## How much likelier (above 1) or rarer an item of `data`'s category is picked within its rarity.
static func category_weight(data: ItemData) -> float:
	return maxf(float(listings().get("category_weight", {}).get(data.category_name(), 1.0)), 0.0)


# --- Checks -------------------------------------------------------------------------------------

## What's wrong with flea.json (empty if nothing). Needs the items loaded: ItemDB runs it.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var where := source.get_file()
	var rules := config()
	if unlock_level() < 1 or unlock_level() > Progression.max_level() or float(rules.get("refresh_minutes", 0.0)) <= 0.0:
		found.append("%s: unlock_level must be 1-%d and refresh_minutes above 0" % [where, Progression.max_level()])
	var listed := listings()
	var counts: Variant = listed.get("per_refresh")
	if not counts is Dictionary or ItemData.RARITY_IDS.any(func(rarity: String) -> bool: return not _number(counts.get(rarity)) or float(counts[rarity]) < 0.0) \
			or float(counts.get("common", 0.0)) <= 0.0:
		found.append("%s: listings per_refresh needs a count of 0 or more for every rarity (common above 0)" % where)
	elif float(counts.get("legendary", 0.0)) > float(counts.get("epic", 0.0)) or float(counts.get("epic", 0.0)) > float(counts.get("rare", 0.0)):
		found.append("%s: listings per_refresh must list rarer items less often" % where)
	var weights: Variant = listed.get("category_weight", {})
	if not weights is Dictionary or (weights as Dictionary).keys().any(func(name: Variant) -> bool: return not str(name) in ItemData.CATEGORY_NAMES) \
			or (weights as Dictionary).values().any(func(value: Variant) -> bool: return not _number(value) or float(value) < 0.0):
		found.append("%s: listings category_weight needs categories with weights of 0 or more" % where)
	for key in ["minutes", "spread", "condition", "stack", "rating"]:
		if not _range(listed.get(key), 0.0):
			found.append("%s: listings %s needs [from, to], from above 0 and not above to" % [where, key])
	if _range(listed.get("condition"), 0.0) and float(listed.condition[1]) > 1.0 or _range(listed.get("stack"), 0.0) and float(listed.stack[1]) > 1.0:
		found.append("%s: listings condition and stack are shares: at most 1" % where)
	var parts: Variant = listed.get("parts", {})
	if not parts is Dictionary or not _number(parts.get("chance")) or float(parts.chance) < 0.0 or float(parts.chance) > 1.0 or not _range(parts.get("count"), 0.0):
		found.append("%s: listings parts needs a chance (0-1) and count [from, to]" % where)
	var names: Variant = listed.get("names", {})
	if not names is Dictionary or not names.get("first") is Array or not names.get("second") is Array or names.first.is_empty() or names.second.is_empty():
		found.append("%s: listings names needs first and second parts" % where)
	var walk := drift()
	if not (_number(walk.get("min")) and _number(walk.get("max")) and _number(walk.get("center"))) \
			or not (0.0 < float(walk.min) and float(walk.min) <= float(walk.center) and float(walk.center) <= float(walk.max)) \
			or float(walk.get("bucket_minutes", 0.0)) <= 0.0 or int(walk.get("window", 0)) < 1 or float(walk.get("speed", 0.0)) <= 0.0 \
			or float(walk.get("trend_hours", 0.0)) <= 0.0 or not _number(walk.get("trend_threshold")):
		found.append("%s: drift needs 0 < min <= center <= max, bucket_minutes, window, speed, trend_hours above 0 and a trend_threshold" % where)
	var push := pressure()
	if ["buy", "sell", "max"].any(func(key: String) -> bool: return not _number(push.get(key)) or float(push[key]) < 0.0) \
			or float(push.get("half_life_hours", 0.0)) <= 0.0 or float(push.get("max", 0.0)) >= float(walk.get("min", 0.0)):
		found.append("%s: pressure needs buy, sell and max of 0 or more (max below drift min) and half_life_hours above 0" % where)
	var cost := fee()
	if not (_number(cost.get("base")) and _number(cost.get("over")) and _number(cost.get("max"))) or float(cost.base) <= 0.0 or float(cost.over) < 0.0 \
			or float(cost.max) < float(cost.base) or float(cost.max) >= 1.0:
		found.append("%s: fee needs base above 0, over of 0 or more and max from base to below 1" % where)
	var slot_rules: Variant = rules.get("slots", {})
	if not slot_rules is Dictionary or int(slot_rules.get("base", 0)) < 1 or int(slot_rules.get("every", 0)) < 1:
		found.append("%s: slots needs base and every of 1 or more" % where)
	var selling := sale()
	var curve: Variant = selling.get("minutes")
	var last := Vector2(-1.0, -1.0)
	var curve_ok: bool = curve is Array and not curve.is_empty()
	if curve_ok:
		for point: Variant in curve:
			if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]) or float(point[0]) <= last.x \
					or float(point[1]) < last.y or float(point[1]) <= 0.0:
				curve_ok = false
				break
			last = Vector2(float(point[0]), float(point[1]))
	if not curve_ok:
		found.append("%s: sale minutes needs [price ratio, minutes] points, both rising, minutes above 0" % where)
	elif not _range(selling.get("spread"), 0.0) or float(selling.get("hours", 0.0)) * 60.0 < last.y * float(selling.spread[1]):
		found.append("%s: sale needs a spread [from, to] and hours long enough for the slowest sale (%.0f minutes)" % [where, last.y * span(selling, "spread", Vector2.ONE).y])
	var banned: Variant = rules.get("banned", {})
	if not banned is Dictionary or not banned.get("ids", []) is Array or not banned.get("categories", []) is Array or not banned.get("tags", []) is Array \
			or not _number(banned.get("min_penetration")):
		found.append("%s: banned needs ids, categories, tags and a min_penetration" % where)
	else:
		for id: Variant in banned.ids:
			if not ItemDB.has_item(str(id)):
				found.append("%s: banned id %s isn't an item" % [where, id])
		for name: Variant in banned.categories:
			if not str(name) in ItemData.CATEGORY_NAMES:
				found.append("%s: banned category %s doesn't exist" % [where, name])
	return found


static func _number(value: Variant) -> bool:
	return value is float or value is int


## True for [from, to] with from above `low` and not above to.
static func _range(value: Variant, low: float) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and float(value[0]) > low and float(value[0]) <= float(value[1])
