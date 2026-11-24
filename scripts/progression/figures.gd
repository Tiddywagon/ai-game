class_name Figures
extends RefCounted
## What your profile does with collectible figures (DESIGN.md §6.6; the data is FigureTable): the
## Collectors Shelf, the set bonuses, the figures you've seen, spares and the free Drip spin.
##
## GameState.figures: {"shelf": {slot (0 up): ItemInstance} (the figures on display), "seen": [figure
## ids] (every figure you've owned: the COLLECTION screen names only those), "spin": {"day", "used"}
## (the real day free Drip spins were last used on, and how many that day)}. Saved (to_save()).
##
## The shelf (the hideout's Collectors Shelf station) displays as many figures as its level's
## "display_slots", one of each figure at most. place() takes a figure out of the stash (or a container
## in it) and puts that very item on the shelf (it keeps its found-in-raid status); move() changes its
## slot (swapping with a figure already there); remove() puts it back in the stash, which needs room.
## A figure on the shelf isn't in the stash or on your character, so nothing that works on those ever
## touches it: death, sorting, selling, barters, quests, auto-equip, the flea market.
##
## A set's bonus (FigureTable: type and value) is on while every figure of the set is on the shelf.
## bonus(type) answers every caller: loot search time (LootSearch), XP for PMC kills and for exploring
## (RaidController), trader prices both ways (Trading.price(), Selling), the boss's chance (BossTable
## .chance()), energy and hydration drain (Consumables.drain_multiplier()) and free Drip spins.
##
## Spares are the copies beyond the one you keep: every figure in the stash whose kind is on the shelf,
## and all but one of a kind that isn't (the kept one found in raid if any is). Quest hand-ins and
## generic barter requirements ("any 2 Rare figures") only ever count and take spares (Requirement).

## The bonus types (FigureTable.BONUS_TYPES).
const SEARCH_SPEED := "search_speed"
const PMC_KILL_XP := "pmc_kill_xp"
const TRADER_PRICES := "trader_prices"
const BOSS_CHANCE := "boss_chance"
const METABOLISM := "metabolism"
const DRIP_SPIN := "drip_spin"
const EXPLORATION_XP := "exploration_xp"
## Seconds in a real day (free spins come back when the day number changes).
const DAY := 86400.0


## A new profile's figures: an empty shelf, nothing seen, no spin used.
static func blank() -> Dictionary:
	return {"shelf": {}, "seen": [], "spin": {"day": -1, "used": 0}}


# --- The shelf ----------------------------------------------------------------------------------

## The shelf: {slot: ItemInstance}.
static func shelf() -> Dictionary:
	return GameState.figures.get_or_add("shelf", {})


## How many figures the shelf displays at the level built (0: not built).
static func slots() -> int:
	return int(Hideout.built_value(FigureTable.station_id(), "display_slots", 0))


## The figure in `slot` (null: empty).
static func placed(slot: int) -> ItemInstance:
	return shelf().get(slot) as ItemInstance


## The slot figure `id` is displayed in (-1: it isn't).
static func slot_of(id: String) -> int:
	for slot: int in shelf():
		if (shelf()[slot] as ItemInstance).data.id == id:
			return slot
	return -1


static func is_displayed(id: String) -> bool:
	return slot_of(id) >= 0


## How many figures are on the shelf.
static func displayed_count() -> int:
	return shelf().size()


## The first empty slot (-1: the shelf is full or not built).
static func free_slot() -> int:
	for slot in slots():
		if not shelf().has(slot):
			return slot
	return -1


## The figures you could place: every figure in the stash and the containers in it, in stash order.
static func in_stash() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	if GameState.stash:
		for item in GameState.stash.all_items():
			if FigureTable.is_figure(item.data):
				result.append(item)
	return result


