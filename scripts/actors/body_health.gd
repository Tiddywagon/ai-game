class_name BodyHealth
extends RefCounted
## Tarkov-style health (DESIGN.md §13.5): seven body parts with their own HP. Head or thorax at 0 is
## death. Any other part at 0 is "blacked": damage it takes from then on (and damage beyond its HP)
## is multiplied and shared by every part that still has HP. Hits can cause light or heavy bleeds and,
## on arms and legs, fractures; fractures and blacked parts cause pain. Every actor has one.
##
## Causes are Dictionaries describing what did the damage, e.g. {"kind": "shot", "attacker": "Scav",
## "weapon": "AK-74N", "ammo": "5.45x39 PS", "part": Part.LEFT_ARM, "damage": 50.0, "distance": 12.0}.
## When the actor dies, `death_cause` is the cause of the killing damage plus "fatal_part".

## Something changed: HP, a status, or death.
signal changed
signal died

## Saved as numbers nowhere yet, but keep the order: arrays below are indexed by it.
enum Part { HEAD, THORAX, STOMACH, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }
enum Bleed { NONE, LIGHT, HEAVY }

const PART_NAMES: Array[String] = ["Head", "Thorax", "Stomach", "Left arm", "Right arm", "Left leg", "Right leg"]
const ARMS: Array[Part] = [Part.LEFT_ARM, Part.RIGHT_ARM]
const LEGS: Array[Part] = [Part.LEFT_LEG, Part.RIGHT_LEG]

var config: HealthConfig
var hp: Array[float] = []
var bleeds: Array[Bleed] = []
var fractures: Array[bool] = []
var is_dead := false
## What killed the actor (see above); empty while alive.
var death_cause := {}

## Cause of the hit that started each part's bleed, for "bled out" death messages.
var _bleed_causes: Array[Dictionary] = []


func _init(health_config: HealthConfig) -> void:
	config = health_config
	heal_all()


## Back to full health with no status effects (and alive again).
func heal_all() -> void:
	hp.clear()
	bleeds.clear()
	fractures.clear()
	_bleed_causes.clear()
	for part in Part.size():
		hp.append(config.max_hp(part))
		bleeds.append(Bleed.NONE)
		fractures.append(false)
		_bleed_causes.append({})
	is_dead = false
	death_cause = {}
	changed.emit()


# --- Damage -----------------------------------------------------------------------------------

## A bullet hit: damages `part`, then (if still alive) may start a bleed or, on a limb, a fracture.
func hit(part: int, damage: float, cause: Dictionary) -> void:
	if is_dead:
		return
	apply_damage(part, damage, cause)
	if is_dead:
		return
	var scale := clampf(damage / config.reference_damage, 0.0, 1.5)
	if bleeds[part] != Bleed.HEAVY and randf() < config.heavy_bleed_chance * scale:
		_start_bleed(part, Bleed.HEAVY, cause)
	elif bleeds[part] == Bleed.NONE and randf() < config.light_bleed_chance * scale:
		_start_bleed(part, Bleed.LIGHT, cause)
	if is_limb(part) and not fractures[part] and randf() < config.fracture_chance * scale:
		fractures[part] = true
	changed.emit()


## Takes `amount` HP from `part`. Whatever the part can't absorb (all of it once blacked) spreads.
func apply_damage(part: int, amount: float, cause: Dictionary) -> void:
	if is_dead or amount <= 0.0:
		return
	var taken := minf(hp[part], amount)
	hp[part] -= taken
	if hp[part] <= 0.0 and is_vital(part):
		_die(part, cause)
		return
	var excess := amount - taken
	if excess > 0.0:
		_spread(excess * spread_multiplier(part), cause)
	changed.emit()


## Bleeding, every physics tick.
func tick(delta: float) -> void:
	if is_dead:
		return
	for part in Part.size():
		match bleeds[part]:
			Bleed.LIGHT:
				_bleed_damage(part, config.light_bleed_rate * delta)
			Bleed.HEAVY:
				_bleed_damage(part, config.heavy_bleed_rate * delta)
		if is_dead:
			return


