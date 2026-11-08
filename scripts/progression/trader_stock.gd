class_name TraderStock
extends RefCounted
## Restocks, stock limits, Wanted items and the fence's worn gear (DESIGN.md §10). Every trader
## restocks on a real-time clock (TraderTable.restock_minutes(), 60 minutes unless a trader says) that
## runs while the game is closed. GameState.trader_stock keeps, per trader: when the next restock is due
## ("restock", unix time), how many restocks there have been ("number", 1 for the first stock), how many
## of each limited offer you bought since the last one ("bought", by offer id: any offer with an "id"
## and a "stock", so barters can carry stock as well as buy offers) and how many of each Wanted item you
## sold them ("wanted", by item id). Reading any of it first catches up on restocks that came due
## (refresh()): a restock refills every limited offer and brings new Wanted items. A trader seen for the
## first time (a new profile, a save from before version 10) starts with full stock and a restock one
## period from now.
##
## Wanted: each restock every trader wants 2-3 valuables or barter goods among what they buy
## (Selling.buys()) and no trader sells for money, picked with a random generator seeded by the
## trader's id and the restock number, so the list is never saved, only what you sold of it. Selling one
## pays ×1.5 for up to 3 of each (Selling.price()). The fence (Mole) sells 8-12 worn items rolled from
## the Scav kit tables the same way (used_offers()), one of each, nothing his loyalty level couldn't buy
## from a trader and nothing a trader could want (shelf_allows()), so nothing you can buy pays a Wanted
## bonus; only what you bought is saved, as bought offers. His loyalty level is your Scav karma's
## (ScavRuns): each level above 1 lets him stock rarer gear in better condition, a little cheaper (never
## as cheap as any trader pays for it), and pay more when you sell; karma below 0 makes it more worn and
## dearer. The numbers are in data/config/trading.json.

## How many times the fence re-rolls a slot of his shelf that came up with something he may not sell.
const SHELF_TRIES := 30

## Unix time to use instead of the clock (tests); -1: the real clock.
static var now_override := -1.0
## Wanted lists and the fence's gear by "trader:restock number" (they never change within a restock).
static var _wanted_cache := {}
static var _used_cache := {}
## Every trader's Wanted pool by trader id, and the ids of every item in any of them (they follow the
## data, so they never change).
static var _pool_cache := {}
static var _wanted_any := {}


static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


## Seconds between `trader_id`'s restocks.
static func period(trader_id: String) -> float:
	return maxf(TraderTable.restock_minutes(trader_id), 1.0) * 60.0


## `trader_id`'s entry in GameState.trader_stock, brought up to date (refresh()).
static func state(trader_id: String) -> Dictionary:
	refresh(trader_id)
	return GameState.trader_stock[trader_id]


## Catches up on `trader_id`'s restocks: each period that has passed since one was due is a restock
## (several if the game was closed long enough), which clears what you bought and sold since. A trader
## seen for the first time gets full stock and a restock a period from now; a clock that went back by
## more than a period starts the wait again. True if they restocked.
static func refresh(trader_id: String) -> bool:
	var length := period(trader_id)
	var time := now()
	var entry: Dictionary = GameState.trader_stock.get(trader_id, {})
	if entry.is_empty():
		GameState.trader_stock[trader_id] = {"restock": snappedf(time + length, 1.0), "number": 1, "bought": {}, "wanted": {}}
		return false
	if float(entry.restock) - time > length:
		entry.restock = snappedf(time + length, 1.0)
	if time < float(entry.restock):
		return false
	var passed := floori((time - float(entry.restock)) / length) + 1
	entry.restock = float(entry.restock) + passed * length
	entry.number = int(entry.number) + passed
	entry.bought = {}
	entry.wanted = {}
	return true


## refresh() for every trader. Returns the ones that restocked.
static func refresh_all() -> Array[String]:
	var restocked: Array[String] = []
	for trader_id in TraderTable.ids():
		if refresh(trader_id):
			restocked.append(trader_id)
	return restocked


## How many restocks `trader_id` has had (1: the first stock).
static func restock_number(trader_id: String) -> int:
	return int(state(trader_id).number)


