extends "res://tests/test_base.gd"
## The quest system (DESIGN.md §11, docs/plan/E11_quests.md): the loader and its problems() (a broken
## copy per rule), each objective type through its real trigger (live raids on the Test Yard for kills
## with every condition, visit, place and mark with the hold-to-place interaction, extract and
## extract_with; the hideout for craft and upgrade), found-in-raid hand-ins, survive-only progress, death
## keeping the rest, Scav and practice raids counting nothing, chains and states, every reward and unlock
## kind, the log and tracker through their controls, old-save migration and the save round trip.

const QUESTS := "res://scripts/progression/quest_log.gd"
const MAP := "res://maps/test_level.tscn"

var quests: GDScript
var status: Dictionary


func run() -> void:
	quests = load(QUESTS)
	status = load("res://scripts/raid/raid_outcome.gd").Status
	fresh_profile()
	_loader()
	_existing()
	_states_and_chains()
	_rewards_and_unlocks()
	_out_of_raid()
	await _raid_kills()
	await _raid_places()
	await _raid_survive()
	await _raid_not_counted()
	_saves()
	quests.reload()
	_design_table()


## A test quest added to the loaded list (removed again by quests.reload()), accepted unless `take` is false.
func _quest(id: String, objectives: Array, extra := {}, take := true) -> Dictionary:
	var quest := {"id": id, "name": id.capitalize(), "trader": "bulat", "description": "Test.", "objectives": objectives, "rewards": {"xp": 100}}
	quest.merge(extra, true)
	quests.all().append(quest)
	if take:
		quests.accept(quest)
	return quest


func _pmc_raid(extra := {}) -> Dictionary:
	var raid := {"side": "pmc", "map": "test_yard", "loadout": gs.pmc_loadout(), "seed": 4, "boss": true, "pmcs": 0}
	raid.merge(extra, true)
	return raid


# --- The loader --------------------------------------------------------------------------------------

