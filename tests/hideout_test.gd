extends "res://tests/test_base.gd"
## The hideout (DESIGN.md §9): every station's data and the loader's checks (a broken copy for each
## rule), rules.json and the cosmetics, and loading saves from before the hideout's real-time state
## (version 16) with their levels kept.

const NOW := 1_000_000.0
const HOUR := 3600.0

var hideout: GDScript
var work: GDScript


func run() -> void:
	hideout = load("res://scripts/progression/hideout.gd")
	work = load("res://scripts/progression/hideout_work.gd")
	_data()
	_loader()
	_migration()
	_handover()
	_builds()
	_crafts()
	work.now_override = -1.0


## Gives `amount` of `id` to the stash, found in raid or not.
func _give(id: String, amount := 1, found := false) -> void:
	for i in amount:
		var piece := item(id)
		piece.fir = found
		gs.stash.add(piece)


## Moves the hideout clock on `minutes` and brings it up to date.
func _later(minutes: float) -> void:
	work.now_override += minutes * 60.0
	work.update()


## A station built to `at_level` at once (for the checks that need it).
func _built(id: String, at_level := 1) -> Dictionary:
	gs.hideout[id] = at_level
	return hideout.find(id)


func _requirement(id: String, count: int, fir: bool) -> RefCounted:
	return load("res://scripts/progression/requirement.gd").from_dict({"item": id, "count": count, "fir": fir})


## A new BEAR profile at `when` with plenty of money.
func _profile(when := NOW) -> void:
	work.now_override = when
	fresh_profile()
	gs.roubles = 50_000_000


func _data() -> void:
	section("Every station's data")
	check(hideout.problems().is_empty(), "the hideout data has no problems (%s)" % str(hideout.problems()))
	var ids: Array = hideout.stations().map(func(station: Dictionary) -> String: return station.id)
	check(ids == hideout.ALL_STATIONS and ids.size() == 13, "all 13 stations, in order (%s)" % str(ids))
	for station: Dictionary in hideout.stations():
		var levels: int = station.levels.size()
		check(levels == (4 if station.id == "stash" else 3), "%s has %d levels" % [station.name, levels])
		var times: Array = station.levels.map(func(entry: Dictionary) -> float: return float(entry.build_minutes))
		var rising := true
		for i in range(1, times.size()):
			rising = rising and times[i] > times[i - 1]
		var first: float = times[hideout.start_level(station)] if hideout.start_level(station) < times.size() else 0.0
		check(rising and first <= (60.0 if station.id == "stash" else 30.0) and times[-1] >= 150.0 and times[-1] <= 360.0,
			"%s builds in real time: minutes for the first level built, hours for the top (%s min)" % [station.name, str(times)])
		var fir := true
		for entry: Dictionary in station.levels.slice(1):
			for wanted: Dictionary in entry.get("requires", []):
				fir = fir and bool(wanted.get("fir", false))
		check(fir, "%s: every item from level 2 must be found in raid" % station.name)
	for id in ["water_collector", "bitcoin_farm"]:
		var caps: Array = hideout.find(id).levels.map(func(entry: Dictionary) -> int: return int(entry.produces.cap))
		check(caps[0] < caps[1] and caps[1] < caps[2], "the %s holds more each level (%s)" % [id, str(caps)])
	var slots: Array = hideout.find("generator").levels.map(func(entry: Dictionary) -> int: return int(entry.fuel_slots))
	var efficiency: Array = hideout.find("generator").levels.map(func(entry: Dictionary) -> float: return float(entry.fuel_efficiency))
	check(slots == [2, 4, 6] and efficiency == [1.0, 1.25, 1.5], "generator levels add fuel slots (%s) and efficiency (%s)" % [str(slots), str(efficiency)])
	var cards: Array = hideout.find("bitcoin_farm").levels.map(func(entry: Dictionary) -> int: return int(entry.card_slots))
	check(cards == [3, 6, 10] and hideout.find("bitcoin_farm").cards.item == "gpu", "the farm takes more graphics cards each level (%s)" % str(cards))
	var cooldown: Array = hideout.find("intelligence_center").levels.map(func(entry: Dictionary) -> float: return float(entry.scav_cooldown))
	check(cooldown == [0.9, 0.8, 0.7], "the Intelligence Center shortens the Scav cooldown more each level (%s)" % str(cooldown))
	check(hideout.find("bitcoin_farm").unpowered_rate == 0.0 and hideout.unpowered_rate(hideout.find("bitcoin_farm")) == 0.0
		and hideout.unpowered_rate(hideout.find("medstation")) == 0.5 and hideout.unpowered_rate(hideout.find("gym")) == 1.0,
		"without power the farm stops, crafts go at half speed, the Gym doesn't care")
	var needs_level := false
	var needs_loyalty := false
	for station: Dictionary in hideout.stations():
		for entry: Dictionary in station.levels:
			needs_level = needs_level or entry.has("player_level")
			needs_loyalty = needs_loyalty or entry.has("traders")
	check(needs_level and needs_loyalty, "some levels need a player level, some a trader's loyalty level")
	var crafts := 0
	for station: Dictionary in hideout.stations():
		crafts += hideout.all_crafts(station).size()
	check(crafts == 59 and hideout.all_crafts(hideout.find("lavatory")).size() == 7, "all 57 earlier crafts and the Lavatory's two new ones (%d)" % crafts)
	check(hideout.cosmetics().size() == 4 and hideout.plan_size() == Vector2i(32, 20) and hideout.craft_queue_size() == 3,
		"four cosmetics, a 32 x 20 plan, three crafts queued a station")


