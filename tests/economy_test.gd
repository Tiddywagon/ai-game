extends "res://tests/test_base.gd"
## Economy: buying, loyalty, stock and restocks, selling, Wanted items, the exchange, no resale profit,
## barters, Mole's karma levels, player levels, the hideout and crafting.

const NOW := 1_000_000.0
## What a dollar is worth in roubles when it's sold at the exchange: the no-resale check's rate.
const DOLLAR := 125

## Game scripts, loaded in run() (the autoloads they use exist by then).
var trading: GDScript
var selling: GDScript
var stock: GDScript
var traders: GDScript
var barters: GDScript
var progression: GDScript
var hideout: GDScript
var search: GDScript


func run() -> void:
	trading = load("res://scripts/progression/trading.gd")
	selling = load("res://scripts/progression/selling.gd")
	stock = load("res://scripts/progression/trader_stock.gd")
	traders = load("res://scripts/data/trader_table.gd")
	barters = load("res://scripts/data/barter_table.gd")
	progression = load("res://scripts/progression/progression.gd")
	hideout = load("res://scripts/progression/hideout.gd")
	search = load("res://scripts/progression/item_search.gd")
	_buying()
	_loyalty_prices()
	_loyalty_and_stock()
	_selling()
	_wanted()
	_exchange()
	_no_resale()
	_barters()
	_mole()
	_levels()
	_hideout()
	stock.now_override = -1.0


## A new BEAR profile at a fixed time (restocks an hour later).
func _profile() -> void:
	stock.now_override = NOW
	sm.delete_save()
	gs.new_profile(gs.Faction.BEAR)


func _offer(trader: String, id: String) -> Dictionary:
	for offer: Dictionary in trading.buy_list(trader):
		if offer.get("id") == id:
			return offer
	return {}


## `amount` single found-in-raid (or not) items of `id` put in the stash.
func _give(id: String, amount := 1, found := false) -> void:
	for i in amount:
		var piece := item(id)
		piece.fir = found
		gs.stash.add(piece)


func _fir_count(id: String) -> int:
	var total := 0
	for each in gs.stash.items:
		if each.data.id == id and each.fir:
			total += each.count
	return total


func _unlock_broker() -> void:
	gs.quests["zoya_introduction"] = {"state": "completed", "progress": [1, 2, 150000]}


func _buying() -> void:
	section("Buying")
	_profile()
	var nails := _offer("zoya", "zoya_nails")
	check(int(nails.price) == 7500 and trading.buy_block_reason(nails, "zoya") == "", "Zoya's nails cost 7,500 and can be bought")
	check(trading.buy("zoya", nails) == "", "buy() succeeds")
	check(gs.roubles == 500000 - 7500, "the price is taken")
	check(gs.stash.count_of("nails") == 1 and _fir_count("nails") == 0, "the item is in the stash, not found in raid")
	check(gs.trader_loyalty.zoya.spent == 7500, "the price counts toward money spent with Zoya")
	var rounds := _offer("bulat", "bulat_ammo_9x18_p")
	check(trading.buy("bulat", rounds) == "" and gs.stash.count_of("ammo_9x18_p") == 50 and gs.roubles == 500000 - 7500 - 2300,
		"an offer of 50 rounds gives 50 for its one price")
	gs.roubles = 7499
	check(trading.buy("zoya", nails) == "Not enough roubles" and gs.roubles == 7499 and gs.stash.count_of("nails") == 1,
		"too little money: nothing is bought")
	check(trading.buy_list("mole").size() >= 8 and trading.buy_list("mole").size() <= 12
		and trading.buy_list("mole").all(func(offer: Dictionary) -> bool: return offer.get("used", false) and int(offer.stock) == 1),
		"Mole sells 8-12 worn items, one of each")