## Seconds until `trader_id` restocks.
static func seconds_left(trader_id: String) -> float:
	return maxf(float(state(trader_id).restock) - now(), 0.0)


## "42:10" until `trader_id` restocks ("1:02:03" for an hour or more).
static func countdown_text(trader_id: String) -> String:
	return clock(seconds_left(trader_id))


## "42:10" or "1:02:03" for `seconds`.
static func clock(seconds: float) -> String:
	var total := maxi(ceili(seconds), 0)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, total / 60 % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


# --- Stock --------------------------------------------------------------------------------------

## How many of `offer` sell each restock (-1: no limit). Only offers with an "id" can be limited.
static func stock_of(offer: Dictionary) -> int:
	return int(offer.stock) if offer.has("stock") and str(offer.get("id", "")) != "" else -1


## How many of `offer` `trader_id` has left this restock (-1: no limit).
static func left(trader_id: String, offer: Dictionary) -> int:
	var stock := stock_of(offer)
	if stock < 0:
		return -1
	return maxi(stock - int(state(trader_id).bought.get(str(offer.id), 0)), 0)


## Takes `amount` of `offer` off `trader_id`'s stock (nothing for an offer with no limit).
static func take(trader_id: String, offer: Dictionary, amount := 1) -> void:
	if stock_of(offer) < 0 or not TraderTable.has(trader_id):
		return
	var bought: Dictionary = state(trader_id).bought
	bought[str(offer.id)] = int(bought.get(str(offer.id), 0)) + amount


# --- Wanted -------------------------------------------------------------------------------------

## The Wanted rules from data/config/trading.json: {"count", "multiplier", "per_item", "categories",
## "max_rarity"}.
static func wanted_rules() -> Dictionary:
	return Trading.config().get("wanted", {})


## How much more a Wanted item pays: 1.5 is +50%.
static func wanted_multiplier() -> float:
	return float(wanted_rules().get("multiplier", 1.0))


## The item ids `trader_id` wants this restock.
static func wanted(trader_id: String) -> Array[String]:
	return wanted_on(trader_id, restock_number(trader_id))


## The item ids `trader_id` wants at restock `number`: 2-3 of wanted_pool(), picked with a generator
## seeded by the trader and the number.
static func wanted_on(trader_id: String, number: int) -> Array[String]:
	var key := "%s:%d" % [trader_id, number]
	if not _wanted_cache.has(key):
		var pool := wanted_pool(trader_id)
		var rng := _rng(trader_id, number, "wanted")
		var count: Array = wanted_rules().get("count", [2, 3])
		var amount := rng.randi_range(int(count[0]), int(count[1]))
		var picked: Array[String] = []
		while picked.size() < amount and not pool.is_empty():
			picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)).id)
		_wanted_cache[key] = picked
	return _wanted_cache[key]


## What `trader_id` can want: valuables and barter goods (the rules' categories) that turn up as loot,
## no rarer than the rules' max_rarity, that the trader buys and no trader sells for money
## (Trading.sold_at_level(): else buying one and selling it back Wanted could pay more than it cost); by
## id. A copy: wanted_on() takes items out of it.
static func wanted_pool(trader_id: String) -> Array[ItemData]:
	if not _pool_cache.has(trader_id):
		var rules := wanted_rules()
		var top := ItemData.RARITY_IDS.find(str(rules.get("max_rarity", "epic")))
		var categories: Array = rules.get("categories", [])
		var pool: Array[ItemData] = []
		for data in ItemDB.all_items():
			if data.category_name() in categories and data.loot_weight > 0.0 and data.rarity <= top and Selling.buys(trader_id, data) \
					and Trading.sold_at_level(data.id) == 0:
				pool.append(data)
		pool.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.id < b.id)
		_pool_cache[trader_id] = pool
	return _pool_cache[trader_id].duplicate()


## True if some trader could want item `id` at some restock (it's in a wanted_pool()).
static func could_be_wanted(id: String) -> bool:
	if _wanted_any.is_empty():
		for trader_id in TraderTable.ids():
			for data in wanted_pool(trader_id):
				_wanted_any[data.id] = true
	return _wanted_any.has(id)


