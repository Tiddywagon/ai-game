class_name ItemGroups
extends RefCounted
## Groups, tags and value bands of barter goods and valuables (DESIGN.md §6.5), from
## data/config/item_groups.json. Every junk and valuable item has a group ("Hardware", "Jewelry"...) and
## tags ("electronics", "flammable", "valuable"...); loot tables roll by them, and each rarity has a
## band its base value should sit in (Common 5k-25k ... Legendary 1M and up).

const CONFIG_PATH := "res://data/config/item_groups.json"

static var _config := {}


static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {}
		if _config.is_empty():
			push_error("ItemGroups: %s isn't valid JSON" % CONFIG_PATH)
	return _config


## Every group name, in the config's order.
static func names() -> Array:
	return config().get("groups", {}).keys()


## What a group holds and where it turns up.
static func about(group: String) -> String:
	return str(config().get("groups", {}).get(group, ""))


static func is_tag(tag: String) -> bool:
	return config().get("tags", {}).has(tag)


## Base value range [low, high] for `rarity` (ItemData.Rarity); high 0 means no cap.
static func value_band(rarity: int) -> Vector2i:
	var band: Array = config().get("value_bands", {}).get(ItemData.RARITY_IDS[rarity], [0, 0])
	return Vector2i(int(band[0]), int(band[1]))


## True for items that need a group, tags and a value in their band: barter goods and valuables.
static func applies_to(data: ItemData) -> bool:
	return data.category in [ItemData.Category.JUNK, ItemData.Category.VALUABLE]


## Problems with `data`'s group, tags or value, as messages ("" each when fine).
static func problems(data: ItemData) -> PackedStringArray:
	var result := PackedStringArray()
	if not applies_to(data):
		return result
	if not data.group in names():
		result.append("\"%s\" has unknown group \"%s\" (use one of %s)" % [data.id, data.group, ", ".join(names())])
	for tag in data.tags:
		if not is_tag(tag):
			result.append("\"%s\" has unknown tag \"%s\"" % [data.id, tag])
	var band := value_band(data.rarity)
	if data.base_value < band.x or (band.y > 0 and data.base_value > band.y):
		result.append("\"%s\" is worth %d, outside its rarity's band %d-%s" % [data.id, data.base_value, band.x, str(band.y) if band.y > 0 else ""])
	return result