func _loyalty_prices() -> void:
	section("Loyalty prices")
	_profile()
	_unlock_broker()
	check(traders.problems().is_empty() and trading.problems().is_empty(), "TraderTable.problems() and Trading.problems() are empty")
	for trader: String in traders.ids():
		var shares: Array = [trading.buy_discount(trader, 1), trading.buy_discount(trader, 2), trading.buy_discount(trader, 3), trading.buy_discount(trader, 4)]
		check(shares == ([0.0, 0.0, 0.0, 0.0] if trader == "mole" else [0.0, 0.03, 0.06, 0.09]),
			"%s takes %s off at LL1-4" % [trader, str(shares)])
	var nails := _offer("zoya", "zoya_nails")
	var rifle := _offer("bulat", "bulat_ak_74n")
	var scope := _offer("broker", "broker_scope_6_8")
	var money := func(amount: int, currency := "RUB") -> String: return load("res://scripts/ui/ui_format.gd").money(amount, currency)
	check(trading.price("zoya", nails) == 7500 and trading.price_text("zoya", nails) == money.call(7500), "at LL1 the price is the offer's own, shown plain")
	check(trading.discount_text("zoya") == "Buy prices: full price at your LL1 (3% off at LL2, 6% at LL3, 9% at LL4)",
		"the panel says what each level takes off (%s)" % trading.discount_text("zoya"))
	for level in [2, 3, 4]:
		gs.trader_loyalty.bulat.level = level
		gs.trader_loyalty.broker.level = level
		var share: float = [0.0, 0.0, 0.03, 0.06, 0.09][level]
		check(trading.price("bulat", rifle) == roundi(41000 * (1.0 - share)) and trading.price("broker", scope) == roundi(1150 * (1.0 - share)),
			"LL%d: the AK-74N costs %d, the 6-8x scope $%d" % [level, trading.price("bulat", rifle), trading.price("broker", scope)])
	gs.trader_loyalty.bulat.level = 2
	check(trading.price_text("bulat", rifle) == "%s  ·  −3%% at your loyalty (was %s)" % [money.call(39770), money.call(41000)],
		"a BUY row shows the discount (%s)" % trading.price_text("bulat", rifle))
	check(trading.discount_text("bulat") == "Buy prices: 3% off at your LL2 (6% at LL3, 9% at LL4)", "and the panel the levels to come (%s)" % trading.discount_text("bulat"))
	gs.trader_loyalty.bulat.level = 4
	check(trading.discount_text("bulat") == "Buy prices: 9% off at your LL4" and trading.discount_text("mole") == "", "at the top level just the share; Mole has no line")
	# Every path charges price(): buy_block_reason() and buy() at LL4.
	gs.trader_loyalty.bulat.level = 2
	gs.roubles = 39770
	check(trading.buy_block_reason(rifle, "bulat") == "", "39,770 is enough at LL2 (the discounted price is what's checked)")
	gs.roubles = 39769
	check(trading.buy_block_reason(rifle, "bulat") == "Not enough roubles", "39,769 isn't")
	gs.roubles = 100000
	var spent: int = gs.trader_loyalty.bulat.spent
	check(trading.buy("bulat", rifle) == "" and gs.roubles == 100000 - 39770 and gs.trader_loyalty.bulat.spent == spent + 39770,
		"buy() takes 39,770 and counts 39,770 toward money spent")
	gs.trader_loyalty.broker.level = 4
	gs.dollars = 1047
	spent = gs.trader_loyalty.broker.spent
	check(trading.buy("broker", scope) == "" and gs.dollars == 0 and gs.trader_loyalty.broker.spent == spent + 1047 * 140,
		"a dollar offer at LL4: $1,047, counted at 140 a dollar")
	# The floor: a discount never goes below what the best-paying trader pays, plus 3%.
	var floor_rifle: int = trading.offer_floor(rifle)
	var resale: int = selling.best_resale(trading.offer_item(rifle))
	check(resale > 0 and floor_rifle == ceili(resale * 1.03), "the AK-74N's floor is its best resale (%d) plus 3%% (%d)" % [resale, floor_rifle])
	gs.trader_loyalty.bulat.level = 4
	check(trading.price("bulat", rifle, 0.9) == floor_rifle and trading.price("bulat", rifle, 0.0) == 37310,
		"a 90% cut stops at the floor; LL4's 9% leaves 37,310")
	var cheap := {"id": "test_cheap_rifle", "item": "ak_74n", "count": 1, "price": floor_rifle - 100}
	check(trading.price("bulat", cheap) == floor_rifle - 100, "an offer already below its floor isn't raised")
	var whole: RefCounted = trading.offer_item(rifle)
	var parts := 0
	for part: RefCounted in whole.mods.values():
		parts += selling.best_resale(part)
	check(resale >= parts, "the floor counts the gun taken apart too (%d whole or in parts, the parts alone %d)" % [resale, parts])


