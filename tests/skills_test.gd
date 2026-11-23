extends "res://tests/test_base.gd"
## Player levels and skills (DESIGN.md §2.2, §12.3; plan E13): the level curve to 60 and old saves,
## skills.json and its checks, the points each level needs, fatigue in a raid, bonuses and their caps,
## each skill gaining from its real action and its bonus changing the real effect, the Gym, lifetime
## stats counted from raids and menus, the save round trip.

const MAP := "res://maps/test_level.tscn"
const HOUR := 3600.0

var skills: GDScript
var progression: GDScript


func run() -> void:
	skills = load("res://scripts/progression/skills.gd")
	progression = load("res://scripts/progression/progression.gd")
	_levels()
	_data()
	_points()
	_fatigue()
	_bonuses()
	_metabolism_and_stims()
	_weapon_handling()
	_vitality_body()
	_search()
	_crafting()
	_gym()
	await _raid_training()
	await _practice()
	await _raid_stats()
	_menu_stats()
	_saves()


func _levels() -> void:
	section("Player levels 1-60")
	var table: Array = progression.level_xp()
	check(progression.problems().is_empty(), "progression.json has no problems (%s)" % str(progression.problems()))
	check(progression.max_level() == 60 and table.size() == 60, "60 levels")
	var same := true
	for level in range(2, 61):
		var raw := 33000.0 * pow((level - 1) / 9.0, 1.68)
		var step := 50.0 if raw < 10000.0 else 500.0 if raw < 100000.0 else 1000.0
		same = same and int(table[level - 1]) == int(roundf(raw / step) * step)
	check(same, "every level is 33,000 x ((level - 1) / 9)^1.68, rounded (the same curve as levels 1-50)")
	check(int(table[49]) == 569000 and int(table[59]) == 777000, "level 50 still at 569,000 XP, 60 at 777,000")
	fresh_profile()
	check(gs.add_xp(777000) == 59 and gs.level == 60, "777,000 XP: level 60")
	check(gs.add_xp(100000) == 0 and gs.level == 60, "and no further")
	var save: Dictionary = {"version": 19, "profile": {"faction": "BEAR", "level": 50, "xp": 600000, "skills": {}}, "stash": []}
	gs.from_dict(sm.upgrade(save))
	check(gs.xp == 600000 and gs.level == 51, "a version 19 save at level 50 with 600,000 XP keeps its XP and moves on to level 51")
	gs.from_dict(sm.upgrade({"version": 19, "profile": {"faction": "BEAR", "level": 12, "xp": 50000}, "stash": []}))
	check(gs.level == 12 and gs.xp == 50000, "one at level 12 stays at 12")


func _data() -> void:
	section("skills.json")
	check(skills.problems().is_empty(), "skills.json has no problems (%s)" % str(skills.problems()))
	var ids: Array[String] = skills.ids()
	for id in ["strength", "endurance", "vitality", "metabolism", "stim_resistance", "search", "covert_movement", "crafting",
			"pistols", "smgs", "shotguns", "assault_rifles", "marksman_rifles", "bolt_action_rifles", "lmgs"]:
		check(id in ids, "%s is a skill (%s)" % [id, skills.display_name(id)])
	check(ids.size() == 15, "15 skills: 8 and the 7 weapon classes")
	var classes := {}
	for data: Resource in db.all_items():
		if data.weapon and data.weapon.skill != "":
			classes[data.weapon.skill] = true
	check(classes.size() == 7 and classes.keys().all(func(id: String) -> bool: return skills.is_weapon_class(id)), "every gun trains one of the 7 weapon class skills")
	for id in ids:
		var skill: Dictionary = skills.find(id)
		check(not skill.actions.is_empty() and not skill.bonuses.is_empty() and str(skill.trains) != "", "%s: trained by \"%s\", gives %s" % [id, skill.trains, skills.bonuses_text(id, 50)])
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(skills.PATH))
	parsed.skills[0].bonuses.recoil.per_level = 0
	parsed.skills[1].erase("trains")
	parsed.fatigue.floor = 0
	parsed.skills.remove_at(7)  # Crafting.
	var found: Array[String] = skills.problems_of(parsed)
	check(found.size() == 4 and found.any(func(p: String) -> bool: return "recoil" in p) and found.any(func(p: String) -> bool: return "crafting" in p),
		"a broken copy: four problems (%s)" % str(found))
	parsed.weapon_classes.skills.remove_at(0)  # Pistols: the pistols train a skill that isn't there.
	check(skills.problems_of(parsed).any(func(p: String) -> bool: return "trains pistols" in p), "a gun whose skill isn't a weapon class: a problem")


