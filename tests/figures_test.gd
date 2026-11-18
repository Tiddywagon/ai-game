extends "res://tests/test_base.gd"
## Collectible figures (DESIGN.md §6.6, docs/plan/E10_figures.md): the figure data and the loader's
## checks (a broken copy for each rule); every boss and every original point of interest has its figure;
## where figures come from (seeded rolls); the Collectors Shelf: place, move and remove with the slots of
## each level and a full stash, and its figures safe from death, sorting, selling, barters, quests and
## the flea market; each set bonus on and off through what it changes; the no-resale sweep with the
## Traders set on display (tests/economy_test.gd); spares; the free Drip spin allowance; save version
## 18 round trip and older saves; selling figures, the generic "any n figures" barter requirement and
## the Collector quest line from Mole to the Omega secure container.

const NOW := 1_000_000.0
const DAY := 86400.0

var ft: GDScript
var figs: GDScript
var work: GDScript


func run() -> void:
	ft = load("res://scripts/data/figure_table.gd")
	figs = load("res://scripts/progression/figures.gd")
	work = load("res://scripts/progression/hideout_work.gd")
	work.now_override = NOW
	_data()
	_loader()
	_owners()
	_sources()
	_shelf()
	_safety()
	_bonuses()
	_spares()
	_selling()
	_generic_barters()
	_quest_line()
	_free_spin()
	_saves()
	_design_table()
	work.now_override = -1.0
	gs.raid = {}


## A new profile with the Collectors Shelf built to `level` (0: not built).
func _profile(level := 1) -> void:
	fresh_profile()
	if level > 0:
		gs.hideout["collectors_shelf"] = level
	else:
		gs.hideout.erase("collectors_shelf")


## Figure `id` put in the stash (found in raid with `fir`); returns it.
func _give(id: String, fir := false) -> RefCounted:
	var piece: RefCounted = item(id)
	piece.fir = fir
	gs.stash.add(piece)
	return piece


## Puts every figure of set `id` on the shelf (each given to the stash first).
func _display_set(id: String) -> void:
	for data: Resource in ft.in_set(id):
		figs.place(_give(data.id), figs.free_slot())


func _ids(list: Array) -> Array:
	return list.map(func(data: Resource) -> String: return data.id)


func _data() -> void:
	section("The figures and figures.json")
	check(ft.problems().is_empty(), "the figure data has no problems (%s)" % str(ft.problems()))
	var sizes := {}
	for id: String in ft.set_ids():
		sizes[id] = ft.in_set(id).size()
	check(ft.set_ids() == ["raiders", "factions", "traders", "bosses", "wildlife", "oddities", "landmarks"], "seven sets in collection order (%s)" % str(ft.set_ids()))
	check(sizes == {"raiders": 6, "factions": 6, "traders": 7, "bosses": 6, "wildlife": 6, "oddities": 6, "landmarks": 18},
		"6 Raiders, 6 Factions, 7 Traders, 6 Bosses, 6 Wildlife, 6 Oddities, 18 Landmarks (%s)" % str(sizes))
	check(ft.figures().size() == 55, "55 figures in all (%d)" % ft.figures().size())
	var well_formed := true
	var models := true
	var model_script: GDScript = load("res://scripts/ui/figure_model.gd")
	for data: Resource in ft.figures():
		well_formed = well_formed and data.size == Vector2i.ONE and data.max_stack == 1 and data.weight_kg >= 0.1 and data.weight_kg <= 0.3 \
			and data.description != "" and data.has_tag("figure") and db.get_item(data.id) == data
		models = models and model_script.problems(data.stats.get("model")).is_empty()
	check(well_formed, "every figure is a 1×1 item of 0.1-0.3 kg that doesn't stack, with a description and the figure tag")
	check(models, "every figure has a model recipe FigureModel builds")
	var bonuses := {}
	for entry: Dictionary in ft.sets():
		bonuses[entry.id] = [entry.bonus.type, entry.bonus.value]
	check(bonuses == {"raiders": ["search_speed", 0.05], "factions": ["pmc_kill_xp", 0.05], "traders": ["trader_prices", 0.03],
		"bosses": ["boss_chance", 0.1], "wildlife": ["metabolism", 0.1], "oddities": ["drip_spin", 1.0], "landmarks": ["exploration_xp", 0.1]},
		"each set's bonus as the plan has it (%s)" % str(bonuses))
	check(ft.bonus_text(ft.find_set("raiders")) == "+5% loot search speed" and ft.bonus_text(ft.find_set("oddities")) == "+1 free Drip slot spin a day"
		and ft.bonus_text(ft.find_set("traders")) == "3% better trader prices", "bonuses read as words (%s)" % ft.bonus_text(ft.find_set("raiders")))
	var shelf: Dictionary = load("res://scripts/progression/hideout.gd").find("collectors_shelf")
	var slots: Array = shelf.levels.map(func(entry: Dictionary) -> int: return int(entry.display_slots))
	check(slots == [12, 28, 56] and slots[2] >= ft.figures().size(), "the Collectors Shelf displays 12 / 28 / 56 figures (%s): every figure at the top" % str(slots))


