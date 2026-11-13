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
## A listing of yours is up, sold (the money waits to be collected) or expired (the item does).
const UP := "up"
const SOLD := "sold"
const EXPIRED := "expired"
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


## Brings the market up to date: moves its clock on to now and settles your listings whose time came
## (also while the game was closed): one past its sale time has sold, one past its end without a sale
## is back. A settled listing stays settled. Returns the listings that just settled.
static func update() -> Array[Dictionary]:
	var now := time()
	GameState.flea.clock = now
	var settled: Array[Dictionary] = []
	for listing: Dictionary in GameState.flea.listings:
		if listing.state != UP:
			continue
		if float(listing.sells) > 0.0 and now >= float(listing.sells):
			listing.state = SOLD
		elif now >= float(listing.ends):
			listing.state = EXPIRED
		else:
			continue
		settled.append(listing)
	return settled


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



# --- Your listings ------------------------------------------------------------------------------

## Your listings, brought up to date (update()), oldest first: each {"id" ("own_7"), "item"
## (ItemInstance.to_dict()), "price" (the asking price, roubles), "fee" (paid when listed), "market" (its
## market price then), "listed", "ends" and "sells" (unix times; "sells" 0: it won't sell), "state" (UP,
## SOLD or EXPIRED)}.
static func own_listings() -> Array:
	update()
	return GameState.flea.listings


## How many listings you may have up at your level (FleaTable.slots()).
static func slots() -> int:
	return FleaTable.slots(GameState.level)


## How many of your listings are up (sold and expired ones waiting to be collected don't take a slot).
static func slots_used() -> int:
	return own_listings().filter(func(listing: Dictionary) -> bool: return listing.state == UP).size()


## The asking price against `item`'s market price now (1: at market).
static func fairness(item: ItemInstance, asking: int) -> float:
	return float(asking) / maxf(market_price(item), 1.0)


## The share of the asking price listing `item` at `asking` costs: the fee's base, plus "over" for each
## 1.0 the price is above market (fairness()), at most "max".
static func fee_share(item: ItemInstance, asking: int) -> float:
	var rules := FleaTable.fee()
	return minf(float(rules.get("base", 0.05)) + float(rules.get("over", 0.0)) * maxf(fairness(item, asking) - 1.0, 0.0), float(rules.get("max", 0.5)))


## The fee for listing `item` at `asking`, in roubles (rounded up; paid up front, never refunded).
static func listing_fee(item: ItemInstance, asking: int) -> int:
	return ceili(asking * fee_share(item, asking))


## How many minutes a listing at `ratio` times the market price takes to sell, before its random factor:
## the sale curve's straight lines between points, as fast as the first point under it, -1 (never) over
## the last.
static func sale_minutes(ratio: float) -> float:
	var curve: Array = FleaTable.sale().get("minutes", [])
	if curve.is_empty():
		return -1.0
	if ratio <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		if ratio <= float(curve[i][0]):
			var from: Array = curve[i - 1]
			var to: Array = curve[i]
			return lerpf(float(from[1]), float(to[1]), (ratio - float(from[0])) / (float(to[0]) - float(from[0])))
	return -1.0


## The most the asking price may be above market and still sell (the sale curve's last point: 1.3).
static func max_fairness() -> float:
	var curve: Array = FleaTable.sale().get("minutes", [[1.0, 1.0]])
	return float(curve[-1][0])


## "Sells in 5-11 min", "Sells in 1 h 30 min - 3 h 30 min" or "Won't sell: over 1.3× the market price"
## for listing `item` at `asking` now.
static func estimate_text(item: ItemInstance, asking: int) -> String:
	var minutes := sale_minutes(fairness(item, asking))
	if minutes < 0.0:
		return "Won't sell: over %s× the market price" % String.num(max_fairness(), 2)
	var spread := FleaTable.span(FleaTable.sale(), "spread", Vector2.ONE)
	return "Sells in %s - %s" % [duration_text(minutes * spread.x * 60.0), duration_text(minutes * spread.y * 60.0)]


