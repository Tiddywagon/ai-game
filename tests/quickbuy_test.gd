extends "res://tests/test_base.gd"
## Quick buy (DESIGN.md §16.6) and loyalty prices: the card loader's checks (a crafted bad card for each
## rule), faction cards, unlock rules, prices (every card: the lines less 10%, held at the floor, lower at
## LL4, as DESIGN's table says), buying with a realistic kit (nothing lost or made, the secure container
## untouched, stock, money spent, not found in raid), dollars, a full stash, each substitution rule,
## nothing to stand in, custom cards (through a save, five at most, left-outs kept), the save upgrade and
## the time a full stash takes; then the QUICK BUY tab on the LOADOUT screen: the tab keys (not while
## typing or with a window open), the cards, the confirm dialog's focus and shade, CONFIRM once, and the
## dialog and CONFIRM times on a full stash.

const NOW := 1_000_000.0

var table: GDScript
var quick: GDScript
var trading: GDScript
var stock: GDScript
var traders: GDScript
var mods: GDScript


func run() -> void:
	table = load("res://scripts/data/quick_buy_table.gd")
	quick = load("res://scripts/progression/quick_buy.gd")
	trading = load("res://scripts/progression/trading.gd")
	stock = load("res://scripts/progression/trader_stock.gd")
	traders = load("res://scripts/data/trader_table.gd")
	mods = load("res://scripts/inventory/weapon_mods.gd")
	_loader()
	_factions_and_unlocks()
	_prices()
	_buying()
	_dollars_and_room()
	_substitutes()
	_custom()
	_timing()
	await _screen()
	stock.now_override = -1.0


## A new profile (BEAR, or USEC) at a fixed time, The Broker unlocked when `broker`.
func _profile(usec := false, broker := false) -> void:
	stock.now_override = NOW
	fresh_profile(1 if usec else 0)
	gs.roubles = 50_000_000
	gs.dollars = 100_000
	if broker:
		gs.quests["zoya_introduction"] = {"state": "completed", "progress": [1, 2, 150000]}


## Every trader at `level` (or each at what `card`'s unlock asks, LL1 for the rest).
func _levels(level: int, card := {}) -> void:
	for trader: String in gs.trader_loyalty:
		gs.trader_loyalty[trader].level = int(card.get("unlock", {}).get("loyalty", {}).get(trader, 1)) if not card.is_empty() else level


func _card(id: String) -> Dictionary:
	return table.find(id)


## `card` with its unlock met: loyalty levels, tasks and quests.
func _meet(card: Dictionary) -> void:
	_levels(1, card)
	var unlock: Dictionary = card.get("unlock", {})
	var needed: int = int(unlock.get("tasks", 0))
	for id: Variant in unlock.get("quests", []):
		gs.quests[str(id)] = {"state": "completed", "progress": []}
	for quest: Dictionary in load("res://scripts/progression/quest_log.gd").all():
		if quick.tasks_completed() >= needed:
			break
		gs.quests[quest.id] = {"state": "completed", "progress": []}


func _line(plan: Dictionary, item_id: String) -> Dictionary:
	for line: Dictionary in plan.lines:
		if line.wanted == item_id:
			return line
	return {}


func _problems_of(card: Dictionary) -> Array:
	return table.card_problems(card)


## True if one of `problems` contains `text`.
func _has(problems: Array, text: String) -> bool:
	return problems.any(func(problem: String) -> bool: return problem.contains(text))