## problems() is clean, then each rule broken in a copy of a valid quest.
func _loader() -> void:
	section("Loader and problems()")
	check(quests.problems().is_empty(), "the quest files have no problems (%s)" % str(quests.problems().slice(0, 3)))
	var list: Array[Dictionary] = quests.all()
	var original: Array[Dictionary] = list.duplicate(true)
	var base := {"id": "probe", "name": "Probe", "trader": "bulat", "description": "x", "objectives": [{"type": "level", "level": 5}], "rewards": {"xp": 1}}
	var cases := [
		[{"trader": "nobody"}, "trader nobody doesn't exist"],
		[{"faction": "red"}, "faction red isn't"],
		[{"requires": ["later_one"]}, "isn't a quest listed before it"],
		[{"loyalty": {"bulat": 9}}, "isn't a trader's level"],
		[{"colour": "red"}, "unknown key \"colour\""],
		[{"gives": [{"item": "no_such_item"}]}, "quest item"],
		[{"rewards": {"items": [{"item": "no_such_item"}]}}, "isn't an item and a count"],
		[{"rewards": {"reputation_with": {"nobody": 0.1}}}, "reputation_with"],
		[{"rewards": {"fame": 1}}, "unknown reward"],
		[{"objectives": []}, "no objectives"],
		[{"objectives": [{"type": "dance"}]}, "isn't one of"],
		[{"objectives": [{"type": "kill", "target": "cow"}]}, "kill target cow"],
		[{"objectives": [{"type": "kill", "target": "scav", "faction": "usec"}]}, "kill faction usec"],
		[{"objectives": [{"type": "kill", "boss": "nobody"}]}, "boss nobody doesn't exist"],
		[{"objectives": [{"type": "kill", "boss": "krane", "map": "factory"}]}, "boss krane isn't on factory"],
		[{"objectives": [{"type": "kill", "weapon": "bandage"}]}, "isn't a gun"],
		[{"objectives": [{"type": "kill", "weapon_class": "catapult"}]}, "weapon class catapult"],
		[{"objectives": [{"type": "kill", "body_part": "tail"}]}, "body part tail"],
		[{"objectives": [{"type": "kill", "min_distance": -5}]}, "min_distance"],
		[{"objectives": [{"type": "kill", "colour": 1}]}, "has no \"colour\""],
		[{"objectives": [{"type": "kill", "map": "moon"}]}, "map moon doesn't exist"],
		[{"objectives": [{"type": "hand_in", "item": "no_such_item"}]}, "hand_in item no_such_item"],
		[{"objectives": [{"type": "visit", "map": "test_yard"}]}, "needs a poi or a spot"],
		[{"objectives": [{"type": "visit", "map": "test_yard", "poi": "nowhere"}]}, "point of interest nowhere"],
		[{"objectives": [{"type": "visit", "map": "test_yard", "spot": "nowhere"}]}, "quest spot nowhere"],
		[{"objectives": [{"type": "mark", "map": "test_yard", "poi": "signal_hut"}]}, "needs the quest to give a marker"],
		[{"objectives": [{"type": "place", "item": "bolts", "map": "test_yard", "poi": "signal_hut", "seconds": 0}]}, "seconds must be above 0"],
		[{"objectives": [{"type": "visit", "map": "test_yard", "poi": "signal_hut", "survive": "yes"}]}, "survive must be true or false"],
		[{"objectives": [{"type": "extract", "map": "test_yard", "extract": "nowhere"}]}, "extract nowhere isn't on map"],
		[{"objectives": [{"type": "extract_with", "item": "no_such_item"}]}, "extract_with item"],
		[{"objectives": [{"type": "explore", "map": "test_yard", "count": 99}]}, "points to explore"],
		[{"objectives": [{"type": "craft", "recipe": "nothing"}]}, "craft nothing doesn't exist"],
		[{"objectives": [{"type": "craft", "item": "bandage", "station": "workbench"}]}, "names one of recipe, item or station"],
		[{"objectives": [{"type": "craft", "item": "zsh_helmet"}]}, "no craft makes"],
		[{"objectives": [{"type": "craft", "station": "stash"}]}, "has no crafts"],
		[{"objectives": [{"type": "upgrade", "station": "workbench", "level": 9}]}, "station workbench level 9"],
		[{"objectives": [{"type": "level", "level": 1}]}, "level of 2 or more"],
		[{"objectives": [{"type": "loyalty", "trader": "bulat", "level": 7}]}, "loyalty bulat LL7"],
		[{"objectives": [{"type": "trick_kill", "target": "boss"}]}, "trick-kill target"],
		[{"objectives": [{"type": "upgrade", "station": "workbench", "level": 2, "count": 2}]}, "has no count"],
	]
	for case: Array in cases:
		var broken: Dictionary = base.duplicate(true)
		broken.merge(case[0], true)
		list.clear()
		list.append(broken)
		var found: Array = quests.problems()
		check(found.any(func(line: String) -> bool: return case[1] in line), "a broken copy is caught: %s (%s)" % [case[1], str(found.slice(0, 2))])
	list.clear()
	list.append(base.duplicate(true))
	var twice: Dictionary = base.duplicate(true)
	list.append(twice)
	check(quests.problems().any(func(line: String) -> bool: return "used twice" in line), "an id used twice is caught")
	var usec: Dictionary = base.duplicate(true)
	usec.id = "probe_usec"
	usec.faction = "usec"
	var after: Dictionary = base.duplicate(true)
	after.id = "probe_after"
	after.faction = "bear"
	after.requires = ["probe_usec"]
	list.clear()
	list.append_array([usec, after])
	check(quests.problems().any(func(line: String) -> bool: return "a quest for usec only" in line), "a prerequisite for the other faction is caught")
	list.clear()
	list.append_array(original)
	check(quests.problems().is_empty(), "the files are clean again")


## The quests that were there before keep their objectives (types, items, counts) and rewards.
func _existing() -> void:
	section("Existing quests keep their schema")
	var scrap: Dictionary = quests.find("scrap_run")
	check(JSON.stringify(scrap.objectives) == JSON.stringify([{"type": "hand_in", "item": "bolts", "count": 3.0, "fir": true}, {"type": "hand_in", "item": "screws", "count": 2.0, "fir": true}]),
		"Scrap Run still asks for 3 bolts and 2 screws, found in raid")
	var contractors: Dictionary = quests.find("bear_contractors")
	check(JSON.stringify(contractors.objectives) == JSON.stringify([{"type": "kill", "target": "pmc", "faction": "usec", "count": 3.0}]), "Contractors still asks for 3 USEC kills")
	check(quests.objective_text(contractors, 0) == "Kill USEC operators", "its line reads \"%s\"" % quests.objective_text(contractors, 0))
	var showboat: Dictionary = quests.find("showboat")
	check(quests.objective_text(showboat, 0) == "360 trick-shot kills", "Showboat: \"%s\"" % quests.objective_text(showboat, 0))
	for quest: Dictionary in quests.all():
		for i in quest.objectives.size():
			if quests.objective_text(quest, i) == "":
				check(false, "%s objective %d has a line" % [quest.id, i])