## problems() on broken copies of figures.json and of a figure: each rule caught.
func _loader() -> void:
	section("Loader checks")
	var original: Dictionary = ft.config().duplicate(true)
	var cases := [
		["an unknown bonus type", func(c: Dictionary) -> void: c.sets[0].bonus.type = "luck", "its bonus needs a type"],
		["a bonus out of range", func(c: Dictionary) -> void: c.sets[2].bonus.value = 0.5, "a trader_prices bonus is 0.005 to 0.1"],
		["a part spin", func(c: Dictionary) -> void: c.sets[5].bonus.value = 1.5, "a whole number"],
		["a set with no figures", func(c: Dictionary) -> void: c.sets.append({"id": "toys", "name": "Toys", "about": "", "found": "", "bonus": {"type": "search_speed", "value": 0.05}}), "has 0 figures (at least 3)"],
		["a figure's set missing", func(c: Dictionary) -> void: c.sets.remove_at(4), "its set \"wildlife\" doesn't exist"],
		["two sets with one id", func(c: Dictionary) -> void: c.sets[1].id = "raiders", "an id and a name of its own"],
		["an unknown set key", func(c: Dictionary) -> void: c.sets[0]["colour"] = "red", "unknown key \"colour\""],
		["an unknown source", func(c: Dictionary) -> void: c.sources["trees"] = {"chance": 0.1}, "source trees: isn't one of"],
		["a chance above 1", func(c: Dictionary) -> void: c.sources.boss.chance = 1.5, "a chance is a number from 0 to 1"],
		["a missing source", func(c: Dictionary) -> void: c.sources.erase("landmark"), "source landmark: missing"],
		["a table that isn't there", func(c: Dictionary) -> void: c.sources.scav_body.table = "res://nothing.tres", "isn't a loot table"],
		["a table with other items", func(c: Dictionary) -> void: c.sources.flea.table = "res://data/loot_tables/drawer.tres", "which isn't a figure"],
		["an unknown container", func(c: Dictionary) -> void: c.sources.container.chances["trophy_case"] = 0.1, "no container type trophy_case"],
		["an unknown faction table", func(c: Dictionary) -> void: c.sources.pmc_body.faction_tables["spetsnaz"] = c.sources.pmc_body.faction_tables.bear, "faction spetsnaz doesn't exist"],
		["a shelf station that isn't there", func(c: Dictionary) -> void: c.shelf.station = "trophy_room", "no hideout station trophy_room"],
		["no columns", func(c: Dictionary) -> void: c.shelf.columns = 0, "columns must be 1 or more"],
	]
	for case: Array in cases:
		var copy: Dictionary = original.duplicate(true)
		case[1].call(copy)
		ft.reload()
		ft._config = copy
		var found: Array = ft.problems()
		check(found.any(func(problem: String) -> bool: return case[2] in problem), "%s is caught (%s)" % [case[0], str(found.slice(0, 3))])
	ft.reload()
	var scav: Resource = db.get_item("figure_scav")
	var keep := [scav.weight_kg, scav.base_value, scav.size, scav.stats.duplicate(true)]
	var figure_cases := [
		["a heavy figure", func() -> void: scav.weight_kg = 2.0, "weighs 2"],
		["a figure worth too much for its rarity", func() -> void: scav.base_value = 900000, "outside its rarity's band"],
		["a 1×2 figure", func() -> void: scav.size = Vector2i(1, 2), "is 1×1"],
		["a model with an unknown shape", func() -> void: scav.stats.model.body.shape = "teapot", "model:"],
	]
	for case: Array in figure_cases:
		case[1].call()
		var found: Array = ft.problems()
		check(found.any(func(problem: String) -> bool: return "figure_scav" in problem and case[2] in problem), "%s is caught (%s)" % [case[0], str(found.slice(0, 2))])
		scav.weight_kg = keep[0]
		scav.base_value = keep[1]
		scav.size = keep[2]
		scav.stats = keep[3].duplicate(true)
	check(ft.problems().is_empty(), "the real data is back without problems")


