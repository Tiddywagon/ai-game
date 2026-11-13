extends "res://tests/test_base.gd"
## The flea market (DESIGN.md §10, Flea market): the rules' loader and its checks (a broken copy for each
## rule), the unlock level, market prices (the drift's bounds, the same numbers on the same clock, how
## fast it moves, your pressure and its decay, the trend) and the floor against trader prices; the
## market's listings (seeded per refresh, the same again, coming and going while the game is closed,
## rarer items less often, no banned ones, worn guns and armor, extra parts, never under the floor) and
## buying them (the price charged, never found in raid, pressure, gone once bought, every refusal); your
## own listings (found in raid from the stash only, the fee, slots by level), how fast they sell by how
## fair the price is (also while the game is closed), expiry and collecting, banned items and the save.

const NOW := 1_000_000.0
const HOUR := 3600.0

var table: GDScript
var flea: GDScript
var trading: GDScript
var selling: GDScript
var stock: GDScript


func run() -> void:
	table = load("res://scripts/data/flea_table.gd")
	flea = load("res://scripts/progression/flea_market.gd")
	trading = load("res://scripts/progression/trading.gd")
	selling = load("res://scripts/progression/selling.gd")
	stock = load("res://scripts/progression/trader_stock.gd")
	_loader()
	_unlock()
	_drift()
	_pressure()
	_floor()
	_listings()
	_buying()
	_own_listings()
	_sale_timing()
	_banned()
	_saving()
	stock.now_override = -1.0


## A new BEAR profile at `when`, at player level `level`, with plenty of money.
func _profile(level := 15, when := NOW) -> void:
	stock.now_override = when
	fresh_profile()
	gs.level = level
	gs.roubles = 50_000_000


func _loader() -> void:
	section("Rules and their checks")
	var problems: Array = table.problems()
	check(problems.is_empty(), "data/config/flea.json has no problems (%s)" % ", ".join(problems))
	var rules: Dictionary = table.config()
	var broken := {
		"unlock_level": [0, "unlock level 0"],
		"refresh_minutes": [0, "refresh_minutes 0"],
		"listings.per_refresh": [{"common": 5, "uncommon": 3, "rare": 1, "ultra_rare": 1, "epic": 1, "legendary": 2}, "Legendary listed more often than Epic"],
		"listings.spread": [[1.2, 1.0], "a spread from above its to"],
		"listings.condition": [[0.5, 1.2], "a condition above 1"],
		"listings.category_weight": [{"gadgets": 2}, "a category weight for a category that doesn't exist"],
		"listings.names": [{"first": []}, "no seller names"],
		"drift": [{"bucket_minutes": 60, "window": 24, "min": 1.2, "max": 1.4, "center": 1.0, "speed": 0.2, "trend_hours": 6, "trend_threshold": 0.02}, "a drift min above its center"],
		"pressure": [{"buy": 0.04, "sell": 0.04, "max": 0.9, "half_life_hours": 6}, "a pressure max at or above the drift's min"],
		"fee": [{"base": 0.0, "over": 0.5, "max": 0.6}, "no base fee"],
		"slots": [{"base": 0, "every": 5}, "no listing slots"],
		"sale.minutes": [[[1.0, 8], [0.9, 45]], "a sale curve whose ratios fall"],
		"sale.hours": [2, "listings that come down before the slowest sale"],
		"banned": [{"ids": ["no_such_item"], "categories": [], "tags": [], "min_penetration": 55}, "a banned id that isn't an item"],
	}
	var copy_path := "user://flea_broken.json"
	for key: String in broken:
		var copy: Dictionary = rules.duplicate(true)
		var parts := key.split(".")
		var holder: Dictionary = copy
		for i in parts.size() - 1:
			holder = holder[parts[i]]
		holder[parts[-1]] = broken[key][0]
		var file := FileAccess.open(copy_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(copy))
		file.close()
		table.source = copy_path
		table.forget()
		check(not table.problems().is_empty(), "the check catches %s" % broken[key][1])
	table.source = table.CONFIG_PATH
	table.forget()
	check(table.problems().is_empty() and table.unlock_level() == 15, "the real rules load again")