func _loader() -> void:
	section("Cards and the loader's checks")
	_profile(false, true)
	check(table.problems().is_empty(), "QuickBuyTable.problems() is empty (%s)" % str(table.problems()))
	check(table.all().size() == 10, "there are ten cards (%d)" % table.all().size())
	check(table.all()[0].id == "last_resort" and table.all()[-1].id == "iron_wall", "the cheapest unlock first, the LL4 kit last")
	var good: Dictionary = _card("workhorse").duplicate(true)
	check(_problems_of(good).is_empty(), "a copy of Workhorse passes")
	var cases := [
		["an item that doesn't exist", func(card: Dictionary) -> void: card.gear.helmet.item = "no_such_helmet", "doesn't exist"],
		["an item in the wrong slot", func(card: Dictionary) -> void: card.gear.helmet = {"item": "armor_6b23", "trader": "stitch"}, "doesn't go in the helmet slot"],
		["a trader who doesn't sell it", func(card: Dictionary) -> void: card.gear.helmet.trader = "vera", "isn't sold for money by vera"],
		["a level the unlock doesn't reach", func(card: Dictionary) -> void: card.unlock.loyalty.stitch = 1, "above the unlock's LL1"],
		["The Broker without his quest", func(card: Dictionary) -> void:
			card.unlock.loyalty.broker = 2
			card.gear.helmet = {"item": "fast_helmet", "trader": "broker"}, "must list the quest zoya_introduction"],
		["more tasks than quests", func(card: Dictionary) -> void: card.unlock.tasks = 99, "99 tasks completed can't be reached"],
		["a quest that doesn't exist", func(card: Dictionary) -> void: card.unlock.quests = ["no_such_quest"], "quests that exist"],
		["a part that doesn't fit", func(card: Dictionary) -> void: card.parts.primary[0].item = "stanag_30", "doesn't fit"],
		["parts out of order", func(card: Dictionary) -> void: card.parts.primary = [card.parts.primary[1], card.parts.primary[0], card.parts.primary[2]], "No such slot"],
		["rounds for no gun", func(card: Dictionary) -> void: card.rounds[0]["for"] = "secondary", "don't match a gun"],
		["rounds of another caliber", func(card: Dictionary) -> void: card.rounds[0].item = "ammo_9x18_p"; card.rounds[0].count = 100, "don't match a gun"],
		["too few rounds", func(card: Dictionary) -> void: card.rounds[0].count = 0, "needs a count of 1 or more"],
		["rounds not in whole packs", func(card: Dictionary) -> void: card.rounds[0].count = 90, "whole packs of 60"],
		["gear with a count", func(card: Dictionary) -> void: card.gear.helmet["count"] = 2, "must have a count of 1"],
		["more than the stock", func(card: Dictionary) -> void:
			card.gear.helmet = {"item": "fast_helmet", "trader": "stitch"}
			card.carried.append({"item": "fast_helmet", "trader": "stitch", "count": 2}), "which sells 2 each restock"],
		["a kit that doesn't fit", func(card: Dictionary) -> void: card.carried.append({"item": "salewa", "trader": "vera", "count": 40}), "doesn't fit on an empty character"],
		["a wrong faction", func(card: Dictionary) -> void: card.faction = "scav", "isn't bear or usec"],
		["no name", func(card: Dictionary) -> void: card.name = " ", "needs a name"],
	]
	for case: Array in cases:
		var card: Dictionary = good.duplicate(true)
		(case[1] as Callable).call(card)
		var found := _problems_of(card)
		check(_has(found, case[2]), "caught: %s (%s)" % [case[0], str(found)])
	var two_mags: Dictionary = _card("last_resort").duplicate(true)
	two_mags.gear.pistol = {"item": "strelka_mp", "trader": "bulat"}
	two_mags.unlock.loyalty = {"bulat": 2}
	check(_has(_problems_of(two_mags), "is less than 2 magazines of the Strelka MP (40)") == false and _problems_of(two_mags).is_empty(),
		"50 rounds for a Strelka (two 20-round magazines are 40) pass")
	two_mags.rounds[0].count = 0
	check(not _problems_of(two_mags).is_empty(), "no rounds at all don't")
	var stingy: Dictionary = _card("taiga_patrol").duplicate(true)
	stingy.rounds[0].count = 40
	check(_has(_problems_of(stingy), "less than 2 magazines of the Tundra 47 (80)"), "40 rounds for a Tundra with a 40-round magazine are too few")


func _factions_and_unlocks() -> void:
	section("Factions and unlocks")
	_profile()
	var ids: Array = quick.cards().map(func(card: Dictionary) -> String: return card.id)
	check(ids.size() == 9 and "taiga_patrol" in ids and not "contract_work" in ids, "BEAR sees nine cards, Taiga Patrol and not Contract Work")
	_profile(true)
	ids = quick.cards().map(func(card: Dictionary) -> String: return card.id)
	check(ids.size() == 9 and "contract_work" in ids and not "taiga_patrol" in ids, "USEC sees Contract Work and not Taiga Patrol")
	check(_card("taiga_patrol").faction == "bear" and _card("contract_work").faction == "usec", "the two faction cards say so")
	_profile()
	check(quick.is_unlocked(_card("last_resort")), "Last Resort is open from the start")
	check(quick.missing(_card("doorkicker")) == ["1 tasks completed (0 so far)"], "Doorkicker needs a task first (%s)" % str(quick.missing(_card("doorkicker"))))
	var wall: Dictionary = _card("iron_wall")
	check(quick.missing(wall) == ["Bulat LL3", "Stitch LL4", "Tinker LL2", "Doc Vera LL3", "14 tasks completed (0 so far)"],
		"Iron Wall lists every level and the tasks (%s)" % str(quick.missing(wall)))
	var plan: Dictionary = quick.plan(wall)
	check(plan.reasons[0].begins_with("Locked: needs Bulat LL3") and quick.buy(plan, gs.inventory, gs.stash).ok == false, "a locked card can't be bought")
	gs.quests["scrap_run"] = {"state": "completed", "progress": []}
	check(quick.missing(wall)[-1] == "14 tasks completed (1 so far)", "the tasks count up")
	var contract: Dictionary = _card("contract_work")
	_profile(true)
	_levels(1, contract)
	check(quick.missing(contract).has("Quest: A Word in His Ear"), "Contract Work needs The Broker's quest (%s)" % str(quick.missing(contract)))
	_meet(contract)
	check(quick.is_unlocked(contract), "with the quest, the levels and 10 tasks it's open")