## Every boss and every original point of interest has a figure of its own; every trader a barter that
## gives theirs. The loader checks these too: here a broken copy of the owners.
func _owners() -> void:
	section("A figure for every boss, original point of interest and trader")
	var bosses: GDScript = load("res://scripts/data/boss_table.gd")
	var pois: GDScript = load("res://scripts/data/poi_table.gd")
	var boss_figures := []
	for map_id: String in bosses.maps():
		boss_figures.append(str(bosses.maps()[map_id].get("figure", "")))
	check(boss_figures.size() == 6 and boss_figures.all(func(id: String) -> bool: return ft.set_of(db.get_item(id)) == "bosses" if db.has_item(id) else false)
		and _as_set(boss_figures).size() == 6, "all %d bosses have a Bosses figure of their own (%s)" % [boss_figures.size(), str(boss_figures)])
	var poi_figures := []
	for pair: Array in pois.originals():
		poi_figures.append(str(pair[1].get("figure", "")))
	check(poi_figures.size() == 18 and poi_figures.all(func(id: String) -> bool: return ft.set_of(db.get_item(id)) == "landmarks" if db.has_item(id) else false)
		and _as_set(poi_figures).size() == 18, "all %d original points of interest have a Landmarks figure of their own" % poi_figures.size())
	var barters: GDScript = load("res://scripts/data/barter_table.gd")
	var traded := {}
	for barter: Dictionary in barters.all():
		for reward: Dictionary in barters.rewards(barter):
			if db.has_item(str(reward.item)) and ft.set_of(db.get_item(str(reward.item))) == "traders":
				traded[str(barter.trader)] = str(reward.item)
	check(traded.size() == 7 and traded.bulat == "figure_bulat" and traded.broker == "figure_broker", "each of the 7 traders barters their own figure (%s)" % str(traded))
	var map_id: String = bosses.maps().keys()[0]
	var figure: String = bosses.maps()[map_id].figure
	bosses.maps()[map_id].erase("figure")
	check(ft.problems().any(func(problem: String) -> bool: return "boss of %s" % map_id in problem), "a boss without a figure is caught")
	check(ft.problems().any(func(problem: String) -> bool: return figure in problem and "no boss it belongs to" in problem), "and its figure, now nobody's")
	bosses.maps()[map_id].figure = figure
	var poi: Dictionary = pois.originals()[0][1]
	var landmark: String = poi.figure
	poi.figure = "figure_fox"
	check(ft.problems().any(func(problem: String) -> bool: return "isn't a Landmarks figure" in problem), "a point of interest with a figure of another set is caught")
	poi.figure = landmark
	check(ft.problems().is_empty(), "back to no problems")


func _as_set(list: Array) -> Dictionary:
	var result := {}
	for each: Variant in list:
		result[each] = true
	return result


## Seeded rolls: the same seed, the same figure; over many seeds about the chance the data gives.
func _sources() -> void:
	section("Where figures come from (seeded)")
	var bosses: GDScript = load("res://scripts/data/boss_table.gd")
	var boss: Dictionary = bosses.maps().values()[0]
	var hits := 0
	var right := true
	for seed_value in 2000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var got: RefCounted = ft.roll_boss(boss, rng)
		if got:
			hits += 1
			right = right and got.data.id == boss.figure
	check(right and hits > 2000 * 0.25 and hits < 2000 * 0.35, "a boss carries its own figure about 30%% of the time (%d of 2000)" % hits)
	var crates := 0
	var drawers := 0
	var finds := true
	for seed_value in 2000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var crate: RefCounted = ft.roll_container("airdrop_crate", ft.stream(rng, "container"))
		var drawer: RefCounted = ft.roll_container("drawer", ft.stream(rng, "container"))
		crates += 1 if crate else 0
		drawers += 1 if drawer else 0
		for got: RefCounted in [crate, drawer]:
			finds = finds and (got == null or ft.set_of(got.data) in ["wildlife", "oddities"])
	check(crates > 2000 * 0.33 and crates < 2000 * 0.47 and drawers > 2000 * 0.01 and drawers < 2000 * 0.045,
		"an airdrop crate holds one 40%% of the time (%d), a drawer 2.5%% (%d)" % [crates, drawers])
	check(finds, "containers hold Wildlife and Oddities figures")
	var same := true
	for seed_value in 50:
		var a := RandomNumberGenerator.new()
		a.seed = seed_value
		var b := RandomNumberGenerator.new()
		b.seed = seed_value
		var first: RefCounted = ft.roll_container("airdrop_crate", ft.stream(a, "container"))
		var second: RefCounted = ft.roll_container("airdrop_crate", ft.stream(b, "container"))
		same = same and ((first == null and second == null) or (first != null and second != null and first.data.id == second.data.id))
	check(same, "the same seed rolls the same figure")
	var untouched := RandomNumberGenerator.new()
	untouched.seed = 7
	var state := untouched.state
	ft.roll_container("airdrop_crate", ft.stream(untouched, "container"))
	check(untouched.state == state, "a figure roll leaves the raid's own random stream alone")
	var bodies := {"bear": 0, "usec": 0, "raiders": 0, "none": 0}
	for seed_value in 3000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var got: RefCounted = ft.roll_body(true, &"bear", rng)
		if got == null:
			bodies.none += 1
		elif ft.set_of(got.data) == "raiders":
			bodies.raiders += 1
		else:
			bodies["bear" if got.data.id.begins_with("figure_bear") else "usec"] += 1
	check(bodies.usec == 0 and bodies.bear > 0 and bodies.raiders > 0 and bodies.bear + bodies.raiders > 3000 * 0.05 and bodies.bear + bodies.raiders < 3000 * 0.11,
		"a BEAR PMC carries one about 8%% of the time, of its own faction or a raider, never USEC (%s)" % str(bodies))
	var scavs := 0
	var scav_sets := true
	for seed_value in 3000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var got: RefCounted = ft.roll_body(false, &"", rng)
		if got:
			scavs += 1
			scav_sets = scav_sets and ft.set_of(got.data) == "raiders"
	check(scav_sets and scavs > 3000 * 0.025 and scavs < 3000 * 0.055, "a Scav carries a Raiders figure about 4%% of the time (%d)" % scavs)
	var pois: GDScript = load("res://scripts/data/poi_table.gd")
	var poi: Dictionary = pois.originals()[0][1]
	var landmarks := 0
	for seed_value in 2000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var got: RefCounted = ft.roll_landmark(poi, rng)
		if got:
			landmarks += 1 if got.data.id == poi.figure else 1000
	check(landmarks > 2000 * 0.07 and landmarks < 2000 * 0.13, "an original point of interest holds its own figure about 10%% of raids (%d)" % landmarks)
	var flea: GDScript = load("res://scripts/progression/flea_market.gd")
	var first: int = flea.refresh_number()
	var with_figure := 0
	for number in range(first, first + 300):
		if flea.listings_on(number).any(func(listing: Dictionary) -> bool: return ft.is_figure(listing.item.data)):
			with_figure += 1
	check(with_figure > 300 * 0.06 and with_figure < 300 * 0.2, "now and then a figure on the flea market (%d of 300 refreshes)" % with_figure)
	gs.raid = {"practice": true}
	check(not ft.drops_in_raid(), "never in a Shooting Range practice raid")
	gs.raid = {"side": "pmc", "map": "test_yard", "seed": 4}
	check(ft.drops_in_raid(), "in a real raid they do")
	gs.raid = {}