func _unlock() -> void:
	section("Unlock and slots")
	_profile(14)
	check(not flea.is_unlocked() and flea.lock_text() == "Level 15" and flea.lock_reason() != "", "level 14: locked, the buttons say \"Level 15\"")
	gs.level = 15
	check(flea.is_unlocked() and flea.lock_reason() == "", "level 15: open")
	check(table.slots(14) == 0 and table.slots(15) == 3 and table.slots(19) == 3 and table.slots(20) == 4 and table.slots(25) == 5 and table.slots(50) == 10,
		"listing slots: none before 15, 3 at 15, one more every 5 levels (10 at 50)")


func _drift() -> void:
	section("Market price drift")
	_profile()
	var walk: Dictionary = table.drift()
	var low := float(walk.min)
	var high := float(walk.max)
	var ids := ["ak_74n", "ledx", "bandage", "ammo_556_fmj", "roler"]
	var lowest := 10.0
	var highest := 0.0
	var biggest_step := 0.0
	var moves := 0
	for id: String in ids:
		var last: float = flea.drift(id, NOW)
		for hour in range(1, 24 * 30):
			var now: float = flea.drift(id, NOW + hour * HOUR)
			lowest = minf(lowest, now)
			highest = maxf(highest, now)
			biggest_step = maxf(biggest_step, absf(now - last))
			if absf(now - last) > 0.0001:
				moves += 1
			last = now
	check(lowest >= low - 0.0001 and highest <= high + 0.0001, "30 days of hourly drift for 5 items stays within ×%.2f-×%.2f (%.3f-%.3f)" % [low, high, lowest, highest])
	check(highest - lowest > (high - low) * 0.5, "and wanders over most of that range (%.3f-%.3f)" % [lowest, highest])
	var step_cap := 2.0 * float(walk.speed) * maxf(high - 1.0, 1.0 - low)
	check(biggest_step <= step_cap + 0.0001 and moves > 5 * 24 * 30 * 0.9, "it moves every hour, by at most %.2f (largest %.3f)" % [step_cap, biggest_step])
	var bucket: float = flea.bucket_seconds()
	var start := floorf(NOW / bucket) * bucket
	check(flea.drift("ak_74n", start) == flea.drift("ak_74n", start + bucket - 1.0) and flea.drift("ak_74n", start) != flea.drift("ak_74n", start + bucket),
		"a price holds within its hour and moves at the next")
	var before: float = flea.drift("ak_74n", NOW + 77 * HOUR)
	flea._drift_cache.clear()
	fresh_profile(1)
	check(flea.drift("ak_74n", NOW + 77 * HOUR) == before, "the same number on the same clock for anyone (a USEC profile, the cache cleared)")
	check(flea.drift("ak_74n", NOW) != flea.drift("ledx", NOW), "each item drifts on its own")
	_profile()
	var gun: RefCounted = item("ak_74n")
	var worth: int = selling.item_value(gun)
	check(flea.market_price(gun) == roundi(worth * flea.multiplier("ak_74n")) and flea.multiplier("ak_74n") == flea.drift("ak_74n"),
		"market price = worth (%d) × the drift with no pressure: %d" % [worth, flea.market_price(gun)])
	gun.durability = 40.0
	check(flea.market_price(gun) < flea.unit_price("ak_74n"), "a worn gun's market price is lower (%d against %d new)" % [flea.market_price(gun), flea.unit_price("ak_74n")])
	var rising := ""
	var falling := ""
	for hour in range(0, 24 * 10):
		var when := NOW + hour * HOUR
		var change: float = flea.drift("roler", when) / flea.drift("roler", when - 6 * HOUR) - 1.0
		if rising == "" and change > 0.05:
			rising = str(flea.trend("roler", when))
		if falling == "" and change < -0.05:
			falling = str(flea.trend("roler", when))
	check(rising == "1" and falling == "-1", "the trend is up after a rise over 6 hours and down after a fall (%s, %s)" % [rising, falling])