func _loyalty_and_stock() -> void:
	section("Loyalty and stock")
	_profile()
	var rifle := _offer("bulat", "bulat_ak_74n")
	check(int(rifle.ll) == 2 and int(rifle.stock) == 2, "Bulat's AK-74N is an LL2 offer with 2 in stock")
	check(trading.buy("bulat", rifle) == "Needs loyalty level 2" and gs.roubles == 500000, "it can't be bought at LL1")
	check(not trading.shown_offers("bulat").has(rifle) and int(trading.hidden_offers("bulat").get(2, 0)) > 0, "the BUY tab hides it and counts it for LL2")
	check(trading.shown_offers("bulat").size() + _sum(trading.hidden_offers("bulat")) == trading.buy_list("bulat").size(),
		"shown and hidden offers add up to all of them")
	gs.level = 15
	gs.trader_loyalty.bulat.reputation = 0.2
	gs.trader_loyalty.bulat.spent = 749999
	check(not trading.update_loyalty("bulat") and gs.trader_loyalty.bulat.level == 1, "level 15, 0.2 reputation but 749,999 spent: still LL1")
	gs.trader_loyalty.bulat.spent = 750000
	check(trading.update_loyalty("bulat") and gs.trader_loyalty.bulat.level == 2, "750,000 spent: LL2")
	gs.level = 60
	gs.trader_loyalty.bulat.reputation = 0.34
	gs.trader_loyalty.bulat.spent = 9000000
	check(not trading.update_loyalty("bulat") and gs.trader_loyalty.bulat.level == 2, "0.34 reputation doesn't reach LL3 (0.35)")
	check(trading.shown_offers("bulat").has(rifle) and stock.left("bulat", rifle) == 2, "at LL2 the offer shows, 2 left")
	check(trading.price("bulat", rifle) == 39770, "at LL2 it costs 3%% less: 39,770, not 41,000 (%d)" % trading.price("bulat", rifle))
	check(trading.buy("bulat", rifle) == "" and trading.buy("bulat", rifle) == "" and gs.stash.count_of("ak_74n") == 3, "both are bought")
	check(stock.left("bulat", rifle) == 0 and trading.buy("bulat", rifle).begins_with("Sold out until the restock")
		and gs.stash.count_of("ak_74n") == 3 and gs.roubles == 500000 - 2 * 39770, "then it's sold out and a third costs nothing")
	check(stock.left("bulat", _offer("bulat", "bulat_ammo_9x18_p")) == -1, "an offer without stock has no limit")
	check(is_equal_approx(stock.seconds_left("bulat"), 3600.0) and stock.restock_number("bulat") == 1, "the restock is an hour away")
	stock.now_override = NOW + 3599.0
	check(stock.left("bulat", rifle) == 0, "a second before the restock it's still sold out")
	stock.now_override = NOW + 3600.0
	check(stock.left("bulat", rifle) == 2 and stock.restock_number("bulat") == 2, "the restock brings both back")
	check(trading.buy("bulat", rifle) == "" and stock.left("bulat", rifle) == 1, "and it sells again")
	stock.now_override = NOW + 3600.0 * 4
	check(stock.restock_number("bulat") == 5 and is_equal_approx(stock.seconds_left("bulat"), 3600.0), "three more hours are three more restocks")


