class_name ScavRuns
extends RefCounted
## Scav runs (DESIGN.md §2, §4.1, §5.1, §10, §16.3), from data/config/scav_runs.json (checked when it
## loads: problems(); a value of the wrong type is read as missing):
## - The mid-raid start: a Scav run joins a raid already under way, at a random share of the raid time
##   (start_window(), roll_offset(): GameState.raid "offset", which RaidSetup rolls), with at least
##   min_left_seconds on the clock. RaidController and RaidEvents fast-forward what happened before you
##   came (loot_taken(), pmc_death_chance(), squad_spacing(), pick_over()); a Run Through counts from
##   when you came, against a shorter time on a late join (run_through_seconds()).
## - The cooldown: 20 real minutes from deploying as a Scav (deploy()) until the next Scav run, times the
##   hideout's Intelligence Center multiplier (Hideout.scav_cooldown_multiplier()) and the kit tier's
##   cooldown, saved as a unix "ready at" (GameState.scav_ready_at; seconds_left(), ready_text()). The
##   Scav kit is rolled once per cooldown cycle (kit(), saved as GameState.scav_kit until you deploy).
## - Karma: Mole's standing (GameState.scav_karma, -6 to +6 from 0). A Scav raid's changes (killing a
##   friendly AI Scav, a guard or a boss: one that hadn't attacked you and wasn't hostile to you for your
##   karma alone when you first attacked it; killing PMCs; a bot dying of wounds you gave it counts as
##   your kill; extracting with others; extracting) are counted by RaidController and applied when the
##   raid settles (apply(); changes_text() for the summary).
##   Effects: below hostile_below AI Scavs are hostile to your Scav on sight and react sooner the lower it
##   is (hostile(), reaction_multiplier()); the kit tier follows it (kit_tier(): worse at -2 and -4,
##   better at +2, +4 and +6, the top two with a shorter cooldown); Mole's loyalty level, sell rate and
##   worn gear follow it (TraderTable.karma_levels(), Selling.rate(), TraderStock).

const PATH := "res://data/config/scav_runs.json"
const KIT_PATH := "res://data/bots/scav_kit.tres"
const KARMA_FIELDS := ["friendly_kill", "guard_kill", "boss_kill", "pmc_kill", "extract_with_others", "extract",
	"with_others_radius", "with_others_seconds", "hostile_below"]
## Kit tier overrides BotKit.with_tier() takes.
const TIER_OVERRIDES := ["rarity", "ammo_rarity", "armor_chance", "helmet_chance", "backpack_chance", "melee_chance",
	"bandage_chance", "medkit_chance", "medkit_rarity", "gun_durability", "pocket_items", "armored_rigs", "pistol_chance", "stim_chance", "gun_mods"]
## A raid's karma changes by reason, in the order the summary lists them: [one, several ("%d")].
const REASONS := {
	"friendly_kill": ["Killed a friendly Scav", "Killed %d friendly Scavs"],
	"guard_kill": ["Killed a friendly guard", "Killed %d friendly guards"],
	"boss_kill": ["Killed a friendly boss", "Killed %d friendly bosses"],
	"pmc_kill": ["Killed a PMC", "Killed %d PMCs"],
	"extract_with_others": ["Extracted with a Scav", "Extracted with a Scav"],
	"extract": ["Extracted", "Extracted"],
}
const MINUS := "−"
const FALLBACK_WINDOW := Vector2(0.2, 0.65)
const FALLBACK_COOLDOWN_MINUTES := 20.0
## The most a karma-hostile Scav's reaction time may be multiplied by: much slower and one that sees you
## for a second or so ducks into cover before it fires.
const MAX_REACTION := 2.0

## The file data() loads (tests point it at a broken copy), and what was wrong with it when it last
## loaded (each one also an error).
static var path := PATH
static var load_problems: Array[String] = []
## Unix time to use instead of the clock (tests); -1: the real clock.
static var now_override := -1.0
static var _data := {}
static var _loaded := false
## The Scav kit dressed for each kit tier, by tier id (BotKit.with_tier()).
static var _tier_kits := {}