func _shelf() -> void:
	section("The Collectors Shelf: place, move, remove")
	_profile(0)
	var scav: RefCounted = _give("figure_scav", true)
	check(figs.slots() == 0 and figs.place(scav, 0) == "Build the Collectors Shelf first", "not built: no slots")
	gs.hideout["collectors_shelf"] = 1
	check(figs.slots() == 12, "level 1: 12 slots")
	check(figs.place(scav, 12) == "The shelf has no slot 13 at this level", "no slot 13 at level 1")
	check(figs.place(item("bandage"), 0) == "Only figures go on the shelf", "only figures")
	check(figs.place(item("figure_fox"), 0) == "It isn't in your stash", "only from the stash")
	check(figs.place(scav, 3) == "" and figs.placed(3) == scav and gs.stash.count_of("figure_scav") == 0 and figs.displayed_count() == 1,
		"placed in slot 4: that very item, out of the stash")
	check(figs.placed(3).fir, "it keeps its found-in-raid mark")
	var second: RefCounted = _give("figure_scav")
	check(figs.place(second, 4).ends_with("is already on the shelf (one of each)"), "one of each figure at most")
	var fox: RefCounted = _give("figure_fox")
	check(figs.place(fox, 3) == "That slot is taken", "one figure a slot")
	var backpack: RefCounted = item("backpack_tourist") if db.has_item("backpack_tourist") else null
	if backpack:
		gs.stash.add(backpack)
		gs.stash.remove(fox)
		backpack.contents.add(fox)
		check(figs.place(fox, 5) == "" and backpack.contents.count_of("figure_fox") == 0, "a figure in a container in the stash can go up too")
	else:
		check(figs.place(fox, 5) == "", "(the fox placed)")
	check(figs.move(3, 5) == "" and figs.placed(5) == scav and figs.placed(3) == fox, "moving onto a taken slot swaps the two")
	check(figs.move(5, 11) == "" and figs.placed(11) == scav and figs.placed(5) == null, "moving to an empty slot")
	check(figs.move(11, 12) != "" and figs.move(7, 1) == "No figure in that slot", "no move past the shelf or from an empty slot")
	check(figs.remove(11) == "" and figs.placed(11) == null and gs.stash.count_of("figure_scav") == 2, "removed: back in the stash")
	check(figs.remove(11) == "No figure in that slot", "nothing to remove twice")
	gs.hideout["collectors_shelf"] = 2
	check(figs.slots() == 28 and figs.place(scav, 27) == "", "level 2: 28 slots")
	gs.hideout["collectors_shelf"] = 3
	check(figs.slots() == 56, "level 3: 56 slots")
	# A full stash: the figure stays on the shelf.
	var filler := 0
	while gs.stash.add(item("figure_hare")):
		filler += 1
	check(figs.remove(27) == "No room in the stash" and figs.placed(27) == scav, "with the stash full it can't come down (%d fillers): nothing lost" % filler)
	check(figs.free_slot() == 0, "the first empty slot is offered first")