## "45 s", "8 min", "2 h 30 min", "1 d 4 h".
static func duration_text(seconds: float) -> String:
	var total := maxi(ceili(seconds), 0)
	if total < 60:
		return "%d s" % total
	var minutes := ceili(total / 60.0)
	if minutes < 60:
		return "%d min" % minutes
	if minutes < 24 * 60:
		return "%d h" % (minutes / 60) + (" %d min" % (minutes % 60) if minutes % 60 > 0 else "")
	return "%d d" % (minutes / 1440) + (" %d h" % (minutes / 60 % 24) if minutes / 60 % 24 > 0 else "")


## Why `item` can't be listed at `asking` now ("" if it can): the market is locked, every slot is taken,
## it isn't in your stash, it's banned, it (or anything on or in it) isn't found in raid, it's a container
## with something inside, it's worth nothing, no price, or not the roubles for the fee.
static func list_block_reason(item: ItemInstance, asking: int) -> String:
	var locked := lock_reason()
	if locked != "":
		return locked
	if slots_used() >= slots():
		return "All %d listing slots are taken" % slots()
	if item == null or GameState.stash.find_holder(item) == null:
		return "Only items in your stash can be listed"
	var banned := FleaTable.ban_reason(item.data)
	if banned != "":
		return banned
	if not item.fir:
		return "Only found-in-raid items can be listed"
	if not item.all_items().all(func(each: ItemInstance) -> bool: return each.fir):
		return "Something on or in it isn't found in raid"
	if not item.is_empty_container():
		return "Empty it first"
	if Selling.item_value(item) <= 0:
		return "Worth nothing"
	if asking < 1:
		return "Set a price"
	if GameState.roubles < listing_fee(item, asking):
		return "Not enough roubles for the %s fee" % UiFormat.money(listing_fee(item, asking))
	return ""


## Lists `item` from the stash at `asking`: pays the fee, takes it out of the stash and works out when
## it sells from how fair the price is (sale_minutes() × a factor seeded by the listing; never over the
## last point), and pushes the item's price down (pressure "sell"). "" on success, else why not.
static func put_up(item: ItemInstance, asking: int) -> String:
	var reason := list_block_reason(item, asking)
	if reason != "":
		return reason
	var now := time()
	var number := int(GameState.flea.get("next_id", 1))
	var id := "own_%d" % number
	var minutes := sale_minutes(fairness(item, asking))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:%d" % [id, int(now)]).hash()
	var spread := FleaTable.span(FleaTable.sale(), "spread", Vector2.ONE)
	var sells := snappedf(now + minutes * 60.0 * rng.randf_range(spread.x, spread.y), 1.0) if minutes >= 0.0 else 0.0
	var fee := listing_fee(item, asking)
	var listing := {"id": id, "item": item.to_dict(), "price": asking, "fee": fee, "market": market_price(item), "listed": now,
		"ends": now + float(FleaTable.sale().get("hours", 12.0)) * 3600.0, "sells": sells, "state": UP}
	var holder := GameState.stash.find_holder(item)
	holder.remove(item)
	if holder != GameState.stash:
		GameState.stash.changed.emit()
	GameState.roubles -= fee
	GameState.flea.next_id = number + 1
	GameState.flea.listings.append(listing)
	push(item.data.id, -float(FleaTable.pressure().get("sell", 0.0)))
	return ""


## Seconds until `listing` comes down (0 once it's sold or back).
static func time_left(listing: Dictionary) -> float:
	return maxf(float(listing.ends) - time(), 0.0) if listing.state == UP else 0.0


## Takes the money for a sold listing (into roubles) or the item of an expired one (into the stash) and
## drops it. "" on success, else why not ("No room in the stash", "Still up").
static func collect(listing: Dictionary) -> String:
	update()
	if not listing in GameState.flea.listings:
		return "Gone"
	match str(listing.state):
		SOLD:
			GameState.roubles += int(listing.price)
		EXPIRED:
			var piece := ItemInstance.from_dict(listing.item)
			if piece and not GameState.stash.add(piece):
				return "No room in the stash"
		_:
			return "Still up"
	GameState.flea.listings.erase(listing)
	return ""


