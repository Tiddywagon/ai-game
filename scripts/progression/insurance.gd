class_name Insurance
extends RefCounted
## Insurance (DESIGN.md §2): before a raid, pay a trader (an insurer in data/config/insurers.json:
## Prapor is cheap and slow, Therapist dearer and faster; GameState.insurer is the one you pick) to
## insure your gear for a share of its value (at least RaidConfig.insurance_min_price each). If you die
## or go missing and nobody takes them (claim(): when you're killed, hostile AI near your body may),
## insured items you lost come back to the stash after the insurer's return time: 24-48 game hours, a
## game day being a real minute, so 1-2 real minutes. A gun or helmet comes back with the parts fitted
## to it, a rig or backpack empty (insure what's inside separately), no rounds. Returned items aren't
## found in raid and aren't insured any more. They wait in GameState.insurance_pending ({"item", "due"
## (unix time), "insurer"}) until due and there's room in the stash (deliver_due()).
##
## Insurable: guns, weapon parts, armor, helmets, rigs, backpacks and melee weapons. Not ammo, meds,
## food, barter goods, valuables, keys or the secure container (always kept anyway).

const CONFIG: RaidConfig = preload("res://data/config/raid.tres")
const INSURERS_PATH := "res://data/config/insurers.json"
const INSURABLE: Array[ItemData.Category] = [ItemData.Category.WEAPON, ItemData.Category.ATTACHMENT,
	ItemData.Category.ARMOR, ItemData.Category.HELMET, ItemData.Category.RIG, ItemData.Category.BACKPACK,
	ItemData.Category.MELEE]


## Unix time to use instead of the clock (tests); -1: the real clock.
static var now_override := -1.0
static var _config := {}


static func is_insurable(item: ItemInstance) -> bool:
	return item.data.category in INSURABLE and not item.data.stats.get("secure", false)


## data/config/insurers.json.
static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INSURERS_PATH))
		_config = parsed if parsed is Dictionary else {"insurers": [], "taken": {}, "game_hours_per_real_minute": 24.0}
	return _config


## Every insurer: [{"id", "name", "rate", "return_hours": [from, to], "note"}].
static func insurers() -> Array:
	return config().get("insurers", [])


## The insurer `id` (else the one you picked, else the first; {} if there are none).
static func insurer(id := "") -> Dictionary:
	for wanted in [id, GameState.insurer]:
		for each: Dictionary in insurers():
			if each.id == wanted:
				return each
	return insurers()[0] if not insurers().is_empty() else {}


static func insurer_name(id := "") -> String:
	return str(insurer(id).get("name", "the insurer"))


## Real seconds `game_hours` of game time take (a game day is a real minute).
static func real_seconds(game_hours: float) -> float:
	return game_hours / float(config().get("game_hours_per_real_minute", 24.0)) * 60.0


## "Prapor · 8% · back in 36-48 h (1:30-2:00)".
static func insurer_text(id := "") -> String:
	var each := insurer(id)
	if each.is_empty():
		return ""
	var hours: Array = each.return_hours
	return "%s · %d%% · back in %d-%d h (%s-%s)" % [each.name, roundi(float(each.rate) * 100.0), int(hours[0]), int(hours[1]),
		_clock(real_seconds(float(hours[0]))), _clock(real_seconds(float(hours[1])))]


static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


## What insuring `item` with `insurer_id` (default: your pick) costs: the insurer's share of its value
## with its parts fitted (not what's inside it or loaded in it).
static func price(item: ItemInstance, insurer_id := "") -> int:
	var value := item.data.base_value * item.count
	for part in WeaponMods.installed(item):
		value += part.data.base_value
	var rate := float(insurer(insurer_id).get("rate", CONFIG.insurance_rate))
	return maxi(ceili(value * rate / 100.0) * 100, CONFIG.insurance_min_price)


## Items on `inventory` that could be insured and aren't: equipment (but the secure container) and
## anything in the pockets, rig and backpack, at any depth; parts fitted to a gun or helmet go with it.
static func uninsured(inventory: Inventory) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for slot: String in inventory.equipment:
		if slot != "secure" and inventory.equipment[slot]:
			_collect(inventory.equipment[slot], result)
	for item in inventory.pockets.items:
		_collect(item, result)
	return result


static func _collect(item: ItemInstance, into: Array[ItemInstance]) -> void:
	if is_insurable(item) and not item.insured:
		into.append(item)
	if item.contents and item.contents.kind != &"secure":
		for inside in item.contents.items:
			_collect(inside, into)


static func total_price(items: Array, insurer_id := "") -> int:
	var total := 0
	for item: ItemInstance in items:
		total += price(item, insurer_id)
	return total


## Insures `items` with `insurer_id` (default: your pick), paying from GameState.roubles. "" on
## success, else why not.
static func insure(items: Array, insurer_id := "") -> String:
	var cost := total_price(items, insurer_id)
	if items.is_empty():
		return "Nothing to insure"
	if GameState.roubles < cost:
		return "Not enough roubles: %s needed" % UiFormat.money(cost)
	GameState.roubles -= cost
	var by := str(insurer(insurer_id).get("id", ""))
	for item: ItemInstance in items:
		item.insured = true
		item.insurer = by
	return ""