func _selling() -> void:
	section("Selling")
	_profile()
	_unlock_broker()
	# [trader, item, count, the trader's rate at LL1, their multiplier for it]
	var sales := [["bulat", "ammo_545_ps", 60, 0.5, 1.0], ["vera", "bandage", 1, 0.55, 1.0], ["zoya", "nails", 1, 0.5, 1.0],
		["stitch", "paca_armor", 1, 0.5, 1.0], ["tinker", "red_dot", 1, 0.5, 1.0], ["mole", "nails", 1, 0.3, 1.0],
		["bulat", "red_dot", 1, 0.5, 0.8], ["zoya", "crackers", 1, 0.5, 0.8]]
	for sale: Array in sales:
		var trader: String = sale[0]
		var sold := item(sale[1], sale[2])
		gs.stash.place(sold, Vector2i(0, 20), false)
		var expected := floori(sold.data.base_value * int(sale[2]) * float(sale[3]) * float(sale[4]))
		check(expected > 0 and selling.price(trader, sold) == expected,
			"%s pays %d%% of the worth of %s (x%.1f): %d" % [trader, roundi(float(sale[3]) * 100), sale[1], sale[4], expected])
		var roubles: int = gs.roubles
		var spent: int = gs.trader_loyalty[trader].spent
		check(selling.sell(trader, [sold]) == "" and gs.roubles == roubles + expected and gs.trader_loyalty[trader].spent == spent + expected
			and gs.stash.find_holder(sold) == null, "selling it pays that, counts toward money spent and takes the item")
	var gun := item("ak_74n")
	gs.stash.add(gun)
	var dollars := floori(selling.item_value(gun) * 0.65 / 140.0)
	check(selling.currency("broker") == "USD" and dollars > 0 and selling.price("broker", gun) == dollars,
		"The Broker pays 65%% of a gun's worth in dollars at 140: $%d" % dollars)
	check(selling.sell("broker", [gun]) == "" and gs.dollars == dollars and gs.trader_loyalty.broker.spent == dollars * 140,
		"selling it pays dollars and counts them at 140 toward money spent")
	var plain := item("ak_74n")
	check(selling.item_value(plain) > plain.data.base_value, "a gun's worth includes its parts")
	plain.durability = 50.0
	check(is_equal_approx(selling.condition(plain), 0.6), "a gun at half durability keeps 60% of its value")
	gs.stash.add(plain)
	check(selling.price("vera", plain) == 0 and selling.sell("vera", [plain]) == "AK-74N: Doc Vera doesn't buy that" and gs.stash.count_of("ak_74n") == 2,
		"Doc Vera doesn't buy guns")
	var worn: RefCounted = gs.inventory.equipment.armor
	check(selling.sell("stitch", [worn]) == "%s: Take it off first" % worn.data.display_name and gs.inventory.equipment.armor == worn, "what you wear can't be sold")
	var secured := item("bolts")
	gs.inventory.equipment.secure.contents.add(secured)
	check(selling.sell("mole", [secured]).ends_with("Take it out of your secure container first"), "nor what's in the secure container")
	var pack := item("sling_bag")
	pack.contents.add(item("bolts"))
	gs.stash.add(pack)
	check(selling.sell("stitch", [pack]).ends_with("Empty it first: 1 item inside") and gs.stash.count_of("sling_bag") == 1, "nor a pack with something in it")
	check(selling.sell("mole", []) == "Nothing to sell", "an empty sale is refused")
	var unsold := 0
	for data in db.all_items():
		if not selling.buys("mole", data):
			unsold += 1
	check(unsold == 0, "Mole buys every one of the 505 items")
	gs.trader_loyalty.vera.level = 4
	check(is_equal_approx(selling.rate("vera"), 0.64), "each loyalty level adds 3%: Vera pays 64% at LL4")


func _wanted() -> void:
	section("Wanted items")
	_profile()
	var wanted: Array = stock.wanted("zoya")
	check(wanted.size() >= 2 and wanted.size() <= 3, "Zoya wants 2-3 items (%s)" % ", ".join(wanted))
	check(wanted.all(func(id: String) -> bool: return trading.sold_at_level(id) == 0 and selling.buys("zoya", db.get_item(id))),
		"all things she buys and no trader sells")
	var id: String = wanted[0]
	var pieces: Array = []
	for i in 4:
		pieces.append(item(id))
		gs.stash.add(pieces[i])
	var normal := floori(pieces[0].data.base_value * 0.5 * selling.multiplier("zoya", pieces[0].data))
	var bonus := floori(pieces[0].data.base_value * 0.5 * selling.multiplier("zoya", pieces[0].data) * 1.5)
	check(is_equal_approx(stock.wanted_multiplier(), 1.5) and normal > 0 and selling.price("zoya", pieces[0]) == bonus, "a Wanted item pays x1.5 (%d, not %d)" % [bonus, normal])
	check(selling.quote("zoya", pieces) == [bonus, bonus, bonus, normal], "sold together, three pay the bonus and the fourth doesn't")
	var roubles: int = gs.roubles
	check(selling.sell("zoya", pieces.slice(0, 3)) == "" and gs.roubles == roubles + bonus * 3 and stock.wanted_left("zoya", id) == 0, "three sold: the bonus is used up")
	check(selling.price("zoya", pieces[3]) == normal, "the next one pays the normal price")
	check(selling.price("mole", pieces[3]) == floori(pieces[3].data.base_value * 0.3), "a trader who doesn't want it pays no bonus")
	stock.now_override = NOW + 3600.0
	check(stock.wanted_left("zoya", stock.wanted("zoya")[0]) == 3, "after the restock the new list pays for three again")