## Why `item` can't go on the shelf in `slot` ("" if it can): it isn't a figure, the shelf isn't built,
## there's no such slot, the slot is taken, one of that figure is already on display, or it isn't in
## your stash.
static func place_block_reason(item: ItemInstance, slot: int) -> String:
	if item == null or not FigureTable.is_figure(item.data):
		return "Only figures go on the shelf"
	if slots() == 0:
		return "Build the Collectors Shelf first"
	if slot < 0 or slot >= slots():
		return "The shelf has no slot %d at this level" % (slot + 1)
	if shelf().has(slot):
		return "That slot is taken"
	if is_displayed(item.data.id):
		return "%s is already on the shelf (one of each)" % item.data.display_name
	if GameState.stash == null or GameState.stash.find_holder(item) == null:
		return "It isn't in your stash"
	return ""


## Puts `item` (a figure in the stash) on the shelf in `slot`: that very item, so it keeps its
## found-in-raid status. "" on success, else why not.
static func place(item: ItemInstance, slot: int) -> String:
	var reason := place_block_reason(item, slot)
	if reason != "":
		return reason
	var holder := GameState.stash.find_holder(item)
	holder.remove(item)
	if holder != GameState.stash:
		GameState.stash.changed.emit()
	shelf()[slot] = item
	mark_seen(item.data.id)
	return ""


## Moves the figure in slot `from` to slot `to`; a figure already there takes its place. "" on success.
static func move(from: int, to: int) -> String:
	if not shelf().has(from):
		return "No figure in that slot"
	if to < 0 or to >= slots():
		return "The shelf has no slot %d at this level" % (to + 1)
	if from == to:
		return ""
	var moved: ItemInstance = shelf()[from]
	var other := placed(to)
	shelf().erase(from)
	if other:
		shelf()[from] = other
	shelf()[to] = moved
	return ""


## Why the figure in `slot` can't go back to the stash ("" if it can).
static func remove_block_reason(slot: int) -> String:
	if not shelf().has(slot):
		return "No figure in that slot"
	if not GameState.stash.has_room_for(shelf()[slot]):
		return "No room in the stash"
	return ""


## Takes the figure in `slot` off the shelf and puts it back in the stash. "" on success.
static func remove(slot: int) -> String:
	var reason := remove_block_reason(slot)
	if reason != "":
		return reason
	var item: ItemInstance = shelf()[slot]
	if not GameState.stash.add(item):
		return "No room in the stash"
	shelf().erase(slot)
	return ""


# --- Sets and bonuses ---------------------------------------------------------------------------

## How many figures of set `id` are on the shelf.
static func displayed_in(id: String) -> int:
	return FigureTable.in_set(id).filter(func(data: ItemData) -> bool: return is_displayed(data.id)).size()


## How many figures of set `id` you own at least one of (on the shelf, in the stash or on you).
static func owned_in(id: String) -> int:
	var counts := owned_counts()
	return FigureTable.in_set(id).filter(func(data: ItemData) -> bool: return int(counts.get(data.id, 0)) > 0).size()


## True while every figure of set `id` is on the shelf: its bonus is on.
static func set_complete(id: String) -> bool:
	var all := FigureTable.in_set(id)
	return not all.is_empty() and displayed_in(id) == all.size()


## The bonus of `type` (a FigureTable.BONUS_TYPES key) from the sets on display: the values of every
## complete set that gives it, added up; 0 with none. Worked out once per shelf (what's on it, by its
## hash) and sets file: every trader price asks for it, and counting the sets each time made a Quick
## Buy refresh slow.
static func bonus(type: String) -> float:
	var shelf_hash := shelf().hash()
	var config := FigureTable.config()
	if shelf_hash != _bonus_shelf or not is_same(config, _bonus_config):
		_bonuses = {}
		_bonus_shelf = shelf_hash
		_bonus_config = config
	if not _bonuses.has(type):
		_bonuses[type] = _bonus(type)
	return float(_bonuses[type])


static var _bonus_shelf := 0
static var _bonus_config := {}
static var _bonuses := {}


static func _bonus(type: String) -> float:
	var total := 0.0
	for entry in FigureTable.sets():
		var rule: Variant = entry.get("bonus")
		if rule is Dictionary and str(rule.get("type", "")) == type and set_complete(str(entry.get("id", ""))):
			total += float(rule.get("value", 0.0))
	return total


## The sets whose bonus is on now.
static func active_sets() -> Array[Dictionary]:
	return FigureTable.sets().filter(func(entry: Dictionary) -> bool: return set_complete(str(entry.get("id", ""))))


