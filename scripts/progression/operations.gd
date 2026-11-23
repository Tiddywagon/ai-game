class_name Operations
extends RefCounted
## Daily and weekly operational tasks (DESIGN.md §11, Operations): a set of dailies every real day and
## of weeklies every real week (data/tasks/operations.json: the reset hours in UTC, the rewards, the pool
## of task templates), rolled from the templates you can do (playable maps, stations you've built that
## have crafts, a weapon class you have or can buy, the other faction's PMCs) by a generator seeded by
## the profile's seed, the kind and the day or week number, so reloading never re-rolls and time away
## just moves on to the current set. Counts and rewards follow the player level at the roll.
##
## A task is shaped like a quest ({"id", "name", "objectives": [one objective], ...}) so QuestLog and
## QuestRaid track it as they track quests (live in PMC raids, the HUD tracker, toasts, the raid
## summary): QuestLog.find() / state() / progress() / add_progress() hand an operation's id or task to
## this class, and QuestLog.tracking() lists the open tasks with the active quests. A task also has
## "operation" (its kind), "template", "slot", "level" (the player level it was rolled at), "progress"
## ([its count so far]), "rewards" ({"roubles", "xp", "drip"}), "rare_chance", "rerolls" (re-rolls
## left), "claimed" and, once claimed, "paid" (what it paid). Saved in GameState.operations
## ({"seed", "daily": {"number", "level", "tasks", "bonus"}, "weekly": {"number", "level", "tasks"},
## "owed": [reward items waiting for room in the stash]}).
##
## A finished task is claimed from the board (CLAIM on the OPERATIONS tab): roubles, XP, its Drip and,
## with its kind's chance, a rare item from the reward table (never found in raid; the roll is seeded by
## the task, so a reload can't change it). Unfinished tasks are gone at the reset; finished ones nobody
## claimed are paid then. Claiming all of a day's dailies pays the all-dailies bonus. problems() checks
## the file when the items load.

const PATH := "res://data/tasks/operations.json"
const KINDS: Array[String] = ["daily", "weekly"]
## Every task id starts with this (QuestLog.find() hands those ids here).
const ID_PREFIX := "op_"
const DAY := 86400.0
const WEEK := 604800.0
## The first Monday after the unix epoch, as a unix day (1970-01-05).
const FIRST_MONDAY := 4
## The objective types a template may use (QuestLog's types; "sell" and "search" were added for these).
const TYPES: Array[String] = ["kill", "extract", "visit", "search", "hand_in", "sell", "craft"]
const TEMPLATE_KEYS := ["id", "name", "kind", "levels", "weight", "objective", "pick", "counts", "reward"]
## What a template's "pick" may list: the roll picks one of each (poi_tiers: a point of interest of
## those tiers on the picked map).
const PICK_KEYS := ["map", "item", "weapon_class", "station", "poi_tiers"]
const KIND_KEYS := ["name", "count", "reward_scale", "rare_chance", "drip", "rerolls"]
## Money rounds to this many roubles, experience to this many points.
const ROUBLE_STEP := 500
const XP_STEP := 50
## A sell task's count (roubles) rounds to this.
const SELL_STEP := 1000

## The file read (tests point it at a copy), and unix time to use instead of the clock (tests); -1 means
## the real clock.
static var path := PATH
static var now_override := -1.0
static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_data = parsed if parsed is Dictionary else {"templates": []}
	return _data


## Reads the file again (tests that edit a copy).
static func reload() -> void:
	_data = {}


static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


static func templates() -> Array:
	return data().get("templates", [])


static func template(id: String) -> Dictionary:
	for entry: Dictionary in templates():
		if str(entry.get("id", "")) == id:
			return entry
	return {}


## The settings of set `kind` (daily, weekly): KIND_KEYS.
static func kind_config(kind: String) -> Dictionary:
	return data().get("kinds", {}).get(kind, {})


## "Daily", "Weekly".
static func kind_name(kind: String) -> String:
	return str(kind_config(kind).get("name", kind.capitalize()))


# --- The clock -----------------------------------------------------------------------------------

## The day number (`kind` daily) or week number (weekly) at unix time `at`, counted from the reset:
## days change at daily_hour_utc, weeks on weekly_day at weekly_hour_utc.
static func period(kind: String, at: float) -> int:
	return floori((at - _start(kind)) / _length(kind))


## Unix time the set of `kind` that's current at `at` ends (its next reset).
static func period_end(kind: String, at: float) -> float:
	return _start(kind) + (period(kind, at) + 1) * _length(kind)


## Seconds until the next reset of `kind`.
static func seconds_left(kind: String) -> float:
	return period_end(kind, now()) - now()


## The first reset of `kind` on or after the unix epoch.
static func _start(kind: String) -> float:
	var reset: Dictionary = data().get("reset", {})
	if kind == "weekly":
		return (FIRST_MONDAY + int(reset.get("weekly_day", 0))) * DAY + float(reset.get("weekly_hour_utc", 0)) * 3600.0
	return float(reset.get("daily_hour_utc", 0)) * 3600.0