func _exchange() -> void:
	section("The Broker's exchange")
	_profile()
	check(trading.exchange().buy == 145 and trading.exchange().sell == 125 and trading.exchange_trader() == "broker", "a dollar costs 145 and sells for 125")
	check(not traders.is_unlocked("broker") and trading.buy_dollars(10) == "The Broker doesn't trade with you yet" and gs.dollars == 0, "The Broker is locked on a new profile")
	check(trading.buy_block_reason(trading.buy_list("broker")[0], "broker") == "The Broker doesn't trade with you yet", "and sells nothing")
	_unlock_broker()
	check(traders.is_unlocked("broker"), "A Word in His Ear unlocks him")
	check(trading.buy_dollars(10) == "" and gs.roubles == 500000 - 1450 and gs.dollars == 10, "10 dollars cost 1,450 roubles")
	check(trading.sell_dollars(10) == "" and gs.roubles == 500000 - 200 and gs.dollars == 0, "and sell for 1,250")
	check(gs.trader_loyalty.broker.spent == 0, "changing money doesn't count as money spent")
	check(trading.sell_dollars(1) == "Not enough dollars" and trading.buy_dollars(0) == "Pick an amount" and trading.buy_dollars(4000) == "Not enough roubles", "bad amounts are refused")
	var offer := _offer("broker", "broker_ammo_9x19_fmj")
	trading.buy_dollars(40)
	check(trading.buy("broker", offer) == "" and gs.dollars == 40 - 32 and gs.trader_loyalty.broker.spent == 32 * 140 and gs.stash.count_of("ammo_9x19_fmj") == 50,
		"a dollar offer takes dollars and counts them at 140 toward money spent")


func _no_resale() -> void:
	section("No resale profit")
	_profile()
	_unlock_broker()
	for trader: String in traders.ids():
		gs.trader_loyalty[trader].level = traders.max_loyalty(trader)
	var offers := 0
	var losing := 0
	var tightest := 1000.0
	var tightest_name := ""
	# The quick-buy bundle discount comes on top of loyalty prices: the least an offer can cost.
	var bundle: float = load("res://scripts/data/quick_buy_table.gd").bundle_discount()
	check(bundle > 0.0, "the quick-buy bundle discount is read (%.2f)" % bundle)
	for trader: String in traders.ids():
		for offer: Dictionary in trading.buy_list(trader):
			offers += 1
			var result := _resale(trader, offer, bundle)
			if result[0] <= 1.0:
				losing += 1
				print("    resale profit: %s %s costs %d, sells for %d to %s" % [trader, offer.id, result[1], result[2], result[3]])
			if result[0] < tightest:
				tightest = result[0]
				tightest_name = "%s (%d bought, %d sold to %s)" % [offer.id, result[1], result[2], result[3]]
	print("    tightest price / best resale: %.4f for %s" % [tightest, tightest_name])
	check(offers == 262 + trading.buy_list("mole").size(), "262 offers for money plus Mole's shelf are checked (%d)" % offers)
	check(losing == 0, "no offer, at its least (top loyalty and the quick-buy bundle price), sells on to any trader at top loyalty, whole or in parts, for its price or more")
	var shelf_losing := 0
	var shelf := 0
	for level in [1, 2, 3, 4]:
		gs.trader_loyalty.mole.level = level
		for number in [1, 2, 3, 4, 5, 6]:
			for offer: Dictionary in stock.used_offers_on("mole", number):
				shelf += 1
				if _resale("mole", offer)[0] <= 1.0:
					shelf_losing += 1
	check(shelf >= 8 * 24 and shelf_losing == 0, "nor does any of Mole's worn gear over 6 restocks at each of his levels (%d items)" % shelf)