## How many more of item `id` `trader_id` pays the Wanted price for this restock (0 if they don't
## want it).
static func wanted_left(trader_id: String, id: String) -> int:
	if not id in wanted(trader_id):
		return 0
	return maxi(int(wanted_rules().get("per_item", 0)) - int(state(trader_id).wanted.get(id, 0)), 0)


## Counts `amount` of item `id` sold to `trader_id` toward their Wanted cap.
static func record_wanted(trader_id: String, id: String, amount: int) -> void:
	var sold: Dictionary = state(trader_id).wanted
	sold[id] = int(sold.get(id, 0)) + amount


## The traders who trade with you and still pay the Wanted price for item `id`, in roster order.
static func wanted_by(id: String) -> Array[String]:
	var result: Array[String] = []
	for trader_id in TraderTable.ids():
		if TraderTable.is_unlocked(trader_id) and wanted_left(trader_id, id) > 0:
			result.append(trader_id)
	return result


## "Wanted by Doc Vera: +50% until restock" for item `id` ("" if nobody wants it).
static func wanted_text(id: String) -> String:
	var traders := wanted_by(id)
	if traders.is_empty():
		return ""
	var names: Array[String] = []
	for trader_id in traders:
		names.append(TraderTable.display_name(trader_id))
	return "Wanted by %s: +%d%% until restock" % [" and ".join(names), roundi((wanted_multiplier() - 1.0) * 100.0)]


# --- The fence's worn gear ----------------------------------------------------------------------

## The used_stock rules from data/config/trading.json: {"trader", "count", "durability", "price",
## "tables"}.
static func used_rules() -> Dictionary:
	return Trading.config().get("used_stock", {})


## The trader who sells worn gear (Mole).
static func used_trader() -> String:
	return str(used_rules().get("trader", ""))


## What the fence sells this restock (nothing for anyone else).
static func used_offers(trader_id: String) -> Array[Dictionary]:
	if trader_id != used_trader() or trader_id == "":
		return []
	return used_offers_on(trader_id, restock_number(trader_id))


## The fence's loyalty level with you (1 to his highest), which his shelf goes by.
static func used_level(trader_id: String) -> int:
	return clampi(int(GameState.trader_loyalty.get(trader_id, {}).get("level", 1)), 1, TraderTable.max_loyalty(trader_id))


## Points of Scav karma below 0 that worsen the fence's shelf (0 at karma 0 and up; only for a trader
## whose standing is your karma).
static func _karma_debt(trader_id: String) -> float:
	return maxf(-GameState.scav_karma, 0.0) if TraderTable.follows_karma(trader_id) else 0.0


## The share of a worn item's value the fence charges: used_stock "price", plus "level_price" (below 0:
## cheaper) for each loyalty level above 1; for `data`, never less than the most any trader pays for it
## at their top level (Selling.best_rate()) plus "resale_margin", so nothing he sells can be sold on at a
## profit; plus "karma_price" for each point of karma below 0.
static func used_price_share(trader_id: String, data: ItemData = null) -> float:
	var rules := used_rules()
	var share := float(rules.get("price", 1.0)) + float(rules.get("level_price", 0.0)) * (used_level(trader_id) - 1)
	if data:
		share = maxf(share, Selling.best_rate(data) + maxf(float(rules.get("resale_margin", 0.0)), 0.0))
	return share + maxf(float(rules.get("karma_price", 0.0)), 0.0) * _karma_debt(trader_id)


## How worn the fence's guns and armor come: used_stock "durability" [from, to] of their maximum, plus
## "level_durability" for each loyalty level above 1 and "karma_durability" for each point of karma
## below 0, kept within 0.05-1.
static func used_durability(trader_id: String) -> Vector2:
	var rules := used_rules()
	var durability: Array = rules.get("durability", [0.4, 0.8])
	var shift := float(rules.get("level_durability", 0.0)) * (used_level(trader_id) - 1) + float(rules.get("karma_durability", 0.0)) * _karma_debt(trader_id)
	return Vector2(clampf(float(durability[0]) + shift, 0.05, 1.0), clampf(float(durability[1]) + shift, 0.05, 1.0))


