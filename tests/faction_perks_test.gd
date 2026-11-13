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
var quests: GDScript
var barters: GDScript

const BEAR_LINE := ["bear_old_unit", "bear_contractors", "bear_ground_truth", "bear_radio_silence", "bear_last_word"]
const USEC_LINE := ["usec_contract_renewal", "usec_hostile_contact", "usec_site_survey", "usec_data_recovery", "usec_clean_exfil"]


func run() -> void:
	trading = load("res://scripts/progression/trading.gd")
	factions = load("res://scripts/data/factions.gd")
	stock = load("res://scripts/progression/trader_stock.gd")
	quick = load("res://scripts/progression/quick_buy.gd")
	money = func(amount: int, currency := "RUB") -> String: return load("res://scripts/ui/ui_format.gd").money(amount, currency)
	quests = load("res://scripts/progression/quest_log.gd")
	barters = load("res://scripts/data/barter_table.gd")
	_discount()
	_floor()
	_other_faction()
	await _panel()
	_hidden()
	_chain_bear()
	_chain_usec()
	_counts()
	_validator()
	_save()
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


func _ids(list: Array) -> Array:
	return list.map(func(quest: Dictionary) -> String: return str(quest.id))


## `amount` found-in-raid `id` in the stash, one by one.
func _give_fir(id: String, amount: int) -> void:
	for i in amount:
		var piece: RefCounted = item(id)
		piece.fir = true
		gs.stash.add(piece)


func _hidden() -> void:
	section("Each faction sees only its own line")
	for faction in [0, 1]:
		_profile(faction)
		var own: Array = [BEAR_LINE, USEC_LINE][faction]
		var other: Array = [USEC_LINE, BEAR_LINE][faction]
		var trader: String = ["bulat", "tinker"][faction]
		var name: String = ["BEAR", "USEC"][faction]
		var listed: Array = _ids(quests.for_trader(trader))
		check(own.all(func(id: String) -> bool: return id in listed) and _ids(quests.for_trader(trader)).filter(func(id: String) -> bool: return id in own) == own,
			"%s: %s lists the five %s quests, in chain order" % [name, trader, name])
		var everywhere: Array = []
		for each: String in load("res://scripts/data/trader_table.gd").ids():
			everywhere.append_array(_ids(quests.for_trader(each)))
		check(other.all(func(id: String) -> bool: return not id in everywhere and not id in _ids(quests.shown())), "%s: no trader lists the other line" % name)
		var stranger: Dictionary = quests.find(other[0])
		check(quests.lock_reason(stranger) == "For %s only" % ["USEC", "BEAR"][faction] and quests.state(stranger) == "locked" and not quests.accept(stranger)
			and not gs.quests.has(other[0]), "%s: the other line's first quest can't be accepted (%s)" % [name, quests.lock_reason(stranger)])
		check(quests.state(quests.find(own[0])) == "available" and quests.lock_reason(quests.find(own[0])) == "", "%s: its own first quest is available at once" % name)


## Completes `id` the quick way (the chain section plays the real objectives).
func _complete(id: String) -> void:
	var count: int = quests.find(id).objectives.size()
	var progress := []
	progress.resize(count)
	progress.fill(0)
	gs.quests[id] = {"state": "completed", "progress": progress}