func _pressure() -> void:
	section("Your pressure on prices")
	_profile()
	var base: float = flea.drift("ledx")
	flea.push("ledx", 0.04)
	check(is_equal_approx(flea.multiplier("ledx"), base + 0.04), "buying pushes the price up by 0.04 (×%.3f → ×%.3f)" % [base, flea.multiplier("ledx")])
	for i in 20:
		flea.push("ledx", 0.04)
	check(is_equal_approx(flea.pressure("ledx"), 0.25), "never more than 0.25 (%.3f)" % flea.pressure("ledx"))
	flea.push("bandage", -0.04)
	check(flea.pressure("bandage") < 0.0 and flea.multiplier("bandage") < flea.drift("bandage"), "putting one up pushes it down")
	stock.now_override = NOW + 6 * HOUR
	check(absf(flea.pressure("ledx") - 0.125) < 0.001, "it halves in 6 hours (%.4f)" % flea.pressure("ledx"))
	stock.now_override = NOW + 48 * HOUR
	check(flea.pressure("ledx") < 0.001, "and is all but gone after two days (%.5f)" % flea.pressure("ledx"))
	flea.update()
	stock.now_override = NOW
	check(flea.time() == NOW + 48 * HOUR and flea.pressure("ledx") < 0.001,
		"the market's clock doesn't run backwards with the computer's (still %.0f hours on)" % ((flea.time() - NOW) / HOUR))


func _floor() -> void:
	section("The floor against trader prices")
	_profile()
	var gun: RefCounted = item("ak_74n")
	check(flea.floor_price(gun) == trading.resale_floor(gun), "a gun's floor is its resale floor: the best trader's top-loyalty price plus 3%% (%d)" % flea.floor_price(gun))
	var wanted := ""
	for data in db.all_items():
		if stock.could_be_wanted(data.id):
			wanted = data.id
			break
	var piece: RefCounted = item(wanted)
	check(wanted != "" and flea.floor_price(piece) >= ceili(selling.best_resale(piece) * 1.5 * 1.03),
		"anything a trader could want has the Wanted bonus in its floor (%s: %d)" % [wanted, flea.floor_price(piece)])