## The whole file, checked the first time it loads. Missing or not valid JSON: {} (every value then
## falls back to its default).
static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_data = parsed if parsed is Dictionary else {}
		if parsed is Dictionary:
			load_problems = problems()
		else:
			load_problems.assign(["%s isn't valid JSON" % path])
		for problem in load_problems:
			push_error("ScavRuns: %s" % problem)
	return _data


## Forgets what was loaded (tests that point `path` elsewhere).
static func reload() -> void:
	_data = {}
	_loaded = false
	_tier_kits.clear()
	load_problems.clear()


static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


static func _is_number(value: Variant) -> bool:
	return PmcAi.is_number(value)


static func _section(key: String) -> Dictionary:
	return PmcAi.dict(data().get(key))


# --- The mid-raid start ---------------------------------------------------------------------------

## The share of the raid (from, to) a Scav run on `map_id` joins at.
static func start_window(map_id: String) -> Vector2:
	var start := _section("start")
	var pair := PmcAi.pair(PmcAi.dict(start.get("maps")).get(map_id), PmcAi.pair(start.get("window"), [FALLBACK_WINDOW.x, FALLBACK_WINDOW.y]))
	return Vector2(float(pair[0]), float(pair[1]))


## Seconds left on the clock a Scav run never joins with less than.
static func min_left_seconds() -> float:
	return PmcAi.number(_section("start"), "min_left_seconds", 300.0)


## When a Scav run on `map` joins its raid: seconds into it, in the map's start window and leaving at
## least min_left_seconds(), rolled with `rng`, to the second.
static func roll_offset(map: MapInfo, rng: RandomNumberGenerator) -> float:
	var length := (map.raid_minutes if map else 15) * 60.0
	var window := start_window(str(map.id) if map else "")
	var latest := maxf(minf(window.y * length, length - min_left_seconds()), 0.0)
	var earliest := minf(window.x * length, latest)
	return snappedf(rng.randf_range(earliest, latest), 1.0)


## The Run Through time for a Scav run that joined with `left_at_join` seconds on the clock: `full`
## (RaidConfig.run_through_seconds, 7 minutes), or run_through_share of the time that was left, whichever
## is shorter, so a late join can still extract as SURVIVED.
static func run_through_seconds(full: float, left_at_join: float) -> float:
	return minf(full, maxf(left_at_join, 0.0) * PmcAi.number(_section("start"), "run_through_share", 0.5))


## How far apart (metres) the AI PMC squads already in the raid start when you join, where the map has
## the room (RaidController._join_spot()): squad_spacing in a clear line, squad_spacing_unseen with a wall
## between them.
static func squad_spacing() -> float:
	return PmcAi.number(_section("fast_forward"), "squad_spacing", 30.0)


static func squad_spacing_unseen() -> float:
	return PmcAi.number(_section("fast_forward"), "squad_spacing_unseen", 12.0)


## The share (0-1) of loot already taken `passed` seconds after it was there, in a `raid_seconds` raid:
## loot_taken per_raid × the share of the raid passed, at most its max.
static func loot_taken(passed: float, raid_seconds: float) -> float:
	var rule := PmcAi.dict(_section("fast_forward").get("loot_taken"))
	var share := PmcAi.number(rule, "per_raid", 0.9) * maxf(passed, 0.0) / maxf(raid_seconds, 1.0)
	return clampf(minf(share, PmcAi.number(rule, "max", 0.6)), 0.0, 1.0)


## The chance (0-1) that an AI PMC `passed` seconds into a `raid_seconds` raid has died by then.
static func pmc_death_chance(passed: float, raid_seconds: float) -> float:
	return clampf(PmcAi.number(_section("fast_forward"), "pmc_deaths", 0.5) * maxf(passed, 0.0) / maxf(raid_seconds, 1.0), 0.0, 1.0)


## Takes each item out of `grid` (its top level) with chance `share`, rolled with `rng`: loot someone
## got to first. Returns how many it took.
static func pick_over(grid: InventoryGrid, share: float, rng: RandomNumberGenerator) -> int:
	if grid == null or share <= 0.0:
		return 0
	var taken := 0
	for item: ItemInstance in grid.items.duplicate():
		if rng.randf() < share:
			grid.remove(item)
			taken += 1
	return taken


