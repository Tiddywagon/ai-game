class_name Consumables
extends RefCounted
## Meds, stims, food and drink (DESIGN.md §13.7): what using one does to a body (BodyHealth), and what
## the quick-treat key would use. Everything an item does is in its "stats":
##
## - "use_time": seconds it takes (in a raid; interrupted, it does nothing and isn't used up).
## - "uses": how many times it can be used (1 if left out), or "hp": a medkit's pool of HP. What's left
##   is ItemInstance.charges.
## - "treats": conditions it fixes on one body part a use: "light_bleed", "heavy_bleed", "fracture",
##   "blacked" (surgery: "restore" share of max HP back, "max_hp_loss" share of max HP gone for the
##   raid); "pain" is descriptive (painkillers work through their effect). A medkit pays "costs"
##   ({condition: HP}) from its pool for each condition, then heals the part's missing HP from what's left.
## - "effects": timed effects ({"kind", "value", "duration", "delay", "side"}, BodyHealth.EFFECT_KINDS).
## - "energy", "hydration": added at once (negative for side effects).
## - "move": walking speed while using it (else ConsumablesConfig.use_move_multiplier).
##
## A med picks its body part (or takes `part` if it can do something there): heavy bleeds first, then
## light bleeds, fractures, blacked parts and missing HP; legs before arms. Out of raid only food and
## drink can be used (on the profile's energy and hydration, which recover over real time, faster with
## the Nutrition Unit and Rest Space built). Eating and drinking train the Metabolism skill (Skills),
## which slows the drain.

const CONFIG: ConsumablesConfig = preload("res://data/config/consumables.tres")
## Conditions on a body part, in the order they're treated.
const PART_CONDITIONS: Array[String] = ["heavy_bleed", "light_bleed", "fracture", "blacked"]
const CONDITION_NAMES := {"heavy_bleed": "heavy bleed", "light_bleed": "light bleed", "fracture": "fracture",
	"blacked": "blacked part", "pain": "pain"}
## Where the quick-treat key looks for each problem, in order: [problem, item filter].
const QUICK_ORDER: Array[String] = ["heavy_bleed", "light_bleed", "fracture", "pain", "heal", "blacked", "hydration", "energy"]
const METABOLISM := "metabolism"

## In a raid, the body the inventory's effect previews compare against (the player's); null out of
## raid, where they use the profile's energy and hydration.
static var preview_health: BodyHealth


static func is_consumable(data: ItemData) -> bool:
	return data != null and data.category in [ItemData.Category.MEDS, ItemData.Category.FOOD]


static func is_medkit(data: ItemData) -> bool:
	return data.stats.has("hp")


## Seconds a use takes.
static func use_time(data: ItemData) -> float:
	return float(data.stats.get("use_time", 3.0))


## Uses (or a medkit's HP) a new one has.
static func max_charges(data: ItemData) -> float:
	return float(data.stats.get("hp", data.stats.get("uses", 1)))


static func treats(data: ItemData) -> Array:
	return data.stats.get("treats", [])


## What fixing `condition` costs a medkit's pool (0 for other items).
static func cost(data: ItemData, condition: String) -> float:
	return float(data.stats.get("costs", {}).get(condition, 0.0))


## Walking speed while using it, ×.
static func move_multiplier(data: ItemData) -> float:
	return float(data.stats.get("move", CONFIG.use_move_multiplier))


## True if it works on one body part (bleeds, fractures, surgery, healing) rather than the whole body.
static func works_on_parts(data: ItemData) -> bool:
	return is_medkit(data) or treats(data).any(func(condition: String) -> bool: return condition in PART_CONDITIONS)


## True if any of its effects is a drawback (or it costs energy or hydration).
static func has_drawbacks(data: ItemData) -> bool:
	if float(data.stats.get("energy", 0.0)) < 0.0 or float(data.stats.get("hydration", 0.0)) < 0.0:
		return true
	return data.stats.get("effects", []).any(func(effect: Dictionary) -> bool: return effect.get("side", false))