# --- States, chains -------------------------------------------------------------------------------

func _states_and_chains() -> void:
	section("States and chains")
	fresh_profile()
	var first := _quest("t_first", [{"type": "hand_in", "item": "bolts", "count": 2, "fir": true}], {}, false)
	var second := _quest("t_second", [{"type": "roubles", "count": 1000}], {"requires": ["t_first"], "level": 3, "loyalty": {"vera": 2}}, false)
	check(quests.state(first) == "available" and quests.state(second) == "locked", "the first is available, the second locked")
	check(quests.lock_reason(second) == "Needs player level 3  ·  needs Doc Vera LL2  ·  finish T First first", "it says what's missing: %s" % quests.lock_reason(second))
	check(not quests.accept(second) and quests.accept_block_reason(second) != "", "a locked quest can't be accepted")
	var chain: Array = quests.prerequisites(second)
	check(chain.size() == 3 and chain[0].name == "after T First" and not chain[0].done, "the chain view: %s" % str(chain))
	check(quests.followers(first) == [second], "the first leads to the second")
	check(quests.accept(first) and quests.state(first) == "active", "accept: active")
	for i in 2:
		gs.stash.add(load("res://scripts/inventory/found_in_raid.gd").make("bolts", 1, 0))
	check(quests.hand_in(first, 0) == 0, "bought bolts (not found in raid) don't count")
	for i in 2:
		var found: RefCounted = item("bolts")
		found.fir = true
		gs.stash.add(found)
	check(quests.hand_in(first, 0) == 2 and quests.state(first) == "ready", "found-in-raid bolts count: ready to turn in")
	check(quests.complete(first) == "" and quests.state(first) == "completed", "turned in: completed")
	gs.level = 3
	gs.trader_loyalty.vera.level = 2
	check(quests.state(second) == "available" and quests.prerequisites(second).all(func(each: Dictionary) -> bool: return each.done),
		"with the level, the loyalty and the first done, the second is available, every link ticked")
	quests.reload()


# --- Rewards and unlocks --------------------------------------------------------------------------

func _rewards_and_unlocks() -> void:
	section("Rewards and unlocks")
	fresh_profile()
	var quest := _quest("t_rewards", [{"type": "level", "level": 2}], {"rewards": {"roubles": 1000, "dollars": 10, "xp": 500, "reputation": 0.05,
		"reputation_with": {"vera": 0.03}, "drip": 7, "items": [{"item": "bandage", "count": 2}]}})
	gs.level = 2
	var before := {"roubles": gs.roubles, "dollars": gs.dollars, "xp": gs.xp, "drip": gs.drip, "bulat": float(gs.trader_loyalty.bulat.reputation),
		"vera": float(gs.trader_loyalty.vera.reputation), "bandages": gs.stash.count_of("bandage")}
	check(quests.state(quest) == "ready", "a level objective already met: ready at once")
	check(quests.complete(quest) == "", "turned in")
	check(gs.roubles - before.roubles == 1000 and gs.dollars - before.dollars == 10 and gs.drip - before.drip == 7, "roubles, dollars and Drip paid")
	check(gs.xp != before.xp or gs.level > 2, "experience added")
	check(is_equal_approx(float(gs.trader_loyalty.bulat.reputation) - before.bulat, 0.05) and is_equal_approx(float(gs.trader_loyalty.vera.reputation) - before.vera, 0.03),
		"reputation with the giver and with another trader")
	var plain: int = gs.stash.all_items().filter(func(each: RefCounted) -> bool: return each.data.id == "bandage" and not each.fir).reduce(
		func(total: int, each: RefCounted) -> int: return total + each.count, 0)
	check(gs.stash.count_of("bandage") - before.bandages == 2 and plain >= 2, "reward items in the stash, not found in raid")
	check(quests.reward_lines(quests.find("scrap_run")).has("25,000 ₽"), "reward lines: %s" % str(quests.reward_lines(quests.find("scrap_run"))))
	# Unlock kinds named by existing data.
	var kinds := {}
	for each: Dictionary in quests.all():
		for unlock: Dictionary in quests.unlocks(each):
			kinds[unlock.kind] = true
	for kind in ["barter", "offer", "craft", "extract", "quick_buy", "trader"]:
		check(kinds.has(kind), "some quest unlocks a %s" % kind)
	check(quests.unlocks(quests.find("zoya_introduction")).any(func(each: Dictionary) -> bool: return each.kind == "trader" and each.id == "broker"),
		"A Word in His Ear unlocks The Broker")
	quests.reload()