func _prices() -> void:
	section("Prices")
	_profile(false, true)
	var bundle: float = table.bundle_discount()
	check(is_equal_approx(bundle, 0.1), "the bundle discount is 10%")
	var design := FileAccess.get_file_as_string("res://DESIGN.md")
	# DESIGN's card table is without the faction discount (the faction's own trader takes it off their lines).
	var perks: Dictionary = load("res://scripts/data/factions.gd").data().perks
	var perk: float = perks.trader_discount
	perks.trader_discount = 0.0
	for card: Dictionary in table.all():
		_levels(1, card)
		var at_unlock: Dictionary = quick.plan(card)
		var sum := 0
		var full := 0
		var floored := true
		for line: Dictionary in at_unlock.lines:
			var unit: int = trading.price(line.trader, line.offer)
			var cut: int = trading.price(line.trader, line.offer, bundle)
			var rate := 145 if line.currency == "USD" else 1
			sum += cut * int(line.packs) * rate
			full += unit * int(line.packs) * rate
			floored = floored and cut >= mini(trading.offer_floor(line.offer), int(line.offer.price)) and cut <= roundi(unit * (1.0 - bundle)) + 1
		var paid: int = int(at_unlock.roubles) + int(at_unlock.dollars) * 145
		check(at_unlock.swaps == 0 and at_unlock.left_out == 0 and sum == paid and full == int(at_unlock.full_roubles) + int(at_unlock.full_dollars) * 145
			and floored, "%s: the lines less 10%% (each held at its floor) are its price, %d" % [card.id, paid])
		_levels(4)
		var top: Dictionary = quick.plan(card)
		var paid_top: int = int(top.roubles) + int(top.dollars) * 145
		check(paid_top < paid, "%s: cheaper at LL4 (%d < %d)" % [card.id, paid_top, paid])
		var row := "| %s " % card.name
		var at := design.find(row)
		var cells := design.substr(at, design.find("\n", at) - at).split("|") if at >= 0 else PackedStringArray()
		var shown := [_money(at_unlock), _money(top)]
		check(cells.size() >= 6 and cells[-3].strip_edges() == shown[0] and cells[-2].strip_edges() == shown[1],
			"%s: DESIGN's card table says %s at unlock and %s at LL4 (%s)" % [card.name, shown[0], shown[1], str(cells)])
	# With it, a BEAR character pays less for Bulat's lines only: Workhorse at LL4, line by line.
	var workhorse: Dictionary = _card("workhorse")
	_levels(4)
	var without: Dictionary = quick.plan(workhorse)
	perks.trader_discount = perk
	var with_perk: Dictionary = quick.plan(workhorse)
	var cheaper := 0
	var others_same := true
	for i in with_perk.lines.size():
		var line: Dictionary = with_perk.lines[i]
		check(int(line.price) == trading.price(line.trader, line.offer, bundle) * int(line.packs), "Workhorse: %s costs what Trading.price() says" % line.offer.id)
		if line.trader == "bulat" and int(line.price) < int(without.lines[i].price):
			cheaper += 1
		others_same = others_same and (line.trader == "bulat" or int(line.price) == int(without.lines[i].price))
	check(cheaper > 0 and others_same and int(with_perk.roubles) < int(without.roubles),
		"Workhorse at LL4 for BEAR: %d of Bulat's lines cheaper, the rest the same, ₽ %d < ₽ %d" % [cheaper, int(with_perk.roubles), int(without.roubles)])


## "₽ 361,599" or "₽ 297,172 + $ 1,782", as DESIGN's table writes a plan's price.
func _money(plan: Dictionary) -> String:
	var text := "₽ %s" % _thousands(int(plan.roubles))
	if int(plan.dollars) > 0:
		text += " + $ %s" % _thousands(int(plan.dollars))
	return text


func _thousands(amount: int) -> String:
	var digits := str(amount)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result


## {id: count} of every item `inventory` wears and carries but the secure container, and everything in
## `stash`, at any depth (loaded rounds and parts too).
func _census() -> Dictionary:
	var counts := {}
	var all: Array = gs.stash.all_items()
	for slot: String in gs.inventory.equipment:
		var worn: RefCounted = gs.inventory.equipment[slot]
		if worn and slot != "secure":
			all.append_array(worn.all_items())
	all.append_array(gs.inventory.pockets.all_items())
	for each: RefCounted in all:
		counts[each.data.id] = int(counts.get(each.data.id, 0)) + each.count
	return counts


## {id: count} of what `plan`'s kit holds: everything it puts on you, the parts it displaces and what had
## no place on you.
func _kit_census(plan: Dictionary) -> Dictionary:
	var counts := {}
	var all: Array = []
	for slot: String in plan.kit.inventory.equipment:
		var piece: RefCounted = plan.kit.inventory.equipment[slot]
		if piece and slot != "secure":
			all.append_array(piece.all_items())
	all.append_array(plan.kit.inventory.pockets.all_items())
	for piece: RefCounted in plan.kit.displaced + plan.kit.overflow:
		all.append_array(piece.all_items())
	for each: RefCounted in all:
		counts[each.data.id] = int(counts.get(each.data.id, 0)) + each.count
	return counts


## `piece` as saved, without where it sits (it moves into the stash).
func _placeless(piece: RefCounted) -> Dictionary:
	var saved: Dictionary = piece.to_dict()
	for key in ["x", "y", "rotated"]:
		saved.erase(key)
	return saved