## The fence's worn gear at restock `number`: 8-12 items rolled from the Scav kit tables (each table
## picked by its weight; a roll he may not sell, shelf_allows(), is rolled again) with a generator
## seeded by the trader, the number and his loyalty level, guns and armor at 40-80% of their durability
## (used_durability()), guns unloaded. Buy offers {"id" ("mole_used_12_3": restock 12, slot 3; at LL2
## and up "mole_used_12_3_ll2"), "item", "count", "price" (80% of its worn value at LL1, a little less
## each level up but always more than any trader pays for it, more below karma 0: used_price_share();
## Selling.item_value(), rounded up to 100), "currency", "stock": 1, "instance" (the piece itself,
## ItemInstance.to_dict()), "used": true}.
static func used_offers_on(trader_id: String, number: int) -> Array[Dictionary]:
	var level := used_level(trader_id)
	var key := "%s:%d:%d:%.2f" % [trader_id, number, level, _karma_debt(trader_id)]
	if _used_cache.has(key):
		return _used_cache[key]
	var rules := used_rules()
	var rng := _rng(trader_id, number, "used" if level <= 1 else "used_ll%d" % level)
	var tables: Dictionary = rules.get("tables", {})
	var paths: Array = tables.keys()
	var weights := PackedFloat32Array()
	for path: String in paths:
		weights.append(float(tables[path]))
	var count: Array = rules.get("count", [8, 12])
	var durability := used_durability(trader_id)
	var suffix := "" if level <= 1 else "_ll%d" % level
	var currency := str(TraderTable.find(trader_id).get("currency", "RUB"))
	var result: Array[Dictionary] = []
	for i in rng.randi_range(int(count[0]), int(count[1])):
		var data: ItemData = null
		for attempt in SHELF_TRIES:
			var index := _pick(rng, weights)
			var table := load(paths[index]) as LootTable if index >= 0 else null
			var rolled: ItemData = table.roll_item(rng) if table else null
			if rolled and shelf_allows(trader_id, rolled, level):
				data = rolled
				break
		if data == null:
			continue
		var amount := rng.randi_range(maxi(data.max_stack / 5, 1), maxi(data.max_stack / 2, 1)) if data.max_stack > 1 else 1
		var item := ItemInstance.create(data.id, amount)
		if item.has_durability():
			item.durability = snappedf(item.max_durability * rng.randf_range(durability.x, durability.y), 0.1)
		var price := maxi(ceili(Selling.item_value(item) * used_price_share(trader_id, data) / 100.0) * 100, 100)
		result.append({"id": "%s_used_%d_%d%s" % [trader_id, number, i + 1, suffix], "item": data.id, "count": item.count, "price": price,
			"currency": currency, "stock": 1, "instance": item.to_dict(), "used": true})
	_used_cache[key] = result
	return result


## True if the fence (`trader_id`) may put `data` on his shelf: nothing rarer than his loyalty level
## (`level`, else the one you have with him: used_level()) could buy from a trader
## (Trading.min_loyalty()), nothing traders only sell from a higher level than that (at LL1 no LL2-4
## rounds or meds) and nothing a trader could want (could_be_wanted(): no valuables), so what he sells
## cheap never pays a Wanted bonus.
static func shelf_allows(trader_id: String, data: ItemData, level := -1) -> bool:
	var top := level if level >= 1 else used_level(trader_id)
	var lowest := Trading.min_loyalty(data)
	return lowest >= 1 and lowest <= top and Trading.sold_at_level(data.id) <= top and not could_be_wanted(data.id)


## An index into `weights` picked in proportion to them (-1 if they're all 0).
static func _pick(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var roll_at := rng.randf() * total
	for index in weights.size():
		roll_at -= weights[index]
		if roll_at < 0.0:
			return index
	return weights.size() - 1 if total > 0.0 else -1


## A generator for `trader_id`'s restock `number`, one per `purpose`: the same numbers every time.
static func _rng(trader_id: String, number: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:%d:%s" % [trader_id, number, purpose]).hash()
	return rng