## The bonuses on now, one phrase each ("Raiders: +5% loot search speed").
static func active_lines() -> Array[String]:
	var lines: Array[String] = []
	for entry in active_sets():
		lines.append("%s: %s" % [entry.get("name", ""), FigureTable.bonus_text(entry)])
	return lines


## "Collectors Shelf: +5% loot search speed" when the set giving bonus `type` is on display, else "".
static func bonus_note(type: String) -> String:
	for entry in active_sets():
		if str(entry.get("bonus", {}).get("type", "")) == type:
			return "Collectors Shelf (%s set): %s" % [entry.get("name", ""), FigureTable.bonus_text(entry)]
	return ""


## What loot search times are multiplied by: +5% search speed is every item found in 1 / 1.05 the time.
static func search_time_multiplier() -> float:
	return 1.0 / (1.0 + bonus(SEARCH_SPEED))


## `base` experience for a PMC kill with the bonus on it.
static func pmc_kill_xp(base: int) -> int:
	return roundi(base * (1.0 + bonus(PMC_KILL_XP)))


## `base` experience for exploring a point of interest with the bonus on it.
static func exploration_xp(base: int) -> int:
	return roundi(base * (1.0 + bonus(EXPLORATION_XP)))


## What trader buy prices are multiplied by (0.97 with the Traders set on display), before the resale
## floor (Trading.price()).
static func buy_price_multiplier() -> float:
	return 1.0 - bonus(TRADER_PRICES)


## What trader sell rates are multiplied by (1.03 with the Traders set on display; Selling).
static func sell_rate_multiplier() -> float:
	return 1.0 + bonus(TRADER_PRICES)


## A boss's chance `base` to be in a raid with the bonus added (percentage points), at most 1.
static func boss_chance(base: float) -> float:
	return minf(base + bonus(BOSS_CHANCE), 1.0)


## What energy and hydration drain is multiplied by (0.9 with the Wildlife set on display).
static func drain_multiplier() -> float:
	return 1.0 - bonus(METABOLISM)


# --- Free Drip spins ----------------------------------------------------------------------------

## The real day now, as a number (unix days; HideoutWork.now(), which tests override).
static func today() -> int:
	return floori(HideoutWork.now() / DAY)


## Free Drip slot spins a real day: the drip_spin bonus (1 with the Oddities set on display, else 0).
static func free_spins_a_day() -> int:
	return int(bonus(DRIP_SPIN))


## Free spins left today: the day's allowance less the ones used today.
static func free_spins_left() -> int:
	var spin: Dictionary = GameState.figures.get_or_add("spin", {"day": -1, "used": 0})
	var used := int(spin.get("used", 0)) if int(spin.get("day", -1)) == today() else 0
	return maxi(free_spins_a_day() - used, 0)


## Uses one of today's free spins (the day and the count are saved with the profile, so a reload doesn't
## give it back). False if none is left.
static func use_free_spin() -> bool:
	if free_spins_left() <= 0:
		return false
	var spin: Dictionary = GameState.figures.spin
	if int(spin.get("day", -1)) != today():
		spin.day = today()
		spin.used = 0
	spin.used = int(spin.used) + 1
	return true


## Seconds until the free spins come back (the next real day).
static func seconds_to_next_day() -> float:
	return (today() + 1) * DAY - HideoutWork.now()


# --- Owned, seen, spares ------------------------------------------------------------------------

## {figure id: how many you own}: on the shelf, in the stash (containers too) and on your character.
static func owned_counts() -> Dictionary:
	var counts := {}
	for item: ItemInstance in shelf().values():
		counts[item.data.id] = int(counts.get(item.data.id, 0)) + 1
	var carried: Array[ItemInstance] = in_stash()
	if GameState.inventory:
		carried.append_array(GameState.inventory.all_items().filter(func(item: ItemInstance) -> bool: return FigureTable.is_figure(item.data)))
	for item in carried:
		counts[item.data.id] = int(counts.get(item.data.id, 0)) + item.count
	return counts


static func owned(id: String) -> int:
	return int(owned_counts().get(id, 0))


