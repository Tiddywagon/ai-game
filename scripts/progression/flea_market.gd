class_name FleaMarket
extends RefCounted
## The flea market (DESIGN.md §10, Flea market), open from player level 15 (FleaTable has the rules,
## data/config/flea.json the numbers). GameState.flea keeps your side of it: the pressure your trades put
## on prices, which listings you bought, your own listings, the next listing number and the market's
## clock.
##
## Market price: an item's worth (Selling.item_value(): its condition, parts and rounds counted) × its
## multiplier: a drift, a seeded walk the same for everyone on the same clock (drift()), plus your own
## pressure (pressure()): buying a listing pushes that item's price up, putting one up pushes it down,
## halving every few hours. Both move only once a bucket (an hour), so a price holds between them.
## The market's clock (time()) never runs backwards: a computer clock set back waits for it.

## Unix time `time` stands for when it's -1: the market's clock now.
const NOW := -1.0
## The most drift multipliers kept before the cache starts again.
const CACHE_LIMIT := 20000

static var _drift_cache := {}
## The listings of each refresh still up, by refresh number (listings_on()), and the gun parts the market
## may list (_part_pool()).
static var _batches := {}
static var _parts := []


## The market's clock: the real clock (TraderStock.now(), which tests override), never earlier than the
## last time the market was brought up to date (GameState.flea "clock").
static func time() -> float:
	return maxf(TraderStock.now(), float(GameState.flea.get("clock", 0.0)))


## GameState.flea for a new profile.
static func blank() -> Dictionary:
	return {"pressure": {}, "bought": {}, "listings": [], "next_id": 1, "clock": 0.0}


static func _at(when: float) -> float:
	return time() if when < 0.0 else when


## True once your level reaches FleaTable.unlock_level().
static func is_unlocked() -> bool:
	return GameState.level >= FleaTable.unlock_level()


## "Level 15": what the locked FLEA MARKET buttons say.
static func lock_text() -> String:
	return "Level %d" % FleaTable.unlock_level()


## Why you can't use the flea market yet ("" once you can).
static func lock_reason() -> String:
	return "" if is_unlocked() else "The flea market opens at level %d" % FleaTable.unlock_level()


## Brings the market up to date: moves its clock on to now.
static func update() -> void:
	GameState.flea.clock = time()


# --- Market price -------------------------------------------------------------------------------

static func bucket_seconds() -> float:
	return maxf(float(FleaTable.drift().get("bucket_minutes", 60.0)), 1.0) * 60.0


## Which drift bucket unix time `when` falls in.
static func bucket(when := NOW) -> int:
	return floori(_at(when) / bucket_seconds())


