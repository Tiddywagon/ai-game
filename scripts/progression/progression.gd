class_name Progression
extends RefCounted
## Player levels and the numbers behind trader loyalty (DESIGN.md §10, §15), from
## data/config/progression.json: the total experience each level 1-50 needs (GameState.add_xp() raises
## the level as experience crosses them, several at once if need be), what each loyalty level above 1
## needs with a trader (player level, reputation, roubles spent), how many roubles a dollar counts as
## toward money spent, and the reputation each barter adds (up to a cap per trader). Checked when it
## loads: problems().

const PATH := "res://data/config/progression.json"
const MAX_LEVEL := 50
## Reputation is kept to this step, so that 14 barters (0.01 each) and a 0.06 quest make 0.20, not
## 0.19999999999999998 (add_reputation()).
const REPUTATION_STEP := 0.001
## How far below a loyalty level's reputation still counts as having it (Trading.update_loyalty()).
const REPUTATION_EPSILON := 0.0001

## The file read (tests point it at a broken copy, then reload()).
static var path := PATH
static var _config := {}
static var _loaded := false


static func config() -> Dictionary:
	if not _loaded:
		_loaded = true  # Before problems(), which reads the config again.
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_config = parsed
			for problem in problems():
				push_warning("Progression: %s" % problem)
		else:
			push_error("Progression: %s isn't valid JSON" % path)
			_config = {"level_xp": [0], "loyalty": [], "dollar_rate": 1.0, "reputation": {}}
	return _config


## Reads the file again on next use.
static func reload() -> void:
	_config = {}
	_loaded = false


## `reputation` plus `gain`, kept to REPUTATION_STEP.
static func add_reputation(reputation: float, gain: float) -> float:
	return snappedf(reputation + gain, REPUTATION_STEP)


# --- Levels -------------------------------------------------------------------------------------

## The total experience each level needs, level 1 first (0).
static func level_xp() -> Array:
	return config().get("level_xp", [0])


## The highest level there is.
static func max_level() -> int:
	return maxi(level_xp().size(), 1)


## The total experience `level` needs (the top level's for anything above it).
static func xp_for_level(level: int) -> int:
	var table := level_xp()
	return int(table[clampi(level, 1, table.size()) - 1])


## The level `xp` experience reaches.
static func level_for_xp(xp: int) -> int:
	var table := level_xp()
	var level := 1
	while level < table.size() and xp >= int(table[level]):
		level += 1
	return level


## How far (0-1) `xp` is from `level`'s threshold to the next one's; 1 at the top level.
static func level_progress(xp: int, level: int) -> float:
	if level >= max_level():
		return 1.0
	var from := xp_for_level(level)
	var to := xp_for_level(level + 1)
	return clampf(float(xp - from) / float(maxi(to - from, 1)), 0.0, 1.0)


## "36,250 / 39,500 XP" (toward the next level), or "600,000 XP  ·  top level".
static func xp_text(xp: int, level: int) -> String:
	if level >= max_level():
		return "%s XP  ·  top level" % UiFormat.thousands(xp)
	return "%s / %s XP" % [UiFormat.thousands(xp), UiFormat.thousands(xp_for_level(level + 1))]


# --- Loyalty ------------------------------------------------------------------------------------

## What loyalty level `loyalty_level` needs: {"player_level", "reputation", "spent"} ({} for level 1
## or past the top).
static func loyalty_needs(loyalty_level: int) -> Dictionary:
	for entry: Dictionary in config().get("loyalty", []):
		if int(entry.get("level", 0)) == loyalty_level:
			return {"player_level": int(entry.player_level), "reputation": float(entry.reputation), "spent": int(entry.spent)}
	return {}


## The highest loyalty level any trader has.
static func max_loyalty() -> int:
	var top := 1
	for entry: Dictionary in config().get("loyalty", []):
		top = maxi(top, int(entry.get("level", 1)))
	return top


## Roubles one dollar counts as when a dollar purchase adds to money spent with a trader.
static func dollar_rate() -> float:
	return float(config().get("dollar_rate", 1.0))


## Reputation each barter with a trader adds.
static func barter_reputation() -> float:
	return float(config().get("reputation", {}).get("barter", 0.0))


## The most reputation barters can add with one trader.
static func barter_reputation_cap() -> float:
	return float(config().get("reputation", {}).get("barter_cap", 0.0))


## What's wrong with progression.json (empty if nothing).
static func problems() -> Array[String]:
	var found: Array[String] = []
	var table: Array = config().get("level_xp", [])
	if table.size() != MAX_LEVEL:
		found.append("level_xp has %d levels, not %d" % [table.size(), MAX_LEVEL])
	if not table.is_empty() and int(table[0]) != 0:
		found.append("level 1 must need 0 XP, not %s" % table[0])
	for i in range(1, table.size()):
		if int(table[i]) <= int(table[i - 1]):
			found.append("level %d needs %s XP, no more than level %d (%s)" % [i + 1, table[i], i, table[i - 1]])
	var loyalty: Array = config().get("loyalty", [])
	if loyalty.is_empty():
		found.append("no loyalty levels")
	var last := {"level": 1, "player_level": 1, "reputation": 0.0, "spent": 0}
	for entry: Dictionary in loyalty:
		for field in ["level", "player_level", "reputation", "spent"]:
			if not entry.has(field):
				found.append("loyalty entry %s: no %s" % [entry, field])
		if not entry.has_all(["level", "player_level", "reputation", "spent"]):
			continue
		if int(entry.level) != int(last.level) + 1:
			found.append("loyalty level %s follows %s" % [entry.level, last.level])
		if int(entry.player_level) < int(last.player_level) or float(entry.reputation) < float(last.reputation) or int(entry.spent) < int(last.spent):
			found.append("loyalty level %s needs less than level %s" % [entry.level, last.level])
		if int(entry.player_level) > table.size():
			found.append("loyalty level %s needs player level %s, past the top level" % [entry.level, entry.player_level])
		last = entry
	if float(config().get("dollar_rate", 0.0)) <= 0.0:
		found.append("dollar_rate must be above 0")
	var reputation: Dictionary = config().get("reputation", {})
	if float(reputation.get("barter", -1.0)) < 0.0 or float(reputation.get("barter_cap", -1.0)) < 0.0:
		found.append("reputation needs barter and barter_cap (0 or more)")
	return found
