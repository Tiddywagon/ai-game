class_name PmcAi
extends RefCounted
## How AI PMC squads play a raid (DESIGN.md §4.4), from data/config/pmc_ai.json (checked when it loads:
## problems()). One source for RaidPlan, Bot, RaidController and the debug overlay: the personalities a
## squad rolls (Rat, Looter, Chad, Quester: roll_personality(), personality(): how it picks its points of
## interest, which noises it goes to look at, raid events, Scavs, how it moves, when it leaves), each
## map's Quester objectives (quest_targets()), the gear tiers a squad rolls by map difficulty
## (roll_tier(), tier()), each map's AI PMC spawn schedule (schedule(), budget()), and the tuning of
## routes, looting, healing, fighting as a squad and the plan itself (route(), loot(), heal(),
## combat(), plan()). A value of the wrong type is reported by problems() and read as missing (dict(),
## pair(), number()), so a broken file doesn't stop a raid.

const PATH := "res://data/config/pmc_ai.json"
const PERSONALITY_FIELDS := ["name", "weight", "pois", "investigate", "investigate_within", "investigate_near_route",
	"avoids_noise", "avoid_within", "hunts", "rush", "rush_within", "rush_needs_quiet", "scavs", "movement", "leave_window", "bag_full"]
const POI_FIELDS := ["count", "tier_values", "tier", "distance", "heat", "centre", "quiet", "random", "quest", "knows_hidden", "hidden"]
## Personality and POI knobs that are numbers (problems() checks them), and those that are true/false.
const NUMBER_KNOBS := ["weight", "investigate_within", "investigate_near_route", "avoid_within", "rush", "rush_within", "bag_full"]
const POI_NUMBER_KNOBS := ["tier", "distance", "heat", "centre", "quiet", "random", "hidden"]
const FLAG_KNOBS := ["avoids_noise", "hunts", "rush_needs_quiet"]
## The noise kinds a personality's investigate chances are given for (noise_category()).
const NOISE_KINDS := ["gunshot", "footstep", "voice"]
const SCAV_STANCES := ["fight", "avoid"]
## Gear tier fields that override the faction's BotKit (Factions.ai_kit()).
const TIER_FIELDS := ["name", "rarity", "ammo_rarity", "helmet_chance", "backpack_chance", "pistol_chance", "stim_chance",
	"gun_mods", "medkit_rarity", "gun_durability"]
const SECTIONS := {
	"route": ["sample_spacing", "hug_radius", "max_detour", "waypoint_reach"],
	"loot": ["min_value", "give_up", "follower_radius"],
	"heal": ["quiet_seconds", "below", "max_treatments", "cooldown"],
	"combat": ["spread", "flank_chance", "regroup_distance", "regroup_timeout"],
	"plan": ["tick", "extract_margin", "detour_estimate", "min_stay", "noise_memory", "hunt_seconds", "avoid_quiet",
		"avoid_distance", "avoid_give_up", "avoid_calm", "rush_wait", "poi_reach"],
}
## AI PMCs a raid gets without the file (or without its schedule): all at the start, without plans (as
## the Factory had before raid plans).
const FALLBACK_BUDGET := 3

## The file data() loads (tests point it at a broken copy), and what was wrong with it when it last
## loaded (problems(); each one also an error).
static var path := PATH
static var load_problems: Array[String] = []
static var _data := {}
static var _loaded := false


## The whole file. Checked the first time it loads (each problem is an error, reported once). A file
## that's missing or isn't valid JSON gives {}: FALLBACK_BUDGET AI PMCs then spawn without plans and
## roam as before.
static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("personalities") is Dictionary:
			_data = parsed
			load_problems = problems()
		else:
			_data = {}
			load_problems = ["%s isn't valid JSON with a \"personalities\" object" % path]
		for problem in load_problems:
			push_error("PmcAi: %s" % problem)
	return _data


## Forgets what was loaded (tests that point `path` elsewhere, or change it).
static func reload() -> void:
	_data = {}
	_loaded = false
	load_problems.clear()


## The personalities' ids, in file order.
static func personalities() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: String in data().get("personalities", {}):
		result.append(StringName(id))
	return result


