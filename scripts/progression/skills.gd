class_name Skills
extends RefCounted
## Player skills (DESIGN.md §12.3), from data/config/skills.json: each skill, what trains it (points per
## action), the points each level needs (a little more every level, up to level 50), the bonuses a level
## gives (per level, up to a cap) and the per-raid fatigue rule. Skills live in GameState.skills as
## {"level", "points" (toward the next level)}. Every caller goes through here: level(), bonus(), add()
## (and train(), which looks up an action's points first). In a raid (begin_raid() / end_raid(), from
## RaidController) gains slow down after a lot of one skill (fatigue), nothing is gained in a raid that
## doesn't go to the profile (practice), and what each skill gained is kept for the raid summary
## (raid_gains). A level gained emits GameState.skill_levelled. Checked when the items load: problems().

const PATH := "res://data/config/skills.json"
const MAX_LEVEL := 50

## The file read (tests point it at a broken copy, then reload()).
static var path := PATH
static var _config := {}
static var _skills: Array[Dictionary] = []
static var _by_id := {}
static var _loaded := false

## A raid is on (begin_raid()), and whether what it does goes to the profile.
static var in_raid := false
static var raid_counts := true
## What each skill gained this raid: id -> {"earned" (points before fatigue), "points" (counted),
## "levels"}.
static var raid_gains := {}


static func config() -> Dictionary:
	if not _loaded:
		_loaded = true  # Before problems(), which reads the config again.
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_config = parsed if parsed is Dictionary else {}
		if not parsed is Dictionary:
			push_error("Skills: %s isn't valid JSON" % path)
		_expand()
		for problem in problems():
			push_warning("Skills: %s" % problem)
	return _config


## Reads the file again on next use.
static func reload() -> void:
	_config = {}
	_skills = []
	_by_id = {}
	_loaded = false


## The skill list with the weapon classes spelled out, one entry each.
static func _expand() -> void:
	_skills = _skill_list(_config)
	_by_id = {}
	for skill in _skills:
		_by_id[str(skill.get("id", ""))] = skill