# --- Using one ---------------------------------------------------------------------------------

## What using `item` on `health` would do: {"ok": true, "part": body part or -1, "fix": [conditions],
## "heal": HP, "spent": charges} or {"ok": false, "reason": why not}. `part` >= 0 asks for that part
## (taken if the item can do something there).
static func plan(item: ItemInstance, health: BodyHealth, part := -1) -> Dictionary:
	if health == null or health.is_dead:
		return {"ok": false, "reason": "Dead"}
	var data := item.data
	if not is_consumable(data):
		return {"ok": false, "reason": "Can't be used"}
	if item.charges <= 0.0:
		return {"ok": false, "reason": "Used up"}
	if not works_on_parts(data):
		return {"ok": true, "part": -1, "fix": [], "heal": 0.0, "spent": 1.0}
	if part < 0 or _urgency(item, health, part) <= 0.0:
		part = best_part(item, health)
	if part < 0:
		return {"ok": false, "reason": _nothing_to_do(item)}
	return _treat(item, health, part, false)


## Why `item` can't be used on `health` now, or "".
static func block_reason(item: ItemInstance, health: BodyHealth) -> String:
	var result := plan(item, health)
	return "" if result.ok else str(result.reason)


## Uses `item` once on `health` (at `part` if it can do something there): fixes, heals, starts its
## effects, feeds, and takes a charge off (a medkit's HP spent). Returns the plan that ran, plus
## "text" (what happened) and "used_up". Doesn't remove a used-up item from where it is.
static func apply(item: ItemInstance, health: BodyHealth, part := -1) -> Dictionary:
	var result := plan(item, health, part)
	if not result.ok:
		return result
	if result.part >= 0:
		result = _treat(item, health, result.part, true)
	var data := item.data
	for effect: Dictionary in data.stats.get("effects", []):
		health.add_effect(str(effect.kind), float(effect.get("value", 0.0)), float(effect.get("duration", 0.0)),
			float(effect.get("delay", 0.0)), bool(effect.get("side", false)), data.id)
	health.feed(float(data.stats.get("energy", 0.0)), float(data.stats.get("hydration", 0.0)))
	item.charges = maxf(item.charges - float(result.spent), 0.0)
	result.used_up = item.charges < (1.0 if is_medkit(data) else 0.5)
	result.text = summary(item, result)
	result.levels = 0
	if health.metabolism and data.category == ItemData.Category.FOOD:
		result.levels = train_metabolism(data)
		health.metabolism_skill = skill_multiplier()
		if result.levels > 0:
			result.text += "  ·  Metabolism level %d" % Skills.level(METABOLISM)
	return result


## The body part `item` is most needed on, or -1.
static func best_part(item: ItemInstance, health: BodyHealth) -> int:
	var best := -1
	var best_score := 0.0
	for part in BodyHealth.Part.size():
		var score := _urgency(item, health, part)
		if score > best_score:
			best_score = score
			best = part
	return best


## What a finished use did, e.g. "Bandage: light bleed stopped (left arm)" or "Salewa: +62 HP (thorax)".
static func summary(item: ItemInstance, result: Dictionary) -> String:
	var data := item.data
	var parts: Array[String] = []
	for condition: String in result.get("fix", []):
		match condition:
			"heavy_bleed", "light_bleed":
				parts.append("%s stopped" % CONDITION_NAMES[condition])
			"fracture":
				parts.append("fracture set")
			"blacked":
				parts.append("surgery done")
	if float(result.get("heal", 0.0)) >= 0.5:
		parts.append("+%d HP" % roundi(result.heal))
	var where := " (%s)" % BodyHealth.PART_NAMES[result.part].to_lower() if int(result.get("part", -1)) >= 0 else ""
	for key in ["energy", "hydration"]:
		var amount := float(data.stats.get(key, 0.0))
		if amount != 0.0:
			parts.append("%+d %s" % [roundi(amount), key])
	for effect: Dictionary in data.stats.get("effects", []):
		if not effect.get("side", false) and float(effect.get("delay", 0.0)) <= 0.0:
			var label := BodyHealth.effect_label(str(effect.kind), float(effect.get("value", 0.0)))
			parts.append(label.left(1).to_lower() + label.substr(1))
	return "%s: %s%s" % [data.display_name, ", ".join(parts) if not parts.is_empty() else "done", where]