# --- The cooldown ---------------------------------------------------------------------------------

## Real minutes from deploying as a Scav to the next Scav run, before any multiplier.
static func cooldown_minutes() -> float:
	return maxf(PmcAi.number(data(), "cooldown_minutes", FALLBACK_COOLDOWN_MINUTES), 0.0)


## Seconds a Scav run deployed now puts you on cooldown for: cooldown_minutes() × the Intelligence
## Center's multiplier × the kit tier's cooldown at `at_karma`.
static func cooldown_seconds(at_karma := NAN) -> float:
	var level := karma() if is_nan(at_karma) else at_karma
	return cooldown_minutes() * 60.0 * Hideout.scav_cooldown_multiplier() * PmcAi.number(kit_tier(level), "cooldown", 1.0)


## Seconds until you can go on a Scav run again (0: now). Never more than a whole cooldown, so a clock
## that went back can't make it longer.
static func seconds_left() -> float:
	return clampf(GameState.scav_ready_at - now(), 0.0, cooldown_minutes() * 60.0)


static func is_ready() -> bool:
	return seconds_left() <= 0.0


## "12:30" until the next Scav run ("" once it's ready).
static func countdown_text() -> String:
	return TraderStock.clock(seconds_left()) if not is_ready() else ""


## "Scav ready in 12:30", or "Scav ready".
static func ready_text() -> String:
	return "Scav ready in %s" % countdown_text() if not is_ready() else "Scav ready"


## Deploying as a Scav: the cooldown starts (GameState.scav_ready_at), the kit is used (the next cycle
## rolls a new one) and the game is saved, so quitting mid-raid doesn't reset it.
static func deploy() -> void:
	GameState.scav_ready_at = snappedf(now() + cooldown_seconds(), 1.0)
	GameState.scav_kit = null
	SaveManager.save_game()


# --- The Scav kit ---------------------------------------------------------------------------------

## This cycle's Scav kit (GameState.scav_kit), rolled with your karma's kit tier the first time it's
## asked for, then the same until you deploy. The Inventory itself: GameState.scav_loadout() hands out
## copies.
static func kit() -> Inventory:
	if GameState.scav_kit == null:
		GameState.scav_kit = roll_kit(null, karma())
	return GameState.scav_kit


## The cycle's Scav kit as saved (GameState.from_dict()): null if there's none, or if it holds an item
## that no longer exists (renamed or removed since it was saved), so the cycle rolls a fresh kit rather
## than send you in with what's left of it.
static func kit_from_save(saved: Variant) -> Inventory:
	if not saved is Dictionary or not _known_items(saved):
		return null
	return Inventory.from_dict(saved)


## True if every item id in `value` (a saved inventory: its items, their contents, parts and rounds)
## exists.
static func _known_items(value: Variant) -> bool:
	if value is Dictionary:
		if value.has("id") and not ItemDB.has_item(str(value.id)):
			return false
		return value.values().all(_known_items)
	if value is Array:
		return value.all(_known_items)
	return true


## A Scav kit for `at_karma`'s kit tier, rolled with `rng` (else at random).
static func roll_kit(rng: RandomNumberGenerator, at_karma: float) -> Inventory:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return tier_kit(kit_tier(at_karma)).build(rng)


## The kit tiers, worst first.
static func tiers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var listed: Variant = data().get("kit_tiers")
	if listed is Array:
		for entry: Variant in listed:
			if entry is Dictionary:
				result.append(entry)
	return result


## The kit tier for `at_karma`: the lowest tier with an at_most it's at or below, else the highest with
## an at_least it's at or above, else the one with neither ({} without tiers).
static func kit_tier(at_karma: float) -> Dictionary:
	var standard := {}
	var best := {}
	for tier in tiers():
		if tier.has("at_most"):
			if at_karma <= PmcAi.number(tier, "at_most") + 0.0001:
				return tier
		elif tier.has("at_least"):
			if at_karma >= PmcAi.number(tier, "at_least") - 0.0001:
				best = tier
		elif standard.is_empty():
			standard = tier
	return best if not best.is_empty() else standard