func _chain_bear() -> void:
	section("The BEAR line, quest by quest")
	_profile(0)
	gs.level = 1
	var old: Dictionary = quests.find("bear_old_unit")
	var next: Dictionary = quests.find("bear_contractors")
	check(quests.lock_reason(next) == "Needs player level 5  ·  finish Old Unit first", "Contractors waits for level 5 and Old Unit (%s)" % quests.lock_reason(next))
	check(quests.accept(old) and quests.state(old) == "active", "Old Unit is accepted")
	check(quests.objective_text(old, 0) == "Survive and extract" and quests.hand_in(old, 0) == 0, "its extract objective is counted in raids, not handed over")
	# A real raid end: killed, then extracted. Only a PMC raid survived counts.
	var outcome: GDScript = load("res://scripts/raid/raid_outcome.gd")
	var inventory: RefCounted = load("res://scripts/inventory/inventory.gd").new()
	outcome.settle(outcome.Status.KILLED, "pmc", inventory, 600.0, 0, 0, true, {}, {"kill_list": [], "map": "factory"})
	check(quests.progress(old, 0) == 0, "killed in raid: no extract")
	outcome.settle(outcome.Status.SURVIVED, "scav", load("res://scripts/inventory/inventory.gd").new(), 600.0, 0, 0, true, {}, {"kill_list": [], "map": "factory"})
	check(quests.progress(old, 0) == 0, "a Scav run doesn't count")
	outcome.settle(outcome.Status.RUN_THROUGH, "pmc", gs.inventory, 60.0, 0, 0, true, {}, {"kill_list": [], "map": "factory"})
	check(quests.progress(old, 0) == 0, "nor a Run Through")
	outcome.settle(outcome.Status.SURVIVED, "pmc", gs.inventory, 900.0, 0, 0, true, {}, {"kill_list": [], "map": "factory"})
	check(quests.progress(old, 0) == 1 and quests.state(old) == "active", "extracting from Factory does (1 / 1), the hand-in still to do")
	_give_fir("tushonka", 2)
	check(quests.hand_in(old, 1) == 2 and quests.state(old) == "ready", "two found-in-raid tushonka handed over: ready")
	var roubles: int = gs.roubles
	var reputation: float = gs.trader_loyalty.bulat.reputation
	var rounds: int = gs.stash.count_of("ammo_545_ps")
	check(quests.complete(old) == "" and gs.roubles == roubles + 30000 and is_equal_approx(gs.trader_loyalty.bulat.reputation, reputation + 0.04)
		and gs.stash.count_of("ammo_545_ps") == rounds + 60, "turned in: ₽ 30,000, +0.04 with Bulat, 60 × 5.45x39 PS")
	check(quests.lock_reason(next) == "Needs player level 5", "Contractors now only waits for level 5")
	gs.level = 5
	check(quests.accept(next) and quests.objective_text(next, 0) == "Kill USEC operators", "at level 5 it's accepted: %s" % quests.objective_text(next, 0))
	var kills := [{"name": "a", "side": "pmc", "faction": "usec"}, {"name": "b", "side": "pmc", "faction": "bear"}, {"name": "c", "side": "scav"},
		{"name": "d", "side": "pmc", "faction": "usec"}]
	outcome.settle(outcome.Status.KILLED, "pmc", load("res://scripts/inventory/inventory.gd").new(), 600.0, 0, 4, true, {}, {"kill_list": kills, "map": "woodland"})
	check(quests.progress(next, 0) == 2, "a raid's kills: the two USEC count, the BEAR and the Scav don't, dead or alive (%d / 3)" % quests.progress(next, 0))
	quests.record_raid([{"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"}], false, "labs")
	check(quests.progress(next, 0) == 3 and quests.state(next) == "ready", "never past the count (3 / 3): ready")
	check(quests.complete(next) == "" and gs.stash.count_of("zsh_helmet") == 1, "the reward: a ZSh-1-2M helmet")
	gs.level = 10
	var survey: Dictionary = quests.find("bear_ground_truth")
	check(quests.accept(survey) and quests.objective_text(survey, 0) == "Explore points of interest on Customs Yard" and quests.objective_text(survey, 1) == "Survive and extract from Customs Yard",
		"Ground Truth: %s, %s" % [quests.objective_text(survey, 0), quests.objective_text(survey, 1)])
	var pois: Array = load("res://scripts/data/poi_table.gd").for_map("customs_yard")
	gs.explore("customs_yard", str(pois[0].id))
	check(quests.progress(survey, 0) == 1, "a point explored counts at once (1 / 6)")
	for poi: Dictionary in pois.slice(1, 8):
		gs.explore("customs_yard", str(poi.id))
	check(quests.progress(survey, 0) == 6, "eight explored: 6 / 6, no more")
	quests.record_raid([], true, "factory")
	check(quests.progress(survey, 1) == 0, "extracting from Factory isn't Customs Yard")
	quests.record_raid([], true, "customs_yard")
	check(quests.state(survey) == "ready" and quests.complete(survey) == "" and gs.stash.count_of("armor_6b23") == 1, "from Customs Yard it is: the reward, 6B23-1 armor")
	gs.level = 15
	var radio: Dictionary = quests.find("bear_radio_silence")
	quests.accept(radio)
	quests.record_raid([{"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"},
		{"side": "pmc", "faction": "usec"}], false, "shoreline")
	var radio_item: RefCounted = item("vhf_radio")
	gs.stash.add(radio_item)
	check(quests.hand_in(radio, 1) == 0, "a VHF radio not found in raid isn't taken")
	_give_fir("vhf_radio", 1)
	check(quests.hand_in(radio, 1) == 1 and quests.complete(radio) == "" and gs.stash.count_of("grizzly_74") == 1, "a found one is: the reward, a Grizzly 74")
	var last: Dictionary = quests.find("bear_last_word")
	check(quests.lock_reason(last) == "Needs player level 20", "Last Word waits for level 20")
	var kit: Dictionary = barters.find("bulat_barter_bear_tundra_kit")
	check(not kit.is_empty() and barters.quest(kit) == "bear_last_word" and barters.quest_block_reason(kit) == "Unlocks after Last Word" and barters.for_trader("bulat").has(kit),
		"Bulat's BEAR barter shows, waiting for Last Word")
	gs.level = 20
	quests.accept(last)
	check(quests.objective_text(last, 0) == "Kill USEC operators on Woodland", "Last Word: %s" % quests.objective_text(last, 0))
	quests.record_raid([{"side": "pmc", "faction": "usec"}], true, "factory")
	check(quests.progress(last, 0) == 0 and quests.progress(last, 1) == 0, "a kill and an extract on Factory count for neither")
	quests.record_raid([{"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"}], true, "woodland")
	quests.record_raid([{"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "usec"}], true, "woodland")
	check(quests.state(last) == "ready" and quests.complete(last) == "", "six on Woodland and two extracts there: done")
	check(barters.quest_block_reason(kit) == "" and trading.barter_block_reason(kit, "bulat") == "Needs loyalty level 3", "the barter is open, at LL3")
	gs.trader_loyalty.bulat.level = 3
	_give_fir("military_medal", 1)
	_give_fir("vodka", 2)
	var guns: int = gs.stash.count_of("tundra_47")
	check(trading.barter(kit, "bulat") == "" and gs.stash.count_of("tundra_47") == guns + 1 and gs.stash.count_of("akm_mag_40") == 2
		and gs.stash.count_of("military_medal") == 0, "and trades: a military medal and two vodka for a Tundra 47, two 40-round magazines and 40 rounds")


func _chain_usec() -> void:
	section("The USEC line")
	_profile(1)
	gs.level = 20
	for id: String in USEC_LINE.slice(0, 4):
		_complete(id)
	var last: Dictionary = quests.find("usec_clean_exfil")
	check(quests.state(last) == "available" and quests.accept(last), "with the first four done, Clean Exfil is accepted")
	quests.record_raid([{"side": "pmc", "faction": "usec"}, {"side": "pmc", "faction": "bear"}], true, "factory")
	check(quests.progress(last, 0) == 1 and quests.progress(last, 1) == 1 and quests.objective_text(last, 0) == "Kill BEAR operators on Factory",
		"only the BEAR kill counts for USEC (%s)" % quests.objective_text(last, 0))
	var sentinel: Dictionary = barters.find("tinker_barter_usec_sentinel_ar")
	check(barters.for_trader("tinker").has(sentinel) and not barters.for_trader("bulat").has(barters.find("bulat_barter_bear_tundra_kit")),
		"USEC sees Tinker's barter, not Bulat's BEAR one")
	var rewards: Dictionary = {}
	for id: String in USEC_LINE:
		var quest: Dictionary = quests.find(id)
		for reward: Dictionary in quest.rewards.get("items", []):
			rewards[str(reward.item)] = true
		check(int(quest.rewards.roubles) > 0 and float(quest.rewards.reputation) > 0.0 and int(quest.rewards.xp) > 0, "%s pays money, reputation and experience" % quest.name)
	check(rewards.has("fast_helmet") and rewards.has("armor_mmac") and rewards.has("hornet_smg"), "USEC's rewards: a FAST helmet, an MMAC carrier, a Hornet SMG")


func _counts() -> void:
	section("Quest counts go by the quests you can see")
	_profile(0)
	var everyone: int = quests.all().filter(func(quest: Dictionary) -> bool: return quests.faction_of(quest) == &"").size()
	check(quests.shown().size() == everyone + 5 and quests.shown(&"usec").size() == everyone + 5 and quests.all().size() == everyone + 10,
		"%d quests for everyone, five more for each faction" % everyone)
	for id: String in USEC_LINE:
		_complete(id)  # A save edited by hand: the other line marked done.
	check(quick.tasks_completed() == 0, "the other faction's completed quests don't count toward quick-buy tasks")
	_complete("bear_old_unit")
	_complete("scrap_run")
	check(quick.tasks_completed() == 2, "your own do (2)")
	var uses: Array = load("res://scripts/progression/item_uses.gd").of("tushonka")
	check(uses.any(func(use: Dictionary) -> bool: return "Old Unit" in str(use.name)) == false, "Old Unit done: tushonka is no longer needed for it")
	_profile(0)
	var bear_uses: Array = load("res://scripts/progression/item_uses.gd").of("ssd_drive").map(func(use: Dictionary) -> String: return str(use.name))
	var bear_medal: Array = load("res://scripts/progression/item_uses.gd").of("military_medal").map(func(use: Dictionary) -> String: return str(use.name))
	_profile(1)
	var usec_uses: Array = load("res://scripts/progression/item_uses.gd").of("ssd_drive").map(func(use: Dictionary) -> String: return str(use.name))
	var usec_medal: Array = load("res://scripts/progression/item_uses.gd").of("military_medal").map(func(use: Dictionary) -> String: return str(use.name))
	check(not bear_uses.any(func(name: String) -> bool: return "Data Recovery" in name) and usec_uses.any(func(name: String) -> bool: return "Data Recovery" in name),
		"an SSD is needed for Data Recovery for USEC only")
	check(bear_medal.any(func(name: String) -> bool: return "Tundra 47" in name) and not usec_medal.any(func(name: String) -> bool: return "Tundra 47" in name),
		"a military medal is used for Bulat's BEAR barter for BEAR only")
	var hidden: int = trading.hidden_barters("bulat").values().reduce(func(sum: int, count: int) -> int: return sum + count, 0)
	check(not trading.shown_barters("bulat").has(barters.find("bulat_barter_bear_tundra_kit")) and hidden + trading.shown_barters("bulat").size() == barters.for_trader("bulat").size()
		and barters.for_trader("bulat").size() == barters.all().filter(func(each: Dictionary) -> bool: return each.trader == "bulat").size() - 1,
		"USEC: Bulat's BEAR barter isn't shown or counted for a later level")


func _validator() -> void:
	section("The quest check")
	check(quests.problems().is_empty(), "QuestLog.problems() is empty (%s)" % str(quests.problems()))
	var all: Array = quests.all()
	var contractors: Dictionary = quests.find("bear_contractors")
	var keep: Dictionary = contractors.duplicate(true)
	var broken := [
		["a faction that doesn't exist", func() -> void: contractors.faction = "scav", "faction scav isn't bear or usec"],
		["a quest required before it's listed", func() -> void: contractors.requires = ["bear_last_word"], "requires bear_last_word, which isn't a quest listed before it"],
		["a quest that doesn't exist", func() -> void: contractors.requires = ["no_such_quest"], "requires no_such_quest"],
		["the other faction's quest", func() -> void: contractors.requires = ["usec_contract_renewal"], "requires usec_contract_renewal, which isn't"],
		["an unknown objective", func() -> void: contractors.objectives = [{"type": "dance", "count": 1}], "isn't one of"],
		["a kill faction that isn't one", func() -> void: contractors.objectives = [{"type": "kill", "target": "pmc", "faction": "scav", "count": 1}], "kill faction scav"],
		["a map that doesn't exist", func() -> void: contractors.objectives = [{"type": "extract", "map": "moon", "count": 1}], "map moon doesn't exist"],
		["more points than the map has", func() -> void: contractors.objectives = [{"type": "explore", "map": "factory", "count": 13}], "13 points to explore on factory, which has 12"],
		["a reward that isn't an item", func() -> void: contractors.rewards = {"items": [{"item": "no_such_item"}]}, "isn't an item"],
	]
	for entry: Array in broken:
		for key: String in contractors.keys():
			contractors.erase(key)
		contractors.merge(keep.duplicate(true))
		entry[1].call()
		var found: Array = quests.problems()
		check(found.any(func(problem: String) -> bool: return entry[2] in problem), "the check catches %s (%s)" % [entry[0], str(found)])
	for key: String in contractors.keys():
		contractors.erase(key)
	contractors.merge(keep)
	var everyone: Dictionary = quests.find("scrap_run")
	everyone.requires = ["bear_old_unit"]
	check(quests.problems().any(func(problem: String) -> bool: return "quest scrap_run: requires bear_old_unit, a quest for bear only" in problem), "a quest for everyone can't wait for a faction's")
	everyone.erase("requires")
	check(quests.problems().is_empty() and all.size() == quests.all().size(), "the real data is back without problems")


func _save() -> void:
	section("Save round trip")
	_profile(1)
	gs.level = 10
	_complete("usec_contract_renewal")
	gs.quests["usec_hostile_contact"] = {"state": "active", "progress": [2]}
	gs.trader_loyalty.tinker.level = 2
	check(sm.save_game(), "saved")
	gs.new_profile(gs.Faction.BEAR)
	check(sm.load_game() and gs.faction == gs.Faction.USEC, "loaded back: USEC")
	var contact: Dictionary = quests.find("usec_hostile_contact")
	check(quests.state(quests.find("usec_contract_renewal")) == "completed" and quests.state(contact) == "active" and quests.progress(contact, 0) == 2,
		"the line's progress is kept (Contract Renewal done, Hostile Contact 2 / 3)")
	check(trading.price("tinker", _offer("tinker", "tinker_wires")) == roundi(10000 * (1.0 - 0.03) * (1.0 - 0.05)), "and the discount at Tinker's with the loyalty level")
	sm.delete_save()