# --- Quick treatment (use_item, E) ---------------------------------------------------------------

## The items quick treatment can reach in `inventory`: in the pockets, rig and secure container (and
## the backpack if the config allows).
static func reachable(inventory: Inventory) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for grid in inventory.grids():
		if grid.kind == &"backpack" and not CONFIG.quick_use_backpack:
			continue
		for item in grid.items:
			if is_consumable(item.data) and not item.hidden:
				result.append(item)
	return result


## What quick treatment would use now: {"item", "part", "problem"}, or {"reason"} if nothing (no
## problem, or nothing in reach for it). Problems in order: heavy bleed, light bleed, fracture, pain,
## missing HP, blacked part, then thirst and hunger (below ConsumablesConfig.quick_eat_below). Among
## the items that fix a problem: dedicated ones before medkits, part-used first, then cheaper (food and
## drink: the most of what's needed). Stims, items with side effects and food that would make you
## thirsty (or drink that would make you hungry) are never picked: use them from the inventory.
static func quick_pick(inventory: Inventory, health: BodyHealth) -> Dictionary:
	if health == null or health.is_dead:
		return {"reason": "Dead"}
	var items := reachable(inventory)
	var missing: Array[String] = []
	for problem in QUICK_ORDER:
		if not has_problem(health, problem):
			continue
		var choice := _choose(items, health, problem)
		if not choice.is_empty():
			choice.problem = problem
			return choice
		missing.append(problem)
	if missing.is_empty():
		return {"reason": "Nothing to treat"}
	return {"reason": "Nothing in your pockets, rig or secure container for the %s" % problem_name(missing[0])}


## True if `health` has `problem` (a QUICK_ORDER entry).
static func has_problem(health: BodyHealth, problem: String) -> bool:
	match problem:
		"heavy_bleed":
			return health.bleeds.has(BodyHealth.Bleed.HEAVY)
		"light_bleed":
			return health.bleeds.has(BodyHealth.Bleed.LIGHT)
		"fracture":
			return health.fractures.has(true)
		"pain":
			return health.has_pain()
		"heal":
			for part in BodyHealth.Part.size():
				if health.is_damaged(part) and health.max_hp(part) - health.hp[part] >= 3.0:
					return true
			return false
		"blacked":
			for part in BodyHealth.Part.size():
				if health.is_blacked(part) and not BodyHealth.is_vital(part):
					return true
			return false
		"hydration":
			return health.metabolism != null and health.hydration <= health.metabolism.max_hydration * CONFIG.quick_eat_below
		"energy":
			return health.metabolism != null and health.energy <= health.metabolism.max_energy * CONFIG.quick_eat_below
	return false


static func problem_name(problem: String) -> String:
	match problem:
		"heal":
			return "lost HP"
		"hydration":
			return "thirst"
		"energy":
			return "hunger"
	return CONDITION_NAMES.get(problem, problem)


# --- Out of raid -------------------------------------------------------------------------------

## Out of raid, energy and hydration come back over real time: catches the profile up to now.
static func recover_profile(now := -1.0) -> void:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	if GameState.metabolism_time > 0.0 and now > GameState.metabolism_time:
		var gain := hideout_recovery_rate() * (now - GameState.metabolism_time) / 60.0
		GameState.energy = minf(GameState.energy + gain, CONFIG.max_energy)
		GameState.hydration = minf(GameState.hydration + gain, CONFIG.max_hydration)
	GameState.metabolism_time = now


