class_name Trading
extends RefCounted
## Buying and bartering with traders (DESIGN.md §10). The traders are in TraderTable; their offers live
## in data/traders/offers.json, by trader id: "buy" [{item, count, price, currency, ll}] and "barters"
## [{give: [requirements], get: {item, count}, ll}]. An offer with "ll" needs that loyalty level with the
## trader (cheap rounds at LL1, AP rounds at LL3-4); a trader who isn't unlocked yet (The Broker) doesn't
## trade at all. What you get goes to the stash and is never found in raid; barters that ask for
## found-in-raid items only take items with the checkmark. Loyalty levels go up on their own once you
## meet the next level's player level, reputation and money spent (Progression.loyalty_needs()), up to
## the trader's highest. Money spent counts roubles, and dollars at Progression.dollar_rate(); every
## barter adds a little reputation with its trader, up to a cap (Progression.barter_reputation()).

const OFFERS_PATH := "res://data/traders/offers.json"

static var _offers := {}


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
	var price := int(offer.get("price", 0))
	if offer.get("currency", "RUB") == "USD":
		if GameState.dollars < price:
			return "Not enough dollars"
	elif GameState.roubles < price:
		return "Not enough roubles"
	var item := ItemInstance.create(str(offer.item), int(offer.get("count", 1)))
	if item == null:
		return "Unknown item"
	if not GameState.stash.has_room_for(item):
		return "No room in the stash"
	return ""


## Buys `offer` from `trader_id` into the stash. Returns "" on success, else why not.
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
	GameState.stash.add(FoundInRaid.make(str(offer.item), int(offer.get("count", 1)), FoundInRaid.Source.TRADER))
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
