class_name Selling
extends RefCounted
## Selling to traders (DESIGN.md §10). Each trader's "sell" block in data/traders/traders.json says
## what they buy and what they pay: a rate (the share of an item's worth they pay at loyalty level 1),
## what each loyalty level above 1 adds, and the entries they buy, by category, group (barter goods and
## valuables), tag or weapon part kind, each with a multiplier (the best matching one counts). Mole, the
## fence, buys anything at a low rate, even what nobody else takes. The Broker pays in dollars (at
## Progression.dollar_rate()); everyone else in roubles.
##
## An item's worth (item_value()) is its value as it is: the whole stack, the uses or HP left in a med,
## food or key, a gun's or armor's durability (from durability_floor of its value worn out to all of it
## new), its upgrade level (upgrade_bonus a level), and a gun's parts and loaded rounds. Items you wear
## and what's in your secure container aren't for sale; the stash and your pockets, rig and backpack are
## (sellable_items()), but a container only once it's empty. Wanted items (TraderStock) pay ×1.5 for as
## many as the trader still takes this restock. A sale pays into roubles or dollars and counts toward
## the money spent with that trader for loyalty (trade volume; dollars at the same rate). With the
## confirm_sell_valuables setting on, the screens ask before selling Epic or Legendary items, valuables
## and insured gear, whose insurance goes with it (needs_confirm()). Numbers in
## data/config/trading.json.

## A new gun's durability (ItemInstance), what a gun's condition is measured against.
const NEW_GUN_DURABILITY := 100.0


## `trader_id`'s sell block ({} if they have none).
static func rules(trader_id: String) -> Dictionary:
	var block: Variant = TraderTable.find(trader_id).get("sell", {})
	return block if block is Dictionary else {}


## The multiplier `trader_id` applies to `data`: the best of the "buys" entries it matches (0: they
## don't buy it).
static func multiplier(trader_id: String, data: ItemData) -> float:
	var best := 0.0
	for entry: Dictionary in rules(trader_id).get("buys", []):
		if _matches(entry, data):
			best = maxf(best, float(entry.get("multiplier", 1.0)))
	return best


static func _matches(entry: Dictionary, data: ItemData) -> bool:
	if entry.get("any", false) or data.category_name() in entry.get("categories", []):
		return true
	if data.group != "" and data.group in entry.get("groups", []):
		return true
	for tag: String in entry.get("tags", []):
		if data.has_tag(tag):
			return true
	var kind := WeaponMods.kind_of(data)
	return kind != "" and kind in entry.get("kinds", [])


## True if `trader_id` buys items like `data`.
static func buys(trader_id: String, data: ItemData) -> bool:
	return multiplier(trader_id, data) > 0.0


## The share of an item's worth `trader_id` pays at your loyalty level with them.
static func rate(trader_id: String) -> float:
	var level := int(GameState.trader_loyalty.get(trader_id, {}).get("level", 1))
	return float(rules(trader_id).get("rate", 0.0)) + float(rules(trader_id).get("per_level", 0.0)) * (level - 1)


## "RUB" or "USD": what `trader_id` pays in.
static func currency(trader_id: String) -> String:
	return str(TraderTable.find(trader_id).get("currency", "RUB"))


# --- Worth --------------------------------------------------------------------------------------

## How worn a gun or armor is, as the share of its value it keeps: durability_floor worn out, 1 new
## (1 for anything that doesn't wear).
static func condition(item: ItemInstance) -> float:
	if not item.has_durability():
		return 1.0
	var floor_share := float(Trading.config().get("sell_value", {}).get("durability_floor", 0.0))
	var full := GearUpgrades.max_durability(item.data, item.upgrade_level) if item.is_armor() else NEW_GUN_DURABILITY
	return floor_share + (1.0 - floor_share) * clampf(item.durability / maxf(full, 1.0), 0.0, 1.0)


## What `item` is worth to a trader before their rate, in roubles: its value for the whole stack, by
## the uses or HP left, its condition and upgrade level, plus the parts fitted to it and the rounds
## loaded in it (not what's inside a container: that's sold on its own).
static func item_value(item: ItemInstance) -> int:
	return roundi(_worth(item))