func _listings() -> void:
	section("Listings")
	_profile()
	var number: int = flea.refresh_number()
	var first: Array = flea.listings_on(number)
	var names := first.map(func(listing: Dictionary) -> String: return "%s %s %d %s" % [listing.id, listing.item.data.id, listing.item.count, listing.seller])
	flea._batches.clear()
	var again: Array = flea.listings_on(number)
	check(not first.is_empty() and names == again.map(func(listing: Dictionary) -> String: return "%s %s %d %s" % [listing.id, listing.item.data.id, listing.item.count, listing.seller]),
		"a refresh's %d listings are the same when rolled again" % first.size())
	check(first.map(func(listing: Dictionary) -> int: return flea.price(listing)) == again.map(func(listing: Dictionary) -> int: return flea.price(listing)),
		"at the same prices")
	var next: Array = flea.listings_on(number + 1)
	check(next.map(func(listing: Dictionary) -> String: return listing.item.data.id) != first.map(func(listing: Dictionary) -> String: return listing.item.data.id),
		"the next refresh brings other listings")
	var up: Array = flea.listings()
	var period: float = table.refresh_seconds()
	check(up.size() > first.size() and up.all(func(listing: Dictionary) -> bool: return float(listing.posted) <= NOW and float(listing.ends) > NOW),
		"%d listings are up: this refresh's and those of earlier ones that haven't ended" % up.size())
	stock.now_override = NOW + 5 * HOUR + 17.0
	var later: Array = flea.listings()
	var later_ids := later.map(func(listing: Dictionary) -> String: return listing.id)
	check(not later.is_empty() and not up.any(func(listing: Dictionary) -> bool: return listing.id in later_ids)
		and later.all(func(listing: Dictionary) -> bool: return float(listing.ends) > NOW + 5 * HOUR),
		"5 hours on (the game closed) a fresh set is up and every earlier one has ended")
	check(absf(flea.seconds_to_refresh() - (period - fmod(NOW + 5 * HOUR + 17.0, period))) < 0.01, "the next refresh comes on the half hour")
	var counts := [0, 0, 0, 0, 0, 0]
	var banned := 0
	var guns := 0
	var worn := 0
	var fitted := 0
	var under_floor := 0
	var under_resale := 0
	var sellers := 0
	var low: Vector2 = table.span(table.listings(), "condition", Vector2.ONE)
	for refresh in range(number, number + 200):
		for listing: Dictionary in flea.listings_on(refresh):
			var piece: RefCounted = listing.item
			counts[piece.data.rarity] += 1
			if table.is_banned(piece.data):
				banned += 1
			if piece.has_durability() and piece.durability >= piece.max_durability * low.x - 0.1 and piece.durability <= piece.max_durability * low.y + 0.1:
				worn += 1
			elif piece.has_durability():
				print("    %s at %.1f of %.1f" % [piece.data.id, piece.durability, piece.max_durability])
			if piece.is_gun():
				guns += 1
				var defaults: Dictionary = piece.data.weapon.default_mods
				if load("res://scripts/inventory/weapon_mods.gd").installed(piece).size() > defaults.size():
					fitted += 1
			var cost: int = flea.price(listing)
			if cost < int(listing.floor):
				under_floor += 1
			if cost < trading.resale_floor(piece):
				under_resale += 1
			if str(listing.seller).length() >= 6 and float(listing.rating) >= 2.5 and float(listing.rating) <= 5.0:
				sellers += 1
	var total := counts.reduce(func(a: int, b: int) -> int: return a + b, 0) as int
	print("    200 refreshes: %s listings by rarity, %d guns (%d with extra parts)" % [counts, guns, fitted])
	check(counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > counts[3] and counts[3] > counts[4] and counts[4] > counts[5],
		"rarer items are listed less often (%s)" % [counts])
	check(counts[5] <= 20, "Legendary almost never: %d in 200 refreshes" % counts[5])
	check(banned == 0, "nothing banned is ever listed (%d listings)" % total)
	check(worn > 0 and guns > 0 and fitted > 0 and fitted < guns, "guns and armor come worn within %.0f-%.0f%% (%d), some guns with extra parts (%d of %d)" % [low.x * 100, low.y * 100, worn, fitted, guns])
	check(under_floor == 0 and under_resale == 0, "no listing is ever cheaper than its floor, nor than its resale floor")
	check(sellers == total, "every listing has a made-up seller and a rating from 2.5 to 5")
	var listing: Dictionary = flea.listings()[0]
	check(flea.value_ratio(listing) == float(flea.price(listing)) / selling.item_value(listing.item), "value for money is the price against the item's worth")
	var trader: Dictionary = flea.trader_price("ak_74n")
	check(trader.get("trader") == "bulat" and int(trader.price) == trading.price("bulat", _offer("bulat", "ak_74n")), "the trader price beside a listing: Bulat's AK-74N at your loyalty (%s)" % trader)
	check(flea.trader_price("ledx").is_empty(), "nothing for what no trader sells for money (the LEDX)")


func _offer(trader: String, id: String) -> Dictionary:
	for offer: Dictionary in trading.offers(trader).get("buy", []):
		if offer.get("item") == id:
			return offer
	return {}