func _points() -> void:
	section("Skill points and levels")
	fresh_profile()
	check(skills.points_to_next(0) == 100.0 and is_equal_approx(skills.points_to_next(49), 590.0) and is_equal_approx(skills.total_points(50), 17250.0),
		"100 points to level 1, 590 from 49 to 50, 17,250 in all")
	check(gs.skills.size() == 15 and gs.skills.values().all(func(entry: Dictionary) -> bool: return int(entry.level) == 0 and float(entry.points) == 0.0),
		"a new profile has every skill at level 0")
	var heard := []
	var listener := func(id: String, old: int, new: int) -> void: heard.append([id, old, new])
	gs.skill_levelled.connect(listener)
	check(skills.add("search", 99.0) == 0 and skills.level("search") == 0 and is_equal_approx(skills.progress("search"), 0.99), "99 points: 99% of level 1")
	check(skills.add("search", 1.0 + 110.0 + 5.0) == 2 and skills.level("search") == 2 and is_equal_approx(skills.points("search"), 5.0), "116 more: two levels at once, 5 points over")
	check(heard == [["search", 0, 2]], "one skill_levelled signal for both (%s)" % str(heard))
	check(skills.add("search", 100000.0) == 48 and skills.level("search") == 50 and skills.points("search") == 0.0 and skills.progress("search") == 0.0,
		"a lot more: level 50, the top, and no points past it")
	check(skills.add("search", 50.0) == 0 and skills.level("search") == 50, "nothing more at 50")
	check(skills.add("nonsense", 50.0) == 0 and skills.add("endurance", -5.0) == 0 and skills.level("endurance") == 0, "an unknown skill or negative points: nothing")
	gs.skill_levelled.disconnect(listener)


func _fatigue() -> void:
	section("Fatigue in a raid")
	fresh_profile()
	check(is_equal_approx(skills.fatigued(0.0, 250.0), 250.0), "the first 250 points of a raid count in full")
	check(is_equal_approx(skills.fatigued(250.0, 250.0), 250.0 * log(2.0)), "the next 250 count 250 x ln 2 (each point 250 / earned)")
	check(is_equal_approx(skills.fatigued(5000.0, 100.0), 10.0), "past 2,500 a tenth")
	check(is_equal_approx(skills.fatigued(0.0, 1000.0), skills.fatigued(0.0, 400.0) + skills.fatigued(400.0, 600.0)), "the same in one step or two")
	skills.begin_raid(true)
	skills.add("endurance", 250.0)
	skills.add("endurance", 250.0)
	check(is_equal_approx(skills.total_points(skills.level("endurance")) + skills.points("endurance"), 250.0 + 250.0 * log(2.0)), "in a raid, 500 points of Endurance count 423")
	skills.add("search", 30.0)
	var gains: Dictionary = skills.end_raid()
	check(is_equal_approx(gains.endurance.earned, 500.0) and is_equal_approx(gains.endurance.points, 250.0 + 250.0 * log(2.0)) and int(gains.endurance.levels) == 3
		and is_equal_approx(gains.search.points, 30.0), "the raid's gains: points earned, counted and levels per skill (%s)" % str(gains))
	skills.begin_raid(true)
	skills.add("endurance", 100.0)
	check(is_equal_approx(skills.end_raid().endurance.points, 100.0), "a new raid starts fresh")
	var before: float = skills.points("endurance") + skills.total_points(skills.level("endurance"))
	skills.add("endurance", 600.0)
	check(is_equal_approx(skills.points("endurance") + skills.total_points(skills.level("endurance")), before + 600.0), "out of a raid, no fatigue")
	skills.begin_raid(false)
	check(skills.add("search", 500.0) == 0 and skills.end_raid().is_empty(), "a raid that doesn't count (practice): no gains")


func _bonuses() -> void:
	section("Bonuses and caps")
	fresh_profile()
	check(skills.bonus("metabolism", "drain") == 0.0, "level 0: no bonus")
	gs.skills.metabolism.level = 20
	check(is_equal_approx(skills.bonus("metabolism", "drain"), 0.2) and skills.bonus_text("metabolism", "drain") == "20% slower energy and hydration drain", "Metabolism 20: 20% slower drain")
	gs.skills.stim_resistance.level = 45
	check(is_equal_approx(skills.bonus("stim_resistance", "side_effects"), 0.3) and skills.cap_level("stim_resistance", "side_effects") == 30, "Stim resistance caps at 30% (level 30)")
	gs.skills.strength.level = 50
	check(is_equal_approx(skills.bonus("strength", "carry"), 5.0) and skills.bonus_text("strength", "carry") == "5 kg more before the weight slows you", "Strength 50: 5 kg more")
	var small := true
	for id in skills.ids():
		for name: String in skills.find(id).bonuses:
			var rules: Dictionary = skills.find(id).bonuses[name]
			small = small and (float(rules.max) <= 0.5 if str(rules.get("unit", "share")) == "share" else float(rules.max) <= 5.0)
	check(small, "every bonus stays small: at most 50% (Metabolism, as built), most 20-30%, Strength 5 kg")


