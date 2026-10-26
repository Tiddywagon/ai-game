class_name Trading
extends RefCounted
## Buying, bartering and changing money with traders (DESIGN.md §10). The traders are in TraderTable;
## their offers live in data/traders/offers.json, by trader id: "buy" [{id, item, count, price, currency,
## ll, stock}] and "barters" [{give: [requirements], get: {item, count}, ll}]. An offer with "ll" needs
## that loyalty level with the trader (cheap rounds at LL1, AP rounds at LL3-4), at least the level its
## item's rarity needs (min_loyalty in data/config/trading.json: Rare LL2, Ultra Rare LL3, Epic LL4,
## Legendary never for money; problems() checks it); the BUY tab shows only what your level reaches and
## counts the rest ("4 more items at LL2"). An offer with "stock" sells that many each restock
## (TraderStock, by the offer's "id"). The fence's worn gear is rolled each restock (buy_list()); an
## offer of it from before his last restock can't be bought. A trader who isn't unlocked yet (The
## Broker) doesn't trade at all. What you get goes to the stash and is never found in raid; barters that
## ask for found-in-raid items only take items with the checkmark.
## Loyalty levels go up on their own once you meet the next level's player level, reputation and money
## spent (Progression.loyalty_needs()), up to the trader's highest. Money spent counts roubles, and
## dollars at Progression.dollar_rate(); selling to a trader counts too (Selling). Changing money at the
## exchange doesn't (buy_dollars(): The Broker changes money once he trades with you, dearer one way
## than the other); the dollars count when you spend them with him. Every barter adds a little
## reputation with its trader, up to a cap (Progression.barter_reputation()).

const OFFERS_PATH := "res://data/traders/offers.json"
const CONFIG_PATH := "res://data/config/trading.json"
const CURRENCIES: Array[String] = ["RUB", "USD"]

static var _offers := {}
static var _config := {}
## The lowest loyalty level each item is sold at for money, by item id (sold_at_level()).
static var _sold_at := {}


## offers.json: {trader id: {"buy": [...], "barters": [...]}}.
static func all_offers() -> Dictionary:
	if _offers.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFERS_PATH))
		_offers = parsed if parsed is Dictionary else {}
		if not parsed is Dictionary:
			push_error("Trading: %s isn't valid JSON" % OFFERS_PATH)
	return _offers


## {"buy": [...], "barters": [...]} for `trader_id`.
static func offers(trader_id: String) -> Dictionary:
	return all_offers().get(trader_id, {"buy": [], "barters": []})


## data/config/trading.json: restocks, the rarity rule, sell values, Wanted items, the exchange and the
## fence's used gear (problems() checks it).
static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {}
		if _config.is_empty():
			push_error("Trading: %s isn't valid JSON" % CONFIG_PATH)
	return _config


## The lowest loyalty level a buy offer for `data` may need, by its rarity (0: never sold for money).
static func min_loyalty(data: ItemData) -> int:
	return int(config().get("min_loyalty", {}).get(ItemData.RARITY_IDS[data.rarity], 1))


## The lowest loyalty level any trader sells item `id` at for money (a buy offer in offers.json), 0 if
## nobody does. The fence's shelf and the Wanted lists go by it (TraderStock).
static func sold_at_level(id: String) -> int:
	if _sold_at.is_empty():
		for trader_id in TraderTable.ids():
			for offer: Dictionary in offers(trader_id).get("buy", []):
				var item := str(offer.get("item", ""))
				_sold_at[item] = mini(int(_sold_at.get(item, offer_level(offer))), offer_level(offer))
	return int(_sold_at.get(id, 0))


