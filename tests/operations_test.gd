extends "res://tests/test_base.gd"
## Daily and weekly operational tasks (DESIGN.md §11 Operations; plan E14): the pool file and its
## checks, the reset clock (UTC hours, the week from Monday), seeded rolls that repeat, the day and
## week boundary (while the game runs and while it's closed), scaling by level, only doable tasks,
## progress through the real triggers (raid kills, a Scav run counting nothing, a container searched,
## a hand-in, a craft, a sale of found-in-raid loot), claiming and the auto-claim at the reset, the
## all-dailies bonus, the rare item (seeded), re-rolls, the save round trip and older saves, the
## OPERATIONS board in the quest log and the pool table in DESIGN.md.

const MAP := "res://maps/test_level.tscn"
## 2027-01-15 08:00 UTC, a Friday: the clock the suite runs on.
const NOW := 1800000000.0
const DAY := 86400.0

var ops: GDScript
var quests: GDScript


func run() -> void:
	ops = load("res://scripts/progression/operations.gd")
	quests = load("res://scripts/progression/quest_log.gd")
	_pool()
	_clock()
	_rolling()
	_scaling()
	_doable()
	_resets()
	await _raid_progress()
	await _not_counted()
	_out_of_raid()
	_claims()
	_rare_items()
	_rerolls()
	_saves()
	_design()
	ops.now_override = -1.0


## A new BEAR (or USEC: `faction` 1) profile on the suite's clock, with roll seed `seed`.
func _profile(seed := 7, faction := 0) -> void:
	ops.now_override = NOW
	gs.raid = {}
	fresh_profile(faction)
	gs.operations = ops.blank(seed)
	ops.update()


func _ids(list: Array) -> Array:
	return list.map(func(task: Dictionary) -> String: return "%s:%s" % [task.template, JSON.stringify(task.objectives)])


func _pool() -> void:
	section("The pool (data/tasks/operations.json)")
	check(ops.problems().is_empty(), "the file has no problems (%s)" % str(ops.problems().slice(0, 3)))
	var by_kind := {"daily": 0, "weekly": 0}
	var types := {}
	for template: Dictionary in ops.templates():
		by_kind[template.kind] += 1
		types[str(template.objective.type)] = true
	check(by_kind.daily >= 12 and by_kind.weekly >= 10, "a pool of %d dailies and %d weeklies" % [by_kind.daily, by_kind.weekly])
	var wanted := ["kill", "extract", "visit", "search", "hand_in", "sell", "craft"]
	check(wanted.all(func(type: String) -> bool: return types.has(type)), "every kind of task is in it: %s" % ", ".join(types.keys()))
	check(int(ops.kind_config("daily").count) == 3 and int(ops.kind_config("weekly").count) == 3, "3 dailies and 3 weeklies a set")
	check(is_equal_approx(float(ops.kind_config("daily").rare_chance), 0.15) and is_equal_approx(float(ops.kind_config("weekly").rare_chance), 0.6),
		"a rare item: 15% for a daily, 60% for a weekly")
	check(is_equal_approx(float(ops.kind_config("weekly").reward_scale) / float(ops.kind_config("daily").reward_scale), 5.0), "weeklies pay 5× a daily")
	# E15 set the Drip: 15 a daily, 60 a weekly (DESIGN.md §6.7; was 0 before the Drip economy).
	check(ops.kind_config("daily").has("drip") and int(ops.kind_config("daily").drip) == 15 and int(ops.kind_config("weekly").drip) == 60,
		"each kind has a per-task Drip reward: 15 a daily, 60 a weekly")
	# Broken copies: each one is caught.
	var saved: Dictionary = ops.data().duplicate(true)
	var cases := [
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "kill", "target": "cow"}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "kill target cow"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "extract"}, "pick": {"map": ["moon"]}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "map moon"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "extract"}, "pick": {"map": ["woodland"]}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "playable"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "hand_in"}, "pick": {"item": ["screws"]}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "found in raid"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "hand_in", "fir": true}, "pick": {"item": ["duct_tape"]}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "made in the hideout"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "kill"}, "counts": [[3, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "count range"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "kill"}, "counts": [[1, 2]]}, "one [low, high] per band"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "visit"}, "pick": {"map": ["test_yard"], "poi_tiers": [1]}, "counts": [[1, 1], [1, 1], [1, 1], [1, 1], [1, 1]]}, "a visit has no counts"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "kill", "target": "pmc", "faction": "usec"}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "\"rival\""],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "place"}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "objective type"],
		[{"id": "x", "name": "X", "kind": "monthly", "levels": [1, 60], "objective": {"type": "kill"}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "a kind"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [0, 70], "objective": {"type": "kill"}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "levels is"],
		[{"id": "x", "name": "X", "kind": "daily", "levels": [1, 60], "objective": {"type": "craft"}, "pick": {"station": ["gym"]}, "counts": [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]}, "has no crafts"],
	]
	for case: Array in cases:
		ops.data().templates = saved.templates.duplicate(true) + [case[0]]
		var found: Array = ops.problems()
		check(found.any(func(problem: String) -> bool: return problem.contains(case[1])), "a template with a broken %s is caught (%s)" % [case[1], str(found.slice(0, 2))])
	ops.data().templates = saved.templates.duplicate(true).slice(0, 2)
	check(ops.problems().any(func(problem: String) -> bool: return problem.contains("a set of 3")), "too few templates for a set is caught")
	ops.data().templates = saved.templates.duplicate(true)
	ops.data().rare_items.items.append({"item": "gpu", "count": 1, "weight": 1, "level": 1})
	check(ops.problems().any(func(problem: String) -> bool: return problem.contains("Epic or rarer")), "an Epic reward before level 30 is caught")
	ops.data().rare_items.items[-1] = {"item": "bolts", "count": 1, "weight": 1, "level": 1}
	check(ops.problems().any(func(problem: String) -> bool: return problem.contains("isn't rare or better")), "a reward below Rare is caught")
	ops.reload()
	check(ops.problems().is_empty(), "the real file again")