## [price / best resale, the price in roubles, the best resale in roubles, who pays it] for `offer`: the
## price at the trader's level now less `bundle` (Trading.price()), against the most any trader pays for
## what it gives, whole or taken apart into its parts (each to whoever pays most).
func _resale(trader: String, offer: Dictionary, bundle := 0.0) -> Array:
	var cost: int = mini(trading.price(trader, offer), trading.price(trader, offer, bundle)) * (DOLLAR if offer.get("currency", "RUB") == "USD" else 1)
	var bought: RefCounted = trading.offer_item(offer)
	var whole := _best_paid(bought)
	var apart := _apart(bought)
	if apart[0] > whole[0]:
		return [float(cost) / maxi(apart[0], 1), cost, apart[0], "several traders (in parts)"]
	return [float(cost) / maxi(whole[0], 1), cost, whole[0], whole[1]]


## [the most a trader pays for `piece` whole, in roubles, who].
func _best_paid(piece: RefCounted) -> Array:
	var best := 0
	var best_trader := ""
	for buyer: String in traders.ids():
		var paid: int = selling.price(buyer, piece) * (DOLLAR if selling.currency(buyer) == "USD" else 1)
		if paid > best:
			best = paid
			best_trader = buyer
	return [best, best_trader]


## [what `piece` fetches taken apart: the bare item and each part (taken apart too) to whoever pays most].
func _apart(piece: RefCounted) -> Array:
	if piece.mods.is_empty():
		return _best_paid(piece)
	var bare: RefCounted = piece.duplicate_deep()
	bare.mods = {}
	var total: int = _best_paid(bare)[0]
	for part: RefCounted in piece.mods.values():
		total += maxi(_best_paid(part)[0], _apart(part)[0])
	return [total, ""]