## Chance each insured item is taken (gone for good) when you're killed with `looters` hostile AI
## alive near your body.
static func taken_chance(looters: int) -> float:
	var taken: Dictionary = config().get("taken", {})
	return minf(float(taken.get("base", 0.0)) + float(taken.get("per_looter", 0.0)) * looters, float(taken.get("max", 1.0)))


## Settles insurance for what you lost (`lost`, as from Inventory.all_items()): each insured item is
## taken with taken_chance(`looters`) (none when missing in action: pass -1), the rest come back
## (returns_for()) and are scheduled with their insurer. Returns {"returning", "taken"} (items).
static func claim(lost: Array[ItemInstance], looters: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var kept: Array[ItemInstance] = []
	var taken: Array[ItemInstance] = []
	var chance := taken_chance(looters) if looters >= 0 else 0.0
	var parts := {}
	for item in lost:
		if not item.insured or parts.has(item):
			continue
		for part in WeaponMods.installed(item):
			parts[part] = true
		if rng.randf() < chance:
			taken.append(item)
	for item in lost:
		if not item in taken and not (parts.has(item) and _part_of_any(item, taken)):
			kept.append(item)
	var returning := returns_for(kept)
	schedule(returning, rng)
	return {"returning": returning, "taken": taken}


static func _part_of_any(part: ItemInstance, guns: Array[ItemInstance]) -> bool:
	return guns.any(func(gun: ItemInstance) -> bool: return part in WeaponMods.installed(gun))


## Queues `items` (insurance returns, each with its insurer) in GameState.insurance_pending, due after
## the insurer's return time (one roll per insurer, so a claim arrives together).
static func schedule(items: Array[ItemInstance], rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var due_by := {}
	for item in items:
		var each := insurer(item.insurer)
		var id := str(each.get("id", ""))
		if not due_by.has(id):
			var hours: Array = each.get("return_hours", [24, 24])
			due_by[id] = now() + real_seconds(rng.randf_range(float(hours[0]), float(hours[1])))
		GameState.insurance_pending.append({"item": item.to_dict(), "due": due_by[id], "insurer": id})


## What comes back for insured items among `lost` (everything the character lost, at any depth, as
## from Inventory.all_items()): a copy of each insured item, emptied, its rounds gone, with its parts
## but not insured any more and not found in raid (it remembers its insurer). Parts fitted to a
## returned item come with it.
static func returns_for(lost: Array[ItemInstance]) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	var covered := {}
	for item in lost:
		if not item.insured or covered.has(item):
			continue
		for part in WeaponMods.installed(item):
			covered[part] = true
		var copy := ItemInstance.from_dict(item.to_dict())
		if copy == null:
			continue
		copy.magazine.clear()
		if copy.contents:
			for inside in copy.contents.items.duplicate():
				copy.contents.remove(inside)
		FoundInRaid.set_found(copy, false)
		for each in copy.all_items():
			each.insured = false
		result.append(copy)
	return result


## GameState.insurance_pending as {"item", "due", "insurer"} entries (older saves kept bare item
## dictionaries, due at once).
static func pending() -> Array:
	var result := []
	for entry: Dictionary in GameState.insurance_pending:
		result.append(entry if entry.has("item") else {"item": entry, "due": 0.0, "insurer": ""})
	return result


## Seconds until the next pending return is due (0: one is; -1: nothing pending).
static func next_due() -> float:
	var soonest := -1.0
	for entry: Dictionary in pending():
		var left := maxf(float(entry.due) - now(), 0.0)
		soonest = left if soonest < 0.0 else minf(soonest, left)
	return soonest


## Puts the pending returns that are due into the stash, as far as it has room (the rest keep
## waiting). Returns the items that arrived.
static func deliver_due() -> Array[ItemInstance]:
	var arrived: Array[ItemInstance] = []
	var waiting := []
	for entry: Dictionary in pending():
		var item := ItemInstance.from_dict(entry.item) if float(entry.due) <= now() else null
		if item and item.insurer == "":
			item.insurer = str(entry.get("insurer", ""))
		if item and GameState.stash.add(item):
			arrived.append(item)
		elif item or float(entry.due) > now():
			waiting.append(entry)
	GameState.insurance_pending = waiting
	return arrived


## "Prapor returned 3 insured items" for what deliver_due() brought ("" for nothing).
static func arrival_text(items: Array[ItemInstance]) -> String:
	if items.is_empty():
		return ""
	var names := {}
	for item in items:
		names[insurer_name(item.insurer)] = true
	return "%s returned %d insured item%s to your stash" % [" and ".join(names.keys()), items.size(), "" if items.size() == 1 else "s"]


## "1:42" for `seconds`.
static func _clock(seconds: float) -> String:
	var total := maxi(ceili(seconds), 0)
	return "%d:%02d" % [total / 60, total % 60]


## "1:42" until the next return ("" if none is pending).
static func countdown_text() -> String:
	var left := next_due()
	return "" if left < 0.0 else _clock(left)