## "Trusted" (the tier's name).
static func tier_name(tier: Dictionary) -> String:
	return str(tier.get("name", tier.get("id", "Standard")))


## data/bots/scav_kit.tres dressed for `tier` (cached by tier id).
static func tier_kit(tier: Dictionary) -> BotKit:
	var id := str(tier.get("id", ""))
	if not _tier_kits.has(id):
		var base := load(KIT_PATH) as BotKit
		var overrides := PmcAi.dict(tier.get("overrides"))
		_tier_kits[id] = base.with_tier(overrides) if not overrides.is_empty() else base
	return _tier_kits[id]


# --- Karma ----------------------------------------------------------------------------------------

static func _karma() -> Dictionary:
	return _section("karma")


## The lowest and highest karma.
static func karma_range() -> Vector2:
	var pair := PmcAi.pair(_karma().get("range"), [-6.0, 6.0])
	return Vector2(float(pair[0]), float(pair[1]))


## The karma a new profile starts at.
static func start_karma() -> float:
	return clamp_karma(PmcAi.number(_karma(), "start", 0.0))


static func clamp_karma(value: float) -> float:
	var bounds := karma_range()
	return clampf(snappedf(value, 0.01), bounds.x, bounds.y)


## Your karma now (Mole's standing).
static func karma() -> float:
	return GameState.scav_karma


## How much a raid event changes karma: "friendly_kill", "guard_kill", "boss_kill", "pmc_kill",
## "extract_with_others", "extract".
static func change_for(reason: String) -> float:
	return PmcAi.number(_karma(), reason, 0.0)


## A friendly AI Scav this close as you extract counts as extracting with others (metres), as does one
## that left through the same extract this many seconds before you.
static func with_others_radius() -> float:
	return PmcAi.number(_karma(), "with_others_radius", 20.0)


static func with_others_seconds() -> float:
	return PmcAi.number(_karma(), "with_others_seconds", 60.0)


## True if AI Scavs shoot your Scav on sight at `at_karma` (below hostile_below).
static func hostile(at_karma: float) -> bool:
	return at_karma < PmcAi.number(_karma(), "hostile_below", -1.0) - 0.0001


## What an AI Scav's reaction time to your Scav is multiplied by at `at_karma` (hostile): reaction[0]
## just below hostile_below, falling in a straight line to reaction[1] at the lowest karma.
static func reaction_multiplier(at_karma: float) -> float:
	var pair := PmcAi.pair(_karma().get("reaction"), [1.5, 1.0])
	var top := PmcAi.number(_karma(), "hostile_below", -1.0)
	var bottom := karma_range().x
	var t := clampf((top - at_karma) / maxf(top - bottom, 0.001), 0.0, 1.0)
	return lerpf(float(pair[0]), float(pair[1]), t)


## The trader whose standing is your karma (Mole: TraderTable.follows_karma()), "" if none.
static func karma_trader() -> String:
	for trader_id in TraderTable.ids():
		if TraderTable.follows_karma(trader_id):
			return trader_id
	return ""


## `changes` ([{"reason", "delta"}]) added up.
static func total(changes: Array) -> float:
	var sum := 0.0
	for change: Dictionary in changes:
		sum += float(change.get("delta", 0.0))
	return sum


## Applies a raid's karma `changes` to the profile (kept within karma_range()), and brings the loyalty of
## the traders whose standing is your karma (Mole) up or down to match. Returns the new karma.
static func apply(changes: Array) -> float:
	GameState.scav_karma = clamp_karma(GameState.scav_karma + total(changes))
	Trading.update_loyalty(karma_trader())
	return GameState.scav_karma


## "1.6", "−1.5", "0.25": up to two decimals, at least one; `signed` puts "+" before what's above 0.
static func number_text(value: float, signed := false) -> String:
	var text := "%.2f" % absf(value)
	if text.ends_with("0"):
		text = text.left(-1)
	var sign := MINUS if value < -0.0001 else ("+" if signed and value > 0.0001 else "")
	return sign + text


