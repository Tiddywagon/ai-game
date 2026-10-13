class_name BodyHealth
extends RefCounted
## Tarkov-style health (DESIGN.md §13.5): seven body parts with their own HP. Head or thorax at 0 is
## death. Any other part at 0 is "blacked": damage it takes from then on (and damage beyond its HP)
## is multiplied and shared by every part that still has HP. Hits can cause light or heavy bleeds and,
## on arms and legs, fractures; fractures and blacked parts cause pain. Every actor has one.
## Treatment (DESIGN.md §13.7, Consumables): bleeds stop, fractures set, parts heal and blacked parts
## come back through surgery (with less max HP). Timed effects from meds, stims and food (`effects`)
## numb pain, regenerate, stop bleed damage, change stamina, speed, recoil and sway, or poison. With
## `metabolism` set (the player in a raid), energy and hydration drain (by `exertion`, the map's
## climate and the Metabolism skill): low (hungry, thirsty) slows stamina recovery; at 0 Exhaustion or
## Dehydration drains HP from every body part, shakes the aim and blurs vision.
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

## Share of each part's max HP lost to surgery (DESIGN.md §13.7), 0 for none.
var max_hp_loss: Array[float] = []
## Timed effects from meds, stims, food and drink: {"kind", "value", "left" (seconds), "delay"
## (seconds before it starts), "side" (a drawback), "source" (item id, or Stims.OVERDOSE)}. The kinds
## are listed in data/config/stims.json (Stims.effect_kinds()).
var effects: Array[Dictionary] = []
## Seconds this body has been ticking (the stim log's clock), and when each stim was injected (for
## Overdose: Stims).
var clock := 0.0
var stim_log: Array[float] = []
## Energy and hydration tuning: set it (the player in a raid) and they drain in tick(). Null: they
## stay put and never matter (the AI).
var metabolism: ConsumablesConfig
var energy := 100.0
var hydration := 100.0
## Drain multiplier right now: the actor sets it from what it's doing (still, crouched, sprinting,
## rolling), its load and injuries.
var exertion := 1.0
## Drain multipliers from the map's climate (MapInfo: hot maps dry you out faster).
var energy_climate := 1.0
var hydration_climate := 1.0
## Drain multiplier from the Metabolism skill (1 = none).
var metabolism_skill := 1.0

## Cause of the hit that started each part's bleed, for "bled out" death messages.
var _bleed_causes: Array[Dictionary] = []

func _init(health_config: HealthConfig) -> void:
	config = health_config
	heal_all()


## Back to full health with no status effects or timed effects (and alive again). Energy and
## hydration stay as they are.
func heal_all() -> void:
	hp.clear()
	bleeds.clear()
	fractures.clear()
	_bleed_causes.clear()
	max_hp_loss.clear()
	effects.clear()
	stim_log.clear()
	for part in Part.size():
		hp.append(config.max_hp(part))
		bleeds.append(Bleed.NONE)
		fractures.append(false)
		_bleed_causes.append({})
		max_hp_loss.append(0.0)
	is_dead = false
	death_cause = {}
	changed.emit()


## Starts draining energy and hydration (tuned by `tuning`) from these values.
func start_metabolism(tuning: ConsumablesConfig, start_energy: float, start_hydration: float) -> void:
	metabolism = tuning
	energy = clampf(start_energy, 0.0, tuning.max_energy)
	hydration = clampf(start_hydration, 0.0, tuning.max_hydration)
	changed.emit()


# --- Damage -----------------------------------------------------------------------------------

## A bullet hit: damages `part`, then (if still alive) may start a bleed or, on a limb, a fracture.
## The round's own bleed chances come in `cause` ("light_bleed", "heavy_bleed"; ArmorRules.resolve()
## sets them: 0 for a round stopped by armor, a light bleed for one that fragmented); without them the
## chances in health.tres apply, scaled by damage.
func hit(part: int, damage: float, cause: Dictionary) -> void:
	if is_dead:
		return
	apply_damage(part, damage, cause)
	if is_dead:
		return
	var scale := clampf(damage / config.reference_damage, 0.0, 1.5)
	var heavy := float(cause.get("heavy_bleed", -1.0))
	var light := float(cause.get("light_bleed", -1.0))
	if heavy < 0.0:
		heavy = config.heavy_bleed_chance * scale
	if light < 0.0:
		light = config.light_bleed_chance * scale
	if not has_effect("bleed_prevention"):
		if bleeds[part] != Bleed.HEAVY and randf() < heavy:
			_start_bleed(part, Bleed.HEAVY, cause)
		elif bleeds[part] == Bleed.NONE and randf() < light:
			_start_bleed(part, Bleed.LIGHT, cause)
	if is_limb(part) and not fractures[part] and not has_effect("fracture_prevention") and randf() < config.fracture_chance * scale:
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