func _buying() -> void:
	section("Buying with a worn kit")
	_profile()
	var card := _card("workhorse")
	_meet(card)
	# A realistic kit: the starter gear, rounds and meds in the pockets, rig and backpack, a loaded gun.
	gs.inventory.pockets.add(item("bandage"))
	gs.inventory.pockets.add(item("ammo_545_ps", 45))
	if gs.inventory.equipment.get("rig"):
		gs.inventory.equipment.rig.contents.add(item("ai2_medkit"))
	var secure: RefCounted = gs.inventory.equipment.get("secure")
	secure.contents.add(item("bolts", 3))
	var secure_before: Dictionary = secure.to_dict()
	var worn := {}
	for slot: String in gs.inventory.equipment:
		if gs.inventory.equipment[slot] and slot != "secure":
			worn[slot] = [gs.inventory.equipment[slot], _placeless(gs.inventory.equipment[slot])]
	var pocketed: Array = gs.inventory.pockets.items.duplicate()
	var before := _census()
	var plan: Dictionary = quick.plan(card, gs.inventory, gs.stash)
	check(plan.reasons.is_empty() and plan.room, "Workhorse can be bought (%s)" % str(plan.reasons))
	var expected := before.duplicate()
	var kit := _kit_census(plan)
	for id: String in kit:
		expected[id] = int(expected.get(id, 0)) + int(kit[id])
	var roubles: int = gs.roubles
	var spent := {}
	var due := {}
	for trader: String in gs.trader_loyalty:
		spent[trader] = gs.trader_loyalty[trader].spent
	for line: Dictionary in plan.lines:
		due[line.trader] = int(due.get(line.trader, 0)) + trading.spent_value(int(line.price), line.currency)
	var plates: Dictionary = quick.offer_for("stitch", "armor_6b23")
	var plates_left: int = stock.left("stitch", plates)
	var result: Dictionary = quick.buy(plan, gs.inventory, gs.stash)
	check(result.ok and result.message.begins_with("Bought Workhorse for"), "CONFIRM buys it (%s)" % result.message)
	check(gs.roubles == roubles - int(plan.roubles), "the price is paid (%d)" % plan.roubles)
	var after := _census()
	check(after == expected, "nothing is lost or made: what you had plus the kit")
	var intact := true
	for slot: String in worn:
		var piece: RefCounted = worn[slot][0]
		intact = intact and gs.stash.items.has(piece) and _placeless(piece) == worn[slot][1]
	check(intact, "everything you wore is in the stash, each with what was in it")
	check(pocketed.all(func(piece: RefCounted) -> bool: return gs.stash.items.has(piece) or piece.data.max_stack > 1),
		"what was loose in your pockets too (stacks topping up the stash's)")
	check(gs.inventory.equipment.secure == secure and secure.to_dict() == secure_before, "the secure container stays on, untouched")
	check(gs.inventory.equipment.primary.data.id == "ak_74n" and mods.mod_at(gs.inventory.equipment.primary, "handguard/foregrip").data.id == "foregrip"
		and gs.inventory.equipment.armor.data.id == "armor_6b23" and gs.inventory.equipment.rig.data.id == "rig_triton", "the kit is on, the parts at their paths")
	var gun: RefCounted = gs.inventory.equipment.primary
	check(gun.rounds_loaded() == mods.capacity(gun) and gun.loaded_ammo == "ammo_545_ps", "the magazine is loaded to capacity (30)")
	var bounded := true
	var found := false
	for piece: RefCounted in gs.inventory.all_items():
		if piece != secure and not secure.all_items().has(piece):
			found = found or piece.fir
	for grid: RefCounted in gs.inventory.grids() + [gs.stash]:
		for piece: RefCounted in grid.items:
			bounded = bounded and piece.count <= piece.data.max_stack
	check(bounded, "every stack is within its max stack")
	check(not found, "nothing bought is found in raid")
	check(stock.left("stitch", plates) == plates_left - 1, "the 6B23-1's stock goes down by one")
	var counted := true
	for trader: String in due:
		counted = counted and gs.trader_loyalty[trader].spent == int(spent[trader]) + int(due[trader])
	check(counted, "each line counts toward its trader's money spent")
	check(quick.buy(plan, gs.inventory, gs.stash).ok == false and gs.roubles == roubles - int(plan.roubles), "the same plan can't be bought twice")
	var spare := 0
	for grid: RefCounted in gs.inventory.ammo_grids():
		spare += grid.count_of("ammo_545_ps")
	check(spare == 90 and gs.inventory.equipment.rig.contents.count_of("ammo_545_ps") == 90, "the 90 spare rounds are in the rig")
	check(gs.inventory.pockets.count_of("salewa") == 1, "the Salewa is in the pockets")
	# Prices that moved since the dialog opened: nothing is bought, the card is shown again.
	_profile()
	_meet(card)
	plan = quick.plan(card, gs.inventory, gs.stash)
	gs.trader_loyalty.bulat.level = 3
	roubles = gs.roubles
	result = quick.buy(plan, gs.inventory, gs.stash)
	check(not result.ok and result.changed and result.plan.signature != plan.signature and gs.roubles == roubles,
		"prices changed since it opened: nothing is bought and it's worked out again")