func _clock() -> void:
	section("The reset clock (UTC)")
	var hour := int(ops.data().reset.daily_hour_utc)
	var end: float = ops.period_end("daily", NOW)
	check(fmod(end - hour * 3600.0, DAY) == 0.0 and end > NOW and end - NOW <= DAY, "the daily reset is at %02d:00 UTC, the next one %.1f h away" % [hour, (end - NOW) / 3600.0])
	check(ops.period("daily", end - 1.0) == ops.period("daily", NOW) and ops.period("daily", end) == ops.period("daily", NOW) + 1, "the day number changes exactly at the reset")
	var week_end: float = ops.period_end("weekly", NOW)
	var day_number := int((week_end - int(ops.data().reset.weekly_hour_utc) * 3600.0) / DAY)
	check((day_number - 4) % 7 == int(ops.data().reset.weekly_day) and week_end > NOW and week_end - NOW <= 7 * DAY,
		"the weekly reset is on a Monday at %02d:00 UTC (in %.1f days)" % [int(ops.data().reset.weekly_hour_utc), (week_end - NOW) / DAY])
	check(ops.period("weekly", week_end - 1.0) == ops.period("weekly", NOW) and ops.period("weekly", week_end) == ops.period("weekly", NOW) + 1, "the week number changes exactly then")
	ops.now_override = NOW
	check(is_equal_approx(ops.seconds_left("daily"), end - NOW) and ops.reset_text("daily") == "Resets in %s" % load("res://scripts/ui/ui_format.gd").countdown(end - NOW),
		"the time left: %s" % ops.reset_text("daily"))


func _rolling() -> void:
	section("Rolling: seeded by the profile and the day or week")
	_profile(7)
	var daily: Array = ops.tasks("daily")
	var weekly: Array = ops.tasks("weekly")
	check(daily.size() == 3 and weekly.size() == 3, "a new profile has 3 dailies and 3 weeklies")
	check(daily.all(func(task: Dictionary) -> bool: return task.operation == "daily" and int(gs.operations.daily.number) == ops.period("daily", NOW)), "rolled for today")
	var templates := daily.map(func(task: Dictionary) -> String: return task.template)
	check(templates.size() == 3 and templates[0] != templates[1] and templates[1] != templates[2] and templates[0] != templates[2], "three different templates (%s)" % str(templates))
	var first := _ids(daily)
	gs.operations = ops.blank(7)
	ops.update()
	check(_ids(ops.tasks("daily")) == first, "the same seed and day roll the same set")
	var same_day := true
	var different := 0
	for seed in range(20, 40):
		gs.operations = ops.blank(seed)
		ops.update()
		var rolled := _ids(ops.tasks("daily"))
		different += 0 if rolled == first else 1
		var again: Array = ops.roll("daily", int(gs.operations.daily.number), gs.level)
		same_day = same_day and _ids(again) == rolled
	check(same_day, "rolling the same day again repeats it, for every seed")
	check(different >= 18, "other profiles roll other sets (%d of 20 differ)" % different)
	gs.operations = ops.blank(7)
	var days := {}
	for day in 10:
		days[str(_ids(ops.roll("daily", 20000 + day, 1)))] = true
	check(days.size() >= 9, "other days roll other sets (%d different in 10 days)" % days.size())
	ops.update()
	check(ops.tasks("daily").all(func(task: Dictionary) -> bool: return str(task.id).begins_with("op_daily_%d_" % ops.period("daily", NOW))), "ids name the kind and the day: %s" % ops.tasks("daily")[0].id)


