extends "res://tests/test_base.gd"
## Faction perks (docs/plan/E9_faction_perks.md, DESIGN.md §3, §10, §11): the faction discount at your
## faction's trader on every price path and its floor, the two faction quest lines (hidden from the other
## faction, chained, their objectives and rewards, the faction-only barter at the end), quest counts that
## only count quests you can see, and the save round trip.

const NOW := 1_000_000.0

var trading: GDScript
var factions: GDScript
var stock: GDScript
var quick: GDScript
var money: Callable


func run() -> void:
	trading = load("res://scripts/progression/trading.gd")
	factions = load("res://scripts/data/factions.gd")
	stock = load("res://scripts/progression/trader_stock.gd")
	quick = load("res://scripts/progression/quick_buy.gd")
	money = func(amount: int, currency := "RUB") -> String: return load("res://scripts/ui/ui_format.gd").money(amount, currency)
	_discount()
	_floor()
	_other_faction()
	await _panel()
	stock.now_override = -1.0


## A new profile (0: BEAR, 1: USEC) at a fixed time, with money to spend.
func _profile(faction := 0) -> void:
	stock.now_override = NOW
	fresh_profile(faction)
	gs.roubles = 5_000_000


func _offer(trader: String, id: String) -> Dictionary:
	for offer: Dictionary in trading.buy_list(trader):
		if offer.get("id") == id:
			return offer
	return {}


func _discount() -> void:
	section("The faction discount: BEAR at Bulat's")
	_profile(0)
	check(is_equal_approx(factions.trader_discount(), 0.05) and factions.problems().is_empty(), "factions.json gives 5%% (%.2f), no problems" % factions.trader_discount())
	for trader: String in load("res://scripts/data/trader_table.gd").ids():
		check(trading.faction_discount(trader) == (0.05 if trader == "bulat" else 0.0), "%s: %.2f off for BEAR" % [trader, trading.faction_discount(trader)])
	var mosin := _offer("bulat", "bulat_mosin_rifle")
	check(int(mosin.price) == 32000 and trading.offer_level(mosin) == 1, "Bulat's Mosin: ₽ 32,000 at LL1")
	check(trading.price("bulat", mosin) == 30400 and trading.price_text("bulat", mosin) == "%s  ·  −5%% as BEAR (was %s)" % [money.call(30400), money.call(32000)],
		"at LL1 it costs 5%% less: %s" % trading.price_text("bulat", mosin))
	check(trading.discount_text("bulat") == "Buy prices: full price at your LL1 (3% off at LL2, 6% at LL3, 9% at LL4)  ·  5% off for BEAR",
		"the panel says so (%s)" % trading.discount_text("bulat"))
	var wires := _offer("tinker", "tinker_wires")
	check(trading.price("tinker", wires) == 10000 and trading.price_text("tinker", wires) == money.call(10000) and not "BEAR" in trading.discount_text("tinker"),
		"Tinker's wires stay ₽ 10,000 for BEAR, nothing on his panel")
	gs.trader_loyalty.bulat.level = 2
	var at_two := roundi(32000 * (1.0 - 0.03) * (1.0 - 0.05))
	check(trading.price("bulat", mosin) == at_two and at_two == 29488, "at LL2 on top of the 3%%: %d" % trading.price("bulat", mosin))
	check(trading.price_text("bulat", mosin) == "%s  ·  −8%% at your loyalty and as BEAR (was %s)" % [money.call(29488), money.call(32000)],
		"the BUY row: %s" % trading.price_text("bulat", mosin))
	check(trading.discount_text("bulat") == "Buy prices: 3% off at your LL2 (6% at LL3, 9% at LL4)  ·  5% more off for BEAR",
		"the panel: %s" % trading.discount_text("bulat"))
	# Every path charges price(): the block reason, buy(), quick buy and the flea market's trader price.
	gs.roubles = 29488
	check(trading.buy_block_reason(mosin, "bulat") == "", "₽ 29,488 is enough")
	gs.roubles = 29487
	check(trading.buy_block_reason(mosin, "bulat") == "Not enough roubles", "₽ 29,487 isn't")
	gs.roubles = 100000
	var spent: int = gs.trader_loyalty.bulat.spent
	check(trading.buy("bulat", mosin) == "" and gs.roubles == 100000 - 29488 and gs.trader_loyalty.bulat.spent == spent + 29488
		and gs.stash.count_of("mosin_rifle") == 1, "buy() takes ₽ 29,488 and counts it toward money spent")
	var flea: Dictionary = load("res://scripts/progression/flea_market.gd").trader_price("mosin_rifle")
	check(flea.get("trader") == "bulat" and int(flea.get("price", 0)) == 29488, "the flea market's trader price is the same (%s)" % str(flea))
	gs.trader_loyalty.bulat.level = 4
	var card: Dictionary = load("res://scripts/data/quick_buy_table.gd").find("workhorse")
	var bundle: float = load("res://scripts/data/quick_buy_table.gd").bundle_discount()
	var bulat_lines := 0
	for line: Dictionary in quick.plan(card).lines:
		if line.trader != "bulat":
			continue
		bulat_lines += 1
		var base := int(line.offer.price)
		var unit := mini(maxi(roundi(base * (1.0 - 0.09) * (1.0 - 0.05)), trading.offer_floor(line.offer)), base)
		var cut := mini(maxi(roundi(base * (1.0 - 0.09) * (1.0 - 0.05) * (1.0 - bundle)), trading.offer_floor(line.offer)), base)
		check(int(line.unit) == unit and int(line.price) == cut * int(line.packs), "quick buy: Workhorse's %s at LL4 as BEAR: %d a pack, %d with the bundle" % [line.offer.id, unit, cut])
	check(bulat_lines >= 2, "Workhorse has Bulat lines (%d)" % bulat_lines)