func _barters() -> void:
	section("Barters")
	_profile()
	check(barters.problems().is_empty(), "BarterTable.problems() is empty")
	check(barters.all().size() == 155, "there are 155 barters (%d)" % barters.all().size())
	var asked := {}
	for barter: Dictionary in barters.all():
		for requirement in barters.requirements(barter):
			asked[requirement.item_id] = true
	var ItemDataScript: GDScript = load("res://scripts/data/item_data.gd")
	var unused_junk: Array = []
	var unused_valuables: Array = []
	var junk := 0
	var valuables := 0
	for data in db.all_items():
		if data.category == ItemDataScript.Category.JUNK:
			junk += 1
			if not asked.has(data.id):
				unused_junk.append(data.id)
		elif data.category == ItemDataScript.Category.VALUABLE:
			valuables += 1
			if not asked.has(data.id):
				unused_valuables.append(data.id)
	check(junk > 0 and unused_junk.is_empty(), "every one of the %d junk items is asked for by a barter %s" % [junk, str(unused_junk)])
	check(valuables > 0 and unused_valuables.is_empty(), "every one of the %d valuables is asked for by a barter %s" % [valuables, str(unused_valuables)])

	var barter: Dictionary = barters.find("bulat_barter_svd")
	check(int(barter.stock) == 1 and barters.level(barter) == 2 and barters.quest(barter) == "", "Bulat's SVD barter: LL2, one each restock, no quest")
	for requirement in barters.requirements(barter):
		_give(requirement.item_id, requirement.count, true)
	check(trading.barter(barter) == "Needs loyalty level 2", "it refuses at LL1")
	gs.trader_loyalty.bulat.level = 2
	check(not trading.shown_barters("bulat").is_empty() and trading.shown_barters("bulat").has(barter) and stock.left("bulat", barter) == 1, "at LL2 it shows, 1 left")
	var roubles: int = gs.roubles
	check(trading.barter(barter) == "", "the barter trades")
	var inputs_left := 0
	for requirement in barters.requirements(barter):
		inputs_left += gs.stash.count_of(requirement.item_id)
	check(inputs_left == 0, "what it asks for leaves the stash")
	var rewards_ok := true
	for reward: Dictionary in barters.rewards(barter):
		rewards_ok = rewards_ok and gs.stash.count_of(str(reward.item)) >= int(reward.get("count", 1)) and _fir_count(str(reward.item)) == 0
	check(rewards_ok and gs.stash.count_of("svd") == 1, "every reward arrives, not found in raid")
	check(gs.roubles == roubles and stock.left("bulat", barter) == 0, "it costs no money and its stock counts down")
	check(is_equal_approx(gs.trader_loyalty.bulat.barter_reputation, 0.01) and is_equal_approx(gs.trader_loyalty.bulat.reputation, 0.06),
		"a barter adds 0.01 reputation with the trader")
	for requirement in barters.requirements(barter):
		_give(requirement.item_id, requirement.count, true)
	check(trading.barter(barter).begins_with("Sold out until the restock") and gs.stash.count_of("svd") == 1, "sold out: a second one refuses")

	var plain: Dictionary = barters.find("bulat_barter_ammo_762x39_ps")
	_give("bolts", 2, false)
	_give("screws", 2, false)
	check(trading.barter(plain) == "Missing from the stash: Bolts ×2 found in raid" and gs.stash.count_of("ammo_762x39_ps") == 0,
		"a barter asking for found-in-raid bolts refuses bought ones")
	gs.stash.take("bolts", gs.stash.count_of("bolts"))
	_give("bolts", 2, true)
	check(trading.barter(plain) == "" and gs.stash.count_of("ammo_762x39_ps") == 120 and gs.stash.count_of("bolts") == 0 and gs.stash.count_of("screws") == 0,
		"with found-in-raid bolts it gives 120 rounds")

	var locked: Dictionary = barters.find("vera_barter_propital")
	gs.trader_loyalty.vera.level = 3
	for requirement in barters.requirements(locked):
		_give(requirement.item_id, requirement.count, true)
	check(barters.quest(locked) == "sanitary_standards" and trading.barter(locked) == "Unlocks after Sanitary Standards" and gs.stash.count_of("propital") == 0
		and gs.stash.count_of("gold_chain") == 1, "a quest-locked barter refuses and takes nothing")
	gs.quests["sanitary_standards"] = {"state": "completed", "progress": [1]}
	check(trading.barter(locked) == "" and gs.stash.count_of("propital") == 1 and gs.stash.count_of("gold_chain") == 0, "once the quest is done it trades")


func _mole() -> void:
	section("Mole and Scav karma")
	_profile()
	check(traders.follows_karma("mole") and traders.karma_levels("mole") == [1.0, 3.0, 5.0] and not traders.follows_karma("bulat"), "Mole's levels need karma 1, 3 and 5")
	for step: Array in [[0.0, 1], [0.99, 1], [1.0, 2], [2.99, 2], [3.0, 3], [5.0, 4], [6.0, 4], [-3.0, 1]]:
		gs.scav_karma = step[0]
		trading.update_all_loyalty()
		check(gs.trader_loyalty.mole.level == step[1], "karma %+.2f: Mole is LL%d" % [step[0], step[1]])
	gs.level = 60
	gs.trader_loyalty.mole.reputation = 1.0
	gs.trader_loyalty.mole.spent = 99000000
	gs.scav_karma = 0.0
	check(not trading.update_loyalty("mole") and gs.trader_loyalty.mole.level == 1, "level, reputation and money spent don't raise him")
	check(is_equal_approx(selling.rate("mole"), 0.3), "at karma 0 Mole pays 30%")
	gs.scav_karma = -2.0
	check(is_equal_approx(selling.rate("mole"), 0.26), "at karma -2 he pays 26%")
	gs.scav_karma = 5.0
	trading.update_loyalty("mole")
	check(is_equal_approx(selling.rate("mole"), 0.39), "at LL4 he pays 39%")


