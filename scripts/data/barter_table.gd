class_name BarterTable
extends RefCounted
## Trader barters (DESIGN.md §10): items for items, one file per trader in data/traders/barters/
## (<trader id>.json: {"barters": [...]}). A barter is {"id" (stable, unique among every trader's buy
## offers and barters: limited stock is saved under it), "trader", "ll" (the loyalty level it needs),
## "requires": [{"item", "count", "fir"}] (fir: only found-in-raid items count), "rewards": [{"item",
## "count", "durability"}] (durability: worn gear, that share of new; guns and armor only),
## "reward_rarity" (the rarest reward's rarity id), "stock" (trades each restock, counted by TraderStock;
## left out: no limit) and "quest" (a quest that must be completed before it trades)}. Trading makes the
## trades; what you get is never found in raid.
##
## The rules, checked by problems() once the items are loaded (Trading.problems()). A barter asks only
## for simple items: never a gun, armor, a part, gear with slots or a container (taking a worn one would
## take what's fitted, loaded or inside with it). A required item is a valuable if it's in the valuable
## category, tagged "valuable" or Ultra Rare or rarer ("valuable_rarity" in data/config/trading.json's
## "barters" block); anything else is junk-tier (barter goods, food, meds, ammo, parts up to Rare). A
## reward never lists a part another reward already comes with (a helmet's face shield). A barter with no
## valuable gives only Common and Uncommon rewards; one whose valuables are all Common or Uncommon gives
## rewards up to Rare; one with a Rare or rarer valuable gives Rare to Epic rewards, never Common or
## Uncommon; a Legendary reward needs a Legendary valuable. The loyalty level is at least what the rarest reward's rarity needs for money
## (Trading.min_loyalty(): Rare LL2, Ultra Rare LL3, Epic LL4; Legendary, never sold, "never_sold_level":
## LL4), no lower than any trader sells a reward for money (Trading.sold_at_level(): a barter never
## hands out sooner what the ammo and med gating keeps for later) and no higher than the trader goes.
## What goes in is worth no more than "max_value_ratio" (3) times what comes out, nor less than a third
## (worth: Selling.item_value() of new items, worn rewards as they come).

const DIR := "res://data/traders/barters"

## The folder read (tests point it at a broken copy, then reload()).
static var dir := DIR
static var _barters: Array[Dictionary] = []
## The file each barter came from (without ".json"), by its place in _barters.
static var _files: Array[String] = []
static var _by_trader := {}
## Entries all() left out for their shape, with why (problems() reports them).
static var _dropped: Array[String] = []
static var _loaded := false


## Every barter: each trader's file in roster order (TraderTable), then any other file. An entry that
## isn't a barter's shape (_shape_problem()) is left out, so nothing that reads barters trips over it;
## problems() names it.
static func all() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true
		var files := Array(DirAccess.get_files_at(dir)).filter(func(file: String) -> bool: return file.ends_with(".json"))
		var order := TraderTable.ids()
		files.sort_custom(func(a: String, b: String) -> bool:
			var rank_a := order.find(a.get_basename())
			var rank_b := order.find(b.get_basename())
			rank_a = rank_a if rank_a >= 0 else order.size()
			rank_b = rank_b if rank_b >= 0 else order.size()
			return a < b if rank_a == rank_b else rank_a < rank_b)
		for file: String in files:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
			if not (parsed is Dictionary and parsed.get("barters") is Array):
				push_error("BarterTable: %s isn't valid JSON with a \"barters\" list" % file)
				continue
			for entry: Variant in parsed.barters:
				var wrong := _shape_problem(entry)
				if wrong != "":
					_dropped.append("%s: barter %s left out: %s" % [file, entry.get("id", entry) if entry is Dictionary else entry, wrong])
					continue
				_barters.append(entry)
				_files.append(file.get_basename())
				var list: Array = _by_trader.get_or_add(str(entry.get("trader", "")), [])
				list.append(entry)
	return _barters


## Reads the files again on next use.
static func reload() -> void:
	_barters = []
	_files = []
	_by_trader = {}
	_dropped = []
	_loaded = false


## Why `entry` can't be read as a barter ("" if it can): it must be a dictionary whose "requires" and
## "rewards" are lists of {"item": id, ...} (an empty list is check()'s to report).
static func _shape_problem(entry: Variant) -> String:
	if not entry is Dictionary:
		return "not a {...} entry"
	for key: String in ["requires", "rewards"]:
		var list: Variant = entry.get(key, [])
		if not list is Array:
			return "%s isn't a list" % key
		for part: Variant in list:
			if not (part is Dictionary and part.get("item") is String):
				return "%s holds %s, not {\"item\": id, \"count\": n}" % [key, part]
	return ""


