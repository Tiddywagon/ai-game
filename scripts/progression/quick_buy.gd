class_name QuickBuy
extends RefCounted
## Quick buy (DESIGN.md §16.6): a whole loadout bought from the traders in one go, from a card on the
## LOADOUT screen's QUICK BUY tab. The cards are QuickBuyTable's (data/quick_buy/), plus up to
## QuickBuyTable.max_custom() custom ones saved from what you wear (save_custom(): GameState.quick_buys,
## saved).
##
## plan() works a card out against the traders as they are now: each line from its trader at your
## loyalty price (Trading.price()), less the bundle discount (QuickBuyTable.bundle_discount(), each line
## held at its resale floor). A line whose offer is sold out (counting what the card itself takes), above
## your loyalty level, from a trader who doesn't trade with you yet, or gone, gets the closest available
## offer of the same kind instead (_substitute(): the same item from another trader first, then the
## nearest by value and key stats, roubles before dollars on a tie), never a downgrade in function (a
## magazine holds as many, a sight is the same type, rounds keep their penetration within
## penetration_drop while an alternative does); a gun swapped to another caliber takes rounds of its
## own. With nothing to stand in, the line is left out and not charged, and a gun left out takes its
## parts and rounds with it. dress() puts the kit together on a new character: gear in its slots, parts
## at their slot paths (the defaults they replace go to the stash), each magazine loaded to capacity,
## spare rounds in the rig, pockets, then backpack in full stacks, meds and other items in the pockets,
## rig, then backpack.
##
## buy() pays for a plan the player confirmed: roubles and dollars, stock taken once per offer, each line
## counted toward its trader's money spent, everything you wore and carried into the stash with what's
## in it (not the secure container, which stays on), then the kit on. Nothing bought is found in raid. It
## checks first, without copying the stash: the prices and stock still being what the plan showed (else
## {"changed": true} and the screen shows the card again), the money, and room in the stash for what
## comes off (else nothing is paid).

const GEAR := "gear"
const PART := "part"
const ROUNDS := "rounds"
const CARRIED := "carried"
## The grids spare rounds go in, in order, and meds and other items.
const ROUND_GRIDS: Array[String] = ["rig", "pockets", "backpack"]
const ITEM_GRIDS: Array[String] = ["pockets", "rig", "backpack"]


# --- Lines ----------------------------------------------------------------------------------------