## A personality's knobs ({} for none).
static func personality(id: StringName) -> Dictionary:
	return dict(dict(data().get("personalities")).get(String(id)))


## "Looter" ("" for none).
static func personality_name(id: StringName) -> String:
	return str(personality(id).get("name", String(id).capitalize()))


## A personality rolled by the weights (&"" if there are none).
static func roll_personality(rng: RandomNumberGenerator) -> StringName:
	var ids := personalities()
	var weights := PackedFloat32Array()
	for id in ids:
		weights.append(maxf(number(personality(id), "weight"), 0.0))
	var index := LootTable._pick(rng, weights)
	return ids[index] if index >= 0 else &""


## How a PMC without a plan reacts (to raid events): this personality's knobs.
static func default_personality() -> StringName:
	return StringName(str(data().get("default_personality", "")))


## The map's Quester objectives (POI ids).
static func quest_targets(map_id: String) -> Array:
	var ids: Variant = dict(data().get("quest_targets")).get(map_id)
	return ids if ids is Array else []


## The gear tiers' ids, cheapest first.
static func tiers() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: String in dict(data().get("gear_tiers")):
		result.append(StringName(id))
	return result


## A gear tier's overrides ({} for none).
static func tier(id: StringName) -> Dictionary:
	return dict(dict(data().get("gear_tiers")).get(String(id)))


## "Well-equipped" ("" for none).
static func tier_name(id: StringName) -> String:
	return str(tier(id).get("name", String(id).capitalize()))


## The weight of each tier on a map of `difficulty` (1-5): {tier id: weight}.
static func tier_weights(difficulty: int) -> Dictionary:
	return dict(dict(data().get("tier_weights")).get(str(clampi(difficulty, 1, 5))))


## A gear tier rolled by the weights for `difficulty` (&"" if there are none).
static func roll_tier(rng: RandomNumberGenerator, difficulty: int) -> StringName:
	var ids := tiers()
	var weights := PackedFloat32Array()
	var by_tier := tier_weights(difficulty)
	for id in ids:
		weights.append(maxf(number(by_tier, String(id)), 0.0))
	var index := LootTable._pick(rng, weights)
	return ids[index] if index >= 0 else &""


## The AI PMC spawn schedule: budget (by map), late_share, late_squads, late_window, late_falloff,
## late_retry, late_give_up.
static func schedule() -> Dictionary:
	return dict(data().get("schedule"))


## AI PMCs in a raid on `map_id` (0 for a map without one; FALLBACK_BUDGET without a schedule at all).
static func budget(map_id: String) -> int:
	if schedule().is_empty():
		return FALLBACK_BUDGET
	return int(number(dict(schedule().get("budget")), map_id))


static func route() -> Dictionary:
	return dict(data().get("route"))


static func loot() -> Dictionary:
	return dict(data().get("loot"))


static func heal() -> Dictionary:
	return dict(data().get("heal"))


static func combat() -> Dictionary:
	return dict(data().get("combat"))


static func plan() -> Dictionary:
	return dict(data().get("plan"))


## `value` if it's a Dictionary, else {}.
static func dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


## `value` if it's [min, max] (two numbers), else `fallback`.
static func pair(value: Variant, fallback: Array) -> Array:
	return value if value is Array and value.size() == 2 and value.all(is_number) else fallback


## `values[key]` if it's a number, else `fallback`.
static func number(values: Dictionary, key: String, fallback := 0.0) -> float:
	var value: Variant = values.get(key)
	return float(value) if is_number(value) else fallback


static func is_number(value: Variant) -> bool:
	return value is int or value is float


## The personality knob category of a noise `kind` (NoiseSystem): "gunshot" for shots, explosions and
## flashbangs, "voice" for voice lines, else "footstep".
static func noise_category(kind: StringName) -> String:
	if kind in [&"gunshot", &"explosion", &"flashbang"]:
		return "gunshot"
	if kind == &"voice":
		return "voice"
	return "footstep"