func set_fracture(part: int, value: bool) -> void:
	if is_limb(part):
		fractures[part] = value
		changed.emit()


# --- Queries ----------------------------------------------------------------------------------

func total() -> float:
	var sum := 0.0
	for value in hp:
		sum += value
	return sum


func max_total() -> float:
	return config.max_total()


func fraction(part: int) -> float:
	return hp[part] / config.max_hp(part)


func is_blacked(part: int) -> bool:
	return hp[part] <= 0.0


## A fractured or blacked arm or leg.
func is_injured_limb(part: int) -> bool:
	return is_limb(part) and (fractures[part] or is_blacked(part))


func injured_arms() -> int:
	return ARMS.filter(is_injured_limb).size()


func injured_legs() -> int:
	return LEGS.filter(is_injured_limb).size()


## Why the legs stop a roll or sprint: "leg fracture", "blacked leg", or "" if they're fine.
func leg_problem() -> String:
	for part in LEGS:
		if is_blacked(part):
			return "blacked leg"
	for part in LEGS:
		if fractures[part]:
			return "leg fracture"
	return ""


## Pain comes from fractures and blacked parts.
func has_pain() -> bool:
	for part in Part.size():
		if fractures[part] or is_blacked(part):
			return true
	return false


func is_bleeding() -> bool:
	return bleeds.any(func(bleed: Bleed) -> bool: return bleed != Bleed.NONE)


## Every active status as short text, worst first, e.g. ["Heavy bleed: left leg", "Pain"].
func status_lines() -> Array[String]:
	var lines: Array[String] = []
	for part in Part.size():
		if bleeds[part] == Bleed.HEAVY:
			lines.append("Heavy bleed: %s" % PART_NAMES[part].to_lower())
	for part in Part.size():
		if bleeds[part] == Bleed.LIGHT:
			lines.append("Light bleed: %s" % PART_NAMES[part].to_lower())
	for part in Part.size():
		if is_blacked(part) and not is_vital(part):
			lines.append("Blacked: %s" % PART_NAMES[part].to_lower())
	for part in Part.size():
		if fractures[part]:
			lines.append("Fracture: %s" % PART_NAMES[part].to_lower())
	if has_pain():
		lines.append("Pain")
	return lines


func spread_multiplier(part: int) -> float:
	match part:
		Part.STOMACH:
			return config.stomach_spread
		Part.LEFT_ARM, Part.RIGHT_ARM:
			return config.arm_spread
		Part.LEFT_LEG, Part.RIGHT_LEG:
			return config.leg_spread
	return 0.0


static func is_vital(part: int) -> bool:
	return part == Part.HEAD or part == Part.THORAX


static func is_limb(part: int) -> bool:
	return part in ARMS or part in LEGS


# --- Internals --------------------------------------------------------------------------------

## Shares `amount` evenly between every part that still has HP.
func _spread(amount: float, cause: Dictionary) -> void:
	var alive_parts: Array[int] = []
	for part in Part.size():
		if hp[part] > 0.0:
			alive_parts.append(part)
	if alive_parts.is_empty():
		return
	var share := amount / alive_parts.size()
	for part in alive_parts:
		hp[part] = maxf(hp[part] - share, 0.0)
	for part in [Part.HEAD, Part.THORAX]:
		if hp[part] <= 0.0:
			_die(part, cause)
			return


func _bleed_damage(part: int, amount: float) -> void:
	var cause := {"kind": "bleed", "bleed": bleeds[part], "part": part, "source": _bleed_causes[part]}
	apply_damage(part, amount, cause)


func _start_bleed(part: int, bleed: Bleed, cause: Dictionary) -> void:
	bleeds[part] = bleed
	_bleed_causes[part] = cause


func _die(fatal_part: int, cause: Dictionary) -> void:
	is_dead = true
	death_cause = cause.duplicate()
	death_cause["fatal_part"] = fatal_part
	changed.emit()
	died.emit()