## Item `id`'s drift multiplier at `when`: the sum of the last "window" seeded steps (each from -speed
## to +speed, seeded by the item and the bucket), kept within -1..1 and mapped onto min..center..max.
## Everyone on the same clock gets the same number.
static func drift(id: String, when := NOW) -> float:
	var number := bucket(when)
	var key := "%s:%d" % [id, number]
	if _drift_cache.has(key):
		return _drift_cache[key]
	var walk := FleaTable.drift()
	var window := maxi(int(walk.get("window", 24)), 1)
	var total := 0.0
	for step in range(number - window + 1, number + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = ("flea:%s:%d" % [id, step]).hash()
		total += rng.randf_range(-1.0, 1.0)
	var position := clampf(total * float(walk.get("speed", 0.1)), -1.0, 1.0)
	var center := float(walk.get("center", 1.0))
	var result := center + position * ((float(walk.get("max", 1.0)) - center) if position > 0.0 else (center - float(walk.get("min", 1.0))))
	if _drift_cache.size() >= CACHE_LIMIT:
		_drift_cache.clear()
	_drift_cache[key] = result
	return result


## How much each bucket keeps of your pressure on a price (it halves every half_life_hours).
static func _decay() -> float:
	return pow(0.5, bucket_seconds() / 3600.0 / maxf(float(FleaTable.pressure().get("half_life_hours", 6.0)), 0.01))


## Your pressure on item `id`'s price at `when`: what your trades added (buying up, putting up for sale
## down), halving every half_life_hours, counted in whole buckets.
static func pressure(id: String, when := NOW) -> float:
	var entry: Variant = GameState.flea.pressure.get(id)
	if not entry is Dictionary:
		return 0.0
	return float(entry.get("value", 0.0)) * pow(_decay(), maxi(bucket(when) - int(entry.get("bucket", 0)), 0))


## Adds `amount` to your pressure on item `id` now, kept within the config's max either way.
static func push(id: String, amount: float) -> void:
	var top := float(FleaTable.pressure().get("max", 0.25))
	GameState.flea.pressure[id] = {"value": clampf(pressure(id) + amount, -top, top), "bucket": bucket()}


## Item `id`'s market multiplier at `when`: its drift plus your pressure.
static func multiplier(id: String, when := NOW) -> float:
	return drift(id, when) + pressure(id, when)


## What `item` (as it is: the stack, its condition, parts and rounds) fetches on the market at `when`,
## in roubles: its worth × multiplier().
static func market_price(item: ItemInstance, when := NOW) -> int:
	return roundi(Selling.item_value(item) * multiplier(item.data.id, when))


## The market price of one new item `id` (0 if there's no such item).
static func unit_price(id: String, when := NOW) -> int:
	var item := ItemInstance.create(id) if ItemDB.has_item(id) else null
	return market_price(item, when) if item else 0


## Which way item `id`'s price went over the last trend_hours: 1 up, -1 down, 0 about the same (within
## trend_threshold).
static func trend(id: String, when := NOW) -> int:
	var walk := FleaTable.drift()
	var before := multiplier(id, _at(when) - float(walk.get("trend_hours", 6.0)) * 3600.0)
	var change := multiplier(id, when) / maxf(before, 0.01) - 1.0
	var threshold := float(walk.get("trend_threshold", 0.02))
	return 1 if change > threshold else (-1 if change < -threshold else 0)


## The least anything may be listed for on the market, in roubles: the item's resale floor
## (Trading.resale_floor(): what the best-paying trader gives for it at their top loyalty level, whole or
## in parts, plus the resale margin) and, for anything a trader could want, that with the Wanted bonus,
## so nothing bought here sells on to any trader at a profit.
static func floor_price(item: ItemInstance) -> int:
	var lowest := Trading.resale_floor(item)
	if TraderStock.could_be_wanted(item.data.id):
		lowest = maxi(lowest, ceili(Selling.best_resale(item) * TraderStock.wanted_multiplier() * (1.0 + Trading.resale_margin())))
	return lowest


# --- Listings -----------------------------------------------------------------------------------

## Which refresh unix time `when` falls in: a new batch of listings goes up at the start of each.
static func refresh_number(when := NOW) -> int:
	return floori(_at(when) / FleaTable.refresh_seconds())


## Seconds until the next batch of listings goes up.
static func seconds_to_refresh() -> float:
	return (refresh_number() + 1) * FleaTable.refresh_seconds() - time()


## Every listing that's up at `when` and that you haven't bought, newest batch first: the batches of the
## refreshes whose listings can still be up (listings_on()), less those that ended.
static func listings(when := NOW) -> Array[Dictionary]:
	var at := _at(when)
	var newest := refresh_number(at)
	var back := ceili(FleaTable.span(FleaTable.listings(), "minutes", Vector2(30, 240)).y * 60.0 / FleaTable.refresh_seconds())
	var result: Array[Dictionary] = []
	for number in range(newest, newest - back - 1, -1):
		for listing in listings_on(number):
			if float(listing.ends) > at and not GameState.flea.bought.has(listing.id):
				result.append(listing)
	_forget_before(newest - back)
	return result


## The listing with id `id` if it's up and not bought ({} if not).
static func find(id: String) -> Dictionary:
	for listing in listings():
		if listing.id == id:
			return listing
	return {}


## The listings that go up at refresh `number`, the same for everyone: per rarity, per_refresh of them
## (a fraction is a chance of one more), each an item of that rarity the market may list (FleaTable.pool(),
## picked by category_weight), with a generator seeded by the refresh number. Each is {"id"
## ("flea_51234_7": refresh, slot), "item" (the ItemInstance: guns and armor worn to condition, a gun
## sometimes with extra parts, stacks a share of a full one), "posted" and "ends" (unix times), "spread"
## (its price against the market price), "seller", "rating", "floor" (floor_price())}. Kept for the
## refreshes still up.
static func listings_on(number: int) -> Array[Dictionary]:
	if _batches.has(number):
		return _batches[number]
	var rules := FleaTable.listings()
	var rng := RandomNumberGenerator.new()
	rng.seed = ("flea:%d" % number).hash()
	var posted := number * FleaTable.refresh_seconds()
	var minutes := FleaTable.span(rules, "minutes", Vector2(30, 240))
	var spread := FleaTable.span(rules, "spread", Vector2.ONE)
	var rating := FleaTable.span(rules, "rating", Vector2(2.5, 5.0))
	var counts: Dictionary = rules.get("per_refresh", {})
	var result: Array[Dictionary] = []
	for rarity in ItemData.RARITY_IDS.size():
		var wanted := float(counts.get(ItemData.RARITY_IDS[rarity], 0.0))
		var amount := floori(wanted) + (1 if rng.randf() < wanted - floorf(wanted) else 0)
		var pool := FleaTable.pool(rarity)
		var weights := PackedFloat32Array()
		for id in pool:
			weights.append(FleaTable.category_weight(ItemDB.get_item(id)))
		for i in amount:
			var index := TraderStock._pick(rng, weights)
			if index < 0:
				break
			var piece := _roll_item(pool[index], rng)
			result.append({"id": "flea_%d_%d" % [number, result.size() + 1], "item": piece, "posted": posted,
				"ends": posted + snappedf(rng.randf_range(minutes.x, minutes.y), 1.0) * 60.0, "spread": snappedf(rng.randf_range(spread.x, spread.y), 0.001),
				"seller": _seller(rng), "rating": snappedf(rng.randf_range(rating.x, rating.y), 0.1), "floor": floor_price(piece)})
	_batches[number] = result
	return result


## Item `id` as a listing has it: a share of a full stack, guns and armor worn to the listings'
## condition, a gun sometimes with extra parts in its empty slots (parts the market may list).
static func _roll_item(id: String, rng: RandomNumberGenerator) -> ItemInstance:
	var rules := FleaTable.listings()
	var data := ItemDB.get_item(id)
	var share := FleaTable.span(rules, "stack", Vector2.ONE)
	var piece := ItemInstance.create(id, maxi(roundi(data.max_stack * rng.randf_range(share.x, share.y)), 1))
	if piece.has_durability():
		var condition := FleaTable.span(rules, "condition", Vector2.ONE)
		piece.durability = snappedf(piece.max_durability * rng.randf_range(condition.x, condition.y), 0.1)
	var parts: Dictionary = rules.get("parts", {})
	if piece.is_gun() and rng.randf() < float(parts.get("chance", 0.0)):
		var count := FleaTable.span(parts, "count", Vector2.ONE)
		var mods := _part_pool()
		for i in rng.randi_range(int(count.x), int(count.y)):
			for attempt in TraderStock.SHELF_TRIES:
				var part := ItemInstance.create(mods[rng.randi_range(0, mods.size() - 1)])
				var path := WeaponMods.slot_for(piece, part, true)
				if path != "":
					WeaponMods.install(piece, path, part)
					break
	FoundInRaid.set_found(piece, FoundInRaid.gives_fir(FoundInRaid.Source.FLEA_MARKET))
	return piece


## The gun parts the market may list (any rarity), sorted by id.
static func _part_pool() -> Array:
	if _parts.is_empty():
		for rarity in ItemData.RARITY_IDS.size():
			for id in FleaTable.pool(rarity):
				var data := ItemDB.get_item(id)
				if WeaponMods.is_mod(data) and not WeaponMods.is_gear_mod(data):
					_parts.append(id)
		_parts.sort()
	return _parts


## A made-up seller handle: "GrimBadger", sometimes with two digits ("SlyOtter07").
static func _seller(rng: RandomNumberGenerator) -> String:
	var names: Dictionary = FleaTable.listings().get("names", {})
	var first: Array = names.get("first", ["Anon"])
	var second: Array = names.get("second", [""])
	var handle := "%s%s" % [first[rng.randi_range(0, first.size() - 1)], second[rng.randi_range(0, second.size() - 1)]]
	return handle + ("%02d" % rng.randi_range(0, 99) if rng.randf() < 0.5 else "")


## Drops the batches and bought marks of refreshes before `number` (their listings are all down).
static func _forget_before(number: int) -> void:
	for key: int in _batches.keys():
		if key < number:
			_batches.erase(key)
	for id: String in GameState.flea.bought.keys():
		var parts := id.split("_")
		if parts.size() >= 3 and int(parts[1]) < number:
			GameState.flea.bought.erase(id)


## What `listing` costs now, in roubles: its item's market price × its spread, never below its floor.
static func price(listing: Dictionary) -> int:
	return maxi(roundi(market_price(listing.item) * float(listing.spread)), int(listing.floor))


## Seconds until `listing` comes down.
static func seconds_left(listing: Dictionary) -> float:
	return maxf(float(listing.ends) - time(), 0.0)


## What `listing`'s price is against its item's worth (Selling.item_value()): below 1 is good value.
static func value_ratio(listing: Dictionary) -> float:
	return float(price(listing)) / maxf(Selling.item_value(listing.item), 1.0)


## The cheapest a trader sells one item `id` for at your loyalty prices (Trading.price()), counting what
## your loyalty level doesn't reach yet: {"trader", "price" (roubles, a dollar at the exchange's buy
## rate), "each" (for a pack of rounds: per round), "level"}, {} if no trader sells it for money.
static func trader_price(id: String) -> Dictionary:
	var best := {}
	for trader_id in TraderTable.ids():
		for offer: Dictionary in Trading.offers(trader_id).get("buy", []):
			if str(offer.get("item", "")) != id:
				continue
			var cost := Trading.price(trader_id, offer) * (Trading.exchange_roubles(1, true) if offer.get("currency", "RUB") == "USD" else 1)
			var each := float(cost) / maxi(int(offer.get("count", 1)), 1)
			if best.is_empty() or each < float(best.each):
				best = {"trader": trader_id, "price": cost, "each": each, "level": Trading.offer_level(offer)}
	return best


## Why `listing` can't be bought now ("" if it can): the market is locked, it's gone (bought or down),
## the price changed since you saw `seen` (-1: don't check), not enough roubles, no room in the stash.
static func buy_block_reason(listing: Dictionary, seen := -1) -> String:
	var locked := lock_reason()
	if locked != "":
		return locked
	if listing.is_empty() or find(str(listing.id)).is_empty():
		return "Gone: sold or taken down"
	var cost := price(listing)
	if seen >= 0 and seen != cost:
		return "The price changed: %s now" % UiFormat.money(cost)
	if GameState.roubles < cost:
		return "Not enough roubles"
	if not GameState.stash.has_room_for(listing.item):
		return "No room in the stash"
	return ""


## Buys `listing` for its price (only if that's still `seen`, unless -1) into the stash, never found in
## raid, and pushes the item's price up (pressure "buy"). "" on success, else why not.
static func buy(listing: Dictionary, seen := -1) -> String:
	var reason := buy_block_reason(listing, seen)
	if reason != "":
		return reason
	var cost := price(listing)
	var piece: ItemInstance = (listing.item as ItemInstance).duplicate_deep()
	FoundInRaid.set_found(piece, FoundInRaid.gives_fir(FoundInRaid.Source.FLEA_MARKET))
	if not GameState.stash.add(piece):
		return "No room in the stash"
	GameState.roubles -= cost
	GameState.flea.bought[str(listing.id)] = true
	push(piece.data.id, float(FleaTable.pressure().get("buy", 0.0)))
	update()
	return ""