## Everything `trader_id` sells this restock: their buy offers in offers.json and, for the fence, his
## worn gear (TraderStock.used_offers()).
static func buy_list(trader_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(offers(trader_id).get("buy", []))
	result.append_array(TraderStock.used_offers(trader_id))
	return result


## What the BUY tab shows: the part of buy_list() your loyalty level with `trader_id` reaches.
static func shown_offers(trader_id: String) -> Array[Dictionary]:
	return buy_list(trader_id).filter(func(offer: Dictionary) -> bool: return loyalty_block_reason(trader_id, offer) == "")


## How many of `trader_id`'s buy offers wait for each loyalty level above yours: {2: 4, 3: 3}.
static func hidden_offers(trader_id: String) -> Dictionary:
	var result := {}
	for offer in buy_list(trader_id):
		if loyalty_block_reason(trader_id, offer) != "":
			result[offer_level(offer)] = int(result.get(offer_level(offer), 0)) + 1
	return result


## The line under the BUY list about what's still to come: "4 more items at LL2  ·  3 at LL3" ("" when
## your level shows everything).
static func hidden_text(trader_id: String) -> String:
	var counts := hidden_offers(trader_id)
	var levels := counts.keys()
	levels.sort()
	var parts: Array[String] = []
	for level: int in levels:
		var count := int(counts[level])
		if parts.is_empty():
			parts.append("%d more item%s at LL%d" % [count, "" if count == 1 else "s", level])
		else:
			parts.append("%d at LL%d" % [count, level])
	return "  ·  ".join(parts)


## The item buying `offer` gives: the worn piece itself for the fence's gear ("instance"), else a new one.
static func offer_item(offer: Dictionary) -> ItemInstance:
	if offer.has("instance"):
		return ItemInstance.from_dict(offer.instance)
	return ItemInstance.create(str(offer.get("item", "")), int(offer.get("count", 1)))


## The loyalty level `offer` needs (1 if it doesn't say).
static func offer_level(offer: Dictionary) -> int:
	return int(offer.get("ll", 1))


## "Needs loyalty level N" if `trader_id`'s loyalty is below what `offer` needs, else "".
static func loyalty_block_reason(trader_id: String, offer: Dictionary) -> String:
	if trader_id == "" or not GameState.trader_loyalty.has(trader_id):
		return ""
	var level := offer_level(offer)
	return "Needs loyalty level %d" % level if int(GameState.trader_loyalty[trader_id].level) < level else ""


## "The Broker doesn't trade with you yet" while `trader_id` is locked (TraderTable.is_unlocked()), else "".
static func trader_block_reason(trader_id: String) -> String:
	if trader_id == "" or TraderTable.is_unlocked(trader_id):
		return ""
	return "%s doesn't trade with you yet" % TraderTable.display_name(trader_id)


## Raises `trader_id`'s loyalty level as far as the player meets Progression.loyalty_needs() (a
## reputation a rounding error short, within Progression.REPUTATION_EPSILON, counts), up to the trader's
## highest (TraderTable.max_loyalty()). Returns true if it went up.
static func update_loyalty(trader_id: String) -> bool:
	if not GameState.trader_loyalty.has(trader_id):
		return false
	var loyalty: Dictionary = GameState.trader_loyalty[trader_id]
	var raised := false
	while int(loyalty.level) < TraderTable.max_loyalty(trader_id):
		var need := Progression.loyalty_needs(int(loyalty.level) + 1)
		if need.is_empty() or GameState.level < int(need.player_level) \
				or float(loyalty.reputation) < float(need.reputation) - Progression.REPUTATION_EPSILON or int(loyalty.spent) < int(need.spent):
			break
		loyalty.level = int(loyalty.level) + 1
		raised = true
	return raised


## update_loyalty() for every trader (after a level-up).
static func update_all_loyalty() -> void:
	for trader_id in TraderTable.ids():
		update_loyalty(trader_id)


## What paying `price` in `currency` ("RUB" or "USD") counts as toward money spent with a trader, in
## roubles: dollars at Progression.dollar_rate().
static func spent_value(price: int, currency: String) -> int:
	return roundi(price * Progression.dollar_rate()) if currency == "USD" else price


## Reputation barters have earned with `trader_id` so far (at most Progression.barter_reputation_cap()).
static func barter_reputation(trader_id: String) -> float:
	return float(GameState.trader_loyalty.get(trader_id, {}).get("barter_reputation", 0.0))


## Adds a barter's reputation with `trader_id`, as far as the cap allows.
static func _add_barter_reputation(trader_id: String) -> void:
	if not GameState.trader_loyalty.has(trader_id):
		return
	var gain := minf(Progression.barter_reputation(), Progression.barter_reputation_cap() - barter_reputation(trader_id))
	if gain <= 0.0:
		return
	var loyalty: Dictionary = GameState.trader_loyalty[trader_id]
	loyalty.barter_reputation = Progression.add_reputation(barter_reputation(trader_id), gain)
	loyalty.reputation = Progression.add_reputation(float(loyalty.reputation), gain)


## Why `offer` can't be bought from `trader_id` right now, or "" if it can.
static func buy_block_reason(offer: Dictionary, trader_id := "") -> String:
	var locked := trader_block_reason(trader_id)
	if locked != "":
		return locked
	var loyalty := loyalty_block_reason(trader_id, offer)
	if loyalty != "":
		return loyalty
	if offer.get("used", false) and not TraderStock.used_offers(trader_id).any(func(each: Dictionary) -> bool: return each.id == offer.get("id")):
		return "Gone: %s has restocked" % TraderTable.display_name(trader_id)  # A row drawn before the restock.
	if trader_id != "" and TraderStock.left(trader_id, offer) == 0:
		return "Sold out until the restock (in %s)" % TraderStock.countdown_text(trader_id)
	var price := int(offer.get("price", 0))
	if offer.get("currency", "RUB") == "USD":
		if GameState.dollars < price:
			return "Not enough dollars"
	elif GameState.roubles < price:
		return "Not enough roubles"
	var item := offer_item(offer)
	if item == null:
		return "Unknown item"
	if not GameState.stash.has_room_for(item):
		return "No room in the stash"
	return ""


## Buys `offer` from `trader_id` into the stash, taking one off its stock if it has a limit (TraderStock).
## Returns "" on success, else why not.
static func buy(trader_id: String, offer: Dictionary) -> String:
	var reason := buy_block_reason(offer, trader_id)
	if reason != "":
		return reason
	var price := int(offer.get("price", 0))
	var currency := str(offer.get("currency", "RUB"))
	if currency == "USD":
		GameState.dollars -= price
	else:
		GameState.roubles -= price
	if GameState.trader_loyalty.has(trader_id):
		GameState.trader_loyalty[trader_id].spent += spent_value(price, currency)
	TraderStock.take(trader_id, offer)
	var item := offer_item(offer)
	FoundInRaid.set_found(item, FoundInRaid.gives_fir(FoundInRaid.Source.TRADER))
	GameState.stash.add(item)
	update_loyalty(trader_id)
	return ""


static func barter_requirements(offer: Dictionary) -> Array[Requirement]:
	return Requirement.list(offer.get("give", []))


## The item a barter gives, as {"item", "count"}.
static func barter_reward(offer: Dictionary) -> Dictionary:
	return offer["get"]


## Why barter `offer` can't be made with `trader_id` right now, or "" if it can.
static func barter_block_reason(offer: Dictionary, trader_id := "") -> String:
	var locked := trader_block_reason(trader_id)
	if locked != "":
		return locked
	var loyalty := loyalty_block_reason(trader_id, offer)
	if loyalty != "":
		return loyalty
	if not ItemSearch.can_afford(barter_requirements(offer)):
		return "Missing items"
	var reward := ItemInstance.create(str(barter_reward(offer).item), int(barter_reward(offer).get("count", 1)))
	if reward == null:
		return "Unknown item"
	if not GameState.stash.has_room_for(reward):
		return "No room in the stash"
	return ""


## Trades the items barter `offer` asks for for its reward, into the stash, and adds a barter's
## reputation with `trader_id`. "" on success, else why not.
static func barter(offer: Dictionary, trader_id := "") -> String:
	var reason := barter_block_reason(offer, trader_id)
	if reason != "":
		return reason
	ItemSearch.pay(barter_requirements(offer))
	var reward := barter_reward(offer)
	GameState.stash.add(FoundInRaid.make(str(reward.item), int(reward.get("count", 1)), FoundInRaid.Source.BARTER))
	_add_barter_reputation(trader_id)
	update_loyalty(trader_id)
	return ""


# --- Currency exchange --------------------------------------------------------------------------

## The trader who changes money (The Broker) and his rates: {"trader", "buy": roubles a dollar costs,
## "sell": roubles a dollar fetches}.
static func exchange() -> Dictionary:
	return config().get("exchange", {})


static func exchange_trader() -> String:
	return str(exchange().get("trader", ""))


## Roubles `dollars` dollars cost at the exchange (`buying`), or fetch (selling them).
static func exchange_roubles(dollars: int, buying: bool) -> int:
	return dollars * int(exchange().get("buy" if buying else "sell", 0))


## Why you can't change `dollars` dollars right now ("" if you can): `buying` them with roubles, or
## selling them for roubles.
static func exchange_block_reason(dollars: int, buying: bool) -> String:
	var locked := trader_block_reason(exchange_trader())
	if locked != "":
		return locked
	if dollars <= 0:
		return "Pick an amount"
	if buying and GameState.roubles < exchange_roubles(dollars, true):
		return "Not enough roubles"
	if not buying and GameState.dollars < dollars:
		return "Not enough dollars"
	return ""


## Buys `dollars` dollars for roubles. Not counted toward money spent with the exchange trader: the
## dollars count when you spend them with him (else buying and selling dollars back would buy loyalty
## for the 20 ₽ a dollar the round trip loses). "" on success, else why not.
static func buy_dollars(dollars: int) -> String:
	var reason := exchange_block_reason(dollars, true)
	if reason != "":
		return reason
	GameState.roubles -= exchange_roubles(dollars, true)
	GameState.dollars += dollars
	return ""


## Sells `dollars` dollars for roubles. "" on success, else why not.
static func sell_dollars(dollars: int) -> String:
	var reason := exchange_block_reason(dollars, false)
	if reason != "":
		return reason
	GameState.dollars -= dollars
	GameState.roubles += exchange_roubles(dollars, false)
	return ""


# --- Checks -------------------------------------------------------------------------------------

## What's wrong with offers.json (against the items and the rarity rule) and trading.json (empty if
## nothing). Needs the items loaded: ItemDB runs it once it has them.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var ids := {}
	var top := Progression.max_loyalty()
	for trader_id in TraderTable.ids():
		var where := "%s %s" % [OFFERS_PATH.get_file(), trader_id]
		for offer: Dictionary in offers(trader_id).get("buy", []):
			var id := str(offer.get("id", ""))
			var data := ItemDB.get_item(str(offer.get("item", ""))) if ItemDB.has_item(str(offer.get("item", ""))) else null
			if id == "" or ids.has(id):
				found.append("%s: offer %s has no id or one already taken" % [where, offer])
			ids[id] = true
			if data == null:
				found.append("%s: offer %s sells an item that doesn't exist" % [where, id])
				continue
			if int(offer.get("price", 0)) <= 0 or int(offer.get("count", 1)) < 1 or not str(offer.get("currency", "RUB")) in CURRENCIES:
				found.append("%s: offer %s needs a price above 0, a count of 1 or more and RUB or USD" % [where, id])
			var level := offer_level(offer)
			if level < 1 or level > top:
				found.append("%s: offer %s needs loyalty level %d, not 1-%d" % [where, id, level, top])
			var lowest := min_loyalty(data)
			if lowest <= 0:
				found.append("%s: offer %s sells %s (%s), which is never sold for money" % [where, id, data.display_name, Palette.RARITY_NAMES[data.rarity]])
			elif level < lowest:
				found.append("%s: offer %s sells %s (%s) at LL%d; that rarity needs LL%d or more" % [where, id, data.display_name,
					Palette.RARITY_NAMES[data.rarity], level, lowest])
			if offer.has("stock") and (not (offer.stock is float or offer.stock is int) or int(offer.stock) < 1 or float(offer.stock) != floorf(float(offer.stock))):
				found.append("%s: offer %s: stock must be a whole number, 1 or more" % [where, id])
		for barter: Dictionary in offers(trader_id).get("barters", []):
			var id := str(barter.get("id", ""))
			if barter.has("stock") and id == "":
				found.append("%s: a barter with stock needs an id" % where)
			if id != "":
				if ids.has(id):
					found.append("%s: barter id %s is already taken" % [where, id])
				ids[id] = true
	found.append_array(_config_problems())
	return found


static func _config_problems() -> Array[String]:
	var found: Array[String] = []
	var where := CONFIG_PATH.get_file()
	var rule := config()
	if float(rule.get("restock_minutes", 0.0)) <= 0.0:
		found.append("%s: restock_minutes must be above 0" % where)
	var lowest: Dictionary = rule.get("min_loyalty", {})
	var last := 1
	for rarity in ItemData.RARITY_IDS:
		var level := int(lowest.get(rarity, -1))
		if level < 0 or level > Progression.max_loyalty() or (level > 0 and level < last):
			found.append("%s: min_loyalty for %s must be 0 (never for money) or 1-%d, rising with rarity" % [where, rarity, Progression.max_loyalty()])
		last = maxi(last, level)
	var value: Dictionary = rule.get("sell_value", {})
	if not (float(value.get("durability_floor", -1.0)) >= 0.0 and float(value.get("durability_floor", 2.0)) <= 1.0 and float(value.get("upgrade_bonus", -1.0)) >= 0.0):
		found.append("%s: sell_value needs durability_floor (0-1) and upgrade_bonus (0 or more)" % where)
	var confirm: Dictionary = rule.get("confirm", {})
	if not str(confirm.get("rarity", "")) in ItemData.RARITY_IDS or not confirm.get("tags", []) is Array:
		found.append("%s: confirm needs a rarity and a list of tags" % where)
	var wanted: Dictionary = rule.get("wanted", {})
	var count: Array = wanted.get("count", [])
	if count.size() != 2 or int(count[0]) < 1 or int(count[1]) < int(count[0]) or float(wanted.get("multiplier", 0.0)) <= 1.0 \
			or int(wanted.get("per_item", 0)) < 1 or not str(wanted.get("max_rarity", "")) in ItemData.RARITY_IDS \
			or not wanted.get("categories", []) is Array or wanted.get("categories", []).any(func(name: Variant) -> bool: return not str(name) in ItemData.CATEGORY_NAMES):
		found.append("%s: wanted needs count [from, to] (1 or more), a multiplier above 1, per_item 1 or more, categories and a max_rarity" % where)
	var money := exchange()
	if not TraderTable.has(exchange_trader()) or int(money.get("buy", 0)) <= int(money.get("sell", 0)) or int(money.get("sell", 0)) <= 0:
		found.append("%s: exchange needs a trader and a buy rate above its sell rate (above 0)" % where)
	var used: Dictionary = rule.get("used_stock", {})
	var range_count: Array = used.get("count", [])
	var durability: Array = used.get("durability", [])
	if not TraderTable.has(str(used.get("trader", ""))) or range_count.size() != 2 or int(range_count[0]) < 1 or int(range_count[1]) < int(range_count[0]) \
			or durability.size() != 2 or float(durability[0]) <= 0.0 or float(durability[1]) > 1.0 or float(durability[1]) < float(durability[0]) \
			or float(used.get("price", 0.0)) <= 0.0:
		found.append("%s: used_stock needs a trader, count [from, to], durability [from, to] within 0-1 and a price above 0" % where)
	var tables: Dictionary = used.get("tables", {})
	if tables.is_empty():
		found.append("%s: used_stock has no tables" % where)
	for path: String in tables:
		if not ResourceLoader.exists(path) or not load(path) is LootTable or float(tables[path]) <= 0.0:
			found.append("%s: used_stock table %s isn't a loot table with a weight above 0" % [where, path])
	return found
