class_name Trading
extends RefCounted
## Buying and bartering with traders (DESIGN.md §10). Offers live in data/traders/offers.json, by
## trader id: "buy" [{item, count, price, currency, ll}] and "barters" [{give: [requirements], get:
## {item, count}, ll}]. An offer with "ll" needs that loyalty level with the trader (cheap rounds at
## LL1, AP rounds at LL3-4). What you get goes to the stash and is never found in raid; barters that
## ask for found-in-raid items only take items with the checkmark. Loyalty levels go up on their own
## once you meet the next level's player level, reputation and roubles spent (LOYALTY).

const OFFERS_PATH := "res://data/traders/offers.json"
## What each loyalty level needs: [player level, reputation, roubles spent with the trader].
const LOYALTY := {2: [15, 0.20, 750_000], 3: [25, 0.35, 1_500_000], 4: [35, 0.50, 2_500_000]}

static var _offers := {}


## {"buy": [...], "barters": [...]} for `trader_id`.
static func offers(trader_id: String) -> Dictionary:
	if _offers.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFERS_PATH))
		_offers = parsed if parsed is Dictionary else {}
		if not parsed is Dictionary:
			push_error("Trading: %s isn't valid JSON" % OFFERS_PATH)
	return _offers.get(trader_id, {"buy": [], "barters": []})


## The loyalty level `offer` needs (1 if it doesn't say).
static func offer_level(offer: Dictionary) -> int:
	return int(offer.get("ll", 1))


## "Needs loyalty level N" if `trader_id`'s loyalty is below what `offer` needs, else "".
static func loyalty_block_reason(trader_id: String, offer: Dictionary) -> String:
	if trader_id == "" or not GameState.trader_loyalty.has(trader_id):
		return ""
	var level := offer_level(offer)
	return "Needs loyalty level %d" % level if int(GameState.trader_loyalty[trader_id].level) < level else ""


## Raises `trader_id`'s loyalty level as far as the player meets LOYALTY. Returns true if it went up.
static func update_loyalty(trader_id: String) -> bool:
	if not GameState.trader_loyalty.has(trader_id):
		return false
	var loyalty: Dictionary = GameState.trader_loyalty[trader_id]
	var raised := false
	while LOYALTY.has(int(loyalty.level) + 1):
		var need: Array = LOYALTY[int(loyalty.level) + 1]
		if GameState.level < int(need[0]) or float(loyalty.reputation) < float(need[1]) or int(loyalty.spent) < int(need[2]):
			break
		loyalty.level = int(loyalty.level) + 1
		raised = true
	return raised


## Why `offer` can't be bought from `trader_id` right now, or "" if it can.
static func buy_block_reason(offer: Dictionary, trader_id := "") -> String:
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
	if offer.get("currency", "RUB") == "USD":
		GameState.dollars -= price
	else:
		GameState.roubles -= price
		GameState.trader_loyalty[trader_id].spent += price
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


## Trades the items barter `offer` asks for for its reward, into the stash. "" on success, else why not.
static func barter(offer: Dictionary, trader_id := "") -> String:
	var reason := barter_block_reason(offer, trader_id)
	if reason != "":
		return reason
	ItemSearch.pay(barter_requirements(offer))
	var reward := barter_reward(offer)
	GameState.stash.add(FoundInRaid.make(str(reward.item), int(reward.get("count", 1)), FoundInRaid.Source.BARTER))
	return ""