## Notes figure `id` as seen (owned at some point): the COLLECTION screen shows its name from now on.
static func mark_seen(id: String) -> void:
	var seen: Array = GameState.figures.get_or_add("seen", [])
	if not id in seen:
		seen.append(id)


## Notes every figure you own now as seen. Run when the profile is saved or loaded and when the shelf
## or the collection opens.
static func update_seen() -> void:
	for id: String in owned_counts():
		mark_seen(id)


## True once you've owned figure `id` (or own it now).
static func is_seen(id: String) -> bool:
	return id in GameState.figures.get("seen", []) or owned(id) > 0


## Your spare figures: for each kind, every copy in the stash if one is on the shelf, else all but one
## (the one kept is found in raid if any copy is), not found in raid first.
static func spares() -> Array[ItemInstance]:
	var by_id := {}
	for item in in_stash():
		(by_id.get_or_add(item.data.id, []) as Array).append(item)
	var result: Array[ItemInstance] = []
	for id: String in by_id:
		var copies: Array = by_id[id]
		copies.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return not a.fir and b.fir)
		if not is_displayed(id):
			copies.pop_back()  # The one you keep: the last, found in raid if any is.
		result.append_array(copies)
	return result


## True if figure `data` passes `filter`: {"rarity": a rarity id, "set": a set id}, either or both left
## out for any.
static func matches(data: ItemData, filter: Dictionary) -> bool:
	if not FigureTable.is_figure(data):
		return false
	if filter.has("rarity") and ItemData.RARITY_IDS.find(str(filter.rarity)) != data.rarity:
		return false
	return not filter.has("set") or str(filter["set"]) == FigureTable.set_of(data)


## The spares passing `filter` (found in raid ones only with `fir_only`), in the order they're taken:
## not found in raid first, then the cheapest.
static func matching_spares(filter: Dictionary, fir_only := false) -> Array[ItemInstance]:
	var result := spares().filter(func(item: ItemInstance) -> bool: return matches(item.data, filter) and (item.fir or not fir_only))
	result.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool:
		if a.fir != b.fir:
			return not a.fir
		return a.data.base_value < b.data.base_value if a.data.base_value != b.data.base_value else a.data.id < b.data.id)
	return result


static func spare_count(filter: Dictionary, fir_only := false) -> int:
	return matching_spares(filter, fir_only).size()


## Takes up to `amount` spares passing `filter` out of the stash. Returns how many.
static func take_spares(filter: Dictionary, amount: int, fir_only := false) -> int:
	var taken := 0
	for item in matching_spares(filter, fir_only):
		if taken >= amount:
			break
		if take(item):
			taken += 1
	return taken


## Takes figure `item` out of the stash (or the container in it holding it). False if it isn't there.
static func take(item: ItemInstance) -> bool:
	var holder := GameState.stash.find_holder(item) if GameState.stash else null
	if holder == null:
		return false
	holder.remove(item)
	if holder != GameState.stash:
		GameState.stash.changed.emit()
	return true


## The spares that would pay every generic figure requirement among `requirements` (Requirement: the
## others are left out), each spare used once: {"ok": enough for all, "items": the spares picked}. The
## strictest requirements pick first (found in raid only, then those filtering by more), so a looser one
## doesn't take the spare a stricter one needs.
static func claim(requirements: Array) -> Dictionary:
	var generic := requirements.filter(func(wanted: Requirement) -> bool: return wanted.is_generic())
	var picked: Array[ItemInstance] = []
	if generic.is_empty():
		return {"ok": true, "items": picked}
	generic.sort_custom(func(a: Requirement, b: Requirement) -> bool:
		return a.fir and not b.fir if a.fir != b.fir else a.figures.size() > b.figures.size())
	var ok := true
	for wanted: Requirement in generic:
		var found := 0
		for spare in matching_spares(wanted.figures, wanted.fir):
			if found >= wanted.count:
				break
			if not spare in picked:
				picked.append(spare)
				found += 1
		ok = ok and found >= wanted.count
	return {"ok": ok, "items": picked}