## Why `item` can't be used out of raid now, or "".
static func profile_block_reason(item: ItemInstance) -> String:
	if not is_consumable(item.data):
		return "Can't be used"
	var energy := float(item.data.stats.get("energy", 0.0))
	var hydration := float(item.data.stats.get("hydration", 0.0))
	if item.data.category != ItemData.Category.FOOD or (energy <= 0.0 and hydration <= 0.0):
		return "Only in a raid"
	recover_profile()
	if (energy <= 0.0 or GameState.energy >= CONFIG.max_energy) and (hydration <= 0.0 or GameState.hydration >= CONFIG.max_hydration):
		return "Not hungry or thirsty"
	return ""


## Eats or drinks `item` out of raid: the profile's energy and hydration change, and it's used up
## (taken out of `holder`, the grid it's in). Returns what happened, or why it couldn't.
static func use_in_profile(item: ItemInstance, holder: InventoryGrid) -> Dictionary:
	var reason := profile_block_reason(item)
	if reason != "":
		return {"ok": false, "reason": reason}
	var energy := float(item.data.stats.get("energy", 0.0))
	var hydration := float(item.data.stats.get("hydration", 0.0))
	GameState.energy = clampf(GameState.energy + energy, 0.0, CONFIG.max_energy)
	GameState.hydration = clampf(GameState.hydration + hydration, 0.0, CONFIG.max_hydration)
	item.charges -= 1.0
	if item.charges < 0.5 and holder:
		holder.remove(item)
	var parts: Array[String] = []
	for change in [[energy, "energy"], [hydration, "hydration"]]:
		if change[0] != 0.0:
			parts.append("%+d %s" % [roundi(change[0]), change[1]])
	var levels := train_metabolism(item.data)
	if levels > 0:
		parts.append("Metabolism level %d" % Skills.level(METABOLISM))
	return {"ok": true, "text": "%s: %s" % [item.data.display_name, ", ".join(parts)], "levels": levels}


## Energy and hydration refill per real minute out of raid: the base rate, faster for each level of the
## Nutrition Unit and the Rest Space.
static func hideout_recovery_rate() -> float:
	var nutrition := int(GameState.hideout.get("nutrition_unit", 0))
	var rest := int(GameState.hideout.get("rest_space", 0))
	return CONFIG.hideout_recovery * (1.0 + nutrition * CONFIG.nutrition_unit_bonus + rest * CONFIG.rest_space_bonus)


# --- Metabolism skill and previews ---------------------------------------------------------------

## Drain × from the Metabolism skill: 1% less per level (by default), up to the config's cap.
static func skill_multiplier() -> float:
	return 1.0 - minf(Skills.level(METABOLISM) * CONFIG.drain_reduction_per_level, CONFIG.max_skill_reduction)


## Metabolism points one use of `data` is worth: its energy and hydration, either way.
static func metabolism_points(data: ItemData) -> float:
	return (absf(float(data.stats.get("energy", 0.0))) + absf(float(data.stats.get("hydration", 0.0)))) * CONFIG.metabolism_points_per_unit


## Eating or drinking `data` trains Metabolism. Returns the levels gained.
static func train_metabolism(data: ItemData) -> int:
	return Skills.add_points(METABOLISM, metabolism_points(data))


## What one use of food or drink `data` would do to energy and hydration now: [["Energy", now, after,
## change], ["Hydration", ...]] for each it changes (against the player in a raid, the profile out of
## raid).
static func preview(data: ItemData) -> Array:
	var rows := []
	var energy := preview_health.energy if preview_health else GameState.energy
	var hydration := preview_health.hydration if preview_health else GameState.hydration
	for entry in [["Energy", "energy", energy, CONFIG.max_energy], ["Hydration", "hydration", hydration, CONFIG.max_hydration]]:
		var change := float(data.stats.get(entry[1], 0.0))
		if change != 0.0:
			rows.append([entry[0], float(entry[2]), clampf(float(entry[2]) + change, 0.0, float(entry[3])), change])
	return rows