## Every physics tick: timed effects run down, regeneration heals, bleeds (unless a hemostatic is
## working), poison and, with `metabolism`, hunger and thirst.
func tick(delta: float) -> void:
	if is_dead:
		return
	clock += delta
	_tick_effects(delta)
	var regen := effect_total("regen")
	if regen > 0.0:
		_regenerate(regen * delta)
	var drain := effect_total("hp_drain")
	if drain > 0.0:
		_drain_every_part(drain * delta, "overdose")
		if is_dead:
			return
	if not has_effect("hemostatic"):
		for part in Part.size():
			match bleeds[part]:
				Bleed.LIGHT:
					_bleed_damage(part, config.light_bleed_rate * delta)
				Bleed.HEAVY:
					_bleed_damage(part, config.heavy_bleed_rate * delta)
			if is_dead:
				return
	var toxin := effect_total("toxin")
	if toxin > 0.0:
		apply_damage(Part.STOMACH, toxin * delta, {"kind": "toxin", "part": Part.STOMACH, "source": _effect_source("toxin")})
		if is_dead:
			return
	if metabolism:
		_tick_metabolism(delta)


func set_fracture(part: int, value: bool) -> void:
	if is_limb(part):
		fractures[part] = value
		changed.emit()


# --- Treatment (DESIGN.md §13.7) ----------------------------------------------------------------

## Stops the bleed on `part`.
func stop_bleed(part: int) -> void:
	bleeds[part] = Bleed.NONE
	_bleed_causes[part] = {}
	changed.emit()


## Heals `part` by up to `amount` (not past its max, and not a blacked part). Returns the HP healed.
func heal(part: int, amount: float) -> float:
	if is_dead or is_blacked(part) or amount <= 0.0:
		return 0.0
	var healed := minf(amount, max_hp(part) - hp[part])
	if healed <= 0.0:
		return 0.0
	hp[part] += healed
	changed.emit()
	return healed


## Surgery on a blacked part (not the head or thorax): it comes back at `restore` of its max HP, but
## first loses `loss` of the max HP it has left, for good (this raid). False if it isn't blacked.
func restore(part: int, restore_share: float, loss: float) -> bool:
	if is_dead or is_vital(part) or not is_blacked(part):
		return false
	max_hp_loss[part] = clampf(1.0 - (1.0 - max_hp_loss[part]) * (1.0 - loss), 0.0, 0.9)
	hp[part] = maxf(max_hp(part) * restore_share, 1.0)
	changed.emit()
	return true


## Starts a timed effect (kinds: Stims.effect_kinds()). One from the same `source` and of the same kind (and
## delay) is replaced, so taking the same stim again refreshes it instead of stacking.
func add_effect(kind: String, value: float, duration: float, delay := 0.0, side := false, source := "") -> void:
	for effect in effects:
		if effect.kind == kind and effect.source == source and source != "" and is_equal_approx(effect.delay_total, delay):
			effects.erase(effect)
			break
	var effect := {"kind": kind, "value": value, "left": duration, "delay": delay, "delay_total": delay, "side": side,
		"source": source, "duration": duration}
	effects.append(effect)
	if delay <= 0.0:
		_on_effect_started(effect)
	changed.emit()


## Adds up the values of the running (not delayed) effects of `kind`.
func effect_total(kind: String) -> float:
	var total := 0.0
	for effect in effects:
		if effect.kind == kind and effect.delay <= 0.0:
			total += float(effect.value)
	return total


## True while an effect of `kind` is running.
func has_effect(kind: String) -> bool:
	return effects.any(func(effect: Dictionary) -> bool: return effect.kind == kind and effect.delay <= 0.0)


## Changes energy and hydration by these amounts, within 0 and their max (no-op without `metabolism`).
func feed(energy_change: float, hydration_change: float) -> void:
	if metabolism == null:
		return
	energy = clampf(energy + energy_change, 0.0, metabolism.max_energy)
	hydration = clampf(hydration + hydration_change, 0.0, metabolism.max_hydration)
	changed.emit()


# --- Effects on the body ------------------------------------------------------------------------

## Extra max stamina from effects.
func stamina_bonus() -> float:
	return effect_total("stamina")


## How fast stamina recovers, ×: faster on stims, slower with Fatigue, when hungry and again when
## thirsty.
func stamina_regen_multiplier() -> float:
	var multiplier := maxf(1.0 + effect_total("stamina_regen"), 0.1) * maxf(1.0 - effect_total("fatigue"), 0.1)
	if is_hungry():
		multiplier *= metabolism.low_stamina_regen
	if is_thirsty():
		multiplier *= metabolism.low_stamina_regen
	return multiplier