## problems() on a broken copy of the data: each rule caught.
func _loader() -> void:
	section("Loader checks")
	var original: Array = hideout._stations.duplicate(true)
	var cases := [
		["an unknown level key", func(all: Array) -> void: all[0].levels[0]["speed"] = 2, "unknown key \"speed\""],
		["no build time", func(all: Array) -> void: all[0].levels[1].erase("build_minutes"), "needs build_minutes"],
		["a level-2 item not found in raid", func(all: Array) -> void: all[0].levels[1].requires[0].erase("fir"), "must be found in raid"],
		["an item named twice", func(all: Array) -> void: all[0].levels[0].requires.append({"item": "fuel_can", "count": 1}), "names fuel_can twice"],
		["overlapping rooms", func(all: Array) -> void: all[1].room = [1, 1, 3, 3], "overlaps"],
		["a room off the plan", func(all: Array) -> void: all[0].room = [30, 0, 6, 5], "isn't inside"],
		["a missing station", func(all: Array) -> void: all.pop_back(), "no security station"],
		["a player level that doesn't exist", func(all: Array) -> void: all[0].levels[2].player_level = 999, "player_level 999"],
		["fuel on another station", func(all: Array) -> void: all[2]["fuel"] = {"fuel_can": 10}, "only the generator has fuel"],
		["a farm level without card slots", func(all: Array) -> void: _station(all, "bitcoin_farm").levels[1].erase("card_slots"), "needs \"card_slots\""],
		["a production cap of 0", func(all: Array) -> void: _station(all, "water_collector").levels[0].produces.cap = 0, "produces needs"],
		["a craft without a time", func(all: Array) -> void: _station(all, "medstation").levels[0].crafts[0].erase("minutes"), "needs minutes above 0"],
		["two crafts with one id", func(all: Array) -> void: _station(all, "workbench").levels[0].crafts[1].id = "bs_rounds", "an id no other craft has"],
		["scouting on the wrong station", func(all: Array) -> void: all[0].levels[0]["scouting"] = 1, "only the security station sets scouting"],
		["an insurance multiplier above 1", func(all: Array) -> void: _station(all, "intelligence_center").levels[0].insurance_price = 1.5, "insurance_price is a multiplier"],
		["generator efficiency going down", func(all: Array) -> void: all[0].levels[2].fuel_efficiency = 0.5, "never go down"],
	]
	for case: Array in cases:
		var copy: Array = original.duplicate(true)
		case[1].call(copy)
		hideout._stations.assign(copy)
		var found: Array = hideout.problems()
		check(found.any(func(problem: String) -> bool: return case[2] in problem), "%s is caught (%s)" % [case[0], str(found)])
	hideout._stations.assign(original)
	var cosmetics: Array = hideout._cosmetics.duplicate(true)
	hideout._cosmetics[1].slot = "lighting"
	check(hideout.problems().any(func(problem: String) -> bool: return "another cosmetic has it" in problem), "two cosmetics in one slot are caught")
	hideout._cosmetics.assign(cosmetics)
	check(hideout.problems().is_empty(), "the real data is back without problems")


func _station(all: Array, id: String) -> Dictionary:
	for station: Dictionary in all:
		if station.id == id:
			return station
	return {}