static func _worth(item: ItemInstance) -> float:
	var unit := float(item.data.base_value)
	if item.is_part_used():
		unit *= item.charges / Consumables.max_charges(item.data)
	unit *= condition(item)
	unit *= 1.0 + float(Trading.config().get("sell_value", {}).get("upgrade_bonus", 0.0)) * item.upgrade_level
	var total := unit * item.count
	for part: ItemInstance in item.mods.values():
		total += _worth(part)
	for rounds in item.magazine:
		total += rounds.value()
	return total


## What `trader_id` pays for `item`, in their currency (roubles, or dollars at
## Progression.dollar_rate()): its worth × their rate × their multiplier for it, the Wanted bonus on as
## many as they still take (less `wanted_counted` already counted in the same sale). 0 if they don't
## buy it.
static func price(trader_id: String, item: ItemInstance, wanted_counted := 0) -> int:
	var times := multiplier(trader_id, item.data)
	if times <= 0.0:
		return 0
	var roubles := _worth(item) * rate(trader_id) * times
	var bonus := clampi(TraderStock.wanted_left(trader_id, item.data.id) - wanted_counted, 0, item.count)
	if bonus > 0:
		roubles += roubles * (TraderStock.wanted_multiplier() - 1.0) * bonus / item.count
	return floori(roubles / Progression.dollar_rate()) if currency(trader_id) == "USD" else floori(roubles)


## What `trader_id` pays for each of `items` sold together (the Wanted bonus runs out across them).
static func quote(trader_id: String, items: Array) -> Array[int]:
	var counted := {}
	var prices: Array[int] = []
	for item: ItemInstance in items:
		prices.append(price(trader_id, item, int(counted.get(item.data.id, 0))))
		counted[item.data.id] = int(counted.get(item.data.id, 0)) + item.count
	return prices


## What `trader_id` pays for `items` sold together, in their currency.
static func total(trader_id: String, items: Array) -> int:
	var sum := 0
	for each in quote(trader_id, items):
		sum += each
	return sum


## The unlocked trader who pays most for `item` (prices compared in roubles, a dollar at
## Progression.dollar_rate(); the first in roster order on a tie), "" if nobody buys it.
static func best_trader(item: ItemInstance) -> String:
	var best := ""
	var best_worth := 0
	for trader_id in TraderTable.ids():
		if not TraderTable.is_unlocked(trader_id):
			continue
		var worth := Trading.spent_value(price(trader_id, item), currency(trader_id))
		if worth > best_worth:
			best = trader_id
			best_worth = worth
	return best


# --- What you can sell --------------------------------------------------------------------------

## Where `item` is among your things: {"holder": the InventoryGrid it's in, "where": "Stash", "Pockets",
## "In Daypack" or "In Daypack (stash)"}, {"slot": an equipment slot} if you wear it, plus "secure":
## true inside the secure container; {} if it isn't yours.
static func locate(item: ItemInstance) -> Dictionary:
	var inventory := GameState.inventory
	for slot: String in inventory.equipment:
		if inventory.equipment[slot] == item:
			return {"slot": slot, "where": "Equipped"}
	for grid in inventory.grids():
		var holder := grid.find_holder(item)
		if holder:
			return {"holder": holder, "where": _where(holder, "Pockets", ""), "secure": grid.kind == &"secure"}
	var held := GameState.stash.find_holder(item) if GameState.stash else null
	if held:
		return {"holder": held, "where": _where(held, "Stash", " (stash)")}
	return {}


static func _where(holder: InventoryGrid, top: String, suffix: String) -> String:
	var owner := holder.owner_item()
	if owner == null:
		return top
	return "In %s%s" % [owner.data.display_name, suffix]