## What's wrong with figure filter `filter` ("" if nothing): only "rarity" (a rarity id) and "set" (a set
## id), either or both ({}: any figure), at least one figure passing it.
static func filter_problem(filter: Variant) -> String:
	if not filter is Dictionary:
		return "a figure filter is {\"rarity\", \"set\"}: one, both or neither"
	for key: String in filter:
		if not key in ["rarity", "set"]:
			return "a figure filter has rarity and set only, not \"%s\"" % key
	if filter.has("rarity") and not str(filter.rarity) in ItemData.RARITY_IDS:
		return "figure rarity %s doesn't exist" % filter.rarity
	if filter.has("set") and FigureTable.find_set(str(filter["set"])).is_empty():
		return "figure set %s doesn't exist" % filter["set"]
	if cheapest(filter) == null:
		return "no figure is %s" % filter_text(filter).trim_prefix("Any ")
	return ""


## What `filter` asks for, as words: "Any figure", "Any Rare figure", "Any Wildlife figure", "Any Epic
## Bosses figure".
static func filter_text(filter: Dictionary) -> String:
	var words := ["Any"]
	if filter.has("rarity"):
		words.append(Palette.RARITY_NAMES[clampi(ItemData.RARITY_IDS.find(str(filter.rarity)), 0, Palette.RARITY_NAMES.size() - 1)])
	if filter.has("set"):
		words.append(FigureTable.set_title(str(filter["set"])))
	words.append("figure")
	return " ".join(words)


## The cheapest figure passing `filter` (what a generic requirement is worth, and its sample icon), or
## null if no figure does.
static func cheapest(filter: Dictionary) -> ItemData:
	var best: ItemData = null
	for data in FigureTable.figures():
		if matches(data, filter) and (best == null or data.base_value < best.base_value):
			best = data
	return best


# --- Saving -------------------------------------------------------------------------------------

## GameState.figures as saved: {"shelf": [{"slot", "item": ItemInstance.to_dict()}] in slot order,
## "seen": [ids], "spin": {"day", "used"}} (what you own now is noted as seen first).
static func to_save() -> Dictionary:
	update_seen()
	var placed_list := []
	var taken: Array = shelf().keys()
	taken.sort()
	for slot: int in taken:
		placed_list.append({"slot": slot, "item": (shelf()[slot] as ItemInstance).to_dict()})
	var spin: Dictionary = GameState.figures.get("spin", {})
	return {"shelf": placed_list, "seen": GameState.figures.get("seen", []).duplicate(),
		"spin": {"day": int(spin.get("day", -1)), "used": int(spin.get("used", 0))}}


## The figures from save data, cleaned (a save from before version 18 has none: an empty shelf): whole
## numbers back from JSON's floats, seen ids that are still figures, and the shelf's figures each in its
## slot. A figure the shelf can't hold any more (an item that isn't a figure now, a slot past the
## shelf's level or taken, a second one of its kind) is listed under "loose" for GameState.from_dict()
## to put in the stash, so it's never lost.
static func from_save(saved: Variant) -> Dictionary:
	var result := blank()
	result["loose"] = []
	if not saved is Dictionary:
		return result
	for id: Variant in saved.get("seen", []) if saved.get("seen") is Array else []:
		if ItemDB.has_item(str(id)) and FigureTable.is_figure(ItemDB.get_item(str(id))) and not str(id) in result.seen:
			result.seen.append(str(id))
	var spin: Variant = saved.get("spin")
	if spin is Dictionary:
		result.spin = {"day": int(spin.get("day", -1)), "used": maxi(int(spin.get("used", 0)), 0)}
	var kinds := {}
	for entry: Variant in saved.get("shelf", []) if saved.get("shelf") is Array else []:
		if not entry is Dictionary or not entry.get("item") is Dictionary or not ItemDB.has_item(str(entry.item.get("id", ""))):
			continue  # An item that no longer exists.
		var item := ItemInstance.from_dict(entry.item)
		if item == null:
			continue
		var slot := int(entry.get("slot", -1))
		if not FigureTable.is_figure(item.data) or slot < 0 or slot >= slots() or result.shelf.has(slot) or kinds.has(item.data.id):
			result.loose.append(item)
			continue
		result.shelf[slot] = item
		kinds[item.data.id] = true
		if not item.data.id in result.seen:
			result.seen.append(item.data.id)
	return result
