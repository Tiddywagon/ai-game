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
	work.now_override = -1.0


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