## Everything you could sell, in order: the stash, then your pockets, rig and backpack, each grid row
## by row with what's inside containers after them; not what you wear, not what's in your secure
## container, nothing worth nothing (the secure containers). [{"item", "where"}].
static func sellable_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if GameState.stash:
		_collect(GameState.stash, "Stash", " (stash)", result)
	for grid in GameState.inventory.grids():
		if grid.kind != &"secure":
			_collect(grid, "Pockets", "", result)
	return result


static func _collect(grid: InventoryGrid, top: String, suffix: String, into: Array[Dictionary]) -> void:
	var items := grid.items.duplicate()
	items.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.cell.y < b.cell.y or (a.cell.y == b.cell.y and a.cell.x < b.cell.x))
	for item: ItemInstance in items:
		if item_value(item) > 0:
			into.append({"item": item, "where": _where(grid, top, suffix)})
	for item: ItemInstance in items:
		if item.contents:
			_collect(item.contents, top, suffix, into)


## Why `item` can't be sold to anyone right now ("" if it can): you wear it, it's in your secure
## container, it's a container with something in it, it's worth nothing, or it isn't yours.
static func block_reason(item: ItemInstance) -> String:
	var place := locate(item)
	if place.is_empty():
		return "It isn't in your stash or inventory"
	if place.has("slot"):
		return "Take it off first"
	if place.get("secure", false):
		return "Take it out of your secure container first"
	if not item.is_empty_container():
		var inside := item.contents.items.size()
		return "Empty it first: %d item%s inside" % [inside, "" if inside == 1 else "s"]
	if item_value(item) <= 0:
		return "Worth nothing to a trader"
	return ""


## Why `trader_id` won't buy `item` ("" if they will).
static func sell_block_reason(trader_id: String, item: ItemInstance) -> String:
	var locked := Trading.trader_block_reason(trader_id)
	if locked != "":
		return locked
	if not buys(trader_id, item.data):
		return "%s doesn't buy that" % TraderTable.display_name(trader_id)
	var reason := block_reason(item)
	if reason != "":
		return reason
	if price(trader_id, item) <= 0:
		return "Worth nothing to %s" % TraderTable.display_name(trader_id)
	return ""


## Sells `items` to `trader_id`: takes them out of the stash or your inventory, pays their price
## (quote()) in the trader's currency, counts it toward the money spent with them (Trading.spent_value())
## and the Wanted ones toward this restock's cap, and checks their loyalty. All or nothing: "" on
## success, else why not.
static func sell(trader_id: String, items: Array) -> String:
	if items.is_empty():
		return "Nothing to sell"
	var seen := {}
	for item: ItemInstance in items:
		if seen.has(item):
			return "The same item twice"
		seen[item] = true
		var reason := sell_block_reason(trader_id, item)
		if reason != "":
			return "%s: %s" % [item.data.display_name, reason]
	var prices := quote(trader_id, items)
	var paid := 0
	for i in items.size():
		var item: ItemInstance = items[i]
		var wanted := mini(item.count, TraderStock.wanted_left(trader_id, item.data.id))
		if wanted > 0:
			TraderStock.record_wanted(trader_id, item.data.id, wanted)
		_take(item)
		paid += prices[i]
	if currency(trader_id) == "USD":
		GameState.dollars += paid
	else:
		GameState.roubles += paid
	if GameState.trader_loyalty.has(trader_id):
		GameState.trader_loyalty[trader_id].spent += Trading.spent_value(paid, currency(trader_id))
	Trading.update_loyalty(trader_id)
	return ""


## Takes `item` out of whichever grid of yours holds it, letting the grids (and the inventory) redraw.
static func _take(item: ItemInstance) -> void:
	if GameState.inventory.holder_of(item):
		GameState.inventory.remove_item(item)
		return
	var holder := GameState.stash.find_holder(item)
	if holder:
		holder.remove(item)
		if holder != GameState.stash:
			GameState.stash.changed.emit()


## True for items the confirm_sell_valuables setting asks about: the confirm rarity (Epic) or rarer, or
## with a confirm tag ("valuable").
static func is_valuable(item: ItemInstance) -> bool:
	var rule: Dictionary = Trading.config().get("confirm", {})
	if item.data.rarity >= ItemData.RARITY_IDS.find(str(rule.get("rarity", "epic"))):
		return true
	for tag: String in rule.get("tags", []):
		if item.data.has_tag(tag):
			return true
	return false