func _buying() -> void:
	section("Buying")
	_profile(14)
	var listing: Dictionary = flea.listings()[0]
	check(flea.buy(listing) == flea.lock_reason() and flea.lock_reason() != "", "locked below level 15 (\"%s\")" % flea.lock_reason())
	gs.level = 15
	var cost: int = flea.price(listing)
	check(flea.buy(listing, cost + 1).begins_with("The price changed"), "a price that changed since it was shown isn't charged")
	var money: int = gs.roubles
	var id: String = listing.item.data.id
	var before: float = flea.multiplier(id)
	var stash_before: int = _count(id)
	check(flea.buy(listing, cost) == "", "buys %s for %d" % [listing.item.title(), cost])
	check(gs.roubles == money - cost, "the price shown is the price charged")
	check(_count(id) == stash_before + listing.item.count, "the item arrives in the stash (%d)" % listing.item.count)
	var bought: RefCounted = _find(id)
	check(bought != null and bought.all_items().all(func(each: RefCounted) -> bool: return not each.fir), "never found in raid (nor anything in it)")
	check(is_equal_approx(flea.multiplier(id), before + 0.04), "buying pushes its price up (×%.3f → ×%.3f)" % [before, flea.multiplier(id)])
	check(flea.find(listing.id).is_empty() and not flea.listings().has(listing), "the listing is gone")
	check(flea.buy(listing).begins_with("Gone"), "and can't be bought twice")
	var other: Dictionary = flea.listings()[0]
	gs.roubles = flea.price(other) - 1
	check(flea.buy(other) == "Not enough roubles", "not without the roubles")
	gs.roubles = 50_000_000
	while gs.stash.add(item("ammo_556_fmj", 60)):
		pass
	check(flea.buy(other) == "No room in the stash", "nor with no room in the stash")
	stock.now_override = NOW + 6 * HOUR
	flea.listings()
	check(not gs.flea.bought.has(listing.id), "a bought mark is dropped once its listing would have ended")


func _count(id: String) -> int:
	var total := 0
	for each: RefCounted in gs.stash.all_items():
		if each.data.id == id:
			total += each.count
	return total


func _find(id: String) -> RefCounted:
	for each: RefCounted in gs.stash.items:
		if each.data.id == id:
			return each
	return null


## A found-in-raid `id` in the stash.
func _fir(id: String, amount := 1) -> RefCounted:
	var piece: RefCounted = item(id, amount)
	load("res://scripts/inventory/found_in_raid.gd").set_found(piece, true)
	check(gs.stash.add(piece), "(%s put in the stash)" % id)
	return piece