func _scaling() -> void:
	section("Counts and rewards scale with the player level")
	_profile(7)
	var sweep: Dictionary = ops.template("scav_sweep")
	var low := []
	var high := []
	for i in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		low.append(ops.make_task(sweep, rng, "daily", 1, 0, 1, ""))
		rng.seed = i
		high.append(ops.make_task(sweep, rng, "daily", 1, 0, 40, ""))
	var count := func(task: Dictionary) -> int: return int(task.objectives[0].count)
	var range_low: Array = ops.count_range(sweep, 0)
	var range_high: Array = ops.count_range(sweep, 4)
	check(low.all(func(task: Dictionary) -> bool: return count.call(task) >= range_low[0] and count.call(task) <= range_low[1])
		and high.all(func(task: Dictionary) -> bool: return count.call(task) >= range_high[0] and count.call(task) <= range_high[1]),
		"Scav Sweep asks for %d-%d kills at level 1, %d-%d at level 40" % [range_low[0], range_low[1], range_high[0], range_high[1]])
	var bands: Array = ops.bands()
	check(bands.size() == 5 and int(bands[0].from) == 1 and int(bands[4].from) == 40, "five level bands: 1, 10, 20, 30, 40+")
	var mid_low: Dictionary = ops.rewards_for(sweep, 5, 1)
	var mid_high: Dictionary = ops.rewards_for(sweep, 12, 40)
	check(int(mid_low.roubles) == int(bands[0].roubles) and int(mid_low.xp) == int(bands[0].xp), "a level-1 daily of middle count pays the band's base: %s ₽, %s XP" % [mid_low.roubles, mid_low.xp])
	check(int(mid_high.roubles) == int(bands[4].roubles) and int(mid_high.xp) == int(bands[4].xp), "at level 40: %s ₽, %s XP" % [mid_high.roubles, mid_high.xp])
	var harder: Dictionary = ops.rewards_for(sweep, 6, 1)
	check(int(harder.roubles) > int(mid_low.roubles) and int(harder.xp) > int(mid_low.xp), "a higher count pays more (%s ₽ for 6)" % harder.roubles)
	var survivor: Dictionary = ops.template("survivor")
	var hunt: Dictionary = ops.template("scav_hunt")
	var weekly_mid: Dictionary = ops.rewards_for(hunt, 30, 25)  # Band 20-29: 26-34 kills, middle 30.
	check(int(weekly_mid.roubles) == int(bands[2].roubles) * 5 and int(weekly_mid.xp) == int(bands[2].xp) * 5, "a weekly pays 5× a daily (%s ₽ at level 25)" % weekly_mid.roubles)
	check(int(ops.rewards_for(survivor, 4, 1).drip) == int(ops.kind_config(str(survivor.kind)).drip) and int(ops.rewards_for(hunt, 30, 25).drip) == 60,
		"and the kind's Drip (%s's %d; 60 for a weekly)" % [survivor.kind, int(ops.rewards_for(survivor, 4, 1).drip)])
	gs.level = 35
	gs.xp = load("res://scripts/progression/progression.gd").xp_for_level(35)
	gs.operations = ops.blank(7)
	ops.update()
	check(ops.tasks("daily").all(func(task: Dictionary) -> bool: return int(task.level) == 35 and int(task.rewards.roubles) >= int(bands[3].roubles) * 0.5),
		"a level-35 profile's set is rolled at 35 and pays like it (%s)" % str(ops.tasks("daily").map(func(task: Dictionary) -> int: return int(task.rewards.roubles))))