# --- Out of raid ------------------------------------------------------------------------------------

func _out_of_raid() -> void:
	section("Craft, upgrade, level, loyalty")
	fresh_profile()
	var work: GDScript = load("res://scripts/progression/hideout_work.gd")
	var hideout: GDScript = load("res://scripts/progression/hideout.gd")
	var bench: Dictionary = hideout.find("workbench")
	var quest := _quest("t_out", [{"type": "craft", "recipe": "bs_rounds", "count": 1}, {"type": "craft", "station": "workbench", "count": 2},
		{"type": "craft", "item": "duct_tape"}, {"type": "upgrade", "station": "workbench", "level": 2}, {"type": "level", "level": 4},
		{"type": "loyalty", "trader": "bulat", "level": 2}])
	check(quests.objective_text(quest, 3) == "Build the Workbench to level 2", "upgrade line: %s" % quests.objective_text(quest, 3))
	gs.hideout["workbench"] = 1
	gs.hideout_state.ready = {"workbench": [{"id": "bs_rounds", "output": {"item": "ammo_545_bs", "count": 10}}, {"id": "hex_nuts", "output": {"item": "hex_nuts", "count": 1}}],
		"lavatory": [{"id": "duct_tape", "output": {"item": "duct_tape", "count": 1}}]}
	check(work.collect(bench) == "", "two crafts collected at the Workbench")
	check(quests.progress(quest, 0) == 1 and quests.progress(quest, 1) == 2 and quests.progress(quest, 2) == 0, "a craft id and any craft at the station count")
	work.collect(hideout.find("lavatory"))
	check(quests.progress(quest, 2) == 1, "a craft by its output item counts")
	check(quests.progress(quest, 3) == 1 and quests.state(quest) == "active", "the Workbench at level 1: 1 / 2")
	gs.hideout["workbench"] = 2
	gs.level = 4
	gs.trader_loyalty.bulat.level = 2
	check(quests.progress(quest, 3) == 2 and quests.progress(quest, 4) == 4 and quests.progress(quest, 5) == 2 and quests.state(quest) == "ready",
		"station, level and loyalty reached: ready")
	# Quest-gated crafts and buy offers.
	var gated_craft := {}
	for station: Dictionary in hideout.stations():
		for pair: Array in hideout.all_crafts(station):
			if pair[1].has("quest"):
				gated_craft = {"station": station, "recipe": pair[1], "level": pair[0]}
	check(not gated_craft.is_empty(), "a craft waits for a quest")
	if not gated_craft.is_empty():
		gs.hideout[gated_craft.station.id] = gated_craft.level
		check(work.craft_block_reason(gated_craft.station, gated_craft.recipe).begins_with("Unlocks after"), "it can't start before: %s" % work.craft_block_reason(gated_craft.station, gated_craft.recipe))
		gs.quests[gated_craft.recipe.quest] = {"state": "completed", "progress": []}
		check(not work.craft_block_reason(gated_craft.station, gated_craft.recipe).begins_with("Unlocks after"), "and can once the quest is done")
	var trading: GDScript = load("res://scripts/progression/trading.gd")
	var gated_offer := {}
	var offer_trader := ""
	for trader: String in load("res://scripts/data/trader_table.gd").ids():
		for offer: Dictionary in trading.offers(trader).get("buy", []):
			if offer.has("quest"):
				gated_offer = offer
				offer_trader = trader
	check(not gated_offer.is_empty(), "a buy offer waits for a quest")
	if not gated_offer.is_empty():
		gs.trader_loyalty[offer_trader].level = 4
		gs.roubles = 10000000
		gs.dollars = 100000
		check(trading.buy_block_reason(gated_offer, offer_trader).begins_with("Unlocks after"), "it can't be bought before: %s" % trading.buy_block_reason(gated_offer, offer_trader))
		gs.quests[gated_offer.quest] = {"state": "completed", "progress": []}
		check(trading.buy_block_reason(gated_offer, offer_trader) == "", "and can once the quest is done")
	quests.reload()