## A displayed figure is kept by the shelf: nothing that works on the stash or your gear touches it.
func _safety() -> void:
	section("Displayed figures are safe")
	_profile(1)
	var medic: RefCounted = _give("figure_bear_medic", true)
	figs.place(medic, 0)
	var outcome: GDScript = load("res://scripts/raid/raid_outcome.gd")
	var inventory: RefCounted = gs.inventory
	outcome.settle(outcome.Status.KILLED, "pmc", inventory, 600.0, 0, 0, true, {}, {"kill_list": [], "map": "factory"})
	check(figs.placed(0) == medic, "dying in a raid leaves the shelf alone")
	gs.stash.sort(0)
	check(figs.placed(0) == medic and gs.stash.count_of("figure_bear_medic") == 0, "sorting the stash doesn't bring it back")
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	check(selling.sell("mole", [medic]) != "" and figs.placed(0) == medic, "it can't be sold (\"%s\")" % selling.block_reason(medic))
	var flea: GDScript = load("res://scripts/progression/flea_market.gd")
	gs.level = 20
	check(flea.list_block_reason(medic, 100000) != "", "nor listed on the flea (\"%s\")" % flea.list_block_reason(medic, 100000))
	var wanted: RefCounted = load("res://scripts/progression/requirement.gd").from_dict({"item": "figure_bear_medic", "count": 1})
	check(wanted.have() == 0 and wanted.have_in_stash() == 0, "barters, quests and the hideout don't count it")
	check(figs.owned("figure_bear_medic") == 1, "but it's yours: the collection counts it")


func _bonuses() -> void:
	section("Each set bonus, on and off")
	_profile(3)
	var search: RefCounted = load("res://scripts/inventory/loot_search.gd").new(func() -> Array: return [], 1.0)
	var scav: RefCounted = item("figure_scav")
	var base_search: float = search.time_for(scav)
	_display_set("raiders")
	check(figs.set_complete("raiders") and is_equal_approx(search.time_for(scav), base_search / 1.05), "Raiders: loot search 5%% faster (%.3f s, was %.3f)" % [search.time_for(scav), base_search])
	check(figs.active_lines() == ["Raiders: +5% loot search speed"], "the active bonus is listed (%s)" % str(figs.active_lines()))
	figs.remove(figs.slot_of("figure_rat"))
	check(not figs.set_complete("raiders") and is_equal_approx(search.time_for(scav), base_search) and figs.active_lines().is_empty(), "one taken down: off at once")

	gs.raid = {"side": "pmc", "map": "test_yard", "seed": 4}
	var controller: Node = load("res://scripts/raid/raid_controller.gd").new()
	var pmc: Node = load("res://scripts/actors/actor.gd").new()
	pmc.side = pmc.Side.PMC
	controller._on_kill(pmc)
	var plain: int = controller.xp
	_display_set("factions")
	controller._on_kill(pmc)
	check(plain == 300 and controller.xp - plain == 315, "Factions: a PMC kill gives 315 XP, not 300 (%d, %d)" % [plain, controller.xp - plain])
	var poi: Node = load("res://scripts/world/point_of_interest.gd").new()
	poi.map_id = "factory"
	poi.poi_id = str(load("res://scripts/data/poi_table.gd").for_map("factory")[0].id)
	var explore_base: int = controller.discovery_xp(poi)
	_display_set("landmarks")
	check(controller.discovery_xp(poi) == roundi(explore_base * 1.1), "Landmarks: 10%% more exploration XP (%d, was %d)" % [controller.discovery_xp(poi), explore_base])
	figs.remove(figs.slot_of("figure_courier_van"))
	figs.remove(figs.slot_of("figure_usec_breacher"))
	controller._on_kill(pmc)
	check(controller.discovery_xp(poi) == explore_base and controller.xp - plain - 315 == 300, "both off again with one figure down")
	controller.free()
	pmc.free()
	poi.free()
	gs.raid = {}

	var trading: GDScript = load("res://scripts/progression/trading.gd")
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	var offer: Dictionary = trading.buy_list("bulat")[0]
	var gpu: RefCounted = item("gpu")
	var buy_before: int = trading.price("bulat", offer)
	var sell_before: int = selling.price("broker", gpu)
	_display_set("traders")
	var buy_after: int = trading.price("bulat", offer)
	var sell_after: int = selling.price("broker", gpu)
	check(buy_after < buy_before and absi(buy_after - roundi(buy_before * 0.97)) <= 1, "Traders: buying 3%% cheaper (%d, was %d)" % [buy_after, buy_before])
	check(absi(sell_after - roundi(sell_before * 1.03)) <= 1 and sell_after > sell_before, "and selling 3%% dearer (%d, was %d)" % [sell_after, sell_before])
	check(trading.discount_text("mole") == "Prices: 3% better both ways (Collectors Shelf)" and trading.discount_text("bulat").ends_with("  ·  3% better both ways (Collectors Shelf)"),
		"the trader panel says so (%s)" % trading.discount_text("bulat"))
	figs.remove(figs.slot_of("figure_mole"))
	check(trading.price("bulat", offer) == buy_before and selling.price("broker", gpu) == sell_before, "off again: the old prices")

	var bosses: GDScript = load("res://scripts/data/boss_table.gd")
	var boss: Dictionary = bosses.maps().values()[0]
	var chance := float(boss.chance)
	check(is_equal_approx(bosses.chance(boss), chance), "a boss's chance is its own without the Bosses set (%.2f)" % chance)
	_display_set("bosses")
	check(is_equal_approx(bosses.chance(boss), minf(chance + 0.1, 1.0)), "Bosses: 10 points more (%.2f)" % bosses.chance(boss))
	boss.chance = 0.95
	check(is_equal_approx(bosses.chance(boss), 1.0), "never above 100%")
	boss.chance = chance
	figs.remove(figs.slot_of("figure_krane"))
	check(is_equal_approx(bosses.chance(boss), chance), "off again")

	var consumables: GDScript = load("res://scripts/inventory/consumables.gd")
	var health: RefCounted = load("res://scripts/actors/body_health.gd").new(load("res://data/config/health.tres"))
	health.start_metabolism(load("res://data/config/consumables.tres"), 80.0, 80.0)
	health.metabolism_skill = consumables.drain_multiplier()
	var energy: float = health.energy_rate()
	var water: float = health.hydration_rate()
	_display_set("wildlife")
	health.metabolism_skill = consumables.drain_multiplier()
	check(energy < 0.0 and is_equal_approx(health.energy_rate(), energy * 0.9) and is_equal_approx(health.hydration_rate(), water * 0.9),
		"Wildlife: energy and hydration drain 10%% slower (%.4f, was %.4f)" % [health.energy_rate(), energy])
	figs.remove(figs.slot_of("figure_fox"))
	health.metabolism_skill = consumables.drain_multiplier()
	check(is_equal_approx(health.energy_rate(), energy), "off again")

	check(figs.free_spins_a_day() == 0, "no free Drip spin without the Oddities set")
	_display_set("oddities")
	check(figs.free_spins_a_day() == 1 and figs.bonus("drip_spin") == 1.0, "Oddities: one free Drip spin a day")
	check(figs.bonus_note("drip_spin") == "Collectors Shelf (Oddities set): +1 free Drip slot spin a day", "the bonus note (%s)" % figs.bonus_note("drip_spin"))