## Move speed from effects, ×.
func speed_multiplier() -> float:
	return clampf(1.0 + effect_total("speed"), 0.3, 2.0)


## Recoil from effects, ×.
func recoil_multiplier() -> float:
	return clampf(1.0 + effect_total("recoil"), 0.3, 2.0)


## Sprinting's stamina cost, ×: more with Fatigue.
func sprint_cost_multiplier() -> float:
	return 1.0 + maxf(effect_total("fatigue"), 0.0)


## Extra kilograms you can carry before slowing down (and before being overweight).
func carry_bonus() -> float:
	return effect_total("carry_weight")


## Reload and jam-clearing speed, ×.
func reload_multiplier() -> float:
	return clampf(1.0 + effect_total("reload_speed"), 0.3, 3.0)


## Vision range, ×.
func vision_range_multiplier() -> float:
	return clampf(1.0 + effect_total("vision_range"), 0.3, 3.0)


## How far footsteps and rolls are heard, ×.
func noise_multiplier() -> float:
	return clampf(1.0 + effect_total("noise"), 0.1, 3.0)


## Blurred-vision effects, 0 to 1.
func blur_effect() -> float:
	return clampf(effect_total("blur"), 0.0, 1.0)


## True while an Overdose is running.
func has_overdose() -> bool:
	return effects.any(func(effect: Dictionary) -> bool: return effect.source == Stims.OVERDOSE and effect.delay <= 0.0)


## Weapon sway added by effects (tremor, or steadier hands below 0), Exhaustion and Dehydration,
## in degrees.
func extra_sway() -> float:
	var amount := effect_total("sway") + effect_total("tremor")
	if has_exhaustion():
		amount += metabolism.exhaustion_sway
	if has_dehydration():
		amount += metabolism.dehydration_sway
	return amount


## Vision cone ×: narrower with Exhaustion, again with Dehydration, and with blurred vision.
func vision_multiplier() -> float:
	var multiplier := 1.0 - 0.2 * blur_effect()
	if has_exhaustion():
		multiplier *= metabolism.depleted_vision
	if has_dehydration():
		multiplier *= metabolism.depleted_vision
	return multiplier


## How blurred the player's view is, 0 to 1: half for Exhaustion, half for Dehydration, plus blurred
## vision from stims and Overdose.
func blur_amount() -> float:
	return minf((0.5 if has_exhaustion() else 0.0) + (0.5 if has_dehydration() else 0.0) + blur_effect(), 1.0)


## Energy at or below the low threshold.
func is_hungry() -> bool:
	return metabolism != null and energy <= metabolism.low_threshold


## Hydration at or below the low threshold.
func is_thirsty() -> bool:
	return metabolism != null and hydration <= metabolism.low_threshold


## No energy left: Exhaustion.
func has_exhaustion() -> bool:
	return metabolism != null and energy <= 0.0


## No hydration left: Dehydration.
func has_dehydration() -> bool:
	return metabolism != null and hydration <= 0.0


## Bleeding, a fracture or a blacked part (energy and hydration drain faster).
func is_injured() -> bool:
	if is_bleeding() or fractures.has(true):
		return true
	for part in Part.size():
		if is_blacked(part) and not is_vital(part):
			return true
	return false


# --- Queries ----------------------------------------------------------------------------------

func total() -> float:
	var sum := 0.0
	for value in hp:
		sum += value
	return sum


## Max HP of all parts (less after surgery).
func max_total() -> float:
	var sum := 0.0
	for part in Part.size():
		sum += max_hp(part)
	return sum


## Max HP of `part`: its config value, less what surgery took.
func max_hp(part: int) -> float:
	return config.max_hp(part) * (1.0 - max_hp_loss[part])


func fraction(part: int) -> float:
	return hp[part] / max_hp(part)


## True if `part` is below its max HP and not blacked (a medkit can heal it).
func is_damaged(part: int) -> bool:
	return not is_blacked(part) and hp[part] < max_hp(part) - 0.01


func is_blacked(part: int) -> bool:
	return hp[part] <= 0.0


## A fractured or blacked arm or leg.
func is_injured_limb(part: int) -> bool:
	return is_limb(part) and (fractures[part] or is_blacked(part))


func injured_arms() -> int:
	return ARMS.filter(is_injured_limb).size()


func injured_legs() -> int:
	return LEGS.filter(is_injured_limb).size()


## Why the legs stop a roll or sprint: "leg fracture", "blacked leg", or "" if they're fine (or numbed
## by a painkiller: you're still slower).
func leg_problem() -> String:
	if has_effect("painkiller"):
		return ""
	for part in LEGS:
		if is_blacked(part):
			return "blacked leg"
	for part in LEGS:
		if fractures[part]:
			return "leg fracture"
	return ""