func _metabolism_and_stims() -> void:
	section("Metabolism and Stim resistance (as built)")
	fresh_profile()
	var consumables: GDScript = load("res://scripts/inventory/consumables.gd")
	var stims: GDScript = load("res://scripts/inventory/stims.gd")
	var water: Resource = db.get_item("water_bottle")
	var units := absf(float(water.stats.get("energy", 0.0))) + absf(float(water.stats.get("hydration", 0.0)))
	check(is_equal_approx(consumables.metabolism_points(water), units * 0.5), "a drink is worth 0.5 Metabolism points per point of energy or hydration")
	consumables.train_metabolism(water)
	check(is_equal_approx(skills.points("metabolism"), units * 0.5), "drinking it trains Metabolism")
	gs.skills.metabolism.level = 10
	check(is_equal_approx(consumables.skill_multiplier(), 0.9), "Metabolism 10: drain x0.9")
	gs.skills.stim_resistance.level = 10
	check(is_equal_approx(stims.side_effect_multiplier(), 0.9), "Stim resistance 10: side effects x0.9")
	var health: RefCounted = load("res://scripts/actors/body_health.gd").new(load("res://data/config/health.tres"))
	health.start_metabolism(consumables.CONFIG, 100.0, 100.0)
	var stim: Resource = db.get_item("propital")
	var before: float = skills.points("stim_resistance")
	stims.inject(stim, health)
	var by_rarity := [15, 20, 25, 35, 45, 60]
	check(is_equal_approx(skills.points("stim_resistance") - before, by_rarity[stim.rarity]), "injecting %s: %d points (by rarity)" % [stim.id, by_rarity[stim.rarity]])


func _weapon_handling() -> void:
	section("Weapon handling: recoil, reloads, aiming")
	fresh_profile()
	var stats: GDScript = load("res://scripts/combat/weapon_stats.gd")
	var gun: RefCounted = load("res://scripts/inventory/inventory.gd").loaded_gun("ak_74n", "ammo_545_ps", 100.0)
	var plain: Resource = stats.build(gun, gs.skills)
	var ai: Resource = stats.build(gun)
	gs.skills.assault_rifles.level = 20
	var trained: Resource = stats.build(gun, gs.skills)
	check(is_equal_approx(trained.skill_recoil_reduction, 0.1) and is_equal_approx(trained.vertical_recoil, plain.vertical_recoil * 0.9), "Assault rifles 20: 10% less recoil")
	check(is_equal_approx(trained.reload_time, plain.reload_time * 0.92) and is_equal_approx(trained.empty_reload_time, plain.empty_reload_time * 0.92), "and 8%% faster reloads (%.2f s from %.2f)" % [trained.reload_time, plain.reload_time])
	check(is_equal_approx(trained.aim_time_multiplier, plain.aim_time_multiplier * 0.92), "and 8% faster aiming")
	gs.skills.strength.level = 30
	check(is_equal_approx(stats.build(gun, gs.skills).skill_recoil_reduction, 0.15), "with Strength 30 (7.5%) together they cap at 15%")
	gs.skills.assault_rifles.level = 50
	check(is_equal_approx(stats.build(gun, gs.skills).reload_time, plain.reload_time * 0.8), "reloads cap at 20% faster (level 50)")
	check(is_equal_approx(ai.reload_time, plain.reload_time) and ai.skill_recoil_reduction == 0.0, "the AI's guns (no skills) are as built")
	var pistol: RefCounted = load("res://scripts/inventory/inventory.gd").loaded_gun("pm", "ammo_9x18_pst", 100.0) if db.has_item("pm") else null
	if pistol:
		check(is_equal_approx(stats.build(pistol, gs.skills).reload_time, stats.build(pistol).reload_time), "an assault rifle skill doesn't speed a pistol's reload")