## Spares: copies beyond the one you keep.
func _spares() -> void:
	section("Spares")
	_profile(1)
	var kept: RefCounted = _give("figure_hare", true)
	var spare: RefCounted = _give("figure_hare")
	_give("figure_fox")
	var ids: Array = figs.spares().map(func(each: RefCounted) -> RefCounted: return each)
	check(ids == [spare], "two hares and a fox: the hare not found in raid is the spare, the fox is kept")
	figs.place(_give("figure_fox"), 0)
	check(figs.spares().size() == 2 and figs.spares().has(spare) and not figs.spares().has(kept), "a fox on the shelf: the one in the stash is a spare too")
	check(figs.spare_count({"rarity": "common"}) == 2 and figs.spare_count({"set": "wildlife"}) == 2 and figs.spare_count({"rarity": "rare"}) == 0,
		"spares counted by rarity and set")
	check(figs.spare_count({"rarity": "common"}, true) == 0, "only found-in-raid ones when asked (none: the kept hare isn't a spare)")
	check(figs.filter_text({"rarity": "rare"}) == "Any Rare figure" and figs.filter_text({"set": "wildlife", "rarity": "epic"}) == "Any Epic Wildlife figure",
		"filters as words (%s)" % figs.filter_text({"set": "wildlife", "rarity": "epic"}))
	check(figs.take_spares({"rarity": "common"}, 5) == 2 and gs.stash.count_of("figure_hare") == 1 and gs.stash.count_of("figure_fox") == 0 and figs.placed(0) != null,
		"taking spares takes those two only: the kept hare and the shelf's fox stay")


func _free_spin() -> void:
	section("The free Drip spin allowance")
	_profile(1)
	work.now_override = NOW
	check(not figs.use_free_spin(), "none without the Oddities set")
	_display_set("oddities")
	check(figs.free_spins_left() == 1 and figs.use_free_spin() and figs.free_spins_left() == 0 and not figs.use_free_spin(), "one a real day, then none")
	var saved: Dictionary = gs.to_dict()
	gs.from_dict(saved)
	check(figs.free_spins_left() == 0, "a reload doesn't give it back")
	work.now_override = NOW + DAY
	check(figs.free_spins_left() == 1, "the next real day it's back")
	work.now_override = NOW


func _saves() -> void:
	section("Saves (version 18)")
	check(sm.SAVE_VERSION >= 18, "the save version is 18 or later (19: E11 quests)")
	_profile(2)
	figs.place(_give("figure_lynx", true), 20)
	figs.place(_give("figure_chad"), 2)
	_give("figure_boar")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	check(saved.profile.figures.shelf.size() == 2 and "figure_boar" in saved.profile.figures.seen, "the shelf and the seen list are saved")
	_profile(0)
	gs.from_dict(saved)
	check(figs.displayed_count() == 2 and figs.placed(20).data.id == "figure_lynx" and figs.placed(20).fir and figs.placed(2).data.id == "figure_chad" and not figs.placed(2).fir,
		"loaded back: each figure in its slot, found in raid as it was")
	check(figs.is_seen("figure_boar") and figs.is_seen("figure_lynx") and not figs.is_seen("figure_leshy"), "the seen list too")
	check(gs.stash.count_of("figure_lynx") == 0 and gs.stash.count_of("figure_boar") == 1, "nothing doubled into the stash")
	# A shelf the save's level can't hold: the figure past the slots goes to the stash, never lost.
	saved.profile.hideout.collectors_shelf = 1
	saved.profile.figures.shelf.append({"slot": 3, "item": {"id": "no_such_figure"}})
	gs.from_dict(saved)
	check(figs.displayed_count() == 1 and figs.placed(2) != null and gs.stash.count_of("figure_lynx") == 1, "a figure in a slot the shelf no longer has comes back to the stash")
	var old := {"version": 17, "profile": {"faction": "BEAR", "level": 9, "xp": 30000, "roubles": 250000, "hideout": {"stash": 1}},
		"stash": [{"id": "figure_scav", "x": 0, "y": 0}]}
	var upgraded: Dictionary = sm.upgrade(old)
	check(int(upgraded.version) == sm.SAVE_VERSION, "a version 17 save comes up to the current version")
	gs.from_dict(upgraded)
	check(figs.displayed_count() == 0 and gs.level == 9 and gs.stash.count_of("figure_scav") == 1, "and loads with an empty shelf, progress kept")
	check(figs.is_seen("figure_scav") and gs.figures.spin.day == -1, "what it owns counts as seen; no spin used")


