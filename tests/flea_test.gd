extends "res://tests/test_base.gd"
## The flea market (DESIGN.md §10, Flea market): the rules' loader and its checks (a broken copy for each
## rule), the unlock level, market prices (the drift's bounds, the same numbers on the same clock, how
## fast it moves, your pressure and its decay, the trend) and the floor against trader prices.

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