## The skills `data` (a skills.json) defines, the weapon classes spelled out.
static func _skill_list(data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in data.get("skills", []):
		if entry is Dictionary:
			result.append(entry)
	var classes: Dictionary = data.get("weapon_classes", {})
	for pair: Variant in classes.get("skills", []):
		if pair is Array and pair.size() >= 2:
			result.append({"id": str(pair[0]), "name": str(pair[1]), "trains": classes.get("trains", ""), "weapon_class": true,
				"actions": classes.get("actions", {}), "bonuses": classes.get("bonuses", {})})
	return result


## Every skill, in the order the CHARACTER screen lists them.
static func all() -> Array[Dictionary]:
	config()
	return _skills


static func ids() -> Array[String]:
	var result: Array[String] = []
	for skill in all():
		result.append(str(skill.id))
	return result


## The skill `id` ({} if there's none).
static func find(id: String) -> Dictionary:
	config()
	return _by_id.get(id, {})


## "Metabolism" for "metabolism".
static func display_name(id: String) -> String:
	return str(find(id).get("name", id.capitalize()))


## What the CHARACTER screen says trains `id`.
static func trains(id: String) -> String:
	return str(find(id).get("trains", ""))


## True for the weapon class skills.
static func is_weapon_class(id: String) -> bool:
	return bool(find(id).get("weapon_class", false))


## A number from `id`'s "rules".
static func rule(id: String, name: String, default := 0.0) -> float:
	return float(find(id).get("rules", {}).get(name, default))


# --- Levels ---------------------------------------------------------------------------------------

## A new profile's skills: every one at level 0.
static func blank() -> Dictionary:
	var result := {}
	for id in ids():
		result[id] = {"level": 0, "points": 0.0}
	return result


## The skills from a save: `saved` (id -> {"level", "points"}, or a version 19 or older save's {"level",
## "progress" (0-1 of the way to the next level)}), every skill there even if the save lacks it.
static func from_save(saved: Variant) -> Dictionary:
	var result := blank()
	if not saved is Dictionary:
		return result
	for id: String in saved:
		var entry: Variant = saved[id]
		if not result.has(id) or not entry is Dictionary:
			continue
		var skill_level := clampi(int(entry.get("level", 0)), 0, MAX_LEVEL)
		var points := float(entry.get("points", float(entry.get("progress", 0.0)) * points_to_next(skill_level)))
		result[id] = {"level": skill_level, "points": 0.0 if skill_level >= MAX_LEVEL else clampf(points, 0.0, points_to_next(skill_level))}
	return result


static func level(id: String, skills: Variant = null) -> int:
	var table: Dictionary = skills if skills is Dictionary else GameState.skills
	return int(table.get(id, {}).get("level", 0))


## Points `id` has toward its next level.
static func points(id: String) -> float:
	return float(GameState.skills.get(id, {}).get("points", 0.0))


## How far `id` is toward its next level (0-1; 0 at the top).
static func progress(id: String) -> float:
	var at := level(id)
	return 0.0 if at >= MAX_LEVEL else clampf(points(id) / points_to_next(at), 0.0, 1.0)


## Points from `skill_level` to the next level.
static func points_to_next(skill_level: int) -> float:
	var rules: Dictionary = config().get("points", {})
	return float(rules.get("base", 100.0)) * (1.0 + float(rules.get("growth", 0.1)) * skill_level)


## Points from level 0 to `skill_level`.
static func total_points(skill_level: int) -> float:
	var total := 0.0
	for at in skill_level:
		total += points_to_next(at)
	return total


# --- Gaining --------------------------------------------------------------------------------------

## The points one `action` of skill `id` is worth (`index`: the entry of a list by rarity).
static func action_points(id: String, action: String, index := 0) -> float:
	var value: Variant = find(id).get("actions", {}).get(action, 0.0)
	if value is Array:
		return float(value[clampi(index, 0, value.size() - 1)]) if not value.is_empty() else 0.0
	return float(value)


## `amount` of `action` for skill `id` (2.5 metres sprinted, 1 craft collected). Returns the levels gained.
static func train(id: String, action: String, amount := 1.0, index := 0) -> int:
	return add(id, action_points(id, action, index) * amount)


## Adds `points` to skill `id` (less in a raid once it's tired: fatigue(), none in a raid that doesn't
## count). Returns how many levels it gained (usually 0).
static func add(id: String, points_in: float) -> int:
	if not GameState.skills.has(id) or points_in <= 0.0 or (in_raid and not raid_counts):
		return 0
	var counted := points_in
	if in_raid:
		var gains: Dictionary = raid_gains.get(id, {"earned": 0.0, "points": 0.0, "levels": 0})
		counted = fatigued(float(gains.earned), points_in)
		gains.earned = float(gains.earned) + points_in
		gains.points = float(gains.points) + counted
		raid_gains[id] = gains
	var entry: Dictionary = GameState.skills[id]
	var old := int(entry.get("level", 0))
	var current := old
	var have := float(entry.get("points", 0.0)) + counted
	while current < MAX_LEVEL and have >= points_to_next(current):
		have -= points_to_next(current)
		current += 1
	entry.level = current
	entry.points = have if current < MAX_LEVEL else 0.0
	if current > old:
		if in_raid:
			raid_gains[id].levels = int(raid_gains[id].levels) + current - old
		GameState.skill_levelled.emit(id, old, current)
	return current - old


## What `points_in` more are worth after `earned` points of the same skill this raid: in full up to
## "fresh", then each point fresh / earned of itself, at least "floor" (integrated over the step).
static func fatigued(earned: float, points_in: float) -> float:
	var rules: Dictionary = config().get("fatigue", {})
	var fresh := maxf(float(rules.get("fresh", 250.0)), 1.0)
	var floor_share := clampf(float(rules.get("floor", 0.1)), 0.0, 1.0)
	var counted := 0.0
	var at := earned
	var left := points_in
	if at < fresh:
		var full := minf(left, fresh - at)
		counted += full
		at += full
		left -= full
	if left <= 0.0:
		return counted
	var limit := fresh / maxf(floor_share, 0.0001)  # Past this, the floor.
	if at < limit:
		var part := minf(left, limit - at)
		counted += fresh * log((at + part) / at)
		at += part
		left -= part
	return counted + left * floor_share


## A raid starts: `counts` false for one that doesn't go to the profile (no skill gains then).
static func begin_raid(counts: bool) -> void:
	in_raid = true
	raid_counts = counts
	raid_gains = {}


## The raid is over: what each skill gained ({id: {"earned", "points", "levels"}}).
static func end_raid() -> Dictionary:
	in_raid = false
	raid_counts = true
	return raid_gains.duplicate(true)


# --- Bonuses --------------------------------------------------------------------------------------

## Bonus `name` of skill `id` at its level (from `skills`, GameState.skills by default): per_level ×
## level, up to its max. A share (0.06: 6%) or kilograms.
static func bonus(id: String, name: String, skills: Variant = null) -> float:
	var rules: Dictionary = find(id).get("bonuses", {}).get(name, {})
	if rules.is_empty():
		return 0.0
	return minf(float(rules.get("per_level", 0.0)) * level(id, skills), float(rules.get("max", 0.0)))


## The level at which `id`'s bonus `name` reaches its max.
static func cap_level(id: String, name: String) -> int:
	var rules: Dictionary = find(id).get("bonuses", {}).get(name, {})
	var per := float(rules.get("per_level", 0.0))
	return mini(ceili(float(rules.get("max", 0.0)) / per - 0.0001), MAX_LEVEL) if per > 0.0 else 0


## "6% less recoil" for one bonus at `skill_level` (the current level by default).
static func bonus_text(id: String, name: String, skill_level := -1) -> String:
	var rules: Dictionary = find(id).get("bonuses", {}).get(name, {})
	var at := level(id) if skill_level < 0 else skill_level
	var value := minf(float(rules.get("per_level", 0.0)) * at, float(rules.get("max", 0.0)))
	return str(rules.get("text", "%s")) % _value_text(value, str(rules.get("unit", "share")))


## Every bonus of `id` at `skill_level` (the current level by default), joined: "6% less recoil, ...".
static func bonuses_text(id: String, skill_level := -1) -> String:
	var parts: Array[String] = []
	for name: String in find(id).get("bonuses", {}):
		parts.append(bonus_text(id, name, skill_level))
	return ", ".join(parts)


static func _value_text(value: float, unit: String) -> String:
	var shown := snappedf(value if unit == "kg" else value * 100.0, 0.01)
	var number := str(roundi(shown)) if is_equal_approx(shown, roundf(shown)) else "%.1f" % shown if is_equal_approx(shown * 10.0, roundf(shown * 10.0)) else "%.2f" % shown
	return number + (" kg" if unit == "kg" else "%")


# --- DESIGN.md §12.3's table ------------------------------------------------------------------------

## How DESIGN.md's table names each action (`%s`: its points).
const ACTION_TEXT := {
	"carry_metre": "%s a metre moved with 10 kg or more, × the load / 25 kg (×2 over 25 kg)", "melee_hit": "%s a melee hit",
	"throw": "%s a throw", "sprint_metre": "%s a metre sprinted", "damage": "%s an HP of damage taken and survived",
	"treat": "%s a bleed or fracture treated", "energy_hydration": "%s a point of energy or hydration eaten or drunk",
	"inject": "%s a stim (Common to Legendary)", "item_found": "%s an item found searching a container or body",
	"covert_metre": "%s a metre crouched or walking within 25 m of an enemy that isn't fighting you",
	"craft": "%s a craft collected", "craft_minute": "%s more a minute of the craft's time", "hit": "%s a bullet hit", "kill": "%s more for a kill",
}


## DESIGN.md §12.3's skill table, worked out from skills.json (the weapon classes share one row):
## | Skill | Trained by (points) | Each level | Cap |.
static func design_table() -> String:
	var lines: Array[String] = ["| Skill | Trained by (points) | Each level | Cap |", "|---|---|---|---|"]
	var classes: Array[String] = []
	for skill in all():
		var id := str(skill.id)
		if bool(skill.get("weapon_class", false)):
			classes.append(str(skill.name))
			if classes.size() > 1:
				continue
		var actions: Array[String] = []
		for action: String in skill.actions:
			var value: Variant = skill.actions[action]
			var amount := "%s-%s" % [_number(value[0]), _number(value[-1])] if value is Array else _number(float(value))
			actions.append(str(ACTION_TEXT.get(action, "%s " + action)) % amount)
		if id in HideoutWork.GYM_SKILLS:
			actions.append("a Gym session (30-60)")
		var each: Array[String] = []
		var caps: Array[String] = []
		for name: String in skill.bonuses:
			each.append(bonus_text(id, name, 1))
			caps.append("%s at level %d" % [_value_text(float(skill.bonuses[name].max), str(skill.bonuses[name].get("unit", "share"))), cap_level(id, name)])
		lines.append("| %s | %s | %s | %s |" % ["WEAPON_CLASSES" if bool(skill.get("weapon_class", false)) else str(skill.name), "; ".join(actions), "; ".join(each), "; ".join(caps)])
	return "\n".join(lines).replace("WEAPON_CLASSES", "Weapon classes (%s)" % ", ".join(classes))


static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 3)