func _own_listings() -> void:
	section("Your listings")
	_profile()
	var watch: RefCounted = item("roler")
	gs.stash.add(watch)
	check(flea.list_block_reason(watch, 100000) == "Only found-in-raid items can be listed", "only found-in-raid items")
	var loose: RefCounted = item("roler")
	loose.fir = true
	check(flea.list_block_reason(loose, 100000) == "Only items in your stash can be listed", "only from the stash")
	var gun: RefCounted = _fir("ak_74n")
	var parts: Array = load("res://scripts/inventory/weapon_mods.gd").installed(gun)
	parts[0].fir = false
	check(flea.list_block_reason(gun, 50000) == "Something on or in it isn't found in raid", "not with a part that isn't found in raid")
	var pack: RefCounted = _fir(_a_backpack())
	var inside: RefCounted = item("bandage")
	inside.fir = true
	pack.contents.add(inside)
	check(flea.list_block_reason(pack, 50000) == "Empty it first", "a container only empty")
	var found: RefCounted = _fir("roler")
	var market: int = flea.market_price(found)
	check(flea.list_block_reason(found, 0) == "Set a price", "not for nothing")
	check(is_equal_approx(flea.fee_share(found, market), 0.05) and flea.listing_fee(found, market) == ceili(market * 0.05),
		"the fee at the market price (%d) is 5%%: %d" % [market, flea.listing_fee(found, market)])
	var dear := roundi(market * 1.2)
	check(absf(flea.fee_share(found, dear) - 0.15) < 0.001, "at 1.2× the market price it's 15%% (%.3f)" % flea.fee_share(found, dear))
	check(is_equal_approx(flea.fee_share(found, market * 5), 0.6), "and never above 60%")
	gs.roubles = flea.listing_fee(found, market) - 1
	check(flea.list_block_reason(found, market).begins_with("Not enough roubles for the"), "not without the roubles for the fee")
	gs.roubles = 1_000_000
	var before: float = flea.multiplier("roler")
	var fee: int = flea.listing_fee(found, market)
	check(flea.put_up(found, market) == "", "lists a found-in-raid Roler at the market price")
	check(gs.roubles == 1_000_000 - fee and gs.stash.find_holder(found) == null, "pays the fee (%d) and takes it out of the stash" % fee)
	var listing: Dictionary = flea.own_listings()[-1]
	check(listing.state == flea.UP and listing.price == market and listing.fee == fee and listing.item.id == "roler" and listing.item.fir, "the listing keeps the item, found in raid")
	check(flea.multiplier("roler") < before, "putting one up pushes its price down (×%.3f → ×%.3f)" % [before, flea.multiplier("roler")])
	check(flea.slots() == 3 and flea.slots_used() == 1, "1 of 3 slots taken at level 15")
	for i in 2:
		check(flea.put_up(_fir("bolts"), 50000) == "", "(another listing)")
	var fourth: RefCounted = _fir("roler")
	check(flea.list_block_reason(fourth, 100000) == "All 3 listing slots are taken", "a fourth needs a free slot")
	gs.level = 20
	check(flea.slots() == 4 and flea.list_block_reason(fourth, 100000) == "", "level 20 has a fourth slot")
	gs.level = 15
	var waiting: Dictionary = flea.own_listings()[0]
	var stash_before: int = _count("roler")
	check(flea.take_down(waiting) == "" and _count("roler") == stash_before + 1 and flea.slots_used() == 2, "taking one down brings the item back (the fee stays paid)")


func _a_backpack() -> String:
	for data in db.all_items():
		if data.category == data.Category.BACKPACK:
			return data.id
	return ""


func _sale_timing() -> void:
	section("Sale timing by fairness")
	_profile(25)
	var cheap: RefCounted = _fir("roler")
	var fair: RefCounted = _fir("roler")
	var over: RefCounted = _fir("roler")
	var far: RefCounted = _fir("roler")
	var market: int = flea.market_price(cheap)
	check(flea.estimate_text(cheap, market) == "Sells in 5 min - 12 min", "at market: \"%s\"" % flea.estimate_text(cheap, market))
	check(flea.estimate_text(far, roundi(market * 1.5)).begins_with("Won't sell"), "far over: \"%s\"" % flea.estimate_text(far, roundi(market * 1.5)))
	flea.put_up(cheap, roundi(market * 0.9))
	flea.put_up(fair, flea.market_price(fair))
	flea.put_up(over, roundi(flea.market_price(over) * 1.15))
	flea.put_up(far, roundi(flea.market_price(far) * 1.5))
	var own: Array = flea.own_listings()
	var minutes := own.map(func(listing: Dictionary) -> float: return (float(listing.sells) - float(listing.listed)) / 60.0 if float(listing.sells) > 0.0 else -1.0)
	print("    minutes to sell at 0.9×, 1×, 1.15× and 1.5× market: %s" % [minutes])
	check(minutes[0] > 0.0 and minutes[0] <= 5.0 * 1.4 and minutes[1] > 0.0 and minutes[1] <= 8.0 * 1.4, "under and at market it sells within minutes")
	check(minutes[2] >= 45.0 * 0.6 and minutes[2] <= 150.0 * 1.4 and minutes[2] > minutes[1], "a little over takes longer")
	check(minutes[3] < 0.0, "far over doesn't sell")
	# The game closes; three hours later it starts again.
	check(sm.save_game(), "(saved)")
	stock.now_override = NOW + 3 * HOUR
	gs.roubles = 0
	sm.load_game()
	own = flea.own_listings()
	check(own.size() == 4 and own.slice(0, 3).all(func(listing: Dictionary) -> bool: return listing.state == flea.SOLD) and own[3].state == flea.UP,
		"three hours later, the game closed in between, the three fairly priced ones have sold")
	check(flea.notice_text().begins_with("Flea market: 3 sold") and flea.slots_used() == 1, "the main menu says so (\"%s\"); sold ones free their slot" % flea.notice_text())
	var money: int = gs.roubles
	var sold_for: int = own[0].price + own[1].price + own[2].price
	var result: Dictionary = flea.collect_all()
	check(result.roubles == sold_for and gs.roubles == money + sold_for and flea.own_listings().size() == 1, "COLLECT pays the asking prices in full (%d)" % sold_for)
	stock.now_override = NOW + 12 * HOUR - 1.0
	check(flea.own_listings()[0].state == flea.UP and flea.time_left(flea.own_listings()[0]) <= 1.0, "the dear one is still up a second before 12 hours")
	stock.now_override = NOW + 12 * HOUR
	var back: Dictionary = flea.own_listings()[0]
	check(back.state == flea.EXPIRED and flea.notice_text() == "Flea market: 1 item back unsold: collect on the FLEA MARKET", "at 12 hours it comes back unsold")
	var filled := 0
	while gs.stash.add(item("ammo_556_fmj", 60)):
		filled += 1
	check(flea.collect(back) == "No room in the stash" and flea.own_listings().size() == 1, "with no room in the stash it waits")
	for each: RefCounted in gs.stash.items.duplicate():
		gs.stash.remove(each)
	check(flea.collect(back) == "" and _count("roler") == 1 and _find("roler").fir and flea.own_listings().is_empty(), "then comes back to the stash, still found in raid")
	stock.now_override = NOW + 10 * HOUR
	check(flea.time() == NOW + 12 * HOUR, "(the market's clock stays at 12 hours)")