# --- Raids --------------------------------------------------------------------------------------------

## Starts `raid` on the Test Yard: returns the RaidController, its bots' AI off and no Scav waves.
func _start(raid: Dictionary) -> Node:
	gs.raid = raid
	change_scene_to_file(MAP)
	await frames(3)
	var controller: Node = root.get_tree().get_first_node_in_group("raid_controller")
	controller.next_wave = -1.0
	for bot: Node in root.get_tree().get_nodes_in_group("bots"):
		bot.ai_enabled = false
	return controller


## The player kills `bot` with a hit to `part` (BodyHealth.Part) from where they stand.
func _kill(controller: Node, bot: Node, part: int) -> void:
	var hit: Dictionary = bot.take_blow(100000.0, controller.player, "melee", "Test", bot.chest_point())
	hit.part = part
	controller.player.on_hit_landed(bot, 100000.0, bot.chest_point(), hit)


func _bots(role := "", side := -1) -> Array:
	return root.get_tree().get_nodes_in_group("bots").filter(func(bot: Node) -> bool:
		return not bot.is_dead and (role == "" or String(bot.role) == role) and (side < 0 or bot.side == side))


func _raid_kills() -> void:
	section("Live raid: kill conditions")
	fresh_profile()
	var raid := _pmc_raid()
	var weapon_id := ""
	var controller: Node = await _start(raid)
	var player: Node = controller.player
	weapon_id = player.weapon.item.id if player.weapon.item else ""
	var scav: int = load("res://scripts/actors/actor.gd").Side.SCAV
	var any := _quest("t_any", [{"type": "kill", "count": 10}])
	var head := _quest("t_head", [{"type": "kill", "target": "scav", "body_part": "head", "count": 2, "map": "test_yard"}])
	var gun := _quest("t_gun", [{"type": "kill", "weapon": weapon_id, "count": 1}])
	var other_gun := _quest("t_other_gun", [{"type": "kill", "weapon": "mosin", "count": 1}])
	var far := _quest("t_far", [{"type": "kill", "min_distance": 30, "count": 1}])
	var boss := _quest("t_boss", [{"type": "kill", "boss": "krane", "map": "test_yard"}, {"type": "kill", "target": "guard", "count": 1}])
	var factory := _quest("t_factory", [{"type": "kill", "map": "factory", "count": 1}])
	var pmc := _quest("t_pmc", [{"type": "kill", "target": "pmc", "count": 1}])
	var toasts: Array = []
	controller.quest_raid.progressed.connect(func(text: String, _done: bool) -> void: toasts.append(text))
	var scavs: Array = _bots("", scav).filter(func(bot: Node) -> bool: return String(bot.role) == "")
	check(scavs.size() >= 2 and weapon_id != "", "a raid with Scavs (%d) and a gun (%s)" % [scavs.size(), weapon_id])
	if scavs.size() < 2:
		return
	scavs[0].global_position = player.global_position + Vector3(2, 0, 0)
	_kill(controller, scavs[0], 1)
	check(quests.progress(any, 0) == 1 and quests.progress(head, 0) == 0, "a thorax kill counts for any kill, not for the headshot one")
	check(quests.progress(gun, 0) == 1 and quests.progress(other_gun, 0) == 0, "with the gun in hand it counts for that gun's objective, not another gun's")
	check(quests.progress(far, 0) == 0, "at 2 m it isn't a 30 m kill")
	check(quests.progress(factory, 0) == 0 and quests.progress(pmc, 0) == 0, "not for another map's objective nor a PMC kill")
	scavs[1].global_position = player.global_position + Vector3(0, 0, 35)
	_kill(controller, scavs[1], 0)
	check(quests.progress(head, 0) == 1 and quests.progress(far, 0) == 1, "a headshot from 35 m counts for both")
	check(toasts.any(func(text: String) -> bool: return "1 / 2" in text) and toasts.any(func(text: String) -> bool: return text.begins_with("Objective complete")),
		"toasts: %s" % str(toasts.slice(0, 4)))
	var bosses := _bots("boss")
	var guards := _bots("guard")
	check(not bosses.is_empty() and not guards.is_empty(), "the boss and a guard are in the raid")
	if not bosses.is_empty() and not guards.is_empty():
		_kill(controller, guards[0], 1)
		check(quests.progress(boss, 0) == 0 and quests.progress(boss, 1) == 1, "a guard counts for the guard kill, not the boss's")
		_kill(controller, bosses[0], 1)
		check(quests.progress(boss, 0) == 1 and quests.state(boss) == "ready", "Krane killed: the boss hunt is ready")
	var pmc_bot: Node = load("res://scenes/actors/bot.tscn").instantiate()
	pmc_bot.profile = load("res://data/bots/pmc.tres")
	controller.add_child(pmc_bot)
	pmc_bot.global_position = player.global_position + Vector3(3, 0, 3)
	pmc_bot.side = pmc_bot.Side.PMC
	pmc_bot.faction = &"usec"
	pmc_bot.ai_enabled = false
	_kill(controller, pmc_bot, 1)
	check(quests.progress(pmc, 0) == 1, "a USEC PMC counts for a PMC kill")
	controller.end_raid(status.KILLED)
	check(quests.progress(any, 0) == 5 and quests.progress(head, 0) == 1, "killed: the kills stay (%d)" % quests.progress(any, 0))
	check(controller.outcome.quest_lines.any(func(line: String) -> bool: return "T Any" in line), "the summary lists the quest progress: %s" % str(controller.outcome.quest_lines.slice(0, 3)))
	quests.reload()