func _selling() -> void:
	section("Selling figures")
	_profile(1)
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	var traders: GDScript = load("res://scripts/data/trader_table.gd")
	var lynx: RefCounted = _give("figure_lynx")
	var buyers := []
	for trader: String in traders.ids():
		if selling.buys(trader, lynx.data):
			buyers.append(trader)
	check(buyers == ["zoya", "mole", "broker"], "Auntie Zoya, Mole and the Broker buy figures (%s)" % str(buyers))
	var roubles: int = gs.roubles
	var paid: int = selling.price("mole", lynx)
	check(paid > 0 and selling.sell("mole", [lynx]) == "" and gs.roubles == roubles + paid and gs.stash.count_of("figure_lynx") == 0, "sold to Mole for %d" % paid)


func _generic_barters() -> void:
	section("Barters for any spare figures")
	_profile(1)
	var barters: GDScript = load("res://scripts/data/barter_table.gd")
	var trading: GDScript = load("res://scripts/progression/trading.gd")
	var requirement: GDScript = load("res://scripts/progression/requirement.gd")
	var generic := []
	for barter: Dictionary in barters.all():
		if barters.requirements(barter).any(func(wanted: RefCounted) -> bool: return wanted.is_generic()):
			generic.append(barter.id)
	check(generic == ["zoya_barter_figures_uncommon", "zoya_barter_figure_ultra_rare", "mole_barter_figures_common", "mole_barter_figures_rare"],
		"four barters ask for any figures: two at Auntie Zoya's, two at Mole's (%s)" % str(generic))
	var commons: Dictionary = barters.find("mole_barter_figures_common")
	var wanted: RefCounted = barters.requirements(commons)[0]
	check(wanted.title() == "Any Common figure" and wanted.count == 3 and wanted.item_data().id == "figure_scav", "it reads \"Any Common figure ×3\", the cheapest one its sample")
	var keep_hare: RefCounted = _give("figure_hare", true)
	_give("figure_hare")
	_give("figure_fox")
	_give("figure_scav")
	check(wanted.have_in_stash() == 1 and trading.barter_block_reason(commons, "mole").begins_with("Missing from the stash: Any Common figure ×2"),
		"four Common figures of three kinds: one spare, so it can't trade yet (%s)" % trading.barter_block_reason(commons, "mole"))
	var on_shelf: RefCounted = _give("figure_courier_van")
	figs.place(on_shelf, 0)
	_give("figure_courier_van")
	_give("figure_fox")
	check(wanted.have_in_stash() == 3 and trading.barter_block_reason(commons, "mole") == "", "a second fox and a van whose kind is on the shelf: three spares")
	var medals: int = gs.stash.count_of("military_medal")
	check(trading.barter(commons, "mole") == "" and gs.stash.count_of("military_medal") == medals + 1, "traded for a military medal")
	check(gs.stash.count_of("figure_hare") == 1 and gs.stash.count_of("figure_fox") == 1 and gs.stash.count_of("figure_scav") == 1 and gs.stash.count_of("figure_courier_van") == 0
		and figs.placed(0) == on_shelf and gs.stash.all_items().has(keep_hare), "the spares went (a hare, a fox, the van): one of each kind is kept, the shelf's untouched")
	var broken := {"id": "test_barter", "trader": "mole", "ll": 1, "requires": [{"figures": {"rarity": "shiny"}, "count": 2}], "rewards": [{"item": "bandage", "count": 1}], "reward_rarity": "common"}
	check(barters.check(broken).any(func(problem: String) -> bool: return "figure rarity shiny doesn't exist" in problem), "an unknown rarity is caught")
	broken.requires = [{"figures": {"set": "toys"}, "count": 2}]
	check(barters.check(broken).any(func(problem: String) -> bool: return "figure set toys doesn't exist" in problem), "an unknown set is caught")
	broken.requires = [{"figures": {"rarity": "epic"}, "count": 1}]
	check(barters.check(broken).any(func(problem: String) -> bool: return "rewards must be Rare or better" in problem), "an Epic figure counts as a valuable for the rarity rules")
	# Two generic requirements share no spare: the stricter picks first.
	_profile(1)
	_give("figure_lynx")
	_give("figure_lynx")
	_give("figure_cliffside_bunker")
	_give("figure_cliffside_bunker")
	var both: Array = [requirement.from_dict({"figures": {"rarity": "rare"}, "count": 1}), requirement.from_dict({"figures": {"rarity": "rare", "set": "wildlife"}, "count": 1})]
	var claimed: Dictionary = figs.claim(both)
	check(claimed.ok and claimed.items.size() == 2 and claimed.items.any(func(each: RefCounted) -> bool: return each.data.id == "figure_lynx")
		and claimed.items.any(func(each: RefCounted) -> bool: return each.data.id == "figure_cliffside_bunker"), "\"any Rare\" and \"any Rare Wildlife\": the lynx for the Wildlife one, the bunker for the other")
	both.append(requirement.from_dict({"figures": {"rarity": "rare"}, "count": 1}))
	check(not figs.claim(both).ok, "a third needs a third spare")