## `trader_id`'s barters, in their file's order.
static func for_trader(trader_id: String) -> Array[Dictionary]:
	all()
	var result: Array[Dictionary] = []
	result.assign(_by_trader.get(trader_id, []))
	return result


## Barter `id` ({} if there's none).
static func find(id: String) -> Dictionary:
	for barter in all():
		if str(barter.get("id", "")) == id:
			return barter
	return {}


## The loyalty level `barter` needs (1 if it doesn't say).
static func level(barter: Dictionary) -> int:
	return int(barter.get("ll", 1))


## What `barter` asks for.
static func requirements(barter: Dictionary) -> Array[Requirement]:
	return Requirement.list(barter.get("requires", []))


## What `barter` gives: [{"item", "count", "durability"}].
static func rewards(barter: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in barter.get("rewards", []):
		if entry is Dictionary:
			result.append(entry)
	return result


## The items `barter` gives, new (or worn, with "durability") and not found in raid: one per stack, so
## 120 rounds that stack to 60 are two, and two medkits two. Empty if a reward isn't an item.
static func reward_items(barter: Dictionary) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for entry in rewards(barter):
		var left := maxi(int(entry.get("count", 1)), 1)
		while left > 0:
			var piece := entry.duplicate()
			piece["count"] = left
			var item := reward_sample(piece)
			if item == null:
				return []
			left -= item.count
			result.append(item)
	return result


## Reward `entry` as it comes, a stack at most (worn if it says), not found in raid: for showing it.
## Null if it isn't an item.
static func reward_sample(entry: Dictionary) -> ItemInstance:
	var id := str(entry.get("item", ""))
	if not ItemDB.has_item(id):
		return null
	var item := FoundInRaid.make(id, maxi(int(entry.get("count", 1)), 1), FoundInRaid.Source.BARTER)
	if entry.has("durability") and item.has_durability():
		item.durability = snappedf(item.max_durability * clampf(float(entry.durability), 0.0, 1.0), 0.1)
	return item


## "PM pistol, 9x18 PM PSt ×50, worn Kolpak riot helmet": what `barter` gives, in a line.
static func reward_text(barter: Dictionary) -> String:
	var parts: Array[String] = []
	for entry in rewards(barter):
		var id := str(entry.get("item", ""))
		var name := ItemDB.get_item(id).display_name if ItemDB.has_item(id) else id
		var count := int(entry.get("count", 1))
		parts.append(("worn " if float(entry.get("durability", 1.0)) < 1.0 else "") + name + (" ×%d" % count if count > 1 else ""))
	return ", ".join(parts)


## The rarest reward's rarity (ItemData.Rarity), from the items themselves (-1 with no known reward).
static func reward_rarity(barter: Dictionary) -> int:
	var top := -1
	for entry in rewards(barter):
		var id := str(entry.get("item", ""))
		if ItemDB.has_item(id):
			top = maxi(top, ItemDB.get_item(id).rarity)
	return top


## The quest `barter` waits for ("" if none).
static func quest(barter: Dictionary) -> String:
	return str(barter.get("quest", ""))


## True once `barter`'s quest is completed (always, with no quest).
static func quest_done(barter: Dictionary) -> bool:
	var quest_id := quest(barter)
	if quest_id == "":
		return true
	var entry := QuestLog.find(quest_id)
	return not entry.is_empty() and QuestLog.state(entry) == "completed"


## "Unlocks after Safekeeping" while `barter`'s quest isn't completed, else "".
static func quest_block_reason(barter: Dictionary) -> String:
	if quest_done(barter):
		return ""
	return "Unlocks after %s" % str(QuestLog.find(quest(barter)).get("name", quest(barter)))


# --- The rules --------------------------------------------------------------------------------

## data/config/trading.json's "barters" block: {"valuable_rarity", "never_sold_level", "max_value_ratio"}.
static func rules() -> Dictionary:
	return Trading.config().get("barters", {})


## True if `data` counts as a valuable when a barter asks for it: the valuable category, the
## "valuable" tag, or Ultra Rare and rarer (the rules' valuable_rarity).
static func is_valuable(data: ItemData) -> bool:
	return data.category == ItemData.Category.VALUABLE or data.has_tag("valuable") \
		or data.rarity >= ItemData.RARITY_IDS.find(str(rules().get("valuable_rarity", "ultra_rare")))


## True if a barter may ask for `data`: not a gun, armor, a part, gear with slots or a container. Taking
## one of those from the stash would take it whole, with its parts, rounds or contents.
static func is_simple(data: ItemData) -> bool:
	var sample := ItemInstance.create(data.id)
	return sample != null and not sample.has_durability() and not sample.has_grid() and WeaponMods.slots_of(sample).is_empty() \
		and data.category != ItemData.Category.ATTACHMENT


## The ids of the parts item `id` comes with fitted (a gun's default mods, a helmet's face shield).
static func default_parts(id: String) -> Array:
	if not ItemDB.has_item(id):
		return []
	var data := ItemDB.get_item(id)
	return (data.weapon.default_mods if data.weapon else data.stats.get("default_mods", {})).values()


## The lowest loyalty level a barter giving a reward of `rarity` may need: what that rarity needs for
## money (Trading.min_loyalty()), or never_sold_level for a rarity never sold (Legendary).
static func min_level(rarity: int) -> int:
	var level := int(Trading.config().get("min_loyalty", {}).get(ItemData.RARITY_IDS[clampi(rarity, 0, ItemData.RARITY_IDS.size() - 1)], 1))
	return level if level > 0 else int(rules().get("never_sold_level", Progression.max_loyalty()))


## What `barter` asks for is worth, in roubles (Selling.item_value() of new items).
static func value_in(barter: Dictionary) -> int:
	var total := 0
	for requirement in requirements(barter):
		var sample := ItemInstance.create(requirement.item_id) if ItemDB.has_item(requirement.item_id) else null
		total += Selling.item_value(sample) * requirement.count if sample else 0
	return total


## What `barter` gives is worth, in roubles (worn rewards as they come).
static func value_out(barter: Dictionary) -> int:
	var total := 0
	for item in reward_items(barter):
		total += Selling.item_value(item)
	return total


## value_in() / value_out(): 1 is an even trade, 2 means the items asked for are worth twice the
## rewards (0 with no rewards).
static func value_ratio(barter: Dictionary) -> float:
	var out := value_out(barter)
	return float(value_in(barter)) / float(out) if out > 0 else 0.0


## What's wrong with `barter` on its own (empty if nothing): its fields, its items, the rarity rules,
## the loyalty level and the value ratio. problems() runs it on every barter; tests run it on made-up
## ones.
static func check(barter: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var id := str(barter.get("id", ""))
	var where := "barter %s" % (id if id != "" else str(barter))
	var trader := str(barter.get("trader", ""))
	if not TraderTable.has(trader):
		found.append("%s: trader %s doesn't exist" % [where, trader])
	var level_value: Variant = barter.get("ll", 1)
	var top := Progression.max_loyalty()
	if not _whole(level_value) or int(level_value) < 1 or int(level_value) > top:
		found.append("%s: ll must be a whole number 1-%d" % [where, top])
	elif TraderTable.has(trader) and int(level_value) > TraderTable.max_loyalty(trader):
		found.append("%s: needs LL%d, but %s only goes to LL%d" % [where, int(level_value), TraderTable.display_name(trader), TraderTable.max_loyalty(trader)])
	var level := level(barter)
	# What it asks for.
	var asks: Variant = barter.get("requires", [])
	if not asks is Array or asks.is_empty():
		found.append("%s: requires nothing" % where)
		asks = []
	var top_valuable := -1
	var asked := {}
	for entry: Variant in asks:
		if not entry is Dictionary or not ItemDB.has_item(str(entry.get("item", ""))):
			found.append("%s: requires an item that doesn't exist (%s)" % [where, entry])
			continue
		var data := ItemDB.get_item(str(entry.item))
		if not _whole(entry.get("count", 1)) or int(entry.get("count", 1)) < 1:
			found.append("%s: needs a whole count of 1 or more of %s" % [where, data.id])
		if not is_simple(data):
			found.append("%s: asks for %s, a gun, armor, part, gear with slots or container (a barter takes only simple items)" % [where, data.id])
		if entry.has("fir") and not entry.fir is bool:
			found.append("%s: fir on %s must be true or false" % [where, data.id])
		if asked.has(data.id):
			found.append("%s: asks for %s twice" % [where, data.id])
		asked[data.id] = true
		if is_valuable(data):
			top_valuable = maxi(top_valuable, data.rarity)
	# What it gives.
	var gives: Variant = barter.get("rewards", [])
	if not gives is Array or gives.is_empty():
		found.append("%s: gives nothing" % where)
		gives = []
	var high := -1
	var low := ItemData.Rarity.LEGENDARY + 1
	var given := {}
	for entry: Variant in gives:
		if not entry is Dictionary or not ItemDB.has_item(str(entry.get("item", ""))):
			found.append("%s: gives an item that doesn't exist (%s)" % [where, entry])
			continue
		var data := ItemDB.get_item(str(entry.item))
		if not _whole(entry.get("count", 1)) or int(entry.get("count", 1)) < 1:
			found.append("%s: gives a whole count of 1 or more of %s" % [where, data.id])
		if entry.has("durability"):
			var sample := ItemInstance.create(data.id)
			if not (entry.durability is float or entry.durability is int) or float(entry.durability) <= 0.0 or float(entry.durability) > 1.0 \
					or not sample.has_durability():
				found.append("%s: durability on %s must be above 0 and at most 1, on a gun or armor" % [where, data.id])
		if given.has(data.id):
			found.append("%s: gives %s twice" % [where, data.id])
		given[data.id] = true
		for other: Variant in gives:
			if other is Dictionary and str(other.get("item", "")) != data.id and data.id in default_parts(str(other.get("item", ""))):
				found.append("%s: gives %s, which %s already comes with" % [where, data.id, other.item])
		high = maxi(high, data.rarity)
		low = mini(low, data.rarity)
		var sold := Trading.sold_at_level(data.id)
		if sold > level:
			found.append("%s: gives %s at LL%d, sooner than traders sell it (LL%d)" % [where, data.display_name, level, sold])
	if high < 0:
		return found
	var rarity_id := str(barter.get("reward_rarity", ""))
	if rarity_id != ItemData.RARITY_IDS[high]:
		found.append("%s: reward_rarity is %s, but its rarest reward is %s" % [where, rarity_id, ItemData.RARITY_IDS[high]])
	# The rarity rules.
	if top_valuable < 0 and high > ItemData.Rarity.UNCOMMON:
		found.append("%s: asks for no valuable, so it may give only Common and Uncommon rewards, not %s" % [where, Palette.RARITY_NAMES[high]])
	elif top_valuable >= 0 and top_valuable <= ItemData.Rarity.UNCOMMON and high > ItemData.Rarity.RARE:
		found.append("%s: its valuables are Common or Uncommon, so it may give rewards up to Rare, not %s" % [where, Palette.RARITY_NAMES[high]])
	elif top_valuable >= ItemData.Rarity.RARE and low < ItemData.Rarity.RARE:
		found.append("%s: it asks for a %s valuable, so its rewards must be Rare or better, not %s" % [where, Palette.RARITY_NAMES[top_valuable], Palette.RARITY_NAMES[low]])
	if high == ItemData.Rarity.LEGENDARY and top_valuable < ItemData.Rarity.LEGENDARY:
		found.append("%s: a Legendary reward needs a Legendary valuable among what it asks for" % where)
	if level < min_level(high):
		found.append("%s: gives a %s reward at LL%d; that rarity needs LL%d or more" % [where, Palette.RARITY_NAMES[high], level, min_level(high)])
	# The rest.
	if barter.has("stock") and (not _whole(barter.stock) or int(barter.stock) < 1):
		found.append("%s: stock must be a whole number, 1 or more" % where)
	if barter.has("quest") and QuestLog.find(quest(barter)).is_empty():
		found.append("%s: quest %s doesn't exist" % [where, quest(barter)])
	if found.is_empty():
		var limit := float(rules().get("max_value_ratio", 3.0))
		var ratio := value_ratio(barter)
		if ratio > limit or ratio < 1.0 / limit:
			found.append("%s: asks for %s worth of items for %s worth (×%.2f); keep it within ×%.1f either way" % [where,
				UiFormat.money(value_in(barter)), UiFormat.money(value_out(barter)), ratio, limit])
	return found


## What's wrong with the barter files (empty if nothing): entries all() left out for their shape, every
## barter's check(), a barter in the wrong trader's file, ids missing or taken (by another barter or a buy
## offer in offers.json), a trader with no file, and the "barters" block of data/config/trading.json.
static func problems() -> Array[String]:
	all()
	var found: Array[String] = _dropped.duplicate()
	var ids := {}
	for trader_id in TraderTable.ids():
		for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
			ids[str(offer.get("id", ""))] = true
		if not FileAccess.file_exists(dir.path_join(trader_id + ".json")):
			found.append("%s: no barter file for %s (an empty \"barters\" list will do)" % [dir, trader_id])
	for index in all().size():
		var barter := _barters[index]
		var id := str(barter.get("id", ""))
		if id == "" or ids.has(id):
			found.append("%s.json: barter %s has no id or one already taken" % [_files[index], id if id != "" else str(barter)])
		ids[id] = true
		if str(barter.get("trader", "")) != _files[index]:
			found.append("%s.json: barter %s says its trader is %s" % [_files[index], id, barter.get("trader", "")])
		found.append_array(check(barter))
	var block := rules()
	if not str(block.get("valuable_rarity", "")) in ItemData.RARITY_IDS or int(block.get("never_sold_level", 0)) < 1 \
			or int(block.get("never_sold_level", 0)) > Progression.max_loyalty() or float(block.get("max_value_ratio", 0.0)) <= 1.0:
		found.append("%s: barters needs valuable_rarity, never_sold_level (1-%d) and max_value_ratio (above 1)" % [Trading.CONFIG_PATH.get_file(),
			Progression.max_loyalty()])
	return found


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and float(value) == floorf(float(value))