func _migration() -> void:
	section("Saves from before version 17")
	_profile()
	var old := {"version": 16, "profile": {"faction": "BEAR", "level": 9, "xp": 30000, "roubles": 250000,
		"hideout": {"stash": 2, "generator": 2, "medstation": 3, "lavatory": 2, "workbench": 1}},
		"stash": [{"id": "gpu", "x": 0, "y": 0}]}
	var result: Dictionary = sm.upgrade(old)
	check(int(result.version) == 17 and sm.SAVE_VERSION == 17, "a version 16 save comes up to version 17")
	work.now_override = NOW + 5.0 * HOUR
	gs.from_dict(old)
	check(gs.hideout == {"stash": 2, "generator": 2, "medstation": 3, "lavatory": 2, "workbench": 1}, "every level it built is kept (%s)" % str(gs.hideout))
	check(gs.stash.size == Vector2i(10, 40) and gs.stash.count_of("gpu") == 1, "the stash keeps its level-2 size and its items")
	var state: Dictionary = gs.hideout_state
	check(is_equal_approx(state.clock, NOW + 5.0 * HOUR) and state.builds.is_empty() and state.crafts.is_empty() and state.fuel.is_empty()
		and state.handed.is_empty() and state.cosmetics.is_empty(), "it starts with nothing handed over, building, crafting or fuelled, the clock at load")
	var saved: Dictionary = gs.to_dict()
	check(saved.profile.hideout_state is Dictionary and saved.profile.hideout_state.has("clock"), "the hideout state is saved")
	var junk := {"clock": "x", "handed": {"medstation": {"bandage": 2, "no_such_item": 4}, "no_such_station": {"bolts": 1}},
		"crafts": {"medstation": [{"id": "medkit", "output": {"item": "ai2_medkit", "count": 1}, "left": 50.0, "total": 300.0}, "junk"]},
		"cards": [{"id": "gpu"}, {"id": "no_such_item"}], "cosmetics": ["poster_wall", "no_such_cosmetic", "poster_wall"]}
	var clean: Dictionary = work.from_save(junk)
	check(clean.handed == {"medstation": {"bandage": 2}} and clean.crafts.medstation.size() == 1 and clean.crafts.medstation[0].left == 50.0
		and clean.cards.size() == 1 and clean.cosmetics == ["poster_wall"], "a damaged state is cleaned: unknown stations, items and cosmetics drop out")


func _handover() -> void:
	section("Handing items over")
	_profile()
	var generator: Dictionary = _built("generator")
	var level2: Array = hideout.requirements(hideout.next_level(generator))
	var cans: RefCounted = level2[0]
	check(cans.item_id == "fuel_can" and cans.count == 2 and cans.fir, "Generator level 2 wants 2 fuel cans found in raid")
	_give("fuel_can", 1, false)
	check(hideout.hand_over(generator, cans) == "You have none found in raid" and hideout.handed(generator, "fuel_can") == 0,
		"one that isn't found in raid doesn't count")
	_give("fuel_can", 1, true)
	check(hideout.hand_over(generator, cans) == "" and hideout.handed(generator, "fuel_can") == 1 and hideout.still_needed(generator, cans) == 1
		and gs.stash.count_of("fuel_can") == 1, "the found-in-raid one is handed over: 1 / 2, the other stays in the stash")
	check(hideout.upgrade(generator) == "Missing items", "the build can't start with items missing")
	_give("fuel_can", 3, true)
	check(hideout.hand_over(generator, cans) == "" and hideout.handed(generator, "fuel_can") == 2 and gs.stash.count_of("fuel_can") == 3,
		"handing over again takes only the one still needed")
	check(hideout.hand_over(generator, cans) == "All handed over", "then that item is done")
	gs.to_dict()
	var saved: Dictionary = gs.to_dict()
	gs.from_dict(saved)
	check(hideout.handed(generator, "fuel_can") == 2, "what's handed over is kept on the station through a save")
	_give("wires", 1, true)
	_give("pressure_gauge", 1, true)
	var roubles: int = gs.roubles
	check(hideout.upgrade(generator) == "" and hideout.is_building(generator) and gs.roubles == roubles and gs.stash.count_of("wires") == 0
		and gs.stash.count_of("fuel_can") == 3 and gs.hideout_state.handed.get("generator", {}).is_empty(),
		"BUILD hands over the rest you have and starts: the handed cans are used, the 3 in the stash kept")
	check(hideout.hand_over(generator, cans) == "Building", "nothing more is handed over while it builds")
	var medstation: Dictionary = hideout.find("medstation")
	gs.roubles = 1000
	_give("bandage", 2)
	check(hideout.upgrade(medstation) == "Not enough roubles" and search_count("bandage") >= 2, "the money is paid when the build starts")


func search_count(id: String) -> int:
	return load("res://scripts/progression/item_search.gd").count(id, false)