## preview() as text: "Energy 62 → 77 (+15)  ·  Hydration 40 → 35 (−5)".
static func preview_text(data: ItemData) -> String:
	return "  ·  ".join(preview(data).map(func(row: Array) -> String:
		return "%s %d → %d (%s)" % [row[0], ceili(snappedf(row[1], 0.1)), ceili(snappedf(row[2], 0.1)), ("%+d" % roundi(row[3])).replace("-", "−")]))


# --- Internals ---------------------------------------------------------------------------------

## How badly `part` needs `item` (0: it can't do anything there): heavy bleed 100, light bleed 80,
## fracture 60, blacked 50 (legs a little higher), else missing HP for a medkit (10-20).
static func _urgency(item: ItemInstance, health: BodyHealth, part: int) -> float:
	var data := item.data
	var pool := item.charges if is_medkit(data) else INF
	var conditions := treats(data)
	var leg_bonus := 5.0 if part in BodyHealth.LEGS else (3.0 if part == BodyHealth.Part.STOMACH else 0.0)
	if "heavy_bleed" in conditions and health.bleeds[part] == BodyHealth.Bleed.HEAVY and cost(data, "heavy_bleed") <= pool:
		return 100.0 + (1.0 - health.fraction(part))
	if "light_bleed" in conditions and health.bleeds[part] == BodyHealth.Bleed.LIGHT and cost(data, "light_bleed") <= pool:
		return 80.0 + (1.0 - health.fraction(part))
	if "fracture" in conditions and health.fractures[part] and cost(data, "fracture") <= pool:
		return 60.0 + leg_bonus
	if "blacked" in conditions and health.is_blacked(part) and not BodyHealth.is_vital(part):
		return 50.0 + leg_bonus
	if is_medkit(data) and health.is_damaged(part):
		return 10.0 + 10.0 * (1.0 - health.fraction(part))
	return 0.0


## Works out (and with `apply`, does) what `item` does to `part`: a bandage, tourniquet, hemostat or
## splint fixes its first condition there; surgery restores it; a medkit pays for every condition it
## can and heals the rest of the part's missing HP from its pool.
static func _treat(item: ItemInstance, health: BodyHealth, part: int, apply_it: bool) -> Dictionary:
	var data := item.data
	var medkit := is_medkit(data)
	var pool := item.charges if medkit else INF
	var spent := 0.0
	var fixed: Array[String] = []
	for condition in PART_CONDITIONS:
		if not condition in treats(data) or not _has(health, part, condition):
			continue
		var price := cost(data, condition)
		if medkit and price > pool - spent:
			continue
		if apply_it:
			_fix(health, part, condition, data)
		spent += price
		fixed.append(condition)
		if not medkit:
			break
	var healed := 0.0
	if medkit:
		healed = minf(pool - spent, health.max_hp(part) - health.hp[part]) if health.is_damaged(part) else 0.0
		healed = maxf(healed, 0.0)
		if apply_it:
			healed = health.heal(part, healed)
		spent += healed
	else:
		spent = 1.0
	if fixed.is_empty() and healed <= 0.0:
		return {"ok": false, "reason": _nothing_to_do(item)}
	return {"ok": true, "part": part, "fix": fixed, "heal": healed, "spent": spent}


static func _has(health: BodyHealth, part: int, condition: String) -> bool:
	match condition:
		"heavy_bleed":
			return health.bleeds[part] == BodyHealth.Bleed.HEAVY
		"light_bleed":
			return health.bleeds[part] == BodyHealth.Bleed.LIGHT
		"fracture":
			return health.fractures[part]
		"blacked":
			return health.is_blacked(part) and not BodyHealth.is_vital(part)
	return false