## Takes `listing` down before it sells: the item goes back to the stash (the fee isn't refunded). "" on
## success, else why not.
static func take_down(listing: Dictionary) -> String:
	update()
	if not listing in GameState.flea.listings or listing.state != UP:
		return "It isn't up any more"
	var piece := ItemInstance.from_dict(listing.item)
	if piece and not GameState.stash.add(piece):
		return "No room in the stash"
	GameState.flea.listings.erase(listing)
	return ""


## collect() for every sold and expired listing. {"roubles": collected, "items": back in the stash,
## "left": items that had no room}.
static func collect_all() -> Dictionary:
	var result := {"roubles": 0, "items": 0, "left": 0}
	for listing: Dictionary in own_listings().duplicate():
		if listing.state == UP:
			continue
		var was_sold: bool = listing.state == SOLD
		if collect(listing) == "":
			if was_sold:
				result.roubles += int(listing.price)
			else:
				result.items += 1
		else:
			result.left += 1
	return result


## What waits to be collected: {"sold": listings sold, "roubles": their money, "expired": items back}.
static func waiting() -> Dictionary:
	var result := {"sold": 0, "roubles": 0, "expired": 0}
	for listing: Dictionary in own_listings():
		if listing.state == SOLD:
			result.sold += 1
			result.roubles += int(listing.price)
		elif listing.state == EXPIRED:
			result.expired += 1
	return result


## The main menu's line: "Flea market: 2 sold (₽ 84,000) and 1 item back: collect on the FLEA MARKET"
## ("" with nothing waiting).
static func notice_text() -> String:
	var waits := waiting()
	var parts: Array[String] = []
	if int(waits.sold) > 0:
		parts.append("%d sold (%s)" % [waits.sold, UiFormat.money(int(waits.roubles))])
	if int(waits.expired) > 0:
		parts.append("%d item%s back unsold" % [waits.expired, "" if int(waits.expired) == 1 else "s"])
	return "" if parts.is_empty() else "Flea market: %s: collect on the FLEA MARKET" % " and ".join(parts)


# --- Saving -------------------------------------------------------------------------------------

## GameState.flea as plain data for the save.
static func to_save() -> Dictionary:
	var pressures := {}
	for id: String in GameState.flea.pressure:
		if absf(pressure(id)) >= 0.001:
			pressures[id] = GameState.flea.pressure[id].duplicate()
	return {"pressure": pressures, "bought": GameState.flea.bought.keys(), "listings": GameState.flea.listings.duplicate(true),
		"next_id": int(GameState.flea.next_id), "clock": float(GameState.flea.clock)}


## GameState.flea from to_save() data (blank() for a save from before version 16): pressure on items that
## still exist and your listings (one whose item no longer exists is dropped); what sold or ended while
## the game was closed settles the next time they're read (own_listings()).
static func from_save(saved: Variant) -> Dictionary:
	var result := blank()
	if not saved is Dictionary:
		return result
	var pressures: Variant = saved.get("pressure", {})
	if pressures is Dictionary:
		for id: Variant in pressures:
			var entry: Variant = pressures[id]
			if ItemDB.has_item(str(id)) and entry is Dictionary:
				result.pressure[str(id)] = {"value": float(entry.get("value", 0.0)), "bucket": int(entry.get("bucket", 0))}
	for id: Variant in saved.get("bought", []):
		result.bought[str(id)] = true
	for entry: Variant in saved.get("listings", []):
		var piece := ItemInstance.from_dict(entry.item) if entry is Dictionary and entry.get("item") is Dictionary and ItemDB.has_item(str(entry.item.get("id", ""))) else null
		if piece:
			result.listings.append({"id": str(entry.get("id", "")), "item": piece.to_dict(), "price": int(entry.get("price", 0)), "fee": int(entry.get("fee", 0)),
				"market": int(entry.get("market", 0)), "listed": float(entry.get("listed", 0.0)), "ends": float(entry.get("ends", 0.0)),
				"sells": float(entry.get("sells", 0.0)), "state": str(entry.get("state", UP)) if str(entry.get("state", UP)) in [UP, SOLD, EXPIRED] else UP})
	result.next_id = maxi(int(saved.get("next_id", 1)), result.listings.size() + 1)
	result.clock = float(saved.get("clock", 0.0))
	return result