## Every task rolled over `days` days for the profile as it is now.
func _rolls(kind: String, days: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for day in days:
		result.append_array(ops.roll(kind, 30000 + day, gs.level))
	return result


func _doable() -> void:
	section("Only tasks the profile can do")
	_profile(11)
	var all: Array[Dictionary] = _rolls("daily", 150) + _rolls("weekly", 150)
	var maps_ok := all.all(func(task: Dictionary) -> bool:
		var map_id := str(task.objectives[0].get("map", ""))
		return map_id == "" or load("res://scripts/data/map_info.gd").find(map_id).is_playable())
	check(maps_ok, "only playable maps (Test Yard and Factory) in %d tasks" % all.size())
	check(not all.any(func(task: Dictionary) -> bool: return task.objectives[0].type == "craft"), "no craft before a station that crafts is built")
	check(not all.any(func(task: Dictionary) -> bool: return task.objectives[0].has("faction")), "no faction kills at level 1 (from level 10)")
	var classes: Array = ops.weapon_classes()
	check(all.all(func(task: Dictionary) -> bool: return not task.objectives[0].has("weapon_class") or task.objectives[0].weapon_class in classes),
		"weapon classes only ones you have or can buy (%s)" % ", ".join(classes))
	check(not all.any(func(task: Dictionary) -> bool: return task.objectives[0].get("target", "") == "boss"), "no boss bounty before level 20")
	var visits := all.filter(func(task: Dictionary) -> bool: return task.objectives[0].type == "visit")
	check(not visits.is_empty() and visits.all(func(task: Dictionary) -> bool:
		var poi: Dictionary = load("res://scripts/data/poi_table.gd").find(task.objectives[0].map, task.objectives[0].poi)
		return not poi.is_empty() and not poi.get("hidden", false) and not poi.has("requires")), "visits go to points of interest anyone can walk into (%d)" % visits.size())
	gs.hideout.workbench = 1
	var crafts := _rolls("daily", 150).filter(func(task: Dictionary) -> bool: return task.objectives[0].type == "craft")
	check(not crafts.is_empty() and crafts.all(func(task: Dictionary) -> bool: return task.objectives[0].station == "workbench"), "with the Workbench built: crafts there only (%d)" % crafts.size())
	gs.level = 12
	var rivals := _rolls("daily", 150).filter(func(task: Dictionary) -> bool: return task.objectives[0].has("faction"))
	check(not rivals.is_empty() and rivals.all(func(task: Dictionary) -> bool: return task.objectives[0].faction == "usec"), "BEAR at level 12: kill USECs (%d)" % rivals.size())
	check(quests.objective_text(rivals[0], 0).begins_with("Kill USEC"), "\"%s\"" % quests.objective_text(rivals[0], 0))
	_profile(11, 1)
	gs.level = 12
	var usec := _rolls("weekly", 150).filter(func(task: Dictionary) -> bool: return task.objectives[0].has("faction"))
	check(not usec.is_empty() and usec.all(func(task: Dictionary) -> bool: return task.objectives[0].faction == "bear"), "USEC: kill BEARs (%d)" % usec.size())


func _resets() -> void:
	section("The day and week boundary")
	_profile(5)
	var end: float = ops.period_end("daily", NOW)
	var before := _ids(ops.tasks("daily"))
	var weekly_before := _ids(ops.tasks("weekly"))
	ops.now_override = end - 1.0
	ops.update()
	check(_ids(ops.tasks("daily")) == before, "a second before the reset: the same set")
	var done: Dictionary = ops.tasks("daily")[0]
	done.progress = [quests.objective_count(done, 0)]
	var open: Dictionary = ops.tasks("daily")[1]
	var money: int = gs.roubles
	var xp: int = gs.xp
	ops.now_override = end
	var paid: Array = ops.update()
	check(int(gs.operations.daily.number) == ops.period("daily", end) and _ids(ops.tasks("daily")) != before, "at the reset: a new day, a new set")
	check(paid.size() == 1 and paid[0] == done and gs.roubles >= money + int(done.rewards.roubles) and gs.xp >= xp + int(done.rewards.xp),
		"the finished task nobody claimed is paid out (%s ₽)" % done.rewards.roubles)
	check(not ops.all_tasks().has(open) and ops.find(str(open.id)).is_empty(), "the unfinished one is gone")
	check(_ids(ops.tasks("weekly")) == weekly_before, "the weeklies stay until Monday")
	var week_end: float = ops.period_end("weekly", NOW)
	ops.now_override = week_end
	ops.update()
	check(_ids(ops.tasks("weekly")) != weekly_before and int(gs.operations.weekly.number) == ops.period("weekly", week_end), "Monday's reset rolls new weeklies")
	gs.raid = {"side": "pmc", "map": "test_yard"}
	var kept := _ids(ops.tasks("daily"))
	ops.now_override = week_end + 2 * DAY
	ops.update()
	check(_ids(ops.tasks("daily")) == kept, "a reset during a raid waits for the raid to end")
	gs.raid = {}
	ops.update()
	check(int(gs.operations.daily.number) == ops.period("daily", week_end + 2 * DAY), "and comes once it's over")
	section("The reset while the game is closed")
	_profile(5)
	var finished: Dictionary = ops.tasks("weekly")[2]
	finished.progress = [quests.objective_count(finished, 0)]
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	saved.version = sm.SAVE_VERSION
	money = gs.roubles
	ops.now_override = NOW + 10 * DAY
	gs.from_dict(saved)
	check(int(gs.operations.daily.number) == ops.period("daily", NOW + 10 * DAY) and int(gs.operations.weekly.number) == ops.period("weekly", NOW + 10 * DAY),
		"ten days away: it moves straight on to the current day and week")
	check(gs.roubles == money + int(finished.rewards.roubles), "the weekly finished before closing is paid on loading (%s ₽)" % finished.rewards.roubles)
	ops.now_override = NOW


func _saves() -> void:
	section("Saves")
	_profile(9)
	var task: Dictionary = ops.tasks("daily")[0]
	task.progress = [1]
	var claimed: Dictionary = ops.tasks("weekly")[1]
	claimed.progress = [quests.objective_count(claimed, 0)]
	check(ops.claim(claimed) == "", "a weekly claimed")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	saved.version = sm.SAVE_VERSION
	var before := JSON.stringify(gs.operations)
	gs.from_dict(saved)
	check(JSON.stringify(gs.operations) == before, "the round trip keeps the seed, the day and week rolled, the tasks, progress and claims")
	check(ops.progress(ops.tasks("daily")[0]) == 1 and ops.state(ops.tasks("weekly")[1]) == "completed", "progress and the claim are back")
	check(typeof(ops.tasks("daily")[0].objectives[0].get("count", 1)) == TYPE_INT and typeof(gs.operations.seed) == TYPE_INT, "numbers come back whole")
	var old: Dictionary = saved.duplicate(true)
	old.version = 20
	old.profile.erase("operations")
	gs.from_dict(old.duplicate(true))
	var first := _ids(ops.all_tasks())
	check(ops.tasks("daily").size() == 3 and ops.tasks("weekly").size() == 3, "a version 20 save gets today's and this week's sets on loading")
	gs.from_dict(old.duplicate(true))
	check(_ids(ops.all_tasks()) == first, "and loading the same old save again rolls the same sets")
	check(gs.roubles == int(old.profile.roubles) and gs.xp == int(old.profile.xp), "an old save keeps its money and experience")


## A task of `template_id` (its first options, `overrides` merged into its objective) put on set `kind`'s
## board in `slot`.
func _put(template_id: String, overrides: Dictionary, kind: String, slot: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var task: Dictionary = ops.make_task(ops.template(template_id), rng, kind, int(gs.operations[kind].number), slot, gs.level, "")
	task.objectives[0].merge(overrides, true)
	gs.operations[kind].tasks[slot] = task
	return task


func _start(raid: Dictionary) -> Node:
	gs.raid = raid
	change_scene_to_file(MAP)
	await frames(3)
	var controller: Node = root.get_tree().get_first_node_in_group("raid_controller")
	controller.next_wave = -1.0
	for bot: Node in root.get_tree().get_nodes_in_group("bots"):
		bot.ai_enabled = false
	return controller


func _kill(controller: Node, bot: Node, part: int) -> void:
	var hit: Dictionary = bot.take_blow(100000.0, controller.player, "melee", "Test", bot.chest_point())
	hit.part = part
	controller.player.on_hit_landed(bot, 100000.0, bot.chest_point(), hit)


func _scavs() -> Array:
	var scav: int = load("res://scripts/actors/actor.gd").Side.SCAV
	return root.get_tree().get_nodes_in_group("bots").filter(func(bot: Node) -> bool: return not bot.is_dead and bot.side == scav and String(bot.role) == "")


func _raid_progress() -> void:
	section("Progress in a PMC raid: the quest tracking, the HUD tracker, toasts")
	_profile(3)
	var sweep := _put("scav_sweep", {"map": "test_yard", "count": 4}, "daily", 0)
	var hold := _put("hold_the_line", {"map": "test_yard", "count": 3}, "daily", 1)
	var recon := _put("recon", {"map": "test_yard", "poi": "signal_hut"}, "daily", 2)
	var hunt := _put("scav_hunt", {"count": 20}, "weekly", 0)
	var rummage := _put("scavenger", {"map": "test_yard", "count": 2}, "weekly", 1)
	var home := _put("home_ground", {"map": "test_yard", "count": 2}, "weekly", 2)
	check(quests.find(str(sweep.id)) == sweep and quests.state(sweep) == "active", "QuestLog finds a task by its id")
	check(quests.set_tracked(sweep, true) == "" and quests.is_tracked(sweep), "a daily is tracked on the HUD like a quest")
	var status: Dictionary = load("res://scripts/raid/raid_outcome.gd").Status
	var controller: Node = await _start({"side": "pmc", "map": "test_yard", "loadout": gs.pmc_loadout(), "seed": 4, "boss": false, "pmcs": 0})
	var toasts := []
	controller.quest_raid.progressed.connect(func(text: String, _done: bool) -> void: toasts.append(text))
	var scavs := _scavs()
	_kill(controller, scavs[0], 0)
	check(ops.progress(sweep) == 1 and ops.progress(hunt) == 1, "a Scav kill counts at once for the daily and the weekly")
	check(ops.progress(hold) == 0 and controller.quest_raid.pending_of(hold, 0) == 1, "Hold the Line's kill waits for the extract")
	check(toasts.has("Daily: Kill Scavs on Test Yard: 1 / 4"), "a toast: %s" % (toasts[0] if not toasts.is_empty() else "none"))
	var hud: Node = root.get_tree().current_scene.find_child("HUD", true, false)
	var lines: Array = hud.tracker_lines()
	check(not lines.is_empty() and lines[0][0] == "DAILY · SCAV SWEEP" and str(lines[1][0]).contains("1 / 4"), "the HUD tracker: %s" % str(lines.slice(0, 2)))
	controller.player.global_position = Vector3(17.5, 0, -5.5)
	await wait(0.5)
	check(ops.state(recon) == "ready" and toasts.has("Daily: Objective complete: Reach Signal hut on Test Yard"), "walking into Signal hut finishes Recon")
	# A container searched to its last item, through the inventory screen.
	var boxes := root.get_tree().get_nodes_in_group("interactables").filter(func(node: Node) -> bool: return node.get("search") is RefCounted and node.get("grid") != null)
	check(boxes.size() >= 2, "the Test Yard has containers (%d)" % boxes.size())
	var layer: Node = root.get_tree().current_scene.find_child("InventoryLayer", true, false)
	for box: Node in boxes.slice(0, 2):
		for each: RefCounted in box.grid.items.duplicate():
			box.grid.remove(each)
		box.grid.add(item("bolts"))
		box.search.hide_all()
		box.search._time_multiplier = 0.01
		box.interact(controller.player)
		await wait(0.3)
		layer.close()
		await frames(2)
	check(ops.progress(rummage) == 2, "two containers searched to the last item: Scavenger 2 / 2 (%d)" % ops.progress(rummage))
	var body: Node = scavs[0]
	controller.player.open_loot("BODY", body.inventory, body)
	await wait(0.5)
	layer.close()
	check(ops.progress(rummage) == 2, "a body doesn't count as a container")
	var outcome: RefCounted = controller.end_raid(status.SURVIVED)
	check(ops.progress(home) == 1 and ops.progress(hold) == 1, "extracting counts Home Ground and adds Hold the Line's kill")
	check(outcome.quest_lines.has("Daily · Scav Sweep: Kill Scavs on Test Yard +1 (1 / 4)"), "the raid summary: %s" % str(outcome.quest_lines.slice(0, 2)))
	gs.raid = {}


func _not_counted() -> void:
	section("Scav runs count nothing")
	_profile(3)
	var sweep := _put("scav_sweep", {"map": "test_yard", "count": 4}, "daily", 0)
	var out := _put("get_out", {"map": "test_yard", "count": 1}, "daily", 1)
	var status: Dictionary = load("res://scripts/raid/raid_outcome.gd").Status
	var controller: Node = await _start({"side": "scav", "map": "test_yard", "seed": 4, "boss": false, "pmcs": 0})
	_kill(controller, _scavs()[0], 1)
	controller.end_raid(status.SURVIVED)
	check(ops.progress(sweep) == 0 and ops.progress(out) == 0, "a Scav run: no kill, no extract")
	gs.raid = {}


func _out_of_raid() -> void:
	section("Hand-ins, crafts and sales")
	_profile(3)
	var parts := _put("spare_parts", {"item": "screws", "count": 2}, "daily", 0)
	for i in 2:
		gs.stash.add(item("screws"))
	check(quests.hand_in(parts, 0) == 0, "bought screws (not found in raid) don't count")
	for i in 2:
		var found: RefCounted = item("screws")
		found.fir = true
		gs.stash.add(found)
	check(quests.hand_in(parts, 0) == 2 and ops.state(parts) == "ready", "found-in-raid screws: Spare Parts done")
	check(quests.objective_text(parts, 0) == "Hand over %s (found in raid)" % db.get_item("screws").display_name, "\"%s\"" % quests.objective_text(parts, 0))
	gs.hideout["workbench"] = 1
	var shift := _put("shift_work", {"station": "workbench", "count": 2}, "daily", 1)
	gs.hideout_state.ready = {"workbench": [{"id": "hex_nuts", "output": {"item": "hex_nuts", "count": 1}}]}
	load("res://scripts/progression/hideout_work.gd").collect(load("res://scripts/progression/hideout.gd").find("workbench"))
	check(ops.progress(shift) == 1, "a craft collected at the Workbench counts for Shift Work")
	var sale := _put("market_run", {"count": 30000}, "daily", 2)
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	var bought: RefCounted = item("gold_chain")
	gs.stash.add(bought)
	check(selling.sell(selling.best_trader(bought), [bought]) == "" and ops.progress(sale) == 0, "selling a bought gold chain counts nothing")
	var crafted: RefCounted = item("hex_nuts")
	crafted.fir = true
	gs.stash.add(crafted)
	check(selling.sell(selling.best_trader(crafted), [crafted]) == "" and ops.progress(sale) == 0, "nor hex nuts made in the hideout (found in raid, but crafted)")
	var loot: RefCounted = item("gold_chain")
	loot.fir = true
	gs.stash.add(loot)
	var trader: String = selling.best_trader(loot)
	var price: int = load("res://scripts/progression/trading.gd").spent_value(selling.price(trader, loot), selling.currency(trader))
	check(selling.sell(trader, [loot]) == "" and ops.progress(sale) == mini(price, 30000), "a found-in-raid gold chain counts what it fetched (%d ₽)" % price)
	check(quests.objective_text(sale, 0) == "Sell found-in-raid loot to traders", "\"%s\"" % quests.objective_text(sale, 0))


func _claims() -> void:
	section("Claiming, and the all-dailies bonus")
	_profile(13)
	var list: Array = ops.tasks("daily")
	check(ops.claim(list[0]) == "Finish the task first", "an unfinished task can't be claimed")
	for task: Dictionary in list:
		task.progress = [quests.objective_count(task, 0)]
	var money: int = gs.roubles
	var xp: int = gs.xp
	var first: Dictionary = list[0]
	check(ops.claim(first) == "" and ops.state(first) == "completed", "a finished daily is claimed")
	check(gs.roubles == money + int(first.rewards.roubles) and gs.xp == xp + int(first.rewards.xp), "it pays %s ₽ and %s XP" % [first.rewards.roubles, first.rewards.xp])
	check(ops.claim(first) == "Already claimed" and gs.roubles == money + int(first.rewards.roubles), "only once")
	gs.raid = {"side": "pmc"}
	check(ops.claim(list[1]) == "Claim it once you're out of the raid", "not during a raid")
	gs.raid = {}
	var bonus: Dictionary = gs.operations.daily.bonus
	check(int(bonus.roubles) == 12500 and int(bonus.xp) == 200, "the all-dailies bonus at level 1: 12,500 ₽ and 200 XP (half a daily's base)")
	ops.claim(list[1])
	check(not ops.bonus_paid(), "two of three: no bonus yet")
	money = gs.roubles
	ops.claim(list[2])
	check(ops.bonus_paid() and gs.roubles == money + int(list[2].rewards.roubles) + int(bonus.roubles), "the third pays the bonus on top")
	check(ops.menu_text().begins_with("Operations: all 3 dailies done"), "the main menu line: %s" % ops.menu_text())
	_profile(13)
	for task: Dictionary in ops.tasks("daily"):
		task.progress = [quests.objective_count(task, 0)]
	money = gs.roubles
	var total := 0
	for task: Dictionary in ops.tasks("daily"):
		total += int(task.rewards.roubles)
	ops.now_override = ops.period_end("daily", NOW)
	ops.update()
	check(gs.roubles == money + total + int(bonus.roubles), "all three left unclaimed: paid at the reset, the bonus too")
	ops.now_override = NOW


func _rare_items() -> void:
	section("The rare item")
	_profile(21)
	var table: Array = ops.data().rare_items.items
	var rare := 2  # ItemData.RARITY_IDS: rare.
	check(table.all(func(entry: Dictionary) -> bool: return db.get_item(entry.item).rarity >= rare), "every reward is Rare or better (%d items)" % table.size())
	var hits := {"daily": 0, "weekly": 0}
	var rolls := 3000
	var level_ok := true
	for kind: String in ["daily", "weekly"]:
		var template: Dictionary = ops.candidates(kind, 1)[0]
		for i in rolls:
			var rng := RandomNumberGenerator.new()
			rng.seed = i
			var task: Dictionary = ops.make_task(template, rng, kind, 40000 + i, 0, 1, "")
			var won: Dictionary = ops.rare_item(task)
			if not won.is_empty():
				hits[kind] += 1
				level_ok = level_ok and ops.rare_pool(1).any(func(entry: Dictionary) -> bool: return entry.item == won.item)
	var daily_rate: float = hits.daily / float(rolls)
	var weekly_rate: float = hits.weekly / float(rolls)
	check(absf(daily_rate - 0.15) < 0.02 and absf(weekly_rate - 0.6) < 0.03, "over %d seeded tasks each: %.1f%% of dailies and %.1f%% of weeklies give one" % [rolls, daily_rate * 100.0, weekly_rate * 100.0])
	check(level_ok and ops.rare_pool(1).all(func(entry: Dictionary) -> bool: return int(entry.level) <= 1), "a level-1 task gives only what's open at level 1")
	check(not ops.rare_pool(29).any(func(entry: Dictionary) -> bool: return db.get_item(entry.item).rarity >= 4) and ops.rare_pool(30).any(func(entry: Dictionary) -> bool: return db.get_item(entry.item).rarity >= 4),
		"Epic rewards from level 30")
	# A claim that wins one: the same item however often it's rolled, never found in raid.
	var winner := {}
	for i in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var task: Dictionary = ops.make_task(ops.template("survivor"), rng, "weekly", int(gs.operations.weekly.number), 0, 1, "_t%d" % i)
		if not ops.rare_item(task).is_empty():
			winner = task
			break
	gs.operations.weekly.tasks[0] = winner
	var won: Dictionary = ops.rare_item(winner)
	check(ops.rare_item(winner) == won, "the roll is seeded by the task: the same every time (%s)" % won.get("item", ""))
	winner.progress = [quests.objective_count(winner, 0)]
	var had: int = gs.stash.count_of(won.item)
	check(ops.claim(winner) == "" and gs.stash.count_of(won.item) == had + int(won.count) and winner.paid.item == won.item, "claiming puts it in the stash")
	var given: Array = gs.stash.all_items().filter(func(each: RefCounted) -> bool: return each.data.id == won.item)
	check(not given.is_empty() and given.all(func(each: RefCounted) -> bool: return not each.fir), "not found in raid")
	check(ops.reward_lines(winner).has(load("res://scripts/data/extract_table.gd").item_name(won.item)) or ops.reward_lines(winner).any(func(line: String) -> bool: return line.ends_with(load("res://scripts/data/extract_table.gd").item_name(won.item))),
		"the board shows what it gave: %s" % str(ops.reward_lines(winner)))
	# No room: it waits and arrives once there's room.
	var second := {}
	for i in range(200, 600):
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var task: Dictionary = ops.make_task(ops.template("survivor"), rng, "weekly", int(gs.operations.weekly.number), 1, 1, "_t%d" % i)
		if not ops.rare_item(task).is_empty():
			second = task
			break
	gs.operations.weekly.tasks[1] = second
	second.progress = [quests.objective_count(second, 0)]
	var filler: Array = []
	while true:
		var brick: RefCounted = item("gold_bar")
		if not gs.stash.add(brick):
			break
		filler.append(brick)
	check(ops.claim(second) == "" and gs.operations.owed.size() >= 1 and ops.owed_text().begins_with("%d reward item" % gs.operations.owed.size()), "with a full stash the item waits: %s" % ops.owed_text())
	for brick: RefCounted in filler:
		gs.stash.remove(brick)
	var item_id := str(ops.rare_item(second).item)
	had = gs.stash.count_of(item_id)
	check(ops.deliver_owed() >= 1 and gs.operations.owed.is_empty() and gs.stash.count_of(item_id) > had, "and arrives once there's room")


func _rerolls() -> void:
	section("Re-rolling a daily")
	_profile(17)
	var task: Dictionary = ops.tasks("daily")[0]
	var fee: int = ops.reroll_fee(task)
	check(fee == maxi(roundi(int(task.rewards.roubles) * 0.25 / 500.0) * 500, 500), "a re-roll costs a quarter of the task's money: %s ₽" % fee)
	quests.set_tracked(task, true)
	task.progress = [1] if quests.objective_count(task, 0) > 1 else [0]
	var money: int = gs.roubles
	var on_board: Array = ops.tasks("daily").map(func(each: Dictionary) -> String: return each.template)
	check(ops.reroll(task) == "", "re-rolled")
	var fresh: Dictionary = ops.tasks("daily")[0]
	check(gs.roubles == money - fee and not str(fresh.template) in on_board and ops.progress(fresh) == 0, "for the fee, a template not on the board, from scratch (%s)" % fresh.template)
	check(str(fresh.id).ends_with("_r1") and quests.is_tracked(fresh), "a new id, still tracked")
	check(ops.reroll(fresh) == "Already re-rolled", "one re-roll per daily")
	var again := _ids(ops.tasks("daily"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	saved.version = sm.SAVE_VERSION
	gs.from_dict(saved)
	check(_ids(ops.tasks("daily")) == again and ops.reroll(ops.tasks("daily")[0]) == "Already re-rolled", "a reload keeps the re-rolled task and its re-roll used")
	check(ops.reroll(ops.tasks("weekly")[0]) == "Weekly tasks can't be re-rolled", "weeklies can't be re-rolled")
	var second: Dictionary = ops.tasks("daily")[1]
	second.progress = [quests.objective_count(second, 0)]
	check(ops.reroll(second) == "Only an unfinished task can be re-rolled", "nor a finished one")
	gs.roubles = 0
	check(ops.reroll(ops.tasks("daily")[2]).begins_with("Not enough money"), "nor without the fee")


func _design() -> void:
	section("DESIGN.md")
	var table: String = ops.design_table()
	var design := FileAccess.get_file_as_string("res://DESIGN.md")
	if not check(table in design, "DESIGN.md §11 has the task pool table as operations.json has it (expected: %s)" % ProjectSettings.globalize_path("user://operations_table.md")):
		var out := FileAccess.open("user://operations_table.md", FileAccess.WRITE)
		out.store_string(table)
		out.close()
	check(table.count("\n") == ops.templates().size() + 1, "a row for each of the %d templates" % ops.templates().size())