## Pain comes from fractures and blacked parts, unless a painkiller is working.
func has_pain() -> bool:
	return is_hurting() and not has_effect("painkiller")


## A fracture or blacked part hurts (numbed or not).
func is_hurting() -> bool:
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
	elif is_hurting():
		lines.append("Pain (numbed)")
	if has_overdose():
		lines.append("Overdose")
	if metabolism:
		if has_dehydration():
			lines.append("Dehydration")
		elif is_thirsty():
			lines.append("Thirsty")
		if has_exhaustion():
			lines.append("Exhaustion")
		elif is_hungry():
			lines.append("Hungry")
	return lines


## The running effects, one line per kind with the longest time left, e.g. "Painkiller 1:23",
## "Regeneration +1.0 HP/s 0:41"; `drawbacks` true lists the side effects (tremor, toxicity), false the
## benefits.
func effect_lines(drawbacks: bool) -> Array[String]:
	var by_kind := {}
	for effect in effects:
		if effect.delay > 0.0 or bool(effect.side) != drawbacks:
			continue
		var entry: Dictionary = by_kind.get(effect.kind, {"value": 0.0, "left": 0.0})
		entry.value += float(effect.value)
		entry.left = maxf(entry.left, float(effect.left))
		by_kind[effect.kind] = entry
	var lines: Array[String] = []
	for kind: String in by_kind:
		lines.append("%s %s" % [effect_label(kind, by_kind[kind].value), _clock(by_kind[kind].left)])
	return lines


## "Speed +8%", "Tremor +1.5°", "Energy -20/min", "Painkiller": an effect's name and value
## (Stims.effect_label()).
static func effect_label(kind: String, value: float) -> String:
	return Stims.effect_label(kind, value)


static func _clock(seconds: float) -> String:
	var whole := ceili(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


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

func _tick_effects(delta: float) -> void:
	var expired := false
	for effect in effects:
		if effect.delay > 0.0:
			effect.delay -= delta
			if effect.delay <= 0.0:
				expired = true  # Just started: redraw.
				_on_effect_started(effect)
			continue
		effect.left -= delta
		if effect.left <= 0.0:
			expired = true
	if expired:
		effects = effects.filter(func(effect: Dictionary) -> bool: return effect.left > 0.0)
		changed.emit()


## An effect's delay is over. Limb restoration acts once, now: every blacked part that isn't the head
## or thorax comes back at the effect's share of its max HP, losing some max HP (like surgery).
func _on_effect_started(effect: Dictionary) -> void:
	if effect.kind == "limb_restore":
		var loss := float(Stims.config().get("limb_restore_max_hp_loss", 0.3))
		for part in Part.size():
			if is_blacked(part) and not is_vital(part):
				restore(part, float(effect.value), loss)


## Heals every damaged part (not blacked ones) by `amount` HP.
func _regenerate(amount: float) -> void:
	var damaged: Array[int] = []
	for part in Part.size():
		if is_damaged(part):
			damaged.append(part)
	for part in damaged:
		hp[part] = minf(hp[part] + amount, max_hp(part))
	if not damaged.is_empty():
		changed.emit()


## Energy and hydration per minute right now (negative: draining), with every multiplier and effect.
func energy_rate() -> float:
	return effect_total("energy_rate") - metabolism.energy_drain * exertion * energy_climate * metabolism_skill if metabolism else 0.0


func hydration_rate() -> float:
	return effect_total("hydration_rate") - metabolism.hydration_drain * exertion * hydration_climate * metabolism_skill if metabolism else 0.0


func _tick_metabolism(delta: float) -> void:
	var minutes := delta / 60.0
	energy = clampf(energy + energy_rate() * minutes, 0.0, metabolism.max_energy)
	hydration = clampf(hydration + hydration_rate() * minutes, 0.0, metabolism.max_hydration)
	if energy <= 0.0:
		_drain_every_part(metabolism.exhaustion_damage * delta, "exhaustion")
	if hydration <= 0.0 and not is_dead:
		_drain_every_part(metabolism.dehydration_damage * delta, "dehydration")


## Exhaustion and Dehydration: `amount` HP off every part that still has HP (a vital one at 0 kills).
func _drain_every_part(amount: float, kind: String) -> void:
	for part in Part.size():
		if hp[part] > 0.0:
			apply_damage(part, amount, {"kind": kind, "part": part})
			if is_dead:
				return


## The item that started the running effect of `kind`, if any (for death messages).
func _effect_source(kind: String) -> String:
	for effect in effects:
		if effect.kind == kind and effect.delay <= 0.0:
			return str(effect.source)
	return ""

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