func _builds() -> void:
	section("Builds take real time, also while the game is closed")
	_profile()
	var lavatory: Dictionary = hideout.find("lavatory")
	_give("duct_tape")
	_give("toilet_paper")
	check(hideout.upgrade(lavatory) == "" and hideout.level(lavatory) == 0 and is_equal_approx(hideout.build_seconds_left(lavatory), 180.0),
		"the Lavatory's level 1 starts: 3 minutes to go")
	check(hideout.upgrade(lavatory).begins_with("Building: 3 min left"), "UPGRADE says it's building (%s)" % hideout.upgrade(lavatory))
	_later(1.0)
	check(hideout.level(lavatory) == 0 and is_equal_approx(hideout.build_seconds_left(lavatory), 120.0), "a minute later: 2 minutes left")
	var saved: Dictionary = gs.to_dict()
	work.now_override += 10.0 * HOUR
	gs.from_dict(saved)
	check(hideout.level(lavatory) == 1 and not hideout.is_building(lavatory), "closed for 10 hours: it finished meanwhile")
	var stash_station: Dictionary = hideout.find("stash")
	gs.trader_loyalty.bulat.level = 2
	for id in ["bolts", "screws"]:
		_give(id, 5, true)
	_give("duct_tape", 2, true)
	check(hideout.upgrade(stash_station) == "" and gs.stash.size == Vector2i(10, 30), "the Stash's level 2 starts building")
	saved = gs.to_dict()
	work.now_override += 41.0 * 60.0
	gs.from_dict(saved)
	check(gs.hideout.stash == 2 and gs.stash.size == Vector2i(10, 40), "loaded 41 minutes later, the stash has grown")
	var gym: Dictionary = hideout.find("gym")
	gs.level = 1
	gs.hideout.rest_space = 2
	gs.hideout.gym = 2
	check(hideout.upgrade(gym) == "Needs player level 12", "the Gym's level 3 needs player level 12")
	var clock: float = gs.hideout_state.clock
	work.now_override -= 2.0 * HOUR
	work.update()
	check(gs.hideout_state.clock == clock, "the clock never runs backwards")
	work.now_override += 2.0 * HOUR


func _crafts() -> void:
	section("Crafts: queued, real time, collected")
	_profile()
	var medstation: Dictionary = _built("medstation")
	var recipe: Dictionary = hideout.all_crafts(medstation)[2][1]  # Glucose shot, 5 minutes.
	check(recipe.id == "glucose_shot" and int(recipe.minutes) == 5, "the glucose shot takes 5 minutes")
	_give("empty_injector", 5)
	_give("sugar", 5)
	for i in 3:
		check(work.craft(medstation, recipe) == "", "craft %d is queued" % (i + 1))
	check(work.craft(medstation, recipe) == "The queue is full (3)" and search_count("empty_injector") == 2, "a fourth doesn't fit the queue; inputs went for three")
	_built("generator")
	gs.hideout_state.fuel.append({"item": "fuel_can", "left": 4.0 * HOUR})
	check(work.has_power(), "with fuel the generator powers the hideout")
	_later(4.0)
	check(work.ready(medstation).is_empty() and work.queue(medstation).size() == 3 and is_equal_approx(work.queue(medstation)[0].left, 60.0),
		"4 minutes in, the first has a minute left")
	_later(2.0)
	check(work.ready(medstation).size() == 1 and work.queue(medstation).size() == 2 and is_equal_approx(work.queue(medstation)[0].left, 240.0),
		"6 minutes in: one done, the next a minute in")
	var saved: Dictionary = gs.to_dict()
	work.now_override += 1.0 * HOUR
	gs.from_dict(saved)
	check(work.ready(medstation).size() == 3 and work.queue(medstation).is_empty(), "loaded an hour later, all three are done")
	var shots: int = gs.stash.count_of("glucose_shot")
	check(work.collect(medstation) == "" and gs.stash.count_of("glucose_shot") == shots + 3 and work.ready(medstation).is_empty(), "COLLECT puts the three in the stash")
	var fir := 0
	for each in gs.stash.items:
		if each.data.id == "glucose_shot" and each.fir:
			fir += 1
	check(fir == 3, "found in raid, as crafts always are")
	check(work.collect(medstation) == "Nothing to collect", "nothing left to collect")
	check(work.craft(medstation, recipe) == "", "another one queued")
	gs.hideout_state.power_on = false
	_later(5.0)
	check(work.ready(medstation).is_empty() and is_equal_approx(work.queue(medstation)[0].left, 150.0), "generator off: 5 minutes do half the work")
	gs.hideout_state.power_on = true
	_later(2.5)
	var filler := []
	while gs.stash.add(item("gold_bar")):
		filler.append(true)
	check(work.collect(medstation) == "No room in the stash" and work.ready(medstation).size() == 1, "with the stash full the craft waits")