static func _fix(health: BodyHealth, part: int, condition: String, data: ItemData) -> void:
	match condition:
		"heavy_bleed", "light_bleed":
			health.stop_bleed(part)
		"fracture":
			health.set_fracture(part, false)
		"blacked":
			health.restore(part, float(data.stats.get("restore", 0.3)), float(data.stats.get("max_hp_loss", 0.3)))


static func _nothing_to_do(item: ItemInstance) -> String:
	var data := item.data
	if is_medkit(data):
		var treatable := treats(data).map(func(condition: String) -> String: return CONDITION_NAMES[condition])
		return "Nothing to heal" + (" or treat (%s)" % ", ".join(treatable) if not treatable.is_empty() else "")
	var names := treats(data).filter(func(condition: String) -> bool: return condition in PART_CONDITIONS) \
		.map(func(condition: String) -> String: return CONDITION_NAMES[condition])
	return "No %s to treat" % " or ".join(names)


## Food or drink quick treatment may pick: no side effects (no alcohol), and whatever it costs of the
## other stat doesn't take that one down to low.
static func _safe_to_eat(data: ItemData, health: BodyHealth) -> bool:
	if data.stats.get("effects", []).any(func(effect: Dictionary) -> bool: return effect.get("side", false)):
		return false
	var low := (health.metabolism if health.metabolism else CONFIG).low_threshold
	for entry in [[health.energy, "energy"], [health.hydration, "hydration"]]:
		var change := float(data.stats.get(entry[1], 0.0))
		if change < 0.0 and float(entry[0]) + change <= low:
			return false
	return true


## The best reachable item for `problem`: {"item", "part"} or {}.
static func _choose(items: Array[ItemInstance], health: BodyHealth, problem: String) -> Dictionary:
	var candidates: Array[ItemInstance] = []
	for item in items:
		var data := item.data
		if data.stats.get("type", "") == "stim" or has_drawbacks(data) and not problem in ["pain", "energy", "hydration"]:
			continue
		var fits := false
		match problem:
			"heavy_bleed", "light_bleed", "fracture", "blacked":
				var part := best_part(item, health)
				fits = part >= 0 and _has(health, part, problem) and _urgency(item, health, part) > 0.0
			"pain":
				fits = str(data.stats.get("type", "")) == "painkiller"
			"heal":
				fits = is_medkit(data) and best_part(item, health) >= 0
			"hydration":
				fits = float(data.stats.get("hydration", 0.0)) > 0.0 and _safe_to_eat(data, health)
			"energy":
				fits = float(data.stats.get("energy", 0.0)) > 0.0 and _safe_to_eat(data, health)
		if fits:
			candidates.append(item)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool:
		var a_kit := is_medkit(a.data)
		var b_kit := is_medkit(b.data)
		if a_kit != b_kit:
			return not a_kit  # A dedicated item before a medkit's pool.
		var a_part_used := a.charges < max_charges(a.data)
		var b_part_used := b.charges < max_charges(b.data)
		if a_part_used != b_part_used:
			return a_part_used  # Finish what's open.
		if problem in ["energy", "hydration"]:
			return float(a.data.stats.get(problem, 0.0)) > float(b.data.stats.get(problem, 0.0))  # The most of what's needed.
		return a.data.base_value < b.data.base_value)
	var item := candidates[0]
	var part := best_part(item, health) if works_on_parts(item.data) else -1
	if problem in PART_CONDITIONS:
		# Make sure it goes on a part that has this problem.
		for each in BodyHealth.Part.size():
			if _has(health, each, problem) and _urgency(item, health, each) >= 50.0:
				if part < 0 or not _has(health, part, problem) or _urgency(item, health, each) > _urgency(item, health, part):
					part = each
	return {"item": item, "part": part}