func _banned() -> void:
	section("Banned items")
	_profile()
	var banned := {"secure_alpha": "a secure container", "drillmaster_whistle": "a boss unique", "ammo_338_ap": "the .338 AP round (79 penetration)",
		"ammo_545_ppbs": "5.45 PPBS (62)"}
	for data in db.all_items():
		if data.category == data.Category.KEY:
			banned[data.id] = "a key (%s)" % data.display_name
			break
	for data in db.all_items():
		if data.has_tag("keycard"):
			banned[data.id] = "a keycard (%s)" % data.display_name
			break
	for id: String in banned:
		var piece: RefCounted = _fir(id)
		check(table.is_banned(piece.data) and flea.list_block_reason(piece, 100000) == table.ban_reason(piece.data), "%s can't be listed (\"%s\")" % [banned[id], table.ban_reason(piece.data)])
	check(not table.is_banned(db.get_item("ammo_545_bs")) and not table.is_banned(db.get_item("roler")) and not table.is_banned(db.get_item("ak_74n")),
		"5.45 BS (45), a Roler and an AK-74N can")


func _saving() -> void:
	section("Save round trip")
	_profile()
	var listing: Dictionary = flea.listings()[0]
	flea.buy(listing)
	var found: RefCounted = _fir("roler")
	flea.put_up(found, 123456)
	var before: Dictionary = flea.to_save()
	check(sm.save_game(), "(saved)")
	gs.flea = flea.blank()
	sm.load_game()
	var after: Dictionary = flea.to_save()
	check(JSON.stringify(after) == JSON.stringify(before), "listings, pressure, what you bought, the next number and the market's clock come back")
	check(flea.find(listing.id).is_empty() and flea.own_listings()[0].price == 123456, "the bought listing stays bought; your listing is still up")
	var old: Dictionary = gs.to_dict()
	old.profile.erase("flea")
	old["version"] = 15
	gs.from_dict(old)
	check(JSON.stringify(gs.flea) == JSON.stringify(flea.blank()), "a version 15 save starts with a blank market")
