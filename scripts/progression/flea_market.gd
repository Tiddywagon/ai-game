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