func _raid_places() -> void:
	section("Live raid: visit, place, mark, extract, extract_with")
	fresh_profile()
	for i in 5:
		gs.stash.add(item("bolts"))
	var visit := _quest("t_visit", [{"type": "visit", "map": "test_yard", "poi": "signal_hut"}, {"type": "visit", "map": "test_yard", "spot": "yard_crossroads"}])
	var mark := _quest("t_mark", [{"type": "mark", "map": "test_yard", "poi": "signal_hut", "seconds": 2}], {"gives": [{"item": "quest_marker"}]})
	var place := _quest("t_place", [{"type": "place", "item": "bolts", "map": "test_yard", "spot": "yard_crossroads", "seconds": 1}])
	var out := _quest("t_out", [{"type": "extract", "map": "test_yard", "extract": "north_east_gate"}, {"type": "extract_with", "item": "bolts", "count": 2},
		{"type": "extract", "map": "test_yard", "extract": "signal_point"}])
	check(gs.stash.count_of("quest_marker") == 1, "accepting the mark quest puts its marker in the stash")
	var marker: RefCounted = null
	for each: RefCounted in gs.stash.all_items():
		if each.data.id == "quest_marker":
			marker = each
	gs.stash.remove(marker)
	check(quests.can_retake_marker(mark) and quests.retake_marker(mark) == "" and gs.stash.count_of("quest_marker") == 1, "a lost marker is taken again for free")
	var raid := _pmc_raid()
	var loadout: RefCounted = raid.loadout
	loadout.unequip("backpack")
	loadout.equip("backpack", item("raid_pack"))
	for each: RefCounted in gs.stash.all_items().duplicate():
		if each.data.id == "quest_marker" or (each.data.id == "bolts" and not each.fir and loadout.count_of("bolts") < 5):
			gs.stash.remove(each)
			loadout.add(each)
	var controller: Node = await _start(raid)
	var player: Node = controller.player
	var sites: Array = root.get_tree().get_nodes_in_group("quest_sites")
	check(sites.size() == 2, "two quest sites on the map (%d)" % sites.size())
	player.global_position = Vector3(17.5, 0, -5.5)
	await wait(0.5)
	check(quests.progress(visit, 0) == 1 and quests.progress(visit, 1) == 0, "walking into Signal hut counts the visit")
	var hut: Node = sites.filter(func(site: Node) -> bool: return site.quest.id == "t_mark")[0] if not sites.is_empty() else null
	if hut:
		hut.interact(player)
		Input.action_press("interact")
		await wait(1.0)
		Input.action_release("interact")
		await wait(0.1)
		check(quests.progress(mark, 0) == 0 and hut.held < 0.0, "letting go after 1 s of 2 cancels the placement")
		hut.interact(player)
		Input.action_press("interact")
		await wait(0.5)
		player.take_blow(1.0, null, "melee", "Test", player.chest_point())
		await wait(0.1)
		check(hut.held < 0.0, "being hit cancels it")
		hut.interact(player)
		await wait(2.3)
		Input.action_release("interact")
		check(quests.progress(mark, 0) == 1 and not player.inventory.all_items().any(func(each: RefCounted) -> bool: return each.data.id == "quest_marker"),
			"held for 2 s: the marker is placed and leaves the inventory")
	player.global_position = Vector3(-1, 0, -6)
	await wait(0.5)
	check(quests.progress(visit, 1) == 1, "the yard crossroads spot is reached")
	var crossroads: Node = sites.filter(func(site: Node) -> bool: return site.quest.id == "t_place")[0] if sites.size() > 1 else null
	if crossroads:
		crossroads.interact(player)
		Input.action_press("interact")
		await wait(1.3)
		Input.action_release("interact")
		check(quests.progress(place, 0) == 1 and player.inventory.count_of("bolts") == 4, "bolts placed: one leaves the inventory (%d left)" % player.inventory.count_of("bolts"))
	var locations: Array = controller.quest_raid.locations(root.get_tree())
	check(locations.size() >= 4, "the map overlay's locations: %d" % locations.size())
	controller.xp = 1000  # Not a Run Through.
	var gate: Node = root.get_tree().get_nodes_in_group("extract_zones").filter(func(zone: Node) -> bool: return zone.extract_id == "north_east_gate")[0]
	player.global_position = gate.global_position
	var waited := 0.0
	while controller.outcome == null and waited < 12.0:
		await wait(0.5)
		waited += 0.5
	check(controller.outcome != null and controller.outcome.status == status.SURVIVED, "out through the North-east gate")
	check(quests.progress(out, 0) == 1 and quests.progress(out, 2) == 0, "the extract objective for that gate counts, another gate's doesn't")
	check(quests.progress(out, 1) == 2 and gs.inventory.count_of("bolts") == 4, "extracting with 4 bolts fills the extract_with objective and keeps them")
	quests.reload()