func _quest_line() -> void:
	section("The Collector quest line")
	_profile(1)
	var quests: GDScript = load("res://scripts/progression/quest_log.gd")
	var line := ["collector_shelf_talk", "collector_odd_lots", "collector_menagerie", "collector_full_house", "collector_the_collector"]
	var found := []
	for quest: Dictionary in quests.for_trader("mole"):
		if str(quest.id).begins_with("collector_"):
			found.append(quest.id)
	check(found == line, "five chained quests from Mole (%s)" % str(found))
	check(quests.problems().is_empty(), "the quest files have no problems (%s)" % str(quests.problems()))
	var last: Dictionary = quests.find("collector_the_collector")
	check(last.rewards.items[0].item == "secure_omega" and item("secure_omega").contents.size == Vector2i(4, 4) and item("secure_kappa").contents.size == Vector2i(3, 4) and db.get_item("secure_omega").stats.secure,
		"the last gives Secure container Omega: 4×4, bigger than Kappa's 3×4")
	gs.level = 20
	var gives := {
		"collector_shelf_talk": ["figure_scav", "figure_fox", "figure_hare"],
		"collector_odd_lots": ["figure_rat", "figure_boar", "figure_pool_house", "figure_rat"],
		"collector_menagerie": ["figure_chad", "figure_lynx", "figure_glowing_mushroom"],
		"collector_full_house": ["figure_bear_medic", "figure_old_oak", "figure_maintenance_cart"],
		"collector_the_collector": ["figure_krane", "figure_quester"],
	}
	for id: String in line:
		var quest: Dictionary = quests.find(id)
		check(quests.accept(quest), "%s: accepted once the one before is done" % quest.name)
		# Each figure twice, so every one handed over is a spare.
		for figure: String in gives[id]:
			_give(figure)
			_give(figure)
		for index in quest.objectives.size():
			quests.hand_in(quest, index)
		check(quests.state(quest) == "ready" and quests.complete(quest) == "", "%s: handed over in spares and turned in" % quest.name)
	var kept := true
	for id: String in gives:
		for figure: String in gives[id]:
			kept = kept and gs.stash.count_of(figure) >= 1
	check(kept, "one of every figure is still in the stash: only spares went")
	check(gs.stash.count_of("secure_omega") == 1, "Secure container Omega is in the stash")
	_profile(1)
	var first: Dictionary = quests.find("collector_shelf_talk")
	quests.accept(first)
	_give("figure_fox")
	_give("figure_hare")
	check(quests.hand_in(first, 0) == 0 and quests.objective(first, 0).have() == 0, "one fox and one hare: no spares, nothing handed over")
	figs.place(_give("figure_lynx"), 0)
	check(quests.hand_in(first, 0) == 0 and figs.placed(0) != null, "the shelf's lynx isn't handed over either")


## DESIGN.md §6.6's table of every figure, as the data has it: | Set | Figure | Rarity | Value | Weight |.
## The check fails while DESIGN.md says anything else (the expected table is written to
## user://figure_table.md to paste in).
func _design_table() -> void:
	section("DESIGN.md's table of every figure")
	var lines: Array[String] = ["| Set | Figure | Rarity | Value | Weight |", "|---|---|---|---|---|"]
	var money: Callable = load("res://scripts/ui/ui_format.gd").thousands
	for data: Resource in ft.figures():
		lines.append("| %s | %s | %s | ₽ %s | %s kg |" % [ft.set_title(ft.set_of(data)), data.display_name, ["Common", "Uncommon", "Rare", "Ultra Rare", "Epic", "Legendary"][data.rarity],
			money.call(data.base_value), str(snappedf(data.weight_kg, 0.01))])
	var table := "\n".join(lines)
	var design := FileAccess.get_file_as_string("res://DESIGN.md")
	if not table in design:
		var file := FileAccess.open("user://figure_table.md", FileAccess.WRITE)
		file.store_string(table + "\n")
		file.close()
	check(table in design, "DESIGN.md §6.6 has the table of every figure as the data has it (expected: %s)" % ProjectSettings.globalize_path("user://figure_table.md"))