static func _length(kind: String) -> float:
	return WEEK if kind == "weekly" else DAY


# --- Level bands and rewards ---------------------------------------------------------------------

static func bands() -> Array:
	return data().get("bands", [])


## The band player level `level` falls in (an index into bands()).
static func band(level: int) -> int:
	var found := 0
	for i in bands().size():
		if level >= int(bands()[i].get("from", 1)):
			found = i
	return found


## `template`'s reward weight in band `index` (one number for every band, or one per band).
static func reward_weight(template: Dictionary, index: int) -> float:
	var reward: Variant = template.get("reward", 1.0)
	if reward is Array:
		return float(reward[clampi(index, 0, reward.size() - 1)]) if not reward.is_empty() else 1.0
	return float(reward)


## `template`'s count range in band `index`: [low, high] ([1, 1] for a visit).
static func count_range(template: Dictionary, index: int) -> Array:
	var counts: Array = template.get("counts", [])
	if counts.is_empty():
		return [1, 1]
	var entry: Array = counts[clampi(index, 0, counts.size() - 1)]
	return [int(entry[0]), int(entry[1])]


## What a task of `template` with `count` pays when rolled at `level`: {"roubles", "xp", "drip"}.
static func rewards_for(template: Dictionary, count: int, level: int) -> Dictionary:
	var index := band(level)
	var entry: Dictionary = bands()[index] if index < bands().size() else {}
	var range := count_range(template, index)
	var middle := maxf((range[0] + range[1]) / 2.0, 1.0)
	var config := kind_config(str(template.get("kind", "daily")))
	var scale := reward_weight(template, index) * float(config.get("reward_scale", 1.0)) * count / middle
	return {"roubles": maxi(roundi(float(entry.get("roubles", 0)) * scale / ROUBLE_STEP) * ROUBLE_STEP, ROUBLE_STEP),
		"xp": maxi(roundi(float(entry.get("xp", 0)) * scale / XP_STEP) * XP_STEP, XP_STEP), "drip": int(config.get("drip", 0))}


## The all-dailies bonus at `level`: {"roubles", "xp"} (all_dailies_bonus of the band's daily base).
static func bonus_for(level: int) -> Dictionary:
	var index := band(level)
	var entry: Dictionary = bands()[index] if index < bands().size() else {}
	var share := float(data().get("all_dailies_bonus", 0.0))
	return {"roubles": roundi(float(entry.get("roubles", 0)) * share / ROUBLE_STEP) * ROUBLE_STEP,
		"xp": roundi(float(entry.get("xp", 0)) * share / XP_STEP) * XP_STEP}


# --- What you can do -----------------------------------------------------------------------------

## The faction whose PMCs a "rival" kill asks for: the other one (&"" without a profile faction).
static func rival() -> StringName:
	var own := Factions.of_profile(GameState.faction)
	if not Factions.has(own):
		return &""
	for id in Factions.ids():
		if id != own:
			return id
	return &""


## `template`'s pick lists narrowed to what this profile can do now, in file order: playable maps (with
## a point of interest of the tiers asked, if any), items that exist, weapon classes you have a gun of
## or can buy, stations built far enough to have crafts. {} entries mean nothing is left.
static func pick_options(template: Dictionary) -> Dictionary:
	var pick: Dictionary = template.get("pick", {})
	var result := {}
	if pick.has("map"):
		result.map = pick.map.filter(func(map_id: Variant) -> bool:
			var map := MapInfo.find(str(map_id))
			return map != null and map.is_playable() and (not pick.has("poi_tiers") or not pois(str(map_id), pick.poi_tiers).is_empty()))
	if pick.has("item"):
		result.item = pick.item.filter(func(id: Variant) -> bool: return ItemDB.has_item(str(id)))
	if pick.has("weapon_class"):
		var classes := weapon_classes()
		result.weapon_class = pick.weapon_class.filter(func(id: Variant) -> bool: return str(id) in classes)
	if pick.has("station"):
		result.station = pick.station.filter(func(id: Variant) -> bool:
			var station := Hideout.find(str(id))
			return not station.is_empty() and not Hideout.crafts(station).is_empty())
	return result