## True if selling `items` should ask first: the setting is on and one of them is_valuable() or
## insured (the insurance is lost with it).
static func needs_confirm(items: Array) -> bool:
	if not bool(Settings.get_value("gameplay", "confirm_sell_valuables")):
		return false
	return items.any(func(item: ItemInstance) -> bool: return is_valuable(item) or item.insured)


## The question before selling `items` to `trader_id`: "Sell Roler Submariner gold wrist watch (Epic) to
## The Broker for $ 2,228?", "Sell AK-74N (insured) to Bulat for ₽ 30,500?", or for several "Sell 4
## items to Mole for ₽ 312,000? Among them: ..." (the valuable and insured ones).
static func confirm_text(trader_id: String, items: Array) -> String:
	var money := UiFormat.money(total(trader_id, items), currency(trader_id))
	var named: Array[String] = []
	for item: ItemInstance in items:
		var notes: Array[String] = []
		if is_valuable(item):
			notes.append(Palette.RARITY_NAMES[item.data.rarity])
		if item.insured:
			notes.append("insured")
		if not notes.is_empty():
			named.append("%s (%s)" % [item.title(), ", ".join(notes)])
	if items.size() == 1:
		return "Sell %s to %s for %s?" % [named[0] if not named.is_empty() else items[0].title(), TraderTable.display_name(trader_id), money]
	return "Sell %d items to %s for %s? Among them: %s." % [items.size(), TraderTable.display_name(trader_id), money, ", ".join(named)]


# --- Checks -------------------------------------------------------------------------------------

## Problems with the traders' sell blocks (empty if nothing): every trader needs one, with a rate in
## 0-1 (also at their top loyalty level), a per_level of 0 or more and "buys" entries that name real
## categories, groups, tags or part kinds with a multiplier above 0.
static func problems() -> Array[String]:
	var found: Array[String] = []
	for entry in TraderTable.all():
		var id := str(entry.get("id", ""))
		var block: Variant = entry.get("sell")
		if not block is Dictionary:
			found.append("trader %s: no sell block" % id)
			continue
		var top := float(block.get("rate", 0.0)) + float(block.get("per_level", 0.0)) * (TraderTable.max_loyalty(id) - 1)
		if float(block.get("rate", 0.0)) <= 0.0 or top > 1.0 or float(block.get("per_level", -1.0)) < 0.0:
			found.append("trader %s: sell rate must be above 0 and at most 1 at the top loyalty level, per_level 0 or more" % id)
		var buys_list: Variant = block.get("buys", [])
		if not buys_list is Array or buys_list.is_empty():
			found.append("trader %s: sell block buys nothing" % id)
			continue
		for rule: Variant in buys_list:
			if not rule is Dictionary or not (rule.get("any", false) or rule.has("categories") or rule.has("groups") or rule.has("tags") or rule.has("kinds")):
				found.append("trader %s: sell entry %s names no categories, groups, tags or kinds" % [id, rule])
				continue
			if float(rule.get("multiplier", 1.0)) <= 0.0:
				found.append("trader %s: sell entry %s needs a multiplier above 0" % [id, rule])
			for name: Variant in rule.get("categories", []):
				if not str(name) in ItemData.CATEGORY_NAMES:
					found.append("trader %s: buys category %s, which doesn't exist" % [id, name])
			for name: Variant in rule.get("groups", []):
				if not str(name) in ItemGroups.names():
					found.append("trader %s: buys group %s, which doesn't exist" % [id, name])
			for name: Variant in rule.get("tags", []):
				if not ItemGroups.is_tag(str(name)):
					found.append("trader %s: buys tag %s, which doesn't exist" % [id, name])
			for name: Variant in rule.get("kinds", []):
				if not WeaponMods.KIND_NAMES.has(str(name)):
					found.append("trader %s: buys part kind %s, which doesn't exist" % [id, name])
	return found