## `card`'s lines in the order they're worked out and put on: gear (in LoadoutPresets.SLOTS order), then
## each gun's parts in the card's order, then rounds, then carried items. Each {"kind", "item", "trader",
## and "slot" (gear, part), "path" (part), "for" (rounds: the gun's slot), "count" (rounds, carried)}.
static func lines(card: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var gear: Variant = card.get("gear", {})
	if gear is Dictionary:
		for slot in LoadoutPresets.SLOTS:
			if gear.has(slot) and gear[slot] is Dictionary:
				var line: Dictionary = (gear[slot] as Dictionary).duplicate()
				line.kind = GEAR
				line.slot = slot
				result.append(_clean(line))
	var parts: Variant = card.get("parts", {})
	if parts is Dictionary:
		for slot: String in parts:
			if parts[slot] is Array:
				for part: Variant in parts[slot]:
					if part is Dictionary:
						var line: Dictionary = (part as Dictionary).duplicate()
						line.kind = PART
						line.slot = slot
						result.append(_clean(line))
	for kind in [ROUNDS, CARRIED]:
		var entries: Variant = card.get(kind, [])
		if entries is Array:
			for entry: Variant in entries:
				if entry is Dictionary:
					var line: Dictionary = (entry as Dictionary).duplicate()
					line.kind = kind
					result.append(_clean(line))
	return result


static func _clean(line: Dictionary) -> Dictionary:
	line.item = str(line.get("item", ""))
	line.trader = str(line.get("trader", ""))
	if line.has("count"):
		line.count = int(line.count)
	if line.has("path"):
		line.path = str(line.path)
	if line.has("for"):
		line["for"] = str(line["for"])
	return line


## `trader_id`'s buy offer for item `id` (the lowest loyalty level if there are several; never the fence's
## worn gear), or {}.
static func offer_for(trader_id: String, id: String) -> Dictionary:
	var best := {}
	for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
		if str(offer.get("item", "")) == id and (best.is_empty() or Trading.offer_level(offer) < Trading.offer_level(best)):
			best = offer
	return best


## How many of `offer` `line` takes: 1 for gear and parts, enough packs for its count otherwise.
static func packs_for(line: Dictionary, offer: Dictionary) -> int:
	if line.kind in [GEAR, PART] or offer.is_empty():
		return 1
	return maxi(ceili(float(int(line.get("count", 1))) / maxi(int(offer.get("count", 1)), 1)), 1)


# --- Unlocking ------------------------------------------------------------------------------------

## How many quests you've completed (QuestLog).
static func tasks_completed() -> int:
	var count := 0
	for quest in QuestLog.all():
		if QuestLog.state(quest) == "completed":
			count += 1
	return count


## What `card` still needs before it can be bought, one entry each: "Bulat LL3", "12 tasks completed (6
## so far)", "Quest: A Word in His Ear". Empty once it's unlocked (custom cards always are).
static func missing(card: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var unlock: Variant = card.get("unlock", {})
	if not unlock is Dictionary:
		return result
	var loyalty: Variant = unlock.get("loyalty", {})
	if loyalty is Dictionary:
		for trader: String in loyalty:
			if int(GameState.trader_loyalty.get(trader, {}).get("level", 1)) < int(loyalty[trader]):
				result.append("%s LL%d" % [TraderTable.display_name(trader), int(loyalty[trader])])
	var tasks := int(unlock.get("tasks", 0))
	var done := tasks_completed()
	if done < tasks:
		result.append("%d tasks completed (%d so far)" % [tasks, done])
	for id: Variant in unlock.get("quests", []):
		var quest := QuestLog.find(str(id))
		if quest.is_empty() or QuestLog.state(quest) != "completed":
			result.append("Quest: %s" % str(quest.get("name", id)))
	return result


static func is_unlocked(card: Dictionary) -> bool:
	return missing(card).is_empty()


## The cards the QUICK BUY tab shows: the ones for your faction, then your custom cards.
static func cards() -> Array[Dictionary]:
	var result := QuickBuyTable.for_faction("usec" if GameState.faction == GameState.Faction.USEC else "bear")
	for card: Dictionary in GameState.quick_buys:
		result.append(card)
	return result


# --- Planning -------------------------------------------------------------------------------------

## `card` worked out now: {"card", "lines" (resolve()), "roubles", "dollars" (what it costs, the bundle
## discount off), "full_roubles", "full_dollars" (the lines at your loyalty prices), "swaps", "left_out",
## "kit" (dress()), "missing" (what the unlock still needs), "reasons" (every reason it can't be bought
## now), "signature" (prices and stock as they were), "done" (bought already)}. With `inventory` and
## `stash` it also checks there's room in the stash for what comes off ("to_stash", "room").
static func plan(card: Dictionary, inventory: Inventory = null, stash: InventoryGrid = null) -> Dictionary:
	var resolved := resolve(card)
	var result := _totals(resolved)
	result.card = card
	result.lines = resolved
	result.kit = dress(resolved, inventory.equipment.get("secure") if inventory else null)
	result.missing = missing(card)
	result.done = false
	result.to_stash = [] as Array[ItemInstance]
	result.room = true
	if inventory and stash:
		result.to_stash = to_stash(result, inventory)
		result.room = stash.has_room_for_all(result.to_stash)
	result.reasons = reasons(result)
	return result


## {"roubles", "dollars", "full_roubles", "full_dollars", "swaps", "left_out", "signature"} of `resolved`.
static func _totals(resolved: Array[Dictionary]) -> Dictionary:
	var result := {"roubles": 0, "dollars": 0, "full_roubles": 0, "full_dollars": 0, "swaps": 0, "left_out": 0}
	var parts: Array[String] = []
	for line in resolved:
		if line.left_out:
			result.left_out += 1
			parts.append("-")
			continue
		if line.swap:
			result.swaps += 1
		var key := "dollars" if line.currency == "USD" else "roubles"
		result[key] += int(line.price)
		result["full_" + key] += int(line.full)
		parts.append("%s:%s:%d:%d" % [line.trader, line.offer.id, int(line.packs), int(line.price)])
	result.signature = "|".join(parts)
	return result


## Every reason `plan` can't be bought now (not just the first): locked, nothing for sale, too little
## money (how much short), no room in the stash.
static func reasons(plan: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if not plan.missing.is_empty():
		result.append("Locked: needs %s" % "  ·  ".join(plan.missing))
	if plan.lines.all(func(line: Dictionary) -> bool: return line.left_out):
		result.append("Nothing on this card is for sale right now")
	if GameState.roubles < int(plan.roubles):
		result.append("Not enough roubles: %s short" % UiFormat.money(int(plan.roubles) - GameState.roubles))
	if GameState.dollars < int(plan.dollars):
		result.append("Not enough dollars: %s short (%s at the exchange)" % [UiFormat.money(int(plan.dollars) - GameState.dollars, "USD"),
			UiFormat.money(Trading.exchange_roubles(int(plan.dollars) - GameState.dollars, true))])
	if not plan.room:
		result.append("No room in the stash for what you wear and carry and the parts the kit replaces: make room first")
	return result


## What buying `plan` puts in the stash, in the order it goes: everything worn but the secure container
## (with what's in it), what's loose in the pockets, the parts the kit's own replace, and anything that
## didn't fit on you.
static func to_stash(plan: Dictionary, inventory: Inventory) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for slot in LoadoutPresets.SLOTS:
		if inventory.equipment.get(slot):
			result.append(inventory.equipment[slot])
	result.append_array(inventory.pockets.items)
	result.append_array(plan.kit.displaced)
	result.append_array(plan.kit.overflow)
	return result


## Each of `card`'s lines as it can be bought now: the line with "offer", "packs", "count" (what you get),
## "unit" (a pack at your loyalty price), "full" (unit × packs), "price" (with the bundle discount),
## "currency", "wanted" and "wanted_trader" (what the card asked for), "swap", "left_out" and "why".
static func resolve(card: Dictionary) -> Array[Dictionary]:
	var taken := {}
	var guns := {}
	var result: Array[Dictionary] = []
	for line in lines(card):
		var entry: Dictionary
		match str(line.kind):
			GEAR:
				entry = _resolve(line, taken, _gear_rule(line))
				if line.slot in QuickBuyTable.GUN_SLOTS and not entry.left_out:
					guns[line.slot] = ItemInstance.create(str(entry.item))
			PART:
				var gun: ItemInstance = guns.get(line.slot)
				if gun == null:
					entry = _left_out(line, "its gun is left out" if card.get("gear", {}).has(line.slot) else "no gun for it")
				else:
					entry = _resolve(line, taken, _part_rule(line, gun))
					if not entry.left_out:
						WeaponMods.install(gun, str(line.path), ItemInstance.create(str(entry.item)))
			ROUNDS:
				var gun: ItemInstance = guns.get(str(line.get("for", "")))
				if gun == null:
					entry = _left_out(line, "its gun is left out")
				else:
					# A gun swapped to another caliber gets at least min_magazines() of its own magazines.
					var wanted := line.duplicate()
					var ammo := ItemDB.get_item(line.item) if ItemDB.has_item(line.item) else null
					if ammo == null or str(ammo.stats.get("caliber", "")) != gun.data.weapon.caliber:
						wanted.count = maxi(int(line.get("count", 0)), QuickBuyTable.min_magazines() * WeaponMods.capacity(gun))
					entry = _resolve(wanted, taken, _rounds_rule(line, gun))
			_:
				entry = _resolve(line, taken, _carried_rule(line))
		if not entry.left_out:
			taken[entry.offer.id] = int(taken.get(entry.offer.id, 0)) + int(entry.packs)
		result.append(entry)
	return result


## `line` left out, for `why`.
static func _left_out(line: Dictionary, why: String) -> Dictionary:
	var entry := line.duplicate()
	entry.wanted = line.item
	entry.wanted_trader = line.trader
	entry.swap = false
	entry.left_out = true
	entry.why = why
	entry.offer = {}
	entry.packs = 0
	entry.count = int(line.get("count", 1))
	entry.unit = 0
	entry.full = 0
	entry.price = 0
	entry.currency = "RUB"
	return entry


## Why `offer` (from `trader_id`) can't supply `packs` now, counting what this card takes already
## (`taken`), or "".
static func unusable(trader_id: String, offer: Dictionary, packs: int, taken: Dictionary) -> String:
	if offer.is_empty():
		return "no longer sold"
	if not TraderTable.is_unlocked(trader_id):
		return "%s doesn't trade with you yet" % TraderTable.display_name(trader_id)
	if Trading.loyalty_block_reason(trader_id, offer) != "":
		return "needs %s LL%d" % [TraderTable.display_name(trader_id), Trading.offer_level(offer)]
	var left := TraderStock.left(trader_id, offer)
	if left >= 0 and left - int(taken.get(str(offer.id), 0)) < packs:
		return "sold out at %s" % TraderTable.display_name(trader_id)
	return ""


## `line` from its own offer if that can supply it and `rule` takes it, else from the closest offer
## `rule` takes (a rule: {"accepts": Callable(ItemData) -> bool, "within": Callable(ItemData) -> bool, an
## alternative within the limits is picked over one that isn't}), else left out.
static func _resolve(line: Dictionary, taken: Dictionary, rule: Dictionary) -> Dictionary:
	var own := offer_for(line.trader, line.item)
	var wanted := ItemDB.get_item(line.item) if ItemDB.has_item(line.item) else null
	var why := unusable(line.trader, own, packs_for(line, own), taken)
	if why == "" and wanted and not (rule.accepts as Callable).call(wanted):
		why = str(rule.get("why", "doesn't fit"))
	if why == "":
		return _priced(line, line.trader, own, false, "")
	if wanted == null:
		return _left_out(line, "no longer in the game")
	var best := {}
	var best_key := []
	var value := _unit_value(line.trader, own) if not own.is_empty() else float(wanted.base_value)
	for trader_id in TraderTable.ids():
		for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
			var data := ItemDB.get_item(str(offer.get("item", ""))) if ItemDB.has_item(str(offer.get("item", ""))) else null
			if data == null or not (rule.accepts as Callable).call(data):
				continue
			if unusable(trader_id, offer, packs_for(line, offer), taken) != "":
				continue
			# The same item from another trader first (any of them as close as the other: then roubles first),
			# then one within the limits, then the nearest, then roubles, the cheaper, the offer id.
			var same := data.id == wanted.id
			var key := [0 if same else 1, 0 if (rule.within as Callable).call(data) else 1,
				0.0 if same else snappedf(distance(wanted, value, data, _unit_value(trader_id, offer)), 0.0001),
				1 if offer.get("currency", "RUB") == "USD" else 0, _unit_value(trader_id, offer), str(offer.id)]
			if best.is_empty() or key < best_key:
				best = {"trader": trader_id, "offer": offer}
				best_key = key
	if best.is_empty():
		return _left_out(line, why + ", and nothing like it is for sale")
	return _priced(line, str(best.trader), best.offer, true, why)


## `line` bought as `offer` from `trader_id`.
static func _priced(line: Dictionary, trader_id: String, offer: Dictionary, swap: bool, why: String) -> Dictionary:
	var entry := line.duplicate()
	entry.wanted = line.item
	entry.wanted_trader = line.trader
	entry.item = str(offer.item)
	entry.trader = trader_id
	entry.offer = offer
	entry.swap = swap and (str(offer.item) != line.item or trader_id != line.trader)
	entry.left_out = false
	entry.why = why
	entry.packs = packs_for(line, offer)
	entry.count = entry.packs * maxi(int(offer.get("count", 1)), 1) if line.kind in [ROUNDS, CARRIED] else 1
	entry.unit = Trading.price(trader_id, offer)
	entry.full = int(entry.unit) * int(entry.packs)
	entry.price = Trading.price(trader_id, offer, QuickBuyTable.bundle_discount()) * int(entry.packs)
	entry.currency = str(offer.get("currency", "RUB"))
	return entry


## One of what `offer` sells, in roubles at your loyalty price (a dollar at the exchange's buy rate).
static func _unit_value(trader_id: String, offer: Dictionary) -> float:
	var each := float(Trading.price(trader_id, offer)) / maxi(int(offer.get("count", 1)), 1)
	return each * Trading.exchange_roubles(1, true) if offer.get("currency", "RUB") == "USD" else each


## How far `other` (one costing `other_value` roubles) is from `wanted` (`wanted_value`): the log of the
## price ratio and the differences in key stats, each times its weight (QuickBuyTable.weight()).
static func distance(wanted: ItemData, wanted_value: float, other: ItemData, other_value: float) -> float:
	var result := absf(log(maxf(other_value, 1.0) / maxf(wanted_value, 1.0))) * QuickBuyTable.weight("value")
	for key in ["class", "penetration", "damage"]:
		if wanted.stats.has(key) or other.stats.has(key):
			result += absf(float(wanted.stats.get(key, 0)) - float(other.stats.get(key, 0))) * QuickBuyTable.weight(key)
	if wanted.stats.has("uses") or other.stats.has("uses"):
		result += absf(float(wanted.stats.get("uses", 0)) - float(other.stats.get("uses", 0))) * QuickBuyTable.weight("uses")
	result += absf(_cells(wanted) - _cells(other)) * QuickBuyTable.weight("cells")
	if wanted.weapon and other.weapon:
		result += absf(wanted.weapon.ergonomics - other.weapon.ergonomics) * QuickBuyTable.weight("ergonomics")
	result += absf(WeaponMods.capacity_of(wanted) - WeaponMods.capacity_of(other)) * QuickBuyTable.weight("capacity")
	return result


static func _cells(data: ItemData) -> int:
	var grid: Array = data.stats.get("grid", [])
	return int(grid[0]) * int(grid[1]) if grid.size() == 2 else 0


static func _armored(data: ItemData) -> bool:
	return int(data.stats.get("class", 0)) > 0


## What may stand in for gear `line`: a gun of the same class for the same slot, armor for armor, a plain
## rig for a plain rig (an armored one for an armored one), and so on.
static func _gear_rule(line: Dictionary) -> Dictionary:
	var wanted := ItemDB.get_item(line.item) if ItemDB.has_item(line.item) else null
	var slot := str(line.slot)
	var empty := Inventory.new()
	var accepts := func(data: ItemData) -> bool:
		if wanted == null or data.category != wanted.category:
			return false
		var piece := ItemInstance.create(data.id)
		if piece == null or not empty.accepts(slot, piece):
			return false
		if wanted.weapon:
			return data.weapon != null and data.weapon.weapon_class == wanted.weapon.weapon_class
		if slot == "rig":
			return _armored(data) == _armored(wanted)
		if slot == "headset":
			return WeaponMods.kind_of(data) == "headset"
		return true
	return {"accepts": accepts, "within": func(_data: ItemData) -> bool: return true}


## What may stand in for part `line` on `gun` (as built so far): a part of the same kind that fits the gun
## at the same slot path; a magazine that holds at least as many, a sight of the same type.
static func _part_rule(line: Dictionary, gun: ItemInstance) -> Dictionary:
	var wanted := ItemDB.get_item(line.item) if ItemDB.has_item(line.item) else null
	var slot := WeaponMods.slot_at(gun, str(line.path))
	var platform := WeaponMods.platform_of(gun)
	var accepts := func(data: ItemData) -> bool:
		if wanted == null or slot.is_empty() or WeaponMods.kind_of(data) != WeaponMods.kind_of(wanted) or not WeaponMods.fits(platform, slot, data):
			return false
		if WeaponMods.kind_of(wanted) == "magazine" and WeaponMods.capacity_of(data) < WeaponMods.capacity_of(wanted):
			return false
		if WeaponMods.kind_of(wanted) == "sight" and int(data.stats.get("optic", 0)) != int(wanted.stats.get("optic", 0)):
			return false
		return true
	return {"accepts": accepts, "within": func(_data: ItemData) -> bool: return true, "why": "doesn't fit the %s" % gun.data.display_name}


## What may stand in for rounds `line` for `gun`: rounds of the gun's caliber, those within
## penetration_drop of the wanted round's penetration first.
static func _rounds_rule(line: Dictionary, gun: ItemInstance) -> Dictionary:
	var wanted := ItemDB.get_item(line.item) if ItemDB.has_item(line.item) else null
	var caliber := gun.data.weapon.caliber
	var least := float(wanted.stats.get("penetration", 0)) * (1.0 - QuickBuyTable.penetration_drop()) if wanted else 0.0
	return {"accepts": func(data: ItemData) -> bool: return data.category == ItemData.Category.AMMO and str(data.stats.get("caliber", "")) == caliber,
		"within": func(data: ItemData) -> bool: return float(data.stats.get("penetration", 0)) >= least - 0.001,
		"why": "the %s takes %s" % [gun.data.display_name, caliber]}


## What may stand in for carried `line`: a med of the same type, else an item of the same category.
static func _carried_rule(line: Dictionary) -> Dictionary:
	var wanted := ItemDB.get_item(line.item) if ItemDB.has_item(line.item) else null
	var accepts := func(data: ItemData) -> bool:
		if wanted == null or data.category != wanted.category:
			return false
		return wanted.category != ItemData.Category.MEDS or str(data.stats.get("type", "")) == str(wanted.stats.get("type", ""))
	return {"accepts": accepts, "within": func(_data: ItemData) -> bool: return true}


# --- Putting it on --------------------------------------------------------------------------------

## The kit of `resolved` lines (resolve(), or lines with "offer" and "packs") put together on a new
## character, with `secure` (the one you wear, or null) in its slot for the totals: {"inventory",
## "displaced" (default parts the kit's own replace), "overflow" (what found no place on you), "placed"
## (where rounds and items went: [text]), "problems" (what didn't go where the card says)}. Every item is
## new.
static func dress(resolved: Array[Dictionary], secure: ItemInstance) -> Dictionary:
	var inventory := Inventory.new()
	var displaced: Array[ItemInstance] = []
	var overflow: Array[ItemInstance] = []
	var problems: Array[String] = []
	var placed: Array[String] = []
	for line in resolved:
		if line.get("left_out", false) or line.get("offer", {}).is_empty():
			continue
		match str(line.kind):
			GEAR:
				var piece := ItemInstance.create(str(line.item))
				if not inventory.equip(str(line.slot), piece):
					problems.append("%s doesn't go in the %s slot" % [piece.data.display_name, line.slot])
					overflow.append(piece)
			PART:
				var gun: ItemInstance = inventory.equipment.get(str(line.slot))
				var part := ItemInstance.create(str(line.item))
				var why := WeaponMods.install_block_reason(gun, str(line.path), part) if gun else "no gun in the %s slot" % line.slot
				if why != "":
					problems.append("%s at %s: %s" % [part.data.display_name, line.path, why])
					overflow.append(part)
				else:
					var replaced := WeaponMods.install(gun, str(line.path), part)
					if replaced:
						displaced.append(replaced)
			ROUNDS:
				_load_rounds(line, inventory, overflow, placed)
			_:
				_carry(line, inventory, overflow, placed)
	if secure:
		inventory.equipment["secure"] = secure  # For the totals only: buy() never moves it.
	return {"inventory": inventory, "displaced": displaced, "overflow": overflow, "placed": placed, "problems": problems}


## Loads rounds `line`'s gun to capacity (on top of what it holds) and puts the rest in the rig, pockets,
## then backpack in full stacks.
static func _load_rounds(line: Dictionary, inventory: Inventory, overflow: Array[ItemInstance], placed: Array[String]) -> void:
	var total := int(line.packs) * maxi(int(line.offer.get("count", 1)), 1)
	var ammo := ItemDB.get_item(str(line.item))
	var gun: ItemInstance = inventory.equipment.get(str(line.get("for", "")))
	if gun and gun.is_gun() and str(ammo.stats.get("caliber", "")) == gun.data.weapon.caliber:
		var load := mini(maxi(WeaponMods.capacity(gun) - gun.rounds_loaded(), 0), total)
		if load > 0:
			gun.load_rounds(ItemInstance.full_rounds(ammo.id, load))
			placed.append("%d × %s loaded in the %s" % [load, ammo.display_name, gun.data.display_name])
			total -= load
	var spots := {}
	while total > 0:
		var piece := ItemInstance.full_rounds(ammo.id, mini(total, ammo.max_stack))
		total -= piece.count
		_put(piece, ROUND_GRIDS, inventory, overflow, spots)
	_placed_text(spots, ammo.display_name, placed)


## Puts carried `line`'s items in the pockets, rig, then backpack (stacks within their max stack).
static func _carry(line: Dictionary, inventory: Inventory, overflow: Array[ItemInstance], placed: Array[String]) -> void:
	var total := int(line.packs) * maxi(int(line.offer.get("count", 1)), 1)
	var data := ItemDB.get_item(str(line.item))
	var spots := {}
	while total > 0:
		var piece := ItemInstance.create(data.id, mini(total, data.max_stack))
		total -= piece.count
		_put(piece, ITEM_GRIDS, inventory, overflow, spots)
	_placed_text(spots, data.display_name, placed)


## Adds `piece` to the first of `grids` (by name) with room, the rest of it to the next; what's left
## goes to `overflow`. `spots` counts what went where.
static func _put(piece: ItemInstance, grids: Array[String], inventory: Inventory, overflow: Array[ItemInstance], spots: Dictionary) -> void:
	for name in grids:
		var grid := _grid(inventory, name)
		if grid == null:
			continue
		var before := piece.count
		if grid.add(piece):
			spots[name] = int(spots.get(name, 0)) + before
			return
		if piece.count < before:
			spots[name] = int(spots.get(name, 0)) + before - piece.count
	overflow.append(piece)
	spots["stash"] = int(spots.get("stash", 0)) + piece.count


static func _grid(inventory: Inventory, name: String) -> InventoryGrid:
	if name == "pockets":
		return inventory.pockets
	var holder: ItemInstance = inventory.equipment.get(name)
	return holder.contents if holder else null


## "90 × 5.45x39 PS → rig, pockets" into `placed`.
static func _placed_text(spots: Dictionary, name: String, placed: Array[String]) -> void:
	var total := 0
	for key: String in spots:
		total += int(spots[key])
	if total > 0:
		placed.append("%s%s → %s" % ["%d × " % total if total > 1 else "", name, ", ".join(spots.keys())])


## "Bandage ×2" for each kind among `items` (in order).
static func names(items: Array) -> Array[String]:
	var counts := {}
	for item: ItemInstance in items:
		counts[item.data.display_name] = int(counts.get(item.data.display_name, 0)) + item.count
	var result: Array[String] = []
	for name: String in counts:
		result.append(name + (" ×%d" % counts[name] if int(counts[name]) > 1 else ""))
	return result


# --- Buying ---------------------------------------------------------------------------------------

## Buys `plan` (plan() with `inventory` and `stash`, as the confirm dialog showed it) onto `inventory`:
## {"ok", "message", "reasons" (every reason it couldn't), "changed" (prices or stock moved since the
## plan: nothing bought, "plan" is the card worked out again to show)}. A plan is bought once ("done").
static func buy(plan: Dictionary, inventory: Inventory, stash: InventoryGrid) -> Dictionary:
	if plan.get("done", false):
		return {"ok": false, "changed": false, "reasons": ["Already bought"], "message": "Already bought"}
	var now := _totals(resolve(plan.card))
	if str(now.signature) != str(plan.signature):
		return {"ok": false, "changed": true, "plan": plan(plan.card, inventory, stash), "reasons": ["Prices or stock changed"],
			"message": "Prices or stock changed since you opened it: check the card again"}
	plan.missing = missing(plan.card)
	plan.to_stash = to_stash(plan, inventory)
	plan.room = stash.has_room_for_all(plan.to_stash)
	plan.reasons = reasons(plan)
	if not plan.reasons.is_empty():
		return {"ok": false, "changed": false, "reasons": plan.reasons, "message": plan.reasons[0]}
	plan.done = true
	_pay(plan)
	# What you wore and carried goes to the stash, with what's in it (the secure container stays on).
	for slot in LoadoutPresets.SLOTS:
		var worn := inventory.unequip(slot)
		if worn:
			_stash(worn, inventory, stash)
	for piece in inventory.pockets.items.duplicate():
		inventory.pockets.remove(piece)
		_stash(piece, inventory, stash)
	var kit: Inventory = plan.kit.inventory
	kit.equipment["secure"] = null
	var bought: Array[ItemInstance] = []
	for slot in LoadoutPresets.SLOTS:
		var piece: ItemInstance = kit.equipment.get(slot)
		if piece:
			kit.equipment[slot] = null
			bought.append(piece)
			if not inventory.equip(slot, piece):
				_stash(piece, inventory, stash)
	for piece in kit.pockets.items.duplicate():
		kit.pockets.remove(piece)
		bought.append(piece)
		if not inventory.pockets.place(piece, piece.cell, piece.rotated) and not inventory.pockets.add(piece):
			_stash(piece, inventory, stash)
	for piece: ItemInstance in plan.kit.displaced + plan.kit.overflow:
		bought.append(piece)
		_stash(piece, inventory, stash)
	for piece in bought:
		FoundInRaid.set_found(piece, FoundInRaid.gives_fir(FoundInRaid.Source.QUICK_BUY))
	inventory.changed.emit()
	stash.changed.emit()
	var paid: Array[String] = []
	if int(plan.roubles) > 0:
		paid.append(UiFormat.money(int(plan.roubles)))
	if int(plan.dollars) > 0:
		paid.append(UiFormat.money(int(plan.dollars), "USD"))
	return {"ok": true, "changed": false, "reasons": [] as Array[String],
		"message": "Bought %s for %s. What you wore is in the stash." % [str(plan.card.get("name", "the card")), " + ".join(paid)]}


## Pays for `plan`'s lines: the money, the stock (once per offer, all the packs the card takes), and
## each line toward its trader's money spent (Trading.spent_value()), then loyalty is checked.
static func _pay(plan: Dictionary) -> void:
	GameState.roubles -= int(plan.roubles)
	GameState.dollars -= int(plan.dollars)
	var stock := {}
	for line: Dictionary in plan.lines:
		if line.left_out:
			continue
		var key := "%s/%s" % [line.trader, line.offer.id]
		if not stock.has(key):
			stock[key] = [line.trader, line.offer, 0]
		stock[key][2] += int(line.packs)
		if GameState.trader_loyalty.has(line.trader):
			GameState.trader_loyalty[line.trader].spent += Trading.spent_value(int(line.price), str(line.currency))
	for key: String in stock:
		TraderStock.take(str(stock[key][0]), stock[key][1], int(stock[key][2]))
	for key: String in stock:
		Trading.update_loyalty(str(stock[key][0]))


## Puts `piece` in the stash (buy() checked it all fits); should that ever fail, on you, never lost.
static func _stash(piece: ItemInstance, inventory: Inventory, stash: InventoryGrid) -> void:
	if stash.add(piece) or piece.count <= 0:
		return
	if not inventory.add(piece):
		GameState.insurance_pending.append({"item": piece.to_dict(), "due": 0.0, "insurer": "", Insurance.FROM_SAVE: true})
		push_error("QuickBuy: no room anywhere for %s; it waits for room in the stash" % piece.data.display_name)


# --- Custom cards ---------------------------------------------------------------------------------

## SAVE CURRENT GEAR AS QUICK-BUY: a custom card named `name` from what `inventory` wears and carries
## (record()), added to GameState.quick_buys. {"ok", "message", "card"}.
static func save_custom(name: String, inventory: Inventory) -> Dictionary:
	if GameState.quick_buys.size() >= QuickBuyTable.max_custom():
		return {"ok": false, "message": "%d custom cards already: delete one first" % QuickBuyTable.max_custom(), "card": {}}
	var card := record(name, inventory)
	if lines(card).is_empty():
		return {"ok": false, "message": "Nothing you wear or carry is sold by a trader", "card": {}}
	GameState.quick_buys.append(card)
	var message := "Saved %s as a quick-buy card." % card.name
	if not card.left_out.is_empty():
		message += " Not for sale, left out: %s." % ", ".join(card.left_out)
	return {"ok": true, "message": message, "card": card}


## Deletes custom card `index`. False if there's no such card.
static func remove_custom(index: int) -> bool:
	if index < 0 or index >= GameState.quick_buys.size():
		return false
	GameState.quick_buys.remove_at(index)
	return true


## A custom card of what `inventory` wears (but the secure container) and carries in the pockets, rig
## and backpack: each item from the cheapest offer you qualify for (else the cheapest anyone sells),
## parts a gun doesn't come with by slot path, rounds (loaded and carried) by kind for the gun of their
## caliber, other items by kind with their counts. What no trader sells, and rounds no gun on the card
## fires, are named in "left_out" (kept on the card).
static func record(name: String, inventory: Inventory) -> Dictionary:
	var cleaned := name.strip_edges().left(QuickBuyTable.name_length()).strip_edges()
	var card := {"id": _free_id(), "name": cleaned if cleaned != "" else _free_name(), "description": "Saved from your gear.",
		"custom": true, "gear": {}, "parts": {}, "rounds": [], "carried": [], "left_out": []}
	var left: Array[String] = []
	var guns := {}
	for slot in LoadoutPresets.SLOTS:
		var item: ItemInstance = inventory.equipment.get(slot)
		if item == null:
			continue
		var source := cheapest(item.data.id)
		if source.is_empty():
			left.append(item.data.display_name)
			continue
		card.gear[slot] = {"item": item.data.id, "trader": source.trader}
		if item.is_gun():
			guns[slot] = item
	for slot: String in guns:
		var gun: ItemInstance = guns[slot]
		var defaults: Dictionary = gun.data.weapon.default_mods
		var parts: Array = []
		var skipped: Array[String] = []
		for entry in WeaponMods.walk(gun):
			if entry.mod == null:
				continue
			var path := str(entry.path)
			var part: ItemInstance = entry.mod
			if skipped.any(func(parent: String) -> bool: return path.begins_with(parent + "/")):
				left.append(part.data.display_name)
				continue
			if str(defaults.get(path, "")) == part.data.id:
				continue
			var source := cheapest(part.data.id)
			if source.is_empty():
				left.append(part.data.display_name)
				skipped.append(path)
				continue
			parts.append({"path": path, "item": part.data.id, "trader": source.trader})
		if not parts.is_empty():
			card.parts[slot] = parts
	# Rounds by kind: loaded in the guns, then carried.
	var rounds := {}
	var order: Array[String] = []
	for slot: String in guns:
		for stack: ItemInstance in (guns[slot] as ItemInstance).magazine:
			if not rounds.has(stack.data.id):
				order.append(stack.data.id)
			rounds[stack.data.id] = int(rounds.get(stack.data.id, 0)) + stack.count
	var carried := {}
	var carried_order: Array[String] = []
	for grid in inventory.ammo_grids():
		for item in grid.items:
			if item.data.category == ItemData.Category.AMMO:
				if not rounds.has(item.data.id):
					order.append(item.data.id)
				rounds[item.data.id] = int(rounds.get(item.data.id, 0)) + item.count
			else:
				if not carried.has(item.data.id):
					carried_order.append(item.data.id)
				carried[item.data.id] = int(carried.get(item.data.id, 0)) + item.count
	for id in order:
		var ammo := ItemDB.get_item(id)
		var gun_slot := ""
		for slot: String in guns:
			var gun: ItemInstance = guns[slot]
			if gun.data.weapon.caliber == str(ammo.stats.get("caliber", "")) and (gun_slot == "" or gun.loaded_ammo == id):
				gun_slot = slot
		var source := cheapest(id)
		if gun_slot == "" or source.is_empty():
			left.append("%s ×%d" % [ammo.display_name, int(rounds[id])])
			continue
		card.rounds.append({"for": gun_slot, "item": id, "trader": source.trader, "count": int(rounds[id])})
	for id in carried_order:
		var data := ItemDB.get_item(id)
		var source := cheapest(id)
		if source.is_empty():
			left.append(data.display_name + (" ×%d" % int(carried[id]) if int(carried[id]) > 1 else ""))
			continue
		card.carried.append({"item": id, "trader": source.trader, "count": int(carried[id])})
	card.left_out = left
	return card


## The offer to buy item `id` from: the cheapest (a dollar at the exchange's buy rate) of those you can buy
## from now (the trader trades with you, your loyalty reaches it), else the cheapest anyone sells.
## {"trader", "offer"}, or {} if no trader sells it for money.
static func cheapest(id: String) -> Dictionary:
	var best := {}
	var best_key := []
	for trader_id in TraderTable.ids():
		for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
			if str(offer.get("item", "")) != id:
				continue
			var qualified := TraderTable.is_unlocked(trader_id) and Trading.loyalty_block_reason(trader_id, offer) == ""
			var key := [0 if qualified else 1, _unit_value(trader_id, offer), str(offer.id)]
			if best.is_empty() or key < best_key:
				best = {"trader": trader_id, "offer": offer}
				best_key = key
	return best


## "custom_N" with the lowest N no custom card has.
static func _free_id() -> String:
	var number := 1
	while GameState.quick_buys.any(func(card: Dictionary) -> bool: return card.get("id") == "custom_%d" % number):
		number += 1
	return "custom_%d" % number


## "Custom N" with the lowest N no custom card is called.
static func _free_name() -> String:
	var number := 1
	while GameState.quick_buys.any(func(card: Dictionary) -> bool: return str(card.get("name", "")).to_lower() == "custom %d" % number):
		number += 1
	return "Custom %d" % number


## Saved custom cards made safe to use (GameState.from_dict()): at most max_custom(), each with a name,
## an id, "custom", and only lines whose item exists and whose trader exists (the rest named in
## "left_out", with what it already had).
static func sanitize(saved: Variant) -> Array:
	var result := []
	if not saved is Array:
		return result
	for entry: Variant in saved:
		if not entry is Dictionary or result.size() >= QuickBuyTable.max_custom():
			continue
		var card := {"id": "custom_%d" % (result.size() + 1), "custom": true, "description": "Saved from your gear.",
			"name": str(entry.get("name", "")).strip_edges().left(QuickBuyTable.name_length()), "gear": {}, "parts": {}, "rounds": [], "carried": [], "left_out": []}
		if card.name == "":
			card.name = "Custom %d" % (result.size() + 1)
		var left: Array = card.left_out
		for name: Variant in entry.get("left_out", []) if entry.get("left_out") is Array else []:
			left.append(str(name))
		var gear: Variant = entry.get("gear", {})
		if gear is Dictionary:
			for slot in LoadoutPresets.SLOTS:
				if gear.get(slot) is Dictionary and _line_ok(gear[slot], left):
					card.gear[slot] = {"item": str(gear[slot].item), "trader": str(gear[slot].trader)}
		var parts: Variant = entry.get("parts", {})
		if parts is Dictionary:
			for slot: Variant in parts:
				if card.gear.has(str(slot)) and parts[slot] is Array:
					var kept := []
					for part: Variant in parts[slot]:
						if part is Dictionary and str(part.get("path", "")) != "" and _line_ok(part, left):
							kept.append({"path": str(part.path), "item": str(part.item), "trader": str(part.trader)})
					if not kept.is_empty():
						card.parts[str(slot)] = kept
		for kind in [ROUNDS, CARRIED]:
			var entries: Variant = entry.get(kind, [])
			for line: Variant in entries if entries is Array else []:
				if line is Dictionary and int(line.get("count", 0)) >= 1 and _line_ok(line, left) \
						and (kind == CARRIED or card.gear.has(str(line.get("for", "")))):
					var kept := {"item": str(line.item), "trader": str(line.trader), "count": int(line.count)}
					if kind == ROUNDS:
						kept["for"] = str(line["for"])
					card[kind].append(kept)
		result.append(card)
	return result


## True if saved `line` names an item and trader that exist; else its item goes into `left`.
static func _line_ok(line: Dictionary, left: Array) -> bool:
	var id := str(line.get("item", ""))
	if not ItemDB.has_item(id):
		left.append("%s (no longer in the game)" % id)
		return false
	if not TraderTable.has(str(line.get("trader", ""))):
		left.append(ItemDB.get_item(id).display_name)
		return false
	return true
