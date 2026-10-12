class_name Trading
extends RefCounted
## Buying and bartering with traders (DESIGN.md §10). Offers live in data/traders/offers.json, by
## trader id: "buy" [{item, count, price, currency}] and "barters" [{give: [requirements], get: {item,
## count}}]. What you get goes to the stash and is never found in raid; barters that ask for
## found-in-raid items only take items with the checkmark.

const OFFERS_PATH := "res://data/traders/offers.json"

static var _offers := {}


## {"buy": [...], "barters": [...]} for `trader_id`.
static func offers(trader_id: String) -> Dictionary:
	if _offers.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFERS_PATH))
		_offers = parsed if parsed is Dictionary else {}
		if not parsed is Dictionary:
			push_error("Trading: %s isn't valid JSON" % OFFERS_PATH)
	return _offers.get(trader_id, {"buy": [], "barters": []})


## Why `offer` can't be bought right now, or "" if it can.
static func buy_block_reason(offer: Dictionary) -> String:
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
	var reason := buy_block_reason(offer)
	if reason != "":
		return reason
	var price := int(offer.get("price", 0))
	if offer.get("currency", "RUB") == "USD":
		GameState.dollars -= price
	else:
		GameState.roubles -= price
		GameState.trader_loyalty[trader_id].spent += price
	GameState.stash.add(FoundInRaid.make(str(offer.item), int(offer.get("count", 1)), FoundInRaid.Source.TRADER))
	return ""


static func barter_requirements(offer: Dictionary) -> Array[Requirement]:
	return Requirement.list(offer.get("give", []))


## The item a barter gives, as {"item", "count"}.
static func barter_reward(offer: Dictionary) -> Dictionary:
	return offer["get"]


## Why barter `offer` can't be made right now, or "" if it can.
static func barter_block_reason(offer: Dictionary) -> String:
	if not ItemSearch.can_afford(barter_requirements(offer)):
		return "Missing items"
	var reward := ItemInstance.create(str(barter_reward(offer).item), int(barter_reward(offer).get("count", 1)))
	if reward == null:
		return "Unknown item"
	if not GameState.stash.has_room_for(reward):
		return "No room in the stash"
	return ""


## Trades the items barter `offer` asks for for its reward, into the stash. "" on success, else why not.
static func barter(offer: Dictionary) -> String:
	var reason := barter_block_reason(offer)
	if reason != "":
		return reason
	ItemSearch.pay(barter_requirements(offer))
	var reward := barter_reward(offer)
	GameState.stash.add(FoundInRaid.make(str(reward.item), int(reward.get("count", 1)), FoundInRaid.Source.BARTER))
	return ""