# --- Checks ---------------------------------------------------------------------------------------

## What's wrong with skills.json (empty if nothing): every skill needs an id, a name, what trains it,
## actions (numbers, or lists of numbers, 0 or more) and bonuses (per_level and max above 0, a unit of
## share or kg, a text with %s); the weapon class skills must be the ones the guns train.
static func problems() -> Array[String]:
	return problems_of(config())


## problems() for `data`, a skills.json's contents (tests check broken copies).
static func problems_of(data: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var list := _skill_list(data)
	var by_id := {}
	for skill in list:
		by_id[str(skill.get("id", ""))] = skill
	if int(data.get("max_level", 0)) != MAX_LEVEL:
		found.append("max_level must be %d" % MAX_LEVEL)
	var rules: Dictionary = data.get("points", {})
	if float(rules.get("base", 0.0)) <= 0.0 or float(rules.get("growth", -1.0)) < 0.0:
		found.append("points needs base above 0 and growth of 0 or more")
	var fatigue: Dictionary = data.get("fatigue", {})
	if float(fatigue.get("fresh", 0.0)) <= 0.0 or float(fatigue.get("floor", -1.0)) <= 0.0 or float(fatigue.get("floor", 2.0)) > 1.0:
		found.append("fatigue needs fresh above 0 and a floor above 0, at most 1")
	var seen := {}
	for skill in list:
		var id := str(skill.get("id", ""))
		if id == "" or seen.has(id):
			found.append("skill id '%s' is missing or used twice" % id)
		seen[id] = true
		if str(skill.get("name", "")) == "" or str(skill.get("trains", "")) == "":
			found.append("%s: needs a name and what trains it" % id)
		var actions: Variant = skill.get("actions", {})
		if not actions is Dictionary or actions.is_empty():
			found.append("%s: no actions" % id)
		else:
			for action: String in actions:
				var values: Array = actions[action] if actions[action] is Array else [actions[action]]
				if values.is_empty() or values.any(func(value: Variant) -> bool: return not (value is float or value is int) or float(value) < 0.0):
					found.append("%s: action %s needs points of 0 or more" % [id, action])
		var bonuses: Variant = skill.get("bonuses", {})
		if not bonuses is Dictionary or bonuses.is_empty():
			found.append("%s: no bonuses" % id)
			continue
		for name: String in bonuses:
			var entry: Variant = bonuses[name]
			if not entry is Dictionary or float(entry.get("per_level", 0.0)) <= 0.0 or float(entry.get("max", 0.0)) <= 0.0 \
					or not str(entry.get("unit", "share")) in ["share", "kg"] or not "%s" in str(entry.get("text", "")):
				found.append("%s: bonus %s needs per_level and max above 0, a unit of share or kg and a text with %%s" % [id, name])
			elif str(entry.get("unit", "share")) == "share" and float(entry.max) >= 1.0:
				found.append("%s: bonus %s caps at %s, a share under 1" % [id, name, entry.max])
	for id in ["strength", "endurance", "vitality", "metabolism", "stim_resistance", "search", "covert_movement", "crafting"]:
		if not seen.has(id):
			found.append("no %s skill" % id)
	for item: ItemData in ItemDB.all_items():  # Empty until the items load (ItemDB checks again then).
		if item.weapon and item.weapon.skill != "" and not (seen.has(item.weapon.skill) and bool(by_id[item.weapon.skill].get("weapon_class", false))):
			found.append("%s trains %s, not a weapon class skill" % [item.id, item.weapon.skill])
	return found