## The summary line: "Killed a friendly Scav −1.0 · Extracted with a Scav +0.5 → karma 1.6" (the
## changes grouped by reason: "Killed 2 PMCs +0.5"), or "No change → karma 0.4". `per_line` above 0:
## a new line after every that many changes.
static func changes_text(changes: Array, after: float, per_line := 0) -> String:
	var parts: Array[String] = []
	for reason: String in REASONS:
		var picked := changes.filter(func(change: Dictionary) -> bool: return str(change.get("reason", "")) == reason)
		if picked.is_empty():
			continue
		var names: Array = REASONS[reason]
		var what: String = names[0] if picked.size() == 1 else (names[1] % picked.size() if "%d" in names[1] else names[1])
		parts.append("%s %s" % [what, number_text(total(picked), true)])
	var text := ""
	for i in parts.size():
		if i > 0:
			text += "\n" if per_line > 0 and i % per_line == 0 else "  ·  "
		text += parts[i]
	return "%s → karma %s" % [text if not parts.is_empty() else "No change", number_text(after)]


## The SCAV button's text in ENTER RAID: what a Scav run is, how AI Scavs take you (by your karma) and,
## on cooldown, "Scav ready in 12:30".
static func side_text() -> String:
	var lines: Array[String] = ["SCAV"]
	if not is_ready():
		lines.append(ready_text())
	lines.append("Random gear, nothing to lose.")
	lines.append("You join a raid already under way.")
	lines.append("Loot you extract goes to your stash.")
	lines.append(scav_attitude_text())
	return "\n".join(lines)


## "AI Scavs leave you alone unless you shoot them." or, below hostile_below, "AI Scavs shoot you on
## sight (karma −2.5)."
static func scav_attitude_text() -> String:
	if hostile(karma()):
		return "AI Scavs shoot you on sight (karma %s)." % number_text(karma())
	return "AI Scavs leave you alone unless you shoot them."


# --- Checks ---------------------------------------------------------------------------------------

## The kit tiers' pocket items that don't exist (empty if none). Needs the items loaded: ItemDB runs it
## once it has them.
static func item_problems() -> Array[String]:
	var found: Array[String] = []
	for tier in tiers():
		var items: Variant = PmcAi.dict(tier.get("overrides")).get("pocket_items", [])
		for item_id: Variant in items if items is Array else []:
			if not ItemDB.has_item(str(item_id)):
				found.append("kit tier %s: pocket item %s doesn't exist" % [tier.get("id", "?"), item_id])
	return found