## The points of interest on `map_id` a visit task may pick: of `tiers`, not hidden, not behind a key,
## a lever or power, and always there (no spawn chance of their own).
static func pois(map_id: String, tiers: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in PoiTable.for_map(map_id):
		if int(entry.get("tier", 1)) in tiers.map(func(tier: Variant) -> int: return int(tier)) and not entry.get("hidden", false) \
				and not entry.has("requires") and not entry.has("spawn_chance"):
			result.append(str(entry.get("id", "")))
	return result


## The weapon classes you have a gun of (stash and character) or can buy from a trader now.
static func weapon_classes() -> Array[String]:
	var result: Array[String] = []
	var guns: Array[ItemInstance] = GameState.inventory.all_items()
	if GameState.stash:
		guns.append_array(GameState.stash.all_items())
	for item in guns:
		if item.data and item.data.weapon and not str(item.data.weapon.weapon_class) in result:
			result.append(str(item.data.weapon.weapon_class))
	for trader_id in TraderTable.ids():
		if Trading.trader_block_reason(trader_id) != "":
			continue
		for offer: Dictionary in Trading.shown_offers(trader_id):
			var quest := str(offer.get("quest", ""))
			var data := ItemDB.get_item(str(offer.get("item", ""))) if ItemDB.has_item(str(offer.get("item", ""))) else null
			if data and data.weapon and (quest == "" or QuestLog.is_completed(quest)) and not str(data.weapon.weapon_class) in result:
				result.append(str(data.weapon.weapon_class))
	return result


## True when this profile can do a task of `template` now: everything it picks has an option left, a
## rival kill has a rival faction, and a boss kill a boss on a playable map.
static func doable(template: Dictionary) -> bool:
	var objective: Dictionary = template.get("objective", {})
	if str(objective.get("faction", "")) == "rival" and rival() == &"":
		return false
	if str(objective.get("target", "")) == "boss" and not BossTable.maps().keys().any(func(map_id: Variant) -> bool:
			var map := MapInfo.find(str(map_id))
			return map != null and map.is_playable()):
		return false
	var options := pick_options(template)
	for key: String in options:
		if (options[key] as Array).is_empty():
			return false
	return true


## The templates of set `kind` that can be rolled at player `level` now (levels, doable()), in file order.
static func candidates(kind: String, level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in templates():
		var levels: Array = entry.get("levels", [1, Progression.MAX_LEVEL])
		if str(entry.get("kind", "")) == kind and level >= int(levels[0]) and level <= int(levels[1]) and doable(entry):
			result.append(entry)
	return result


# --- Rolling -------------------------------------------------------------------------------------

static func _rng(kind: String, number: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("ops:%d:%s:%d:%s" % [int(GameState.operations.get("seed", 0)), kind, number, purpose]).hash()
	return rng


## The set `kind` rolls for day or week `number` at player `level`: up to its count of different
## templates from candidates(), picked by weight with the profile's seeded generator.
static func roll(kind: String, number: int, level: int) -> Array[Dictionary]:
	var rng := _rng(kind, number, "roll")
	var pool := candidates(kind, level)
	var result: Array[Dictionary] = []
	for slot in int(kind_config(kind).get("count", 3)):
		if pool.is_empty():
			break
		var picked := _pick(pool, rng)
		pool.erase(picked)
		result.append(make_task(picked, rng, kind, number, slot, level, ""))
	return result


static func _pick(pool: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var weights := PackedFloat32Array()
	for entry in pool:
		weights.append(maxf(float(entry.get("weight", 1.0)), 0.0))
	return pool[rng.rand_weighted(weights)]


## A task from `template`: one of each pick list's options (pick_options()), a rival kill's faction,
## a count from the band's range for `level`, and the rewards for that count. Id: "op_daily_20415_0"
## (`suffix` after a re-roll).
static func make_task(template: Dictionary, rng: RandomNumberGenerator, kind: String, number: int, slot: int, level: int,
		suffix: String) -> Dictionary:
	var objective: Dictionary = template.get("objective", {}).duplicate(true)
	var options := pick_options(template)
	for key: String in ["map", "item", "weapon_class", "station"]:
		if options.has(key):
			var list: Array = options[key]
			objective[key] = str(list[rng.randi_range(0, list.size() - 1)])
	if template.get("pick", {}).has("poi_tiers"):
		var found := pois(str(objective.get("map", "")), template.pick.poi_tiers)
		objective["poi"] = found[rng.randi_range(0, found.size() - 1)]
	if str(objective.get("faction", "")) == "rival":
		objective["faction"] = String(rival())
	var count := 1
	if str(objective.get("type", "")) != "visit":
		var range := count_range(template, band(level))
		count = rng.randi_range(range[0], range[1])
		if str(objective.get("type", "")) == "sell":
			count = maxi(roundi(count / float(SELL_STEP)) * SELL_STEP, SELL_STEP)  # Money: whole thousands.
		objective["count"] = count
	var config := kind_config(kind)
	return {"id": "%s%s_%d_%d%s" % [ID_PREFIX, kind, number, slot, suffix], "name": str(template.get("name", template.get("id", ""))),
		"operation": kind, "template": str(template.get("id", "")), "slot": slot, "level": level, "objectives": [objective], "progress": [0],
		"rewards": rewards_for(template, count, level), "rare_chance": float(config.get("rare_chance", 0.0)),
		"rerolls": int(config.get("rerolls", 0)), "claimed": false}


# --- The saved state -----------------------------------------------------------------------------

## A new profile's operations: nothing rolled yet, a random seed (`seed` when 0 or more).
static func blank(seed := -1) -> Dictionary:
	var result := {"seed": seed if seed >= 0 else randi(), "owed": []}
	for kind in KINDS:
		result[kind] = {"number": -1, "level": 1, "tasks": []}
	result.daily.bonus = {"roubles": 0, "xp": 0, "paid": false}
	return result


static func to_save() -> Dictionary:
	return GameState.operations.duplicate(true)


## The operations from a save (none before version 21: blank, seeded by `fallback_seed`, so reloading
## the same old save rolls the same set). Numbers come back whole (JSON reads them as floats); a task
## that isn't a task is dropped.
static func from_save(saved: Variant, fallback_seed: int) -> Dictionary:
	if not saved is Dictionary:
		return blank(absi(fallback_seed))
	var result := blank(absi(int(saved.get("seed", fallback_seed))))
	for kind in KINDS:
		var block: Variant = saved.get(kind)
		if not block is Dictionary:
			continue
		result[kind].number = int(block.get("number", -1))
		result[kind].level = maxi(int(block.get("level", 1)), 1)
		for task: Variant in block.get("tasks", []):
			if task is Dictionary and task.get("objectives") is Array and not (task.objectives as Array).is_empty():
				result[kind].tasks.append(_clean_task(task, kind))
		if kind == "daily" and block.get("bonus") is Dictionary:
			result.daily.bonus = {"roubles": int(block.bonus.get("roubles", 0)), "xp": int(block.bonus.get("xp", 0)),
				"paid": bool(block.bonus.get("paid", false))}
	for entry: Variant in saved.get("owed", []):
		if entry is Dictionary:
			result.owed.append(entry)
	return result


static func _clean_task(task: Dictionary, kind: String) -> Dictionary:
	var result := task.duplicate(true)
	result.operation = kind
	result.id = str(task.get("id", ""))
	result.slot = int(task.get("slot", 0))
	result.level = int(task.get("level", 1))
	result.progress = [int((task.get("progress", [0]) as Array)[0]) if not (task.get("progress", []) as Array).is_empty() else 0]
	result.rerolls = int(task.get("rerolls", 0))
	result.claimed = bool(task.get("claimed", false))
	result.rare_chance = float(task.get("rare_chance", 0.0))
	var rewards: Dictionary = task.get("rewards", {})
	result.rewards = {"roubles": int(rewards.get("roubles", 0)), "xp": int(rewards.get("xp", 0)), "drip": int(rewards.get("drip", 0))}
	if task.get("paid") is Dictionary:
		var paid: Dictionary = task.paid
		result.paid = {"roubles": int(paid.get("roubles", 0)), "xp": int(paid.get("xp", 0)), "drip": int(paid.get("drip", 0))}
		if paid.has("item"):
			result.paid.item = str(paid.item)
			result.paid.count = int(paid.get("count", 1))
	var objective: Dictionary = (task.objectives as Array)[0]
	if objective.has("count"):
		objective.count = int(objective.count)
	result.objectives = [objective]
	return result


## The tasks of set `kind` on the board now.
static func tasks(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(GameState.operations.get(kind, {}).get("tasks", []))
	return result


## Every task on the board, dailies first.
static func all_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind in KINDS:
		result.append_array(tasks(kind))
	return result


## The tasks still to finish (QuestLog.tracking()).
static func active() -> Array[Dictionary]:
	return all_tasks().filter(func(task: Dictionary) -> bool: return state(task) == "active")


static func find(id: String) -> Dictionary:
	for task in all_tasks():
		if str(task.id) == id:
			return task
	return {}


## "active", "ready" (done, to claim) or "completed" (claimed).
static func state(task: Dictionary) -> String:
	if task.get("claimed", false):
		return "completed"
	return "ready" if progress(task) >= QuestLog.objective_count(task, 0) else "active"


static func progress(task: Dictionary) -> int:
	var saved: Array = task.get("progress", [])
	return int(saved[0]) if not saved.is_empty() else 0


## Adds `amount` to an active task (up to its count). Returns how much it moved.
static func add_progress(task: Dictionary, amount: int) -> int:
	if amount <= 0 or state(task) != "active":
		return 0
	var before := progress(task)
	task.progress = [mini(before + amount, QuestLog.objective_count(task, 0))]
	return progress(task) - before


## How many of set `kind` are finished (ready or claimed).
static func finished(kind: String) -> int:
	return tasks(kind).filter(func(task: Dictionary) -> bool: return state(task) != "active").size()


# --- The reset -----------------------------------------------------------------------------------

## Brings both sets up to date with the clock: a set whose day or week is over pays out its finished
## tasks nobody claimed (claim(); the unfinished ones are gone) and the current one is rolled at your
## level now. Not during a raid (GameState.raid set): a reset waits for the raid to end, so the raid
## counts toward the tasks you took into it. Then reward items waiting for room go to the stash.
## Returns the tasks paid out at a reset.
static func update() -> Array[Dictionary]:
	var paid: Array[Dictionary] = []
	if not GameState.has_profile() or not GameState.raid.is_empty():
		return paid
	for kind in KINDS:
		var block: Dictionary = GameState.operations.get_or_add(kind, {"number": -1, "level": 1, "tasks": []})
		var number := period(kind, now())
		if int(block.get("number", -1)) == number:
			continue
		for task in tasks(kind):
			if state(task) == "ready" and claim(task) == "":
				paid.append(task)
		block.number = number
		block.level = GameState.level
		block.tasks = roll(kind, number, GameState.level)
		if kind == "daily":
			block.bonus = bonus_for(GameState.level)
			block.bonus.paid = false
	deliver_owed()
	return paid


## Puts reward items that were waiting for room into the stash, as many as fit. Returns how many went in.
static func deliver_owed() -> int:
	var owed: Array = GameState.operations.get_or_add("owed", [])
	var left := []
	var moved := 0
	for entry: Variant in owed:
		var item := ItemInstance.from_dict(entry) if entry is Dictionary else null
		if item == null:
			continue
		if GameState.stash.add(item):
			moved += 1
		else:
			left.append(entry)
	GameState.operations.owed = left
	return moved


# --- Claiming and re-rolling ---------------------------------------------------------------------

## Why `task` can't be claimed, or "".
static func claim_block_reason(task: Dictionary) -> String:
	if not GameState.raid.is_empty():
		return "Claim it once you're out of the raid"
	match state(task):
		"completed":
			return "Already claimed"
		"active":
			return "Finish the task first"
	return ""


## The rare item `task` gives when claimed: {"item", "count"}, or {} (no luck). Rolled with its kind's
## chance and then by weight among the reward table's items for its level, by a generator seeded by the
## profile and the task, so it's the same however often you look or reload.
static func rare_item(task: Dictionary) -> Dictionary:
	var rng := _rng(str(task.get("operation", "")), 0, "rare:%s" % task.get("id", ""))
	if rng.randf() >= float(task.get("rare_chance", 0.0)):
		return {}
	var pool := rare_pool(int(task.get("level", 1)))
	if pool.is_empty():
		return {}
	var weights := PackedFloat32Array()
	for entry in pool:
		weights.append(float(entry.get("weight", 1.0)))
	var picked: Dictionary = pool[rng.rand_weighted(weights)]
	return {"item": str(picked.item), "count": maxi(int(picked.get("count", 1)), 1)}


## The reward table's entries open at player `level`.
static func rare_pool(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in data().get("rare_items", {}).get("items", []):
		if level >= int(entry.get("level", 1)) and ItemDB.has_item(str(entry.get("item", ""))):
			result.append(entry)
	return result


## Claims `task`: its roubles, Drip, the rare item if it drops (in the stash, never found in raid; one
## with no room waits in "owed" and arrives when there's room) and then the XP (GameState.add_xp()). The
## last of a day's dailies claimed pays the all-dailies bonus. "" on success, else why not.
static func claim(task: Dictionary) -> String:
	var reason := claim_block_reason(task)
	if reason != "":
		return reason
	var rewards: Dictionary = task.get("rewards", {})
	var roubles := int(rewards.get("roubles", 0))
	GameState.roubles += roubles
	GameState.drip += int(rewards.get("drip", 0))
	Stats.earned(roubles)
	var paid := {"roubles": roubles, "xp": int(rewards.get("xp", 0)), "drip": int(rewards.get("drip", 0))}
	var rare := rare_item(task)
	if not rare.is_empty():
		paid.item = rare.item
		paid.count = rare.count
		for piece in QuestLog.pieces(str(rare.item), int(rare.count)):
			if not GameState.stash.add(piece):
				GameState.operations.get_or_add("owed", []).append(piece.to_dict())
	task.claimed = true
	task.paid = paid
	GameState.add_xp(int(paid.xp))
	if str(task.get("operation", "")) == "daily":
		_pay_bonus()
	return ""


## The all-dailies bonus, once all of today's dailies are claimed (and only once).
static func _pay_bonus() -> void:
	var block: Dictionary = GameState.operations.get("daily", {})
	var bonus: Dictionary = block.get_or_add("bonus", {"roubles": 0, "xp": 0, "paid": false})
	var list := tasks("daily")
	if bonus.get("paid", false) or list.is_empty() or not list.all(func(task: Dictionary) -> bool: return state(task) == "completed"):
		return
	bonus.paid = true
	GameState.roubles += int(bonus.get("roubles", 0))
	Stats.earned(int(bonus.get("roubles", 0)))
	GameState.add_xp(int(bonus.get("xp", 0)))


## True once all of today's dailies are claimed and the bonus paid.
static func bonus_paid() -> bool:
	return bool(GameState.operations.get("daily", {}).get("bonus", {}).get("paid", false))


## What a re-roll of `task` costs: reroll_fee of its roubles, rounded to 500.
static func reroll_fee(task: Dictionary) -> int:
	var fee := float(task.get("rewards", {}).get("roubles", 0)) * float(data().get("reroll_fee", 0.0))
	return maxi(roundi(fee / ROUBLE_STEP) * ROUBLE_STEP, ROUBLE_STEP)


## The templates a re-roll of `task` may give: its kind's candidates at your level now, less every
## template on the board.
static func reroll_pool(task: Dictionary) -> Array[Dictionary]:
	var kind := str(task.get("operation", ""))
	var used := tasks(kind).map(func(each: Dictionary) -> String: return str(each.get("template", "")))
	return candidates(kind, GameState.level).filter(func(entry: Dictionary) -> bool: return not str(entry.get("id", "")) in used)


## Why `task` can't be re-rolled, or "".
static func reroll_block_reason(task: Dictionary) -> String:
	if not GameState.raid.is_empty():
		return "Re-roll it once you're out of the raid"
	if int(task.get("rerolls", 0)) <= 0:
		return "%ss can't be re-rolled" % kind_name(str(task.get("operation", ""))) if int(kind_config(str(task.get("operation", ""))).get("rerolls", 0)) <= 0 \
			else "Already re-rolled"
	if state(task) != "active":
		return "Only an unfinished task can be re-rolled"
	if GameState.roubles < reroll_fee(task):
		return "Not enough money (%s)" % UiFormat.money(reroll_fee(task))
	if reroll_pool(task).is_empty():
		return "Nothing else to roll"
	return ""


## Swaps `task` for another of its kind (reroll_pool(), seeded by the profile, the day and the slot) at
## your level now, for reroll_fee(); its progress goes with it. A tracked task stays tracked as the new
## one. "" on success, else why not.
static func reroll(task: Dictionary) -> String:
	var reason := reroll_block_reason(task)
	if reason != "":
		return reason
	var kind := str(task.operation)
	var block: Dictionary = GameState.operations[kind]
	var left := int(task.rerolls) - 1
	var rng := _rng(kind, int(block.number), "reroll:%d:%d" % [int(task.slot), left])
	var fresh := make_task(_pick(reroll_pool(task), rng), rng, kind, int(block.number), int(task.slot), GameState.level, "_r%d" % (int(kind_config(kind).get("rerolls", 0)) - left))
	fresh.rerolls = left
	var fee := reroll_fee(task)
	GameState.roubles -= fee
	Stats.spent(fee)
	var index := (block.tasks as Array).find(task)
	block.tasks[index] = fresh
	var tracked_at := GameState.quest_tracked.find(str(task.id))
	if tracked_at >= 0:
		GameState.quest_tracked[tracked_at] = str(fresh.id)
	return ""


# --- Text ----------------------------------------------------------------------------------------

## "Daily · Scav Sweep" (the HUD tracker, toasts, the raid summary).
static func title(task: Dictionary) -> String:
	return "%s · %s" % [kind_name(str(task.get("operation", ""))), task.get("name", "")]


## The reward lines of `task`: "25,000 ₽", "400 XP", "15% chance of a rare item" (or, once claimed,
## what it paid: "Gold chain").
static func reward_lines(task: Dictionary) -> Array[String]:
	var rewards: Dictionary = task.get("paid", task.get("rewards", {}))
	var lines: Array[String] = ["%s ₽" % UiFormat.thousands(int(rewards.get("roubles", 0))), "%s XP" % UiFormat.thousands(int(rewards.get("xp", 0)))]
	if int(rewards.get("drip", 0)) > 0:
		lines.append("%d Drip" % int(rewards.drip))
	if task.has("paid"):
		if task.paid.has("item"):
			var count := int(task.paid.get("count", 1))
			lines.append(("%d× %s" % [count, ExtractTable.item_name(str(task.paid.item))]) if count > 1 else ExtractTable.item_name(str(task.paid.item)))
	elif float(task.get("rare_chance", 0.0)) > 0.0:
		lines.append("%d%% chance of a rare item" % roundi(float(task.rare_chance) * 100.0))
	return lines


## "Resets in 5:12:03" for set `kind`.
static func reset_text(kind: String) -> String:
	return "Resets in %s" % UiFormat.countdown(seconds_left(kind))


## The main menu's line: "Operations: 2 / 3 dailies  ·  resets in 5:12:03" ("all 3 dailies done" once
## every one is claimed).
static func menu_text() -> String:
	var list := tasks("daily")
	var done := "all %d dailies done" % list.size() if not list.is_empty() and list.all(func(task: Dictionary) -> bool: return state(task) == "completed") \
		else "%d / %d dailies" % [finished("daily"), list.size()]
	return "Operations: %s  ·  resets in %s" % [done, UiFormat.countdown(seconds_left("daily"))]


## "1 reward item waiting for room in the stash" ("" for none).
static func owed_text() -> String:
	var count: int = GameState.operations.get("owed", []).size()
	return "" if count == 0 else "%d reward item%s waiting for room in the stash" % [count, "" if count == 1 else "s"]


# --- Checking the file ---------------------------------------------------------------------------

## What's wrong with the file (empty if nothing): the reset hours and day, both kinds and their
## settings, the level bands (from level 1 up, money and XP above 0 and growing), the fee and bonus
## shares; the reward table (items Rare or better, Epic or rarer only from epic_level, counts and
## weights, something at level 1); and each template: a unique id, a name, a kind, levels within
## 1-60, only known keys, an objective type of TYPES that QuestLog accepts (QuestLog's own check, for
## every option it can pick), a count range per band (none for a visit), a reward above 0, pick lists
## of maps that exist (one at least playable), items, weapon classes and stations with crafts,
## hand-ins found in raid and of nothing the hideout makes (so nothing bought or crafted counts), a
## rival kill on PMCs; and every level has enough templates of each kind to fill a set.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var reset: Dictionary = data().get("reset", {})
	for key: String in ["daily_hour_utc", "weekly_hour_utc"]:
		if not reset.has(key) or int(reset[key]) < 0 or int(reset[key]) > 23:
			found.append("reset %s must be an hour, 0-23" % key)
	if int(reset.get("weekly_day", -1)) < 0 or int(reset.get("weekly_day", -1)) > 6:
		found.append("reset weekly_day must be 0 (Monday) to 6 (Sunday)")
	for kind in KINDS:
		var config := kind_config(kind)
		if config.is_empty():
			found.append("kinds has no %s" % kind)
			continue
		for key: String in config:
			if not key in KIND_KEYS:
				found.append("kinds %s: unknown key %s" % [kind, key])
		if int(config.get("count", 0)) < 1 or float(config.get("reward_scale", 0.0)) <= 0.0 or int(config.get("drip", 0)) < 0 \
				or int(config.get("rerolls", 0)) < 0 or float(config.get("rare_chance", -1.0)) < 0.0 or float(config.get("rare_chance", 2.0)) > 1.0:
			found.append("kinds %s: count 1+, reward_scale above 0, drip and rerolls 0+, rare_chance 0-1" % kind)
	var from := 0
	var money := 0
	for i in bands().size():
		var entry: Dictionary = bands()[i]
		if i == 0 and int(entry.get("from", 0)) != 1:
			found.append("bands start at level 1")
		if int(entry.get("from", 0)) <= from or int(entry.get("roubles", 0)) <= money or int(entry.get("xp", 0)) <= 0:
			found.append("band %d: levels and roubles go up, XP above 0" % i)
		from = int(entry.get("from", 0))
		money = int(entry.get("roubles", 0))
	if bands().is_empty():
		found.append("no level bands")
	if float(data().get("reroll_fee", -1.0)) < 0.0 or float(data().get("reroll_fee", 2.0)) > 1.0:
		found.append("reroll_fee is a share, 0-1")
	if float(data().get("all_dailies_bonus", -1.0)) < 0.0:
		found.append("all_dailies_bonus is a share, 0 or more")
	found.append_array(_rare_problems())
	var seen := {}
	for entry: Variant in templates():
		if not entry is Dictionary:
			found.append("template %s isn't an object" % entry)
			continue
		var id := str(entry.get("id", ""))
		if id == "" or seen.has(id):
			found.append("template %s: %s" % [id, "used twice" if id != "" else "no id"])
		seen[id] = true
		found.append_array(_template_problems(entry))
	for kind in KINDS:
		for level in range(1, Progression.MAX_LEVEL + 1):
			var open := templates().filter(func(entry: Variant) -> bool:
				var levels: Array = entry.get("levels", [1, Progression.MAX_LEVEL]) if entry is Dictionary else []
				return entry is Dictionary and str(entry.get("kind", "")) == kind and levels.size() == 2 and level >= int(levels[0]) and level <= int(levels[1]))
			if open.size() < int(kind_config(kind).get("count", 3)) + 1:
				found.append("level %d has %d %s templates: a set of %d and a re-roll need more" % [level, open.size(), kind, int(kind_config(kind).get("count", 3))])
				break
	return found


static func _rare_problems() -> Array[String]:
	var found: Array[String] = []
	var table: Dictionary = data().get("rare_items", {})
	var lowest := ItemData.RARITY_IDS.find(str(table.get("min_rarity", "rare")))
	var epic := ItemData.RARITY_IDS.find("epic")
	for entry: Variant in table.get("items", []):
		var id := str(entry.get("item", "")) if entry is Dictionary else ""
		if not ItemDB.has_item(id):
			found.append("rare_items: item %s doesn't exist" % id)
			continue
		var data_item := ItemDB.get_item(id)
		if data_item.rarity < lowest:
			found.append("rare_items: %s isn't %s or better" % [id, table.get("min_rarity", "rare")])
		if data_item.rarity >= epic and int(entry.get("level", 1)) < int(table.get("epic_level", 30)):
			found.append("rare_items: %s is Epic or rarer, from level %d only" % [id, int(table.get("epic_level", 30))])
		if int(entry.get("count", 1)) < 1 or float(entry.get("weight", 0.0)) <= 0.0 or int(entry.get("level", 0)) < 1 or int(entry.get("level", 0)) > Progression.MAX_LEVEL:
			found.append("rare_items: %s needs a count 1+, a weight above 0 and a level 1-%d" % [id, Progression.MAX_LEVEL])
	if rare_pool(1).is_empty():
		found.append("rare_items: nothing at level 1")
	return found


static func _template_problems(entry: Dictionary) -> Array[String]:
	var where := "template %s" % entry.get("id", "")
	var found: Array[String] = []
	for key: String in entry:
		if not key in TEMPLATE_KEYS:
			found.append("%s: unknown key %s" % [where, key])
	if str(entry.get("name", "")) == "" or not str(entry.get("kind", "")) in KINDS:
		found.append("%s: needs a name and a kind (daily or weekly)" % where)
	var levels: Variant = entry.get("levels")
	if not levels is Array or levels.size() != 2 or int(levels[0]) < 1 or int(levels[1]) > Progression.MAX_LEVEL or int(levels[0]) > int(levels[1]):
		found.append("%s: levels is [first, last] within 1-%d" % [where, Progression.MAX_LEVEL])
	if float(entry.get("weight", 1.0)) <= 0.0:
		found.append("%s: weight above 0" % where)
	var objective: Variant = entry.get("objective")
	if not objective is Dictionary or not str(objective.get("type", "")) in TYPES:
		found.append("%s: objective type is one of %s" % [where, ", ".join(TYPES)])
		return found
	var type := str(objective.type)
	if objective.has("count"):
		found.append("%s: the count comes from counts, not the objective" % where)
	var counts: Array = entry.get("counts", [])
	if type == "visit" and not counts.is_empty():
		found.append("%s: a visit has no counts" % where)
	elif type != "visit":
		if counts.size() != bands().size():
			found.append("%s: counts needs one [low, high] per band (%d)" % [where, bands().size()])
		for range: Variant in counts:
			if not range is Array or range.size() != 2 or int(range[0]) < 1 or int(range[0]) > int(range[1]):
				found.append("%s: a count range is [low, high], 1 or more" % where)
	var reward: Variant = entry.get("reward", 1.0)
	if (reward is Array and (reward.size() != bands().size() or reward.any(func(each: Variant) -> bool: return float(each) <= 0.0))) \
			or (not reward is Array and float(reward) <= 0.0):
		found.append("%s: reward is a weight above 0, or one per band" % where)
	var pick: Dictionary = entry.get("pick", {})
	for key: String in pick:
		if not key in PICK_KEYS or not pick[key] is Array or (pick[key] as Array).is_empty():
			found.append("%s: pick %s isn't a list of %s" % [where, key, ", ".join(PICK_KEYS)])
	if objective.has("map") or objective.has("item") or objective.has("weapon_class") or objective.has("station") or objective.has("poi"):
		found.append("%s: maps, items, weapon classes, stations and points of interest are picked (pick), not fixed" % where)
	if type == "visit" and (not pick.has("map") or not pick.has("poi_tiers")):
		found.append("%s: a visit picks a map and poi_tiers" % where)
	if type == "hand_in" and (not pick.has("item") or objective.get("fir", false) != true):
		found.append("%s: a hand-in picks items and is found in raid (fir: true)" % where)
	if type == "craft" and not pick.has("station"):
		found.append("%s: a craft picks a station" % where)
	if str(objective.get("faction", "rival")) != "rival":
		found.append("%s: a kill's faction is \"rival\" (the other faction's PMCs)" % where)
	if pick.has("map") and not pick.map.any(func(map_id: Variant) -> bool:
			var map := MapInfo.find(str(map_id))
			return map != null and map.is_playable()):
		found.append("%s: no map it picks is playable" % where)
	for item_id: Variant in pick.get("item", []):
		if made_in_hideout(str(item_id)):
			found.append("%s: %s is made in the hideout, so it could be crafted instead of found" % [where, item_id])
	# QuestLog's own check, on every option the roll can pick.
	var range := count_range(entry, 0)
	for variant in _variants(objective, pick):
		if type != "visit":
			variant.count = range[1]
		for problem in QuestLog._objective_problems(where, {"objectives": [variant]}, 0):
			found.append(problem)
	return found


## Every objective a template can roll (each option of each pick list on its own; a visit: every point
## of interest it can pick on every map), for the check.
static func _variants(objective: Dictionary, pick: Dictionary) -> Array[Dictionary]:
	var base := objective.duplicate(true)
	if str(base.get("faction", "")) == "rival":
		base.faction = "usec"
	var result: Array[Dictionary] = []
	if pick.has("poi_tiers"):
		for map_id: Variant in pick.get("map", []):
			for poi in pois(str(map_id), pick.poi_tiers):
				var visit := base.duplicate(true)
				visit.map = str(map_id)
				visit.poi = poi
				result.append(visit)
		return result
	for key: String in ["map", "item", "weapon_class", "station"]:
		for option: Variant in pick.get(key, []):
			var variant := base.duplicate(true)
			for other: String in ["map", "item", "weapon_class", "station"]:
				if pick.has(other):
					variant[other] = str(pick[other][0])
			variant[key] = str(option)
			result.append(variant)
	if result.is_empty():
		result.append(base)
	return result


## True for an item a hideout craft or a station's production makes (found in raid when collected).
static func made_in_hideout(item_id: String) -> bool:
	for station in Hideout.stations():
		for entry: Dictionary in station.get("levels", []):
			if str(entry.get("produces", {}).get("item", "")) == item_id:
				return true
			for recipe: Dictionary in entry.get("crafts", []):
				if str(recipe.get("output", {}).get("item", "")) == item_id:
					return true
	return false


## True when selling `item` counts toward a sell task: it and everything in or on it found in raid,
## none of it made in the hideout (so only raid finds count, never anything bought or crafted).
static func counts_as_loot(item: ItemInstance) -> bool:
	return item.all_items().all(func(each: ItemInstance) -> bool: return each.fir and not made_in_hideout(each.data.id))
