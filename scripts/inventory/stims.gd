class_name Stims
extends RefCounted
## Stimulants (DESIGN.md §13.8): single-use 1×1 injectors. Each has buffs that start after a short
## delay (0-5 s, "delay" in its stats), and side effects that run during the buffs or after them; every
## effect is a timed BodyHealth effect from data/items/meds/stims.json. Stims stack (taking the same one
## again refreshes it), but `threshold` or more injections within the overdose window start an
## Overdose: HP drain from every body part, tremor and blurred vision. The Stim resistance skill
## (trained by injecting stims) shortens side effects. Effect names, units, overdose and resistance
## tuning live in data/config/stims.json.

const CONFIG_PATH := "res://data/config/stims.json"
## The source id of Overdose effects.
const OVERDOSE := "overdose"
const RESISTANCE := "stim_resistance"

static var _config := {}


static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {}
		if _config.is_empty():
			push_error("Stims: %s isn't valid JSON" % CONFIG_PATH)
	return _config


static func is_stim(data: ItemData) -> bool:
	return data != null and data.category == ItemData.Category.MEDS and str(data.stats.get("type", "")) == "stim"


## Seconds between the injection and the buffs starting.
static func buff_delay(data: ItemData) -> float:
	return float(data.stats.get("delay", 0.0))


## The longest buff of stim `data`, in seconds.
static func buff_duration(data: ItemData) -> float:
	var longest := 0.0
	for effect: Dictionary in data.stats.get("effects", []):
		if not effect.get("side", false):
			longest = maxf(longest, float(effect.get("duration", 0.0)))
	return longest


# --- Effect kinds --------------------------------------------------------------------------------

## Every effect kind: {"name", "unit", "about"} from the config.
static func effect_kinds() -> Dictionary:
	return config().get("effects", {})


static func effect_name(kind: String) -> String:
	return str(effect_kinds().get(kind, {}).get("name", kind.capitalize()))


## "Speed +8%", "Tremor +1.5°", "Carry weight +15 kg", "Energy -20/min", "Painkiller": an effect's name
## and value (the sign says which way it goes).
static func effect_label(kind: String, value: float) -> String:
	var name := effect_name(kind)
	match str(effect_kinds().get(kind, {}).get("unit", "")):
		"":
			return name
		"%":
			return "%s %+d%%" % [name, roundi(value * 100.0)]
		"°":
			return "%s %+.1f°" % [name, value]
		"#":
			return "%s %+d" % [name, roundi(value)]
		"kg":
			return "%s %+d kg" % [name, roundi(value)]
		"/min":
			return "%s %+d/min" % [name, roundi(value)]
		var unit:
			return "%s %+.1f %s" % [name, value, unit] if absf(value) < 10.0 else "%s %+d %s" % [name, roundi(value), unit]


static func color(phase: String) -> Color:
	return Color.html(str(config().get("colors", {}).get(phase, "#ffffff")))


# --- Injecting -----------------------------------------------------------------------------------

## Side effects last this share of their time: shorter with the Stim resistance skill.
static func side_effect_multiplier() -> float:
	var tuning: Dictionary = config().get("resistance", {})
	return 1.0 - minf(Skills.level(RESISTANCE) * float(tuning.get("per_level", 0.01)), float(tuning.get("max", 0.3)))


## Injects stim `data` into `health`: its buffs and side effects start (side effects shortened by
## Stim resistance when it's the player: a body with `metabolism`), the injection is logged, and
## reaching the overdose threshold starts an Overdose. Returns {"overdose": bool, "count": stims in
## the window, "levels": Stim resistance levels gained}.
static func inject(data: ItemData, health: BodyHealth) -> Dictionary:
	var player := health.metabolism != null
	var shorten := side_effect_multiplier() if player else 1.0
	for effect: Dictionary in data.stats.get("effects", []):
		var side := bool(effect.get("side", false))
		health.add_effect(str(effect.kind), float(effect.get("value", 0.0)), float(effect.get("duration", 0.0)) * (shorten if side else 1.0),
			float(effect.get("delay", 0.0)), side, data.id)
	var overdose: Dictionary = config().get("overdose", {})
	var window := float(overdose.get("window", 300.0))
	health.stim_log = health.stim_log.filter(func(at: float) -> bool: return health.clock - at < window)
	health.stim_log.append(health.clock)
	var result := {"overdose": false, "count": health.stim_log.size(), "levels": 0}
	var threshold := int(overdose.get("threshold", 3))
	if health.stim_log.size() >= threshold:
		start_overdose(health, health.stim_log.size() - threshold)
		result.overdose = true
	if player:
		var points: Array = config().get("resistance", {}).get("points_by_rarity", [20])
		result.levels = Skills.add_points(RESISTANCE, float(points[clampi(data.rarity, 0, points.size() - 1)]))
	return result


## Starts (or restarts, worse) an Overdose: `extra` stims past the threshold make it that much worse.
static func start_overdose(health: BodyHealth, extra: int) -> void:
	var tuning: Dictionary = config().get("overdose", {})
	var severity := 1.0 + extra * float(tuning.get("extra_per_stim", 0.5))
	var seconds := float(tuning.get("duration", 90.0))
	health.add_effect("hp_drain", float(tuning.get("hp_drain", 0.1)) * severity, seconds, 0.0, true, OVERDOSE)
	health.add_effect("tremor", float(tuning.get("tremor", 2.0)) * severity, seconds, 0.0, true, OVERDOSE)
	health.add_effect("blur", minf(float(tuning.get("blur", 0.5)) * severity, 1.0), seconds, 0.0, true, OVERDOSE)


## Stims injected within the overdose window, so far.
static func recent_count(health: BodyHealth) -> int:
	var window := float(config().get("overdose", {}).get("window", 300.0))
	return health.stim_log.filter(func(at: float) -> bool: return health.clock - at < window).size()


static func overdose_threshold() -> int:
	return int(config().get("overdose", {}).get("threshold", 3))


## The stims working on `health`, for the HUD: [{"source": stim id or OVERDOSE, "phase": "pending"
## (waiting for its delay), "buff" (buffs running) or "side" (only side effects left), or "overdose",
## "left": seconds until that phase ends}], in the order they were taken, Overdose last.
static func active(health: BodyHealth) -> Array:
	var by_source := {}
	for effect in health.effects:
		var source := str(effect.source)
		if source == OVERDOSE or is_stim(ItemDB.get_item(source)):
			if not by_source.has(source):
				by_source[source] = []
			by_source[source].append(effect)
	var result := []
	for source: String in by_source:
		var effects: Array = by_source[source]
		if source == OVERDOSE:
			continue
		var running_buff := 0.0
		var pending := INF
		var side_end := 0.0
		for effect: Dictionary in effects:
			if effect.side:
				side_end = maxf(side_end, maxf(float(effect.delay), 0.0) + float(effect.left))
			elif effect.delay > 0.0:
				pending = minf(pending, float(effect.delay))
			else:
				running_buff = maxf(running_buff, float(effect.left))
		if running_buff > 0.0:
			result.append({"source": source, "phase": "buff", "left": running_buff})
		elif pending < INF:
			result.append({"source": source, "phase": "pending", "left": pending})
		else:
			result.append({"source": source, "phase": "side", "left": side_end})
	if by_source.has(OVERDOSE):
		var left := 0.0
		for effect: Dictionary in by_source[OVERDOSE]:
			left = maxf(left, float(effect.left))
		result.append({"source": OVERDOSE, "phase": "overdose", "left": left})
	return result