## What's wrong with the file (empty if nothing).
static func problems() -> Array[String]:
	var found: Array[String] = []
	var file := data()  # (data() marks itself loaded first, so it checks the file it just read.)
	var start := PmcAi.dict(file.get("start"))
	var windows := {"window": start.get("window")}
	for map_id: Variant in PmcAi.dict(start.get("maps")):
		windows["maps.%s" % map_id] = PmcAi.dict(start.get("maps"))[map_id]
	for key: String in windows:
		var pair: Variant = windows[key]
		if not (pair is Array and pair.size() == 2 and pair.all(_is_number) and float(pair[0]) >= 0.0 and float(pair[0]) <= float(pair[1]) and float(pair[1]) < 1.0):
			found.append("start %s must be [from, to] within 0-1" % key)
	if not PmcAi.is_number(start.get("min_left_seconds")) or float(start.get("min_left_seconds", -1)) < 0.0:
		found.append("start min_left_seconds must be a number, 0 or more")
	if not PmcAi.is_number(start.get("run_through_share")) or float(start.get("run_through_share", -1)) <= 0.0 or float(start.get("run_through_share", 2)) > 1.0:
		found.append("start run_through_share must be a number above 0, at most 1")
	var forward := PmcAi.dict(file.get("fast_forward"))
	var taken := PmcAi.dict(forward.get("loot_taken"))
	if not (PmcAi.is_number(taken.get("per_raid")) and PmcAi.is_number(taken.get("max")) and float(taken.max) >= 0.0 and float(taken.max) <= 1.0):
		found.append("fast_forward loot_taken needs per_raid and max (0-1)")
	if not PmcAi.is_number(forward.get("pmc_deaths")) or float(forward.get("pmc_deaths", -1)) < 0.0:
		found.append("fast_forward pmc_deaths must be a number, 0 or more")
	if not PmcAi.is_number(forward.get("squad_spacing")) or not PmcAi.is_number(forward.get("squad_spacing_unseen")) \
			or float(forward.get("squad_spacing_unseen", -1)) < 0.0 or float(forward.get("squad_spacing", -1)) < float(forward.get("squad_spacing_unseen", 0)):
		found.append("fast_forward squad_spacing and squad_spacing_unseen must be numbers, 0 or more, squad_spacing the larger")
	if not PmcAi.is_number(file.get("cooldown_minutes")) or float(file.get("cooldown_minutes", -1)) <= 0.0:
		found.append("cooldown_minutes must be a number above 0")
	var karma_rules := PmcAi.dict(file.get("karma"))
	var bounds: Variant = karma_rules.get("range")
	if not (bounds is Array and bounds.size() == 2 and bounds.all(_is_number) and float(bounds[0]) < 0.0 and float(bounds[1]) > 0.0):
		found.append("karma range must be [lowest below 0, highest above 0]")
	for key in KARMA_FIELDS + ["start"]:
		if not PmcAi.is_number(karma_rules.get(key)):
			found.append("karma %s must be a number" % key)
	if PmcAi.number(karma_rules, "friendly_kill") >= 0.0 or PmcAi.number(karma_rules, "boss_kill") >= 0.0 or PmcAi.number(karma_rules, "guard_kill") >= 0.0:
		found.append("karma: killing a friendly Scav, guard or boss must lower it")
	var reaction: Variant = karma_rules.get("reaction")
	if not (reaction is Array and reaction.size() == 2 and reaction.all(_is_number) and float(reaction[0]) >= float(reaction[1]) and float(reaction[1]) > 0.0 \
			and float(reaction[0]) <= MAX_REACTION):
		found.append("karma reaction must be [just below hostile_below, at the lowest], above 0, falling, at most %s (else a hostile Scav loses you before it fires)" % MAX_REACTION)
	var listed: Variant = file.get("kit_tiers")
	if not listed is Array or listed.is_empty():
		found.append("no kit_tiers")
		return found
	var plain := 0
	var ids: Array[String] = []
	var last_most := -INF
	var last_least := -INF
	for entry: Variant in listed:
		if not entry is Dictionary:
			found.append("kit tier %s isn't an object" % str(entry))
			continue
		var id := str(entry.get("id", ""))
		if id == "" or id in ids:
			found.append("kit tier %s: the id is missing or taken" % entry)
		ids.append(id)
		if entry.has("at_most") and entry.has("at_least"):
			found.append("kit tier %s has both at_most and at_least" % id)
		elif entry.has("at_most"):
			if not PmcAi.is_number(entry.at_most) or float(entry.at_most) <= last_most:
				found.append("kit tier %s: at_most must be a number above the tier before's" % id)
			last_most = PmcAi.number(entry, "at_most", last_most)
		elif entry.has("at_least"):
			if not PmcAi.is_number(entry.at_least) or float(entry.at_least) <= last_least:
				found.append("kit tier %s: at_least must be a number above the tier before's" % id)
			last_least = PmcAi.number(entry, "at_least", last_least)
		else:
			plain += 1
		if not PmcAi.is_number(entry.get("cooldown", 1.0)) or float(entry.get("cooldown", 1.0)) <= 0.0:
			found.append("kit tier %s: cooldown must be a number above 0" % id)
		var overrides: Variant = entry.get("overrides", {})
		if not overrides is Dictionary:
			found.append("kit tier %s: overrides must be an object" % id)
			continue
		for key: Variant in overrides:
			if not str(key) in TIER_OVERRIDES:
				found.append("kit tier %s: unknown override %s" % [id, key])
	if plain != 1:
		found.append("kit_tiers need exactly one tier without at_most or at_least (the standard kit), not %d" % plain)
	return found