func _raid_survive() -> void:
	section("Live raid: survive-only progress")
	fresh_profile()
	var keep := _quest("t_keep", [{"type": "kill", "count": 3, "survive": true}, {"type": "kill", "count": 3}])
	var controller: Node = await _start(_pmc_raid({"boss": false}))
	var scavs := _bots()
	for bot: Node in scavs.slice(0, 2):
		_kill(controller, bot, 1)
	check(quests.progress(keep, 0) == 0 and controller.quest_raid.progress(keep, 0) == 2 and quests.progress(keep, 1) == 2,
		"survive-only kills wait for the extract; the others count at once")
	controller.end_raid(status.KILLED)
	check(quests.progress(keep, 0) == 0 and quests.progress(keep, 1) == 2, "killed: the survive-only progress is lost, the rest stays")
	check(controller.outcome.quest_lines.any(func(line: String) -> bool: return "lost" in line), "the summary says it was lost")
	controller = await _start(_pmc_raid({"boss": false}))
	for bot: Node in _bots().slice(0, 2):
		_kill(controller, bot, 1)
	controller.end_raid(status.RUN_THROUGH)
	check(quests.progress(keep, 0) == 0, "a Run Through doesn't keep it either")
	controller = await _start(_pmc_raid({"boss": false}))
	for bot: Node in _bots().slice(0, 2):
		_kill(controller, bot, 1)
	controller.end_raid(status.SURVIVED)
	check(quests.progress(keep, 0) == 2, "survived: it counts (2 / 3)")
	quests.reload()


func _raid_not_counted() -> void:
	section("Scav and practice raids count nothing")
	fresh_profile()
	var nothing := _quest("t_nothing", [{"type": "kill", "count": 5}, {"type": "extract"}, {"type": "trick_kill"}])
	var controller: Node = await _start({"side": "scav", "map": "test_yard", "seed": 4, "boss": false, "pmcs": 0})
	for bot: Node in _bots().slice(0, 1):
		_kill(controller, bot, 1)
	controller.end_raid(status.SURVIVED)
	check(quests.progress(nothing, 0) == 0 and quests.progress(nothing, 1) == 0, "a Scav run: no kill, no extract")
	gs.hideout["shooting_range"] = 1
	var raid: Dictionary = load("res://scripts/progression/hideout.gd").practice_raid()
	raid.seed = 4
	controller = await _start(raid)
	for bot: Node in _bots().slice(0, 1):
		_kill(controller, bot, 1)
	controller.end_raid(status.SURVIVED)
	check(quests.progress(nothing, 0) == 0 and quests.progress(nothing, 1) == 0, "practice: nothing")
	gs.raid = {}
	change_scene_to_file("res://ui/main_menu.tscn")
	await frames(3)
	quests.reload()