func _dollars_and_room() -> void:
	section("Dollars and room")
	_profile(true, true)
	var card := _card("contract_work")
	_meet(card)
	var plan: Dictionary = quick.plan(card, gs.inventory, gs.stash)
	check(int(plan.dollars) > 0 and int(plan.roubles) > 0, "Contract Work costs roubles and dollars (%d ₽ + $%d)" % [plan.roubles, plan.dollars])
	gs.dollars = int(plan.dollars) - 1
	plan = quick.plan(card, gs.inventory, gs.stash)
	check(plan.reasons.size() == 1 and plan.reasons[0].begins_with("Not enough dollars: $ 1 short"), "a dollar short says so (%s)" % str(plan.reasons))
	var roubles: int = gs.roubles
	check(not quick.buy(plan, gs.inventory, gs.stash).ok and gs.roubles == roubles and gs.dollars == int(plan.dollars) - 1, "and nothing is paid")
	gs.dollars = int(plan.dollars)
	var spent: int = gs.trader_loyalty.broker.spent
	plan = quick.plan(card, gs.inventory, gs.stash)
	var broker := 0
	for line: Dictionary in plan.lines:
		if line.trader == "broker":
			broker += int(line.price)
	check(quick.buy(plan, gs.inventory, gs.stash).ok and gs.dollars == 0 and gs.trader_loyalty.broker.spent == spent + broker * 140,
		"exactly enough dollars buys it; The Broker counts them at 140")
	gs.roubles = 10
	gs.dollars = 0
	plan = quick.plan(card, gs.inventory, gs.stash)
	check(plan.reasons.size() == 2 and plan.reasons[0].begins_with("Not enough roubles") and plan.reasons[1].begins_with("Not enough dollars"),
		"every reason is listed, not just the first (%s)" % str(plan.reasons))
	# A full stash: nothing is paid.
	_profile()
	card = _card("workhorse")
	_meet(card)
	_fill_stash()
	var worn_before: Dictionary = gs.inventory.to_dict()
	roubles = gs.roubles
	plan = quick.plan(card, gs.inventory, gs.stash)
	check(not plan.room and plan.reasons.size() == 1 and plan.reasons[0].begins_with("No room in the stash"), "a full stash: no room (%s)" % str(plan.reasons))
	check(not quick.buy(plan, gs.inventory, gs.stash).ok and gs.roubles == roubles and gs.inventory.to_dict() == worn_before, "nothing is paid and nothing moves")


## Fills every free cell of the stash with keys.
func _fill_stash() -> void:
	while gs.stash.add(item("dorm_key")):
		pass