## What's wrong with pmc_ai.json: personalities without their fields, values of the wrong type (an
## object, list, number or true/false where another is wanted), weights or chances out of range, a POI
## count outside 2-4, an unknown Scav stance, a leave window outside the raid, quest targets that aren't
## one or two POIs of their map, gear tiers with unknown fields or rarity lists that aren't six
## multipliers, tier weights missing for a difficulty, a map without a budget or a late window outside
## the raid, tuning sections missing values. Empty if it's fine.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var all := dict(data().get("personalities"))
	if all.size() < 4:
		found.append("fewer than four personalities")
	var total := 0.0
	for id: String in all:
		var where := "personality %s" % id
		if not all[id] is Dictionary:
			found.append("%s isn't an object" % where)
			continue
		var knobs: Dictionary = all[id]
		for field in PERSONALITY_FIELDS:
			if not knobs.has(field):
				found.append("%s: no %s" % [where, field])
		for key in NUMBER_KNOBS:
			if knobs.has(key) and not is_number(knobs[key]):
				found.append("%s: %s must be a number" % [where, key])
		for key in FLAG_KNOBS:
			if knobs.has(key) and not knobs[key] is bool:
				found.append("%s: %s must be true or false" % [where, key])
		total += maxf(number(knobs, "weight"), 0.0)
		if number(knobs, "weight") < 0.0:
			found.append("%s: a negative weight" % where)
		if knobs.has("pois") and not knobs.pois is Dictionary:
			found.append("%s: pois must be an object" % where)
		var pois := dict(knobs.get("pois"))
		for field in POI_FIELDS:
			if knobs.get("pois") is Dictionary and not pois.has(field):
				found.append("%s: pois has no %s" % [where, field])
		for key in POI_NUMBER_KNOBS:
			if pois.has(key) and not is_number(pois[key]):
				found.append("%s: pois.%s must be a number" % [where, key])
		for key in ["quest", "knows_hidden"]:
			if pois.has(key) and not pois[key] is bool:
				found.append("%s: pois.%s must be true or false" % [where, key])
		var count := pair(pois.get("count"), [])
		if count.is_empty() or int(count[0]) < 2 or int(count[1]) > 4 or int(count[0]) > int(count[1]):
			found.append("%s: pois.count must be [min, max] within 2-4" % where)
		var values: Variant = pois.get("tier_values")
		if not (values is Array and values.size() == 3 and values.all(is_number)):
			found.append("%s: pois.tier_values needs a value for tiers 1, 2 and 3" % where)
		if knobs.has("investigate") and not knobs.investigate is Dictionary:
			found.append("%s: investigate must be an object" % where)
		for kind in NOISE_KINDS:
			var chance := number(dict(knobs.get("investigate")), kind, -1.0)
			if chance < 0.0 or chance > 1.0:
				found.append("%s: investigate.%s must be 0-1" % [where, kind])
		for key in ["rush", "bag_full"]:
			if number(knobs, key, -1.0) < 0.0 or number(knobs, key, -1.0) > 1.0:
				found.append("%s: %s must be 0-1" % [where, key])
		if not str(knobs.get("scavs", "")) in SCAV_STANCES:
			found.append("%s: scavs must be one of %s" % [where, SCAV_STANCES])
		if knobs.has("movement") and not knobs.movement is Dictionary:
			found.append("%s: movement must be an object" % where)
		var movement := dict(knobs.get("movement"))
		if movement.has("crouch_near_poi") and not is_number(movement.crouch_near_poi):
			found.append("%s: movement.crouch_near_poi must be a number" % where)
		for key in ["sprint", "crouch_along_cover"]:
			if movement.has(key) and not movement[key] is bool:
				found.append("%s: movement.%s must be true or false" % [where, key])
		var window := pair(knobs.get("leave_window"), [])
		if window.is_empty() or float(window[0]) <= 0.0 or float(window[1]) >= 1.0 or float(window[0]) > float(window[1]):
			found.append("%s: leave_window must be [min, max] within the raid (0-1)" % where)
	if total <= 0.0:
		found.append("personalities: no weights")
	if not all.has(str(data().get("default_personality", ""))):
		found.append("default_personality isn't a personality")
	if data().has("quest_targets") and not data().quest_targets is Dictionary:
		found.append("quest_targets must be an object")
	var targets := dict(data().get("quest_targets"))
	for map in MapInfo.load_all():
		var ids: Variant = targets.get(map.id, [])
		if not ids is Array:
			found.append("quest_targets: %s must be a list of POI ids" % map.id)
			ids = []
		if ids.size() < 1 or ids.size() > 2:
			found.append("quest_targets: %s needs 1-2 POIs" % map.id)
		for poi_id: Variant in ids:
			if not poi_id is String or PoiTable.find(map.id, poi_id).is_empty():
				found.append("quest_targets: %s has no POI %s" % [map.id, poi_id])
		if budget(map.id) < 2:
			found.append("schedule: %s needs a budget of at least 2 AI PMCs" % map.id)
	if data().has("gear_tiers") and not data().gear_tiers is Dictionary:
		found.append("gear_tiers must be an object")
	var tier_list := dict(data().get("gear_tiers"))
	if tier_list.size() < 2:
		found.append("fewer than two gear tiers")
	for id: String in tier_list:
		if not tier_list[id] is Dictionary:
			found.append("gear tier %s isn't an object" % id)
			continue
		var entry: Dictionary = tier_list[id]
		for field: String in entry:
			if not field in TIER_FIELDS:
				found.append("gear tier %s: unknown field %s" % [id, field])
		for field in ["rarity", "medkit_rarity"]:
			if entry.has(field) and (not entry[field] is Array or entry[field].size() != LootTable.RARITY_COUNT or not entry[field].all(is_number)):
				found.append("gear tier %s: %s needs %d multipliers" % [id, field, LootTable.RARITY_COUNT])
		for field in ["ammo_rarity", "gun_durability"]:
			if entry.has(field) and pair(entry[field], []).is_empty():
				found.append("gear tier %s: %s must be [min, max]" % [id, field])
		for field in ["helmet_chance", "backpack_chance", "pistol_chance", "stim_chance", "gun_mods"]:
			if entry.has(field) and not is_number(entry[field]):
				found.append("gear tier %s: %s must be a number" % [id, field])
	if data().has("tier_weights") and not data().tier_weights is Dictionary:
		found.append("tier_weights must be an object")
	for difficulty in range(1, 6):
		var weights := tier_weights(difficulty)
		if weights.is_empty() or weights.values().all(func(weight: Variant) -> bool: return not is_number(weight) or float(weight) <= 0.0):
			found.append("tier_weights: no weights for difficulty %d" % difficulty)
		for id: String in weights:
			if not tier_list.has(id):
				found.append("tier_weights %d: no gear tier %s" % [difficulty, id])
			if not is_number(weights[id]):
				found.append("tier_weights %d: %s must be a number" % [difficulty, id])
	if data().has("schedule") and not data().schedule is Dictionary:
		found.append("schedule must be an object")
	var plan_schedule := schedule()
	var late := pair(plan_schedule.get("late_window"), [])
	if late.is_empty() or float(late[0]) <= 0.0 or float(late[1]) >= 1.0 or float(late[0]) > float(late[1]):
		found.append("schedule: late_window must be [min, max] within the raid")
	var squads := pair(plan_schedule.get("late_squads"), [])
	if squads.is_empty() or int(squads[0]) < 1 or int(squads[0]) > int(squads[1]):
		found.append("schedule: late_squads must be [min, max], at least 1")
	var share := number(plan_schedule, "late_share", -1.0)
	if share <= 0.0 or share >= 1.0:
		found.append("schedule: late_share must be between 0 and 1")
	for key in ["late_falloff", "late_retry", "late_give_up"]:
		if number(plan_schedule, key) <= 0.0:
			found.append("schedule: %s must be above 0" % key)
	for section: String in SECTIONS:
		if data().has(section) and not data()[section] is Dictionary:
			found.append("%s must be an object" % section)
		var values := dict(data().get(section))
		for key: String in SECTIONS[section]:
			if number(values, key, -1.0) < 0.0:
				found.append("%s: %s missing, negative or not a number" % [section, key])
	return found