func _floor() -> void:
	section("Never below the resale floor")
	_profile(0)
	gs.trader_loyalty.bulat.level = 4
	var base := _offer("bulat", "bulat_mosin_rifle")
	var floor: int = trading.offer_floor(base)
	check(floor > 0 and floor < 27664, "the Mosin's floor (%d) is below LL4 with the discount (27,664)" % floor)
	check(trading.price("bulat", base) == 27664, "so LL4 and 5%% off: ₽ 27,664 (%d)" % trading.price("bulat", base))
	var near := {"id": "test_perk_floor", "item": "mosin_rifle", "count": 1, "price": floor + 300}
	check(trading.price("bulat", near) == floor, "an offer just above its floor stops at it (%d, floor %d)" % [trading.price("bulat", near), floor])
	check(trading.price("bulat", near, 0.5) == floor, "with a bundle cut on top too")
	check(trading.price_text("bulat", near) == "%s  ·  −%d%% at your loyalty and as BEAR (was %s)" % [money.call(floor), roundi(300 * 100.0 / (floor + 300)), money.call(floor + 300)],
		"the row shows what really comes off (%s)" % trading.price_text("bulat", near))
	var below := {"id": "test_perk_below", "item": "mosin_rifle", "count": 1, "price": floor - 100}
	check(trading.price("bulat", below) == floor - 100 and trading.price_text("bulat", below) == money.call(floor - 100), "one below its floor isn't raised, shown plain")
	var perks: Dictionary = factions.data().perks
	perks.trader_discount = 0.5
	check(not factions.problems().is_empty(), "factions.json's check refuses a discount above 15%")
	check(trading.price("bulat", base) >= floor, "and even a 50%% discount stops at the floor (%d)" % trading.price("bulat", base))
	perks.trader_discount = 0.05


func _other_faction() -> void:
	section("USEC at Tinker's")
	_profile(1)
	var wires := _offer("tinker", "tinker_wires")
	var mosin := _offer("bulat", "bulat_mosin_rifle")
	check(trading.faction_discount("tinker") == 0.05 and trading.faction_discount("bulat") == 0.0, "USEC's discount is at Tinker's")
	check(trading.price("tinker", wires) == 9500 and trading.price_text("tinker", wires) == "%s  ·  −5%% as USEC (was %s)" % [money.call(9500), money.call(10000)],
		"Tinker's wires: %s" % trading.price_text("tinker", wires))
	check(trading.price("bulat", mosin) == 32000 and trading.price_text("bulat", mosin) == money.call(32000) and not "USEC" in trading.discount_text("bulat"),
		"Bulat's Mosin is full price for USEC")
	check(trading.discount_text("tinker").ends_with("  ·  5% off for USEC"), "Tinker's panel says so (%s)" % trading.discount_text("tinker"))
	gs.roubles = 9499
	check(trading.buy("tinker", wires) == "Not enough roubles" and gs.roubles == 9499, "₽ 9,499 doesn't buy them")
	gs.roubles = 9500
	check(trading.buy("tinker", wires) == "" and gs.roubles == 0, "₽ 9,500 does")


## The trader screen: the panel's price line and the BUY row.
func _panel() -> void:
	section("The trader screen")
	_profile(0)
	gs.trader_loyalty.bulat.level = 2
	change_scene_to_file("res://ui/traders_screen.tscn")
	await frames(4)
	var screen: Node = current_scene
	(screen.find_child("Trader_bulat", true, false) as Button).pressed.emit()
	await frames(2)
	var loyalty: Label = screen.find_child("Loyalty", true, false)
	check(loyalty != null and "Buy prices: 3% off at your LL2 (6% at LL3, 9% at LL4)  ·  5% more off for BEAR." in loyalty.text,
		"Bulat's panel shows the faction discount")
	var row: Node = screen.find_child("Offer_bulat_mosin_rifle", true, false)
	var text: Label = row.find_child("OfferText", true, false) if row else null
	check(text != null and text.text.contains(trading.price_text("bulat", _offer("bulat", "bulat_mosin_rifle"))) and text.text.contains("as BEAR"),
		"the Mosin's BUY row too (%s)" % (text.text.replace("\n", " / ") if text else "no row"))
	(screen.find_child("Trader_tinker", true, false) as Button).pressed.emit()
	await frames(2)
	check(not "BEAR" in loyalty.text, "Tinker's panel doesn't")