func _substitutes() -> void:
	section("The closest alternative")
	_profile(true, true)
	var card := _card("contract_work")
	_meet(card)
	var fast: Dictionary = quick.offer_for("broker", "fast_helmet")
	stock.take("broker", fast, 2)
	var plan: Dictionary = quick.plan(card)
	var helmet := _line(plan, "fast_helmet")
	check(helmet.swap and helmet.item == "fast_helmet" and helmet.trader == "stitch" and helmet.currency == "RUB",
		"The Broker's FAST sold out: the same helmet from Stitch, in roubles (%s from %s)" % [helmet.item, helmet.trader])
	check(helmet.why == "sold out at The Broker", "and why (%s)" % helmet.why)
	# A gun sold out: the closest of its class, its parts refitted, rounds of its own caliber.
	_profile()
	card = _card("workhorse")
	_meet(card)
	stock.take("bulat", quick.offer_for("bulat", "ak_74n"), 2)
	plan = quick.plan(card)
	var gun := _line(plan, "ak_74n")
	var rounds := _line(plan, "ammo_545_ps")
	var data: Resource = db.get_item(gun.item)
	check(gun.swap and data.weapon.weapon_class == "assault_rifle" and gun.item != "ak_74n", "the AK-74N sold out: another assault rifle (%s)" % gun.item)
	var caliber: String = data.weapon.caliber
	check(rounds.swap and db.get_item(rounds.item).stats.caliber == caliber and int(rounds.count) >= 2 * mods.capacity(plan.kit.inventory.equipment.primary),
		"its rounds follow its caliber (%s, %d rounds)" % [rounds.item, rounds.count])
	check(_line(plan, "ak_handguard_rail").left_out == false and plan.kit.inventory.equipment.primary.data.id == gun.item
		and mods.mod_at(plan.kit.inventory.equipment.primary, "handguard").data.id == "ak_handguard_rail", "the rail handguard still fits it and goes on")
	# Parts: the same kind that fits; a sight of the same type; a magazine as big, or the gun's own stays.
	_profile()
	card = _card("workhorse")
	_meet(card)
	gs.trader_loyalty.tinker.level = 1
	plan = quick.plan(card)
	var sight := _line(plan, "red_dot")
	check(sight.left_out or (sight.swap and int(db.get_item(sight.item).stats.get("optic", 0)) == int(db.get_item("red_dot").stats.get("optic", 0))),
		"the red dot above Tinker's level: a sight of the same type or nothing (%s)" % ("left out" if sight.left_out else sight.item))
	var big: Dictionary = card.duplicate(true)
	big.parts.primary.append({"path": "magazine", "item": "ak_mag_45", "trader": "tinker"})
	plan = quick.plan(big)
	var mag := _line(plan, "ak_mag_45")
	check(mag.left_out and mods.capacity(plan.kit.inventory.equipment.primary) == 30,
		"no magazine as big as the 45 at LL1: it's left out and the gun keeps its own 30 (%s)" % str(mag.get("why", "")))
	# Rounds keep their penetration while an alternative does.
	_profile()
	var bs: Dictionary = card.duplicate(true)
	bs.rounds[0].item = "ammo_545_bs"
	bs.rounds[0].count = 60
	_meet(card)
	gs.trader_loyalty.bulat.level = 3
	plan = quick.plan(bs)
	rounds = _line(plan, "ammo_545_bs")
	var least: float = float(db.get_item("ammo_545_bs").stats.penetration) * (1.0 - table.penetration_drop())
	var within := false
	for offer: Dictionary in trading.offers("bulat").buy:
		var ammo: Resource = db.get_item(offer.item)
		if ammo.stats.get("caliber", "") == "5.45x39" and int(offer.get("ll", 1)) <= 3 and float(ammo.stats.penetration) >= least:
			within = true
	var pen: float = float(db.get_item(rounds.item).stats.penetration)
	check(rounds.swap and (pen >= least or not within), "BS rounds at LL3: %s (penetration %d, at least %d while one has it)" % [rounds.item, pen, least])
	check(rounds.item == "ammo_545_bt", "the BT rounds stand in for BS")
	# Meds by type; armor for armor; a plain rig for a plain rig.
	_profile()
	_meet(card)
	gs.trader_loyalty.vera.level = 1
	gs.trader_loyalty.stitch.level = 1
	plan = quick.plan(card)
	var med := _line(plan, "salewa")
	check(med.swap and db.get_item(med.item).stats.type == "medkit", "the Salewa at LL1: another medkit (%s)" % med.item)
	var armor := _line(plan, "armor_6b23")
	check(armor.swap and db.get_item(armor.item).category == db.get_item("armor_6b23").category, "the 6B23-1 at LL1: other body armor (%s)" % armor.item)
	var rig := _line(plan, "rig_triton")
	check(rig.swap and int(db.get_item(rig.item).stats.get("class", 0)) == 0, "the Triton (a plain rig) at LL1: a plain rig (%s)" % rig.item)
	check(int(plan.swaps) >= 5 and plan.reasons.size() == 1 and plan.reasons[0].begins_with("Locked"), "the plan counts its swaps (%d)" % plan.swaps)
	# Nothing to stand in: left out and not charged; a gun takes its parts and rounds with it.
	_profile()
	var lone := {"id": "test_lone", "name": "Lone", "description": "Test.", "unlock": {"loyalty": {"bulat": 2}},
		"gear": {"primary": {"item": "grizzly_74", "trader": "bulat"}, "rig": {"item": "tactical_rig", "trader": "stitch"}},
		"parts": {"primary": [{"path": "handguard", "item": "ak_handguard_rail", "trader": "tinker"}]},
		"rounds": [{"for": "primary", "item": "ammo_545_ps", "trader": "bulat", "count": 120}]}
	gs.trader_loyalty.bulat.level = 2
	stock.take("bulat", quick.offer_for("bulat", "grizzly_74"), 2)
	plan = quick.plan(lone)
	check(_line(plan, "grizzly_74").left_out and _line(plan, "ak_handguard_rail").left_out and _line(plan, "ammo_545_ps").left_out,
		"no other machine gun for sale: the Grizzly is left out with its handguard and rounds")
	check(int(plan.roubles) == trading.price("stitch", quick.offer_for("stitch", "tactical_rig"), table.bundle_discount()) and int(plan.left_out) == 3,
		"only the rig is charged (%d)" % plan.roubles)