func _levels() -> void:
	section("Player level")
	_profile()
	check(progression.level_for_xp(0) == 1 and progression.level_for_xp(799) == 1 and progression.level_for_xp(800) == 2
		and progression.level_for_xp(2650) == 3, "levels 2 and 3 start at 800 and 2,650 XP")
	check(progression.max_level() == 50 and progression.level_for_xp(569000) == 50 and progression.level_for_xp(568999) == 49
		and progression.level_for_xp(99999999) == 50, "level 50 at 569,000 XP is the last")
	check(progression.xp_for_level(15) == 69500, "level 15 needs 69,500 XP")
	check(gs.add_xp(799) == 0 and gs.level == 1, "799 XP: still level 1")
	check(gs.add_xp(1) == 1 and gs.level == 2 and gs.xp == 800, "one more: level 2")
	check(gs.add_xp(8000) == 3 and gs.level == 5, "8,000 more: three levels at once")
	check(gs.add_xp(-500) == 0 and gs.xp == 8800 and gs.level == 5, "negative XP is ignored")


func _hideout() -> void:
	section("Hideout and crafting")
	_profile()
	var generator: Dictionary = hideout.find("generator")
	check(hideout.level(generator) == 0 and hideout.upgrade(generator) == "Missing items" and gs.roubles == 500000, "the generator needs a fuel can")
	_give("fuel_can")
	check(hideout.upgrade(generator) == "" and hideout.level(generator) == 1, "with one it's built")
	check(gs.roubles == 450000 and gs.stash.count_of("fuel_can") == 0, "50,000 roubles and the fuel can are taken")

	var stash_station: Dictionary = hideout.find("stash")
	_give("bolts", 5)
	_give("screws", 5)
	_give("duct_tape", 2)
	gs.roubles = 600000
	check(hideout.upgrade(stash_station) == "Needs Bulat LL2" and gs.stash.size == Vector2i(10, 30), "the Stash's level 2 needs Bulat LL2")
	gs.trader_loyalty.bulat.level = 2
	var marker := item("gold_chain")
	gs.stash.place(marker, Vector2i(9, 29), false)
	var kept: Dictionary = {}
	for each in gs.stash.items:
		if not each.data.id in ["bolts", "screws", "duct_tape"]:
			kept[each] = [each.cell, each.count]
	check(hideout.upgrade(stash_station) == "" and gs.hideout.stash == 2 and gs.roubles == 100000, "then it's built for 500,000")
	check(gs.stash.size == Vector2i(10, 40) and hideout.stash_size() == Vector2i(10, 40), "the stash is 10x40")
	var moved := 0
	for each: RefCounted in kept:
		if not each in gs.stash.items or each.cell != kept[each][0] or each.count != kept[each][1]:
			moved += 1
	check(moved == 0 and kept.size() == 15 and gs.stash.item_at(Vector2i(9, 29)) == marker, "every other item is kept where it was")
	check(search.count("bolts", false) == 2 and search.count("screws", false) == 0 and search.count("duct_tape", false) == 0,
		"5 bolts, 5 screws and 2 rolls of duct tape are taken")
	check(gs.stash.place(item("bolts"), Vector2i(0, 39), false), "the new rows take items")

	var medstation: Dictionary = hideout.find("medstation")
	var recipe: Dictionary = hideout.all_crafts(medstation)[0][1]
	check(recipe.id == "medkit" and hideout.craft(medstation, recipe) == "Upgrade the station first", "a craft needs its station built")
	check(search.count("bandage", false) == 4 and hideout.upgrade(medstation) == "" and search.count("bandage", false) == 2 and gs.roubles == 70000,
		"the medstation is built with two of your four bandages and 30,000 roubles")
	check(hideout.craft(medstation, recipe) == "Missing items", "the medkit craft needs duct tape too")
	_give("duct_tape")
	check(hideout.craft(medstation, recipe) == "" and gs.stash.count_of("ai2_medkit") == 2 and _fir_count("ai2_medkit") == 1,
		"the craft makes a found-in-raid medkit")
	check(search.count("bandage", false) == 0 and search.count("duct_tape", false) == 0, "and uses up two bandages and the duct tape")


func _sum(counts: Dictionary) -> int:
	var total := 0
	for key: Variant in counts:
		total += int(counts[key])
	return total