# --- Saves --------------------------------------------------------------------------------------------

func _saves() -> void:
	section("Saves (version 19)")
	check(sm.SAVE_VERSION == 19, "the save version is 19")
	fresh_profile()
	var scrap: Dictionary = quests.find("scrap_run")
	quests.accept(scrap)
	gs.quests.scrap_run.progress = [2, 1]
	gs.quests["shortage"] = {"state": "completed", "progress": [2, 1]}
	check(quests.set_tracked(scrap, true) == "" and quests.is_tracked(scrap), "an active quest is tracked")
	check(quests.set_tracked(quests.find("shortage"), true) != "", "a completed one can't be")
	var data: Dictionary = gs.to_dict()
	var old: Dictionary = data.duplicate(true)
	old.version = 18
	old.profile.erase("quest_tracked")
	gs.quests = {}
	gs.from_dict(sm.upgrade(old))
	check(gs.quests.scrap_run.state == "active" and gs.quests.scrap_run.progress == [2, 1] and gs.quests.shortage.state == "completed",
		"a version 18 save keeps its quest states and progress")
	check(gs.quest_tracked.is_empty(), "and tracks nothing")
	gs.from_dict(data)
	check(quests.tracked() == ["scrap_run"] and gs.quests.scrap_run.progress == [2, 1], "a round trip keeps the tracked quest and progress")
	for id in ["a", "b", "c", "d"]:
		_quest("t_track_" + id, [{"type": "level", "level": 50}])
	var refused := ""
	for id in ["a", "b", "c", "d"]:
		refused = quests.set_tracked(quests.find("t_track_" + id), true)
	check(quests.tracked().size() == 3 and refused != "", "up to three are tracked (%s)" % refused)
	quests.reload()


## DESIGN.md §11's table of every quest, as the data has it: | Quest | Trader | Needs | Objectives |
## Rewards |. The check fails while DESIGN.md says anything else (the expected table is written to
## user://quest_table.md to paste in).
func _design_table() -> void:
	section("DESIGN.md's quest table")
	fresh_profile()
	var lines: Array[String] = ["| Quest | Trader | Needs | Objectives | Rewards and unlocks |", "|---|---|---|---|---|"]
	for quest: Dictionary in quests.all():
		var needs: Array = quest.get("requires", []).map(func(id: String) -> String: return str(quests.find(id).get("name", id)))
		if int(quest.get("level", 1)) > 1:
			needs.append("level %d" % int(quest.level))
		var loyalty: Dictionary = quest.get("loyalty", {})
		for trader: String in loyalty:
			needs.append("%s LL%d" % [load("res://scripts/data/trader_table.gd").display_name(trader), int(loyalty[trader])])
		var objectives := []
		for i in quest.objectives.size():
			var type: String = quests.objective_type(quest, i)
			var count: int = quests.objective_count(quest, i)
			var text: String = quests.objective_text(quest, i)
			if count > 1 and not type in ["upgrade", "level", "loyalty"]:
				text += (" (%s ₽)" % load("res://scripts/ui/ui_format.gd").thousands(count)) if type == "roubles" else " ×%d" % count
			if quest.objectives[i].get("survive", false):
				text += " (survive)"
			objectives.append(text)
		var rewards: Array = quests.reward_lines(quest)
		for unlock: Dictionary in quests.unlocks(quest):
			rewards.append("unlocks " + str(unlock.text).substr(0, 1).to_lower() + str(unlock.text).substr(1))
		var name: String = quest.name + (" (%s)" % str(quest.faction).to_upper() if quest.has("faction") else "")
		lines.append("| %s | %s | %s | %s | %s |" % [name, load("res://scripts/data/trader_table.gd").display_name(quest.trader),
			", ".join(needs) if not needs.is_empty() else "—", "; ".join(objectives), ", ".join(rewards)])
	var table := "\n".join(lines)
	var design := FileAccess.get_file_as_string("res://DESIGN.md")
	if not table in design:
		var file := FileAccess.open("user://quest_table.md", FileAccess.WRITE)
		file.store_string(table + "\n")
		file.close()
	check(table in design, "DESIGN.md §11 has the table of every quest as the data has it (expected: %s)" % ProjectSettings.globalize_path("user://quest_table.md"))