func _custom() -> void:
	section("Custom cards")
	_profile()
	var inventory: RefCounted = gs.inventory
	var legend := item("slick_carrier")
	if inventory.equipment.get("armor"):
		gs.stash.add(inventory.unequip("armor"))
	if inventory.equipment.get("rig") and inventory.equipment.rig.is_armor():
		gs.stash.add(inventory.unequip("rig"))
	check(inventory.equip("armor", legend), "wearing a Slick plate carrier (never sold for money)")
	for piece: RefCounted in inventory.pockets.items.duplicate():
		inventory.pockets.remove(piece)
		gs.stash.add(piece)
	check(inventory.pockets.add(item("salewa")) and inventory.pockets.add(item("ammo_9x19_fmj", 20)), "a Salewa and 20 rounds of 9x19 in the pockets")
	var result: Dictionary = quick.save_custom("My kit", inventory)
	var card: Dictionary = result.card
	check(result.ok and card.custom and card.name == "My kit" and gs.quick_buys.size() == 1, "SAVE CURRENT GEAR AS QUICK-BUY makes a custom card")
	check(card.left_out.has("Slick plate carrier") and result.message.contains("Not for sale, left out: Slick plate carrier"),
		"what no trader sells is named when saving (%s)" % result.message)
	check(not card.gear.has("armor"), "and isn't on the card")
	var gun: RefCounted = inventory.equipment.get("primary")
	if gun:
		check(card.gear.primary.item == gun.data.id and card.rounds.any(func(line: Dictionary) -> bool: return line["for"] == "primary"),
			"the gun is on it with its rounds (%s)" % str(card.rounds))
	check(card.left_out.any(func(name: String) -> bool: return name.begins_with("9x19 FMJ")), "rounds no gun on the card fires are left out")
	check(card.carried.any(func(line: Dictionary) -> bool: return line.item == "salewa" and line.trader == "vera"), "the Salewa from Doc Vera")
	check(quick.is_unlocked(card) and quick.cards().has(card), "a custom card is always unlocked and shown")
	for i in 4:
		check(quick.save_custom("", inventory).ok, "custom card %d saves" % (i + 2))
	check(gs.quick_buys[1].name == "Custom 1" and gs.quick_buys[4].name == "Custom 4", "unnamed ones are Custom 1, Custom 2...")
	result = quick.save_custom("Sixth", inventory)
	check(not result.ok and gs.quick_buys.size() == 5 and result.message.begins_with("5 custom cards already"), "five at most (%s)" % result.message)
	sm.save_game()
	var saved: Array = gs.quick_buys.duplicate(true)
	gs.quick_buys = []
	check(sm.load_game() and gs.quick_buys == saved, "the cards come back from the save, left-outs and all")
	check(gs.quick_buys[0].left_out.has("Slick plate carrier"), "the left-out list survives the save")
	var dirty := [{"name": "Old", "gear": {"helmet": {"item": "no_such_helmet", "trader": "stitch"}, "rig": {"item": "scav_vest", "trader": "stitch"}},
		"carried": [{"item": "bandage", "trader": "nobody", "count": 1}]}, 7, {"name": "x"}, {}, {}, {}, {}]
	var clean: Array = quick.sanitize(dirty)
	check(clean.size() == 5 and clean[0].gear.keys() == ["rig"] and clean[0].left_out.has("no_such_helmet (no longer in the game)")
		and clean[0].carried.is_empty() and clean[0].id == "custom_1" and clean[1].name == "x", "a saved list is cleaned on load (%s)" % str(clean[0]))
	var older := {"version": 14, "profile": {"faction": "BEAR", "level": 1, "xp": 0, "roubles": 1000}, "stash": []}
	gs.from_dict(sm.upgrade(older))
	check(gs.quick_buys == [], "a version 14 save loads with no custom cards")
	_profile()
	var bought: Dictionary = quick.save_custom("Again", gs.inventory)
	var again: Dictionary = quick.plan(bought.card, gs.inventory, gs.stash)
	check(again.reasons.is_empty() and quick.buy(again, gs.inventory, gs.stash).ok, "a custom card is bought by the same rules")
	check(quick.remove_custom(0) and gs.quick_buys.is_empty() and not quick.remove_custom(0), "and deleted")


func _timing() -> void:
	section("A full 10 × 70 stash")
	_profile()
	var card := _card("workhorse")
	_meet(card)
	gs.stash.resize(Vector2i(10, 70))
	for y in 66:
		for x in 10:
			gs.stash.place(item("bolts" if (x + y) % 2 == 0 else "dorm_key"), Vector2i(x, y), false)
	var started := Time.get_ticks_usec()
	var plan: Dictionary = quick.plan(card, gs.inventory, gs.stash)
	var planned := (Time.get_ticks_usec() - started) / 1000.0
	check(plan.room and plan.reasons.is_empty() and planned < 100.0, "working the card out with the room check takes %.1f ms (under 100)" % planned)
	started = Time.get_ticks_usec()
	var result: Dictionary = quick.buy(plan, gs.inventory, gs.stash)
	var bought := (Time.get_ticks_usec() - started) / 1000.0
	check(result.ok and bought < 200.0, "CONFIRM takes %.1f ms (under 200)" % bought)