func _saves() -> void:
	section("Saves")
	fresh_profile()
	skills.add("covert_movement", 250.0)
	skills.add("crafting", 42.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	fresh_profile()
	gs.from_dict(data)
	check(skills.level("covert_movement") == 2 and is_equal_approx(skills.points("covert_movement"), 40.0) and is_equal_approx(skills.points("crafting"), 42.0),
		"skills round-trip with their levels and points")
	var old := {"version": 19, "profile": {"faction": "USEC", "level": 7, "xp": 20000,
		"skills": {"strength": {"level": 3, "progress": 0.5}, "metabolism": {"level": 12, "progress": 0.0}, "gone_skill": {"level": 9, "progress": 0.2}}}, "stash": []}
	gs.from_dict(sm.upgrade(old))
	check(skills.level("strength") == 3 and is_equal_approx(skills.points("strength"), 65.0), "a version 19 skill keeps its level; half way to the next becomes 65 points")
	check(skills.level("metabolism") == 12 and skills.level("crafting") == 0 and skills.level("covert_movement") == 0 and not gs.skills.has("gone_skill"),
		"other levels kept, the new skills at 0, an unknown one dropped")
	var stats: GDScript = load("res://scripts/progression/stats.gd")
	check(gs.stats == stats.blank(), "and lifetime stats all at 0")
	gs.stats.kills.pmc = 4
	gs.stats.longest_kill = 87.5
	gs.stats.raids.scav.mia = 2
	var again: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	fresh_profile()
	gs.from_dict(again)
	check(int(gs.stats.kills.pmc) == 4 and is_equal_approx(gs.stats.longest_kill, 87.5) and int(gs.stats.raids.scav.mia) == 2, "lifetime stats round-trip")


## The skill's total points (every level's and the ones toward the next).
func _total(id: String) -> float:
	return skills.total_points(skills.level(id)) + skills.points(id)


func _vitality_body() -> void:
	section("Vitality: bleeds, fractures, regeneration")
	fresh_profile()
	var body_script: GDScript = load("res://scripts/actors/body_health.gd")
	var config: Resource = load("res://data/config/health.tres")
	var counts := []
	for multiplier in [1.0, 0.7]:
		seed(7)
		var bleeds := 0
		var fractures := 0
		for i in 300:
			var body: RefCounted = body_script.new(config)
			body.bleed_multiplier = multiplier
			body.fracture_multiplier = multiplier
			body.hit(body_script.Part.LEFT_LEG, 20.0, {})
			bleeds += 1 if body.bleeds[body_script.Part.LEFT_LEG] != body_script.Bleed.NONE else 0
			fractures += 1 if body.fractures[body_script.Part.LEFT_LEG] else 0
		counts.append([bleeds, fractures])
	check(counts[1][0] < counts[0][0] and counts[1][1] < counts[0][1] and counts[1][0] > 0,
		"30%% lower chances: fewer bleeds and fractures from the same 300 hits (%s)" % str(counts))
	var healed := []
	for multiplier in [1.0, 1.2]:
		var body: RefCounted = body_script.new(config)
		body.regen_multiplier = multiplier
		body.apply_damage(body_script.Part.LEFT_ARM, 30.0, {})
		body.add_effect("regen", 2.0, 60.0, 0.0, false, "test")
		var before: float = body.hp[body_script.Part.LEFT_ARM]
		body.tick(5.0)
		healed.append(body.hp[body_script.Part.LEFT_ARM] - before)
	check(healed[0] > 0.0 and is_equal_approx(healed[1], healed[0] * 1.2), "20%% more regeneration from a stim (%s)" % str(healed))
	gs.skills.vitality.level = 25
	check(is_equal_approx(1.0 - skills.bonus("vitality", "bleed"), 0.85) and is_equal_approx(1.0 + skills.bonus("vitality", "regen"), 1.1), "Vitality 25: bleeds x0.85, regeneration x1.1")
	var consumables: GDScript = load("res://scripts/inventory/consumables.gd")
	var body: RefCounted = body_script.new(config)
	body.start_metabolism(consumables.CONFIG, 100.0, 100.0)  # The player's body.
	body.bleeds[body_script.Part.LEFT_ARM] = body_script.Bleed.LIGHT
	var before := _total("vitality")
	consumables.apply(item("bandage"), body, body_script.Part.LEFT_ARM)
	check(is_equal_approx(_total("vitality") - before, 10.0) and body.bleeds[body_script.Part.LEFT_ARM] == body_script.Bleed.NONE, "a bleed treated: 10 Vitality points")
	var ai_body: RefCounted = body_script.new(config)
	ai_body.bleeds[body_script.Part.LEFT_ARM] = body_script.Bleed.LIGHT
	before = _total("vitality")
	consumables.apply(item("bandage"), ai_body, body_script.Part.LEFT_ARM)
	check(_total("vitality") == before, "an AI's bandage trains nothing")


func _search() -> void:
	section("Search: items found, faster search")
	fresh_profile()
	var grid_script: GDScript = load("res://scripts/inventory/inventory_grid.gd")
	var search_script: GDScript = load("res://scripts/inventory/loot_search.gd")
	var times := []
	for search_level in [0, 50]:
		gs.skills.search.level = search_level
		var grid: RefCounted = grid_script.new(Vector2i(6, 6), &"loot")
		for id in ["bolts", "screws", "bandage", "water_bottle"]:
			grid.add(item(id))
		var search: RefCounted = search_script.new(func() -> Array: return [grid])
		search.hide_all()
		var seconds := 0.0
		while not search.is_done() and seconds < 60.0:
			search.step(0.05, true)
			seconds += 0.05
		times.append(seconds)
	check(times[0] > 1.0 and absf(times[1] - times[0] / 1.2) < 0.11, "Search 50: the same container 20%% faster (%.2f s, %.2f s)" % times)
	var ai_grid: RefCounted = grid_script.new(Vector2i(6, 6), &"loot")
	ai_grid.add(item("bolts"))
	var ai_search: RefCounted = search_script.new(func() -> Array: return [ai_grid])
	ai_search.hide_all()
	var slow: float = ai_search.time_for(ai_grid.items[0])
	check(ai_search.step(slow * 0.9).is_empty(), "a bot's search (not the player's) isn't sped up")
	gs.skills.search.level = 0
	skills.begin_raid(true)
	var grid: RefCounted = grid_script.new(Vector2i(6, 6), &"loot")
	for id in ["bolts", "screws", "bandage"]:
		grid.add(item(id))
	var search: RefCounted = search_script.new(func() -> Array: return [grid])
	search.hide_all()
	search.step(60.0, true)
	var gains: Dictionary = skills.end_raid()
	check(is_equal_approx(skills.points("search"), 12.0) and is_equal_approx(gains.search.points, 12.0), "three items found in a raid: 12 Search points")
	search.hide_all()
	search.step(60.0, true)
	check(is_equal_approx(skills.points("search"), 12.0), "out of a raid, nothing")


func _crafting() -> void:
	section("Crafting: crafts collected, shorter, sometimes one more")
	var work: GDScript = load("res://scripts/progression/hideout_work.gd")
	var hideout: GDScript = load("res://scripts/progression/hideout.gd")
	fresh_profile()
	work.now_override = 1_800_000_000.0
	gs.hideout_state = work.blank()
	gs.hideout.medstation = 1
	var medstation: Dictionary = hideout.find("medstation")
	var recipe: Dictionary = hideout.all_crafts(medstation)[2][1]  # Glucose shot, 5 minutes.
	check(is_equal_approx(work.craft_seconds(recipe), 300.0), "level 0: the glucose shot takes 5 minutes")
	gs.skills.crafting.level = 25
	check(is_equal_approx(work.craft_seconds(recipe), 270.0), "Crafting 25: 10% shorter, 4:30")
	gs.skills.crafting.level = 0
	for id in ["empty_injector", "sugar"]:
		gs.stash.add(item(id, 2))
	check(work.craft(medstation, recipe) == "" and is_equal_approx(work.queue(medstation)[0].total, 300.0), "queued")
	work.now_override += HOUR
	work.update()
	var before := _total("crafting")
	check(work.collect(medstation) == "" and is_equal_approx(_total("crafting") - before, 20.0 + 0.5 * 5.0), "collected: 20 points and 0.5 a minute (22.5)")
	gs.skills.crafting.level = 50
	var extra := 0
	for number in 2000:
		extra += 1 if work.extra_output(recipe, number) else 0
	check(extra > 140 and extra < 260, "Crafting 50: about one craft in ten makes one more (%d of 2,000)" % extra)
	gs.skills.crafting.level = 0
	check(range(2000).all(func(number: int) -> bool: return not work.extra_output(recipe, number)), "level 0: never")
	gs.skills.crafting.level = 50
	var number := 1
	while not work.extra_output(recipe, int(gs.hideout_state.get("crafted", 0)) + 1) and number < 500:
		gs.hideout_state.crafted = int(gs.hideout_state.get("crafted", 0)) + 1
		number += 1
	gs.stash.add(item("empty_injector", 1))
	gs.stash.add(item("sugar", 1))
	var shots: int = gs.stash.count_of("glucose_shot")
	work.craft(medstation, recipe)
	work.now_override += HOUR
	work.update()
	work.collect(medstation)
	check(gs.stash.count_of("glucose_shot") == shots + 2, "a craft that rolls the extra puts two in the stash")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	var crafted: int = gs.hideout_state.crafted
	gs.from_dict(saved)
	check(int(gs.hideout_state.crafted) == crafted, "the craft count is saved (the next roll stays the same)")
	work.now_override = -1.0


func _gym() -> void:
	section("The Gym")
	var work: GDScript = load("res://scripts/progression/hideout_work.gd")
	fresh_profile()
	work.now_override = 1_800_000_000.0
	gs.hideout_state = work.blank()
	gs.hideout.gym = 1
	check(work.train("strength") == "" and is_equal_approx(skills.points("strength"), 30.0), "a Gym session: 30 Strength points")
	work.now_override += 9.0 * HOUR
	check(work.train("endurance") == "" and is_equal_approx(skills.points("endurance"), 30.0), "and later 30 Endurance points, no fatigue (out of a raid)")
	work.now_override = -1.0


## Starts a raid on the Test Yard: the RaidController, its bots' AI off and no Scav waves.
func _start(extra := {}) -> Node:
	var raid := {"side": "pmc", "map": "test_yard", "loadout": gs.pmc_loadout(), "seed": 4, "boss": false, "pmcs": 0}
	raid.merge(extra, true)
	gs.raid = raid
	change_scene_to_file(MAP)
	await frames(3)
	var controller: Node = root.get_tree().get_first_node_in_group("raid_controller")
	controller.next_wave = -1.0
	for bot: Node in root.get_tree().get_nodes_in_group("bots"):
		bot.ai_enabled = false
	return controller


## The player moves `metres` (in steps of a metre) in `state` (Actor.Move): what training reads.
func _move(player: Node, metres: float, state: int) -> void:
	player._train_movement(0.0)
	var steps := ceili(metres)
	for i in steps:
		player.move_state = state
		player.global_position += Vector3(metres / steps, 0.0, 0.0)
		player._covert_check = 0.0
		player._train_movement(0.0)


func _raid_training() -> void:
	section("In a raid: each skill trained by doing it, and its bonus at work")
	fresh_profile()
	var controller: Node = await _start()
	var player: Node = controller.player
	var move: Dictionary = load("res://scripts/actors/actor.gd").Move
	check(skills.in_raid and skills.raid_counts, "a PMC raid trains skills")
	for bot: Node in root.get_tree().get_nodes_in_group("bots"):
		bot.global_position += Vector3(0.0, 0.0, 400.0)  # Out of the way (Covert movement looks for bots near).
	_move(player, 100.0, move.SPRINT)
	check(is_equal_approx(_total("endurance"), 10.0), "100 m sprinted: 10 Endurance points (%.2f)" % _total("endurance"))
	_move(player, 100.0, move.WALK)
	check(is_equal_approx(_total("endurance"), 10.0), "walking doesn't train it")
	var cap0: float = player.stamina_cap()
	gs.skills.endurance.level = 25
	check(is_equal_approx(player.stamina_cap(), cap0 + 15.0), "Endurance 25: 15%% more stamina (%.0f from %.0f)" % [player.stamina_cap(), cap0])
	var recovered := []
	for endurance_level in [0, 25]:
		gs.skills.endurance.level = endurance_level
		player.stamina = 10.0
		player._regen_cooldown = 0.0
		player._update_stamina(false, 1.0)
		recovered.append(player.stamina - 10.0)
	check(is_equal_approx(recovered[1], recovered[0] * 1.15), "and recovers 15%% faster (%s)" % str(recovered))
	# Strength: a load.
	var light: float = player.carried_weight_kg
	player.debug_extra_weight = maxf(15.0 - light, 0.0)
	var kg: float = player.carried_weight_kg
	var before := _total("strength")
	_move(player, 100.0, move.WALK)
	check(is_equal_approx(_total("strength") - before, 0.03 * 100.0 * kg / 25.0), "100 m with %.1f kg: %.2f Strength points" % [kg, _total("strength") - before])
	player.debug_extra_weight = 30.0 - light
	before = _total("strength")
	_move(player, 100.0, move.WALK)
	check(is_equal_approx(_total("strength") - before, 0.03 * 100.0 * 30.0 / 25.0 * 2.0), "with 30 kg (over the heavy threshold) twice as fast")
	player.debug_extra_weight = 5.0 - light if light < 5.0 else 0.0
	before = _total("strength")
	_move(player, 100.0, move.WALK)
	check(_total("strength") == before or player.carried_weight_kg >= 10.0, "under 10 kg: nothing")
	player.debug_extra_weight = 30.0 - light
	var weight_before: float = player.load_weight()
	gs.skills.strength.level = 30
	check(is_equal_approx(player.load_weight(), weight_before - 3.0), "Strength 30: 3 kg lighter against the thresholds")
	var stats_rows: Array = load("res://scripts/inventory/loadout_stats.gd").carry_rows(player.inventory, player.inventory_config, gs.skills)
	check(str(stats_rows[0].text).contains("43"), "the LOADOUT screen's weight row shows the higher limit (%s)" % stats_rows[0].text)
	player.debug_extra_weight = 0.0
	var grenade_script: GDScript = load("res://scripts/combat/thrown_grenade.gd")
	var far: Vector3 = player.global_position + Vector3(100.0, 0.0, 0.0)
	gs.skills.strength.level = 0
	var plain_throw: Node = grenade_script.throw(player, db.get_item("flashbang_grenade"), far)
	gs.skills.strength.level = 50
	var strong_throw: Node = grenade_script.throw(player, db.get_item("flashbang_grenade"), far)
	var flat := func(grenade: Node) -> float: return Vector2(grenade.target.x - player.global_position.x, grenade.target.z - player.global_position.z).length()
	check(absf(flat.call(strong_throw) / flat.call(plain_throw) - 1.2) < 0.02, "Strength 50: throws 20%% farther (%.1f m, %.1f m)" % [flat.call(plain_throw), flat.call(strong_throw)])
	plain_throw.queue_free()
	strong_throw.queue_free()
	gs.skills.strength.level = 0
	before = _total("strength")
	player.inventory.pockets.add(item("flashbang_grenade"))
	player._throw_cooldown = 0.0
	var thrown: bool = player.throw_item(player.inventory.pockets.items.filter(func(each: RefCounted) -> bool: return each.data.id == "flashbang_grenade")[0])
	check(thrown and is_equal_approx(_total("strength") - before, 3.0), "a throw: 3 Strength points (%s, %.2f)" % [thrown, _total("strength") - before])
	for grenade in root.get_tree().current_scene.get_children().filter(func(node: Node) -> bool: return node.get_script() == grenade_script):
		grenade.queue_free()
	# Weapon class: bullet hits and kills.
	var scav: Node = root.get_tree().get_nodes_in_group("bots")[0]
	var skill: String = player.weapon.data.skill
	before = _total(skill)
	player.on_hit_landed(scav, 10.0, scav.chest_point(), {"damage": 10.0})
	check(skill != "" and is_equal_approx(_total(skill) - before, 2.0), "a bullet hit with the %s: 2 %s points" % [player.weapon.data.resource_path.get_file(), skill])
	player.on_hit_landed(scav, 10.0, scav.chest_point(), {})
	check(is_equal_approx(_total(skill) - before, 2.0), "a grenade or melee hit (no bullet) trains no weapon skill")
	scav.take_blow(100000.0, player, "melee", "Test", scav.chest_point())
	player.on_hit_landed(scav, 100000.0, scav.chest_point(), {"damage": 100000.0})
	check(is_equal_approx(_total(skill) - before, 14.0), "a kill: 2 for the hit and 10 more")
	var reload_before: float = player.weapon.data.reload_time
	gs.skills[skill].level = 50
	player._sync_weapon(true)
	check(is_equal_approx(player.weapon.data.reload_time, reload_before * 0.8), "level 50, the gun drawn again: reloads 20%% faster (%.2f s)" % player.weapon.data.reload_time)
	gs.skills[skill].level = 0
	player._sync_weapon(true)
	# Vitality: damage taken and survived.
	before = _total("vitality")
	player.take_blow(10.0, null, "melee", "Test", player.chest_point())
	check(is_equal_approx(_total("vitality") - before, 5.0) and not player.is_dead, "10 damage taken and survived: 5 Vitality points")
	gs.skills.vitality.level = 50
	player._train_movement(0.0)
	check(is_equal_approx(player.health.bleed_multiplier, 0.7) and is_equal_approx(player.health.fracture_multiplier, 0.7) and is_equal_approx(player.health.regen_multiplier, 1.2),
		"Vitality 50: the body's bleed and fracture chances x0.7, regeneration x1.2")
	gs.skills.vitality.level = 0
	# Covert movement: near an enemy that isn't fighting you.
	var other: Node = root.get_tree().get_nodes_in_group("bots").filter(func(bot: Node) -> bool: return not bot.is_dead)[0]
	other.global_position = player.global_position + Vector3(0.0, 0.0, 15.0)
	before = _total("covert_movement")
	_move(player, 10.0, move.CROUCH)
	check(is_equal_approx(_total("covert_movement") - before, 2.0), "10 m crouched 15 m from an unaware Scav: 2 Covert movement points")
	_move(player, 10.0, move.SPRINT)
	check(is_equal_approx(_total("covert_movement") - before, 2.0), "sprinting doesn't count")
	other.global_position = player.global_position + Vector3(0.0, 0.0, 40.0)
	_move(player, 10.0, move.WALK)
	check(is_equal_approx(_total("covert_movement") - before, 2.0), "40 m away doesn't")
	other.global_position = player.global_position + Vector3(0.0, 0.0, 15.0)
	other.target = player
	other.state = other.State.COMBAT
	_move(player, 10.0, move.WALK)
	check(is_equal_approx(_total("covert_movement") - before, 2.0), "nor one that's fighting you")
	var reaction: float = other.reaction_time()
	gs.skills.covert_movement.level = 50
	check(is_equal_approx(other.reaction_time(), reaction * 1.2), "Covert movement 50: the Scav reacts 20%% later (%.2f s)" % other.reaction_time())
	check(is_equal_approx(player.step_noise_multiplier(), 0.8) and other.step_noise_multiplier() == 1.0, "and your footsteps are 20% quieter (the AI's aren't)")
	other.state = other.State.IDLE
	other.target = null
	# Fatigue and the summary.
	gs.skills.endurance.level = 0
	gs.skills.endurance.points = 0.0
	var outcome: RefCounted = controller.end_raid(load("res://scripts/raid/raid_outcome.gd").Status.SURVIVED)
	check(not skills.in_raid and outcome.skill_gains.has("endurance") and outcome.skill_gains.has(skill), "the raid's skill gains reach its outcome (%s)" % str(outcome.skill_gains.keys()))


func _practice() -> void:
	section("A practice raid trains nothing")
	fresh_profile()
	var controller: Node = await _start({"practice": true})
	var player: Node = controller.player
	check(skills.in_raid and not skills.raid_counts, "the practice raid doesn't count")
	_move(player, 100.0, load("res://scripts/actors/actor.gd").Move.SPRINT)
	check(_total("endurance") == 0.0, "100 m sprinted: no Endurance")
	change_scene_to_file("res://ui/main_menu.tscn")
	await frames(3)
	check(not skills.in_raid, "leaving the raid scene ends the raid for skills")


func _raid_stats() -> void:
	section("Lifetime stats from a raid")
	fresh_profile()
	var stats: GDScript = load("res://scripts/progression/stats.gd")
	var controller: Node = await _start()
	var player: Node = controller.player
	var move: Dictionary = load("res://scripts/actors/actor.gd").Move
	_move(player, 50.0, move.WALK)
	for i in 5:
		player._on_round_fired()
	var bots: Array = root.get_tree().get_nodes_in_group("bots").filter(func(bot: Node) -> bool: return not bot.is_dead)
	var scav: Node = bots[0]
	scav.global_position = player.global_position + Vector3(30.0, 0.0, 0.0)
	player.on_hit_landed(scav, 25.0, scav.chest_point(), {"damage": 25.0, "part": 1})
	scav.take_blow(100000.0, player, "melee", "Test", scav.chest_point())
	player.on_hit_landed(scav, 100.0, scav.chest_point(), {"damage": 100.0, "part": 0})  # The head.
	player.take_blow(12.0, null, "melee", "Test", player.chest_point())
	controller._on_loot_claimed(items([item("bolts"), item("screws")]))
	controller.elapsed = 300.0
	var outcome: RefCounted = controller.end_raid(load("res://scripts/raid/raid_outcome.gd").Status.SURVIVED)
	var counted: Dictionary = gs.stats
	check(int(counted.raids.pmc.survived) == 1 and stats.raids() == 1 and is_equal_approx(stats.survival_rate(), 1.0), "one PMC raid, survived: 100% survival")
	check(int(counted.kills.scav) == 1 and int(counted.headshots) == 1 and absf(float(counted.longest_kill) - 30.0) < 0.2, "a Scav killed, a headshot, 30 m the longest kill (%s m)" % counted.longest_kill)
	check(int(counted.shots) == 5 and int(counted.hits) == 2 and is_equal_approx(counted.damage_dealt, 125.0) and is_equal_approx(counted.damage_taken, 12.0),
		"5 rounds fired, 2 hits, 125 damage dealt, 12 taken")
	check(absf(float(counted.distance) - 50.0) < 0.2 and int(counted.items_looted) == 2 and float(counted.raid_seconds) >= 1.0 and int(counted.best_raid_xp) == outcome.xp,
		"50 m moved, 2 items looted, the time and the best raid's %d XP" % outcome.xp)
	check(stats.rows().size() >= 15 and stats.rows().any(func(row: Array) -> bool: return row[1] == "Kills" and str(row[2]).begins_with("1 ")), "the STATS tab's rows (%d)" % stats.rows().size())
	var practice: Node = await _start({"practice": true})
	practice.player._on_round_fired()
	practice.end_raid(load("res://scripts/raid/raid_outcome.gd").Status.SURVIVED)
	check(stats.raids() == 1 and int(gs.stats.shots) == 5, "a practice raid counts nothing")
	var second: Node = await _start()
	second.end_raid(load("res://scripts/raid/raid_outcome.gd").Status.KILLED)
	check(int(gs.stats.raids.pmc.killed) == 1 and is_equal_approx(stats.survival_rate(), 0.5), "killed in the next: 50% survival")
	change_scene_to_file("res://ui/main_menu.tscn")
	await frames(3)


func _menu_stats() -> void:
	section("Lifetime stats from the menus")
	fresh_profile()
	var trading: GDScript = load("res://scripts/progression/trading.gd")
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	var offer: Dictionary = {}
	for each: Dictionary in trading.buy_list("bulat"):
		if each.get("id") == "bulat_ammo_9x18_p":
			offer = each
	var roubles: int = gs.roubles
	check(trading.buy("bulat", offer) == "" and int(gs.stats.roubles_spent) == roubles - gs.roubles, "buying from a trader: roubles spent (%s)" % gs.stats.roubles_spent)
	var sold := item("ammo_545_ps", 60)
	gs.stash.add(sold)
	roubles = gs.roubles
	check(selling.sell("bulat", [sold]) == "" and int(gs.stats.roubles_earned) == gs.roubles - roubles, "selling: roubles earned (%s)" % gs.stats.roubles_earned)
	var before: int = int(gs.stats.roubles_spent)
	gs.quests["zoya_introduction"] = {"state": "completed", "progress": [1, 2, 150000]}  # The Broker, who exchanges.
	check(trading.buy_dollars(10) == "" and int(gs.stats.roubles_spent) == before, "exchanging money is neither (%s)" % trading.exchange_block_reason(10, true))
	gs.quests.erase("zoya_introduction")
	var quests: GDScript = load("res://scripts/progression/quest_log.gd")
	var first: Dictionary = quests.all().filter(func(quest: Dictionary) -> bool: return quests.state(quest) == "available" and quests.accept_block_reason(quest) == "")[0]
	quests.accept(first)
	for index in first.objectives.size():
		gs.quests[first.id].progress[index] = quests.objective_count(first, index)
	var earned_before: int = int(gs.stats.roubles_earned)
	check(quests.complete(first) == "" and int(gs.stats.quests) == 1 and int(gs.stats.roubles_earned) == earned_before + int(first.rewards.get("roubles", 0)) + roundi(int(first.rewards.get("dollars", 0)) * 140),
		"a quest completed counts, with its money reward (%s)" % first.id)
	var work: GDScript = load("res://scripts/progression/hideout_work.gd")
	var hideout: GDScript = load("res://scripts/progression/hideout.gd")
	work.now_override = 1_800_000_000.0
	gs.hideout_state = work.blank()
	gs.hideout.medstation = 1
	var medstation: Dictionary = hideout.find("medstation")
	gs.stash.add(item("empty_injector", 1))
	gs.stash.add(item("sugar", 1))
	work.craft(medstation, hideout.all_crafts(medstation)[2][1])
	work.now_override += HOUR
	work.update()
	check(work.collect(medstation) == "" and int(gs.stats.crafts) == 1, "a craft collected counts")
	work.now_override = -1.0
