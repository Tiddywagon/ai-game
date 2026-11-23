extends "res://tests/test_base.gd"
## Player levels and skills (DESIGN.md §2.2, §12.3; plan E13): the level curve to 60 and old saves,
## skills.json and its checks, the points each level needs, fatigue in a raid, bonuses and their caps,
## each skill gaining from its real action and its bonus changing the real effect, the Gym, lifetime
## stats counted from raids and menus, the save round trip.

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