func _key(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	var release := InputEventAction.new()
	release.action = action
	root.push_input(release)


func _screen() -> void:
	section("The QUICK BUY tab")
	_profile()
	var card := _card("workhorse")
	_meet(card)
	change_scene_to_file("res://ui/loadout_screen.tscn")
	await frames(4)
	var screen: Control = current_scene
	check(screen.tab == 0 and screen.find_child("TabQuickBuy", true, false) != null, "LOADOUT opens on its LOADOUT tab, QUICK BUY beside it")
	_key("ui_tab_next")
	await frames(2)
	var tab: Control = screen.quick_buy
	check(screen.tab == 1 and tab.visible and not screen.get_node("Margin/Layout/Columns").visible, "E (or RB) switches to QUICK BUY")
	check(tab.card_view("workhorse") != null and tab.card_view("contract_work") == null and tab.card_view("taiga_patrol") != null,
		"it shows the BEAR player's cards")
	var view: Control = tab.card_view("iron_wall")
	check(view.find_child("CardLock", true, false) != null and (view.find_child("CardBuy", true, false) as Button).disabled
		and (view.find_child("CardLock", true, false) as Label).text.begins_with("Needs Bulat LL3"), "a locked card says what it needs, BUY off")
	var price: String = (tab.card_view("workhorse").find_child("CardPrice", true, false) as RichTextLabel).get_parsed_text()
	check(price.contains("−10%") and price.contains(load("res://scripts/ui/ui_format.gd").thousands(int(tab.plans.workhorse.roubles))),
		"a card shows its price, the full one struck through and −10%% (%s)" % price.replace("\n", " "))
	check(not (tab.card_view("workhorse").find_child("CardStats", true, false) as Label).text.is_empty(), "and the would-be loadout's stats")
	_key("ui_tab_previous")
	await frames(2)
	check(screen.tab == 0, "Q (or LB) goes back")
	_key("ui_tab_next")
	await frames(2)
	tab.name_box.grab_focus()
	await frames(1)
	_key("ui_tab_previous")
	await frames(2)
	check(screen.tab == 1 and screen.tabs_allowed() == false, "while the name box has the keys, Q does nothing")
	tab.name_box.release_focus()
	screen.set_tab(0)
	(screen.find_child("PresetName", true, false) as LineEdit).grab_focus()
	await frames(1)
	_key("ui_tab_next")
	await frames(2)
	check(screen.tab == 0, "nor E while the preset name is typed")
	(screen.find_child("PresetName", true, false) as LineEdit).release_focus()
	screen._open_window(gs.inventory.equipment.secure)
	await frames(1)
	_key("ui_tab_next")
	await frames(2)
	check(screen.tab == 0 and not screen.tabs_allowed(), "nor with a container window open")
	screen.set_tab(1)
	await frames(2)
	var plan: Dictionary = tab.open_dialog("workhorse")
	await frames(3)
	var shade: Control = screen.find_child("QuickBuyShade", true, false)
	var overlay: Control = screen.overlay()
	check(tab.dialog_open() and shade.get_index() == overlay.get_child_count() - 1, "BUY opens the dialog over the container window")
	check(root.gui_get_focus_owner() == screen.find_child("DialogConfirm", true, false), "the focus is on CONFIRM (%s)" % root.gui_get_focus_owner())
	var buy_button: Button = tab.card_view("workhorse").find_child("CardBuy", true, false)
	check(buy_button.get_focus_mode_with_override() == Control.FOCUS_NONE and (screen.find_child("CloseButton", true, false) as Control).get_focus_mode_with_override() == Control.FOCUS_NONE,
		"nothing under it can take the focus")
	var stays := true
	for i in 4:
		_key("ui_focus_next")
		await frames(1)
		var owner := root.gui_get_focus_owner()
		stays = stays and owner != null and (owner.name == "DialogConfirm" or owner.name == "DialogCancel")
	check(stays, "moving the focus stays between CANCEL and CONFIRM")
	_key("ui_tab_next")
	await frames(2)
	check(screen.tab == 1 and tab.dialog_open(), "the tab keys do nothing while it's open")
	var lines: Array = tab.dialog_lines()
	check(lines.any(func(text: String) -> bool: return text.begins_with("AK-74N  ·  Bulat")) and lines.any(func(text: String) -> bool: return text.begins_with("To the stash:")),
		"it lists every line with its trader and price, and what goes to the stash")
	_key("ui_cancel")
	await frames(2)
	check(not tab.dialog_open() and screen.is_inside_tree() and buy_button.get_focus_mode_with_override() != Control.FOCUS_NONE,
		"Esc cancels it (the screen stays) and gives the focus back")
	screen._close_window(gs.inventory.equipment.secure)
	# A full 10 x 70 stash: the dialog under 100 ms, CONFIRM under 200 ms, and only once.
	gs.stash.resize(Vector2i(10, 70))
	for y in range(30, 66):
		for x in 10:
			gs.stash.place(item("dorm_key"), Vector2i(x, y), false)
	var started := Time.get_ticks_usec()
	plan = tab.open_dialog("workhorse")
	var opened := (Time.get_ticks_usec() - started) / 1000.0
	check(plan.reasons.is_empty() and opened < 100.0, "on a full 10 x 70 stash the dialog opens in %.1f ms (under 100)" % opened)
	await frames(2)
	var roubles: int = gs.roubles
	started = Time.get_ticks_usec()
	var result: Dictionary = tab.confirm()
	var confirmed := (Time.get_ticks_usec() - started) / 1000.0
	check(result.ok and confirmed < 200.0, "CONFIRM buys it in %.1f ms (under 200, saving included)" % confirmed)
	var again: Dictionary = tab.confirm()
	check(not again.ok and gs.roubles == roubles - int(plan.roubles), "a second press buys nothing more")
	await frames(2)
	check(not tab.dialog_open() and gs.inventory.equipment.primary.data.id == "ak_74n"
		and (tab.find_child("QuickBuyStatus", true, false) as Label).text.begins_with("Bought Workhorse"), "the dialog closes and says what was bought")
	tab.name_box.text = "From the tab"
	var saved: Dictionary = tab.save_current()
	await frames(2)
	check(saved.ok and tab.card_view(saved.card.id) != null and tab.card_view(saved.card.id).find_child("CardTag", true, false).text == "CUSTOM",
		"SAVE CURRENT GEAR AS QUICK-BUY adds a CUSTOM card")
	tab.delete_custom(saved.card.id)
	await frames(2)
	check(gs.quick_buys.is_empty() and tab.card_view(saved.card.id) == null, "DELETE removes it")
	screen.close()
	await frames(2)
