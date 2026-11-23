class_name Stats
extends RefCounted
## Lifetime stats (DESIGN.md §16.2): counted over the whole profile in GameState.stats and shown on the
## CHARACTER screen's STATS tab. Raids add theirs when they settle (record_raid(), from RaidOutcome: raids
## by side and outcome, kills by target type, headshot kills, the longest kill, rounds fired and bullet
## hits, damage dealt and taken, items looted and the value of the loot got out, metres moved, time in
## raids, the best raid by XP and by loot), only a raid that goes to the profile; the menus add the rest
## as it happens: roubles earned and spent (trades, the flea market, the hideout, insurance, quest
## rewards; dollars at Progression.dollar_rate(); exchanging money is neither), quests completed and
## crafts collected. 360 trick shots stay in GameState.trick_shots.

const SIDES := ["pmc", "scav"]
const OUTCOMES := ["survived", "run_through", "killed", "mia"]
const KILL_TYPES := ["scav", "pmc", "guard", "boss"]
## The plain counters (numbers; the longest kill and the best raids are the best so far).
const COUNTERS := ["headshots", "longest_kill", "shots", "hits", "damage_dealt", "damage_taken", "items_looted", "loot_value",
	"roubles_earned", "roubles_spent", "quests", "crafts", "distance", "raid_seconds", "best_raid_xp", "best_raid_loot"]


## A new profile's stats: every count at 0.
static func blank() -> Dictionary:
	var result := {"raids": {}, "kills": {}}
	for side in SIDES:
		result.raids[side] = {}
		for outcome in OUTCOMES:
			result.raids[side][outcome] = 0
	for kind in KILL_TYPES:
		result.kills[kind] = 0
	for key in COUNTERS:
		result[key] = 0.0
	return result


## The stats from a save (missing before version 20: all 0), every count there and a number.
static func from_save(saved: Variant) -> Dictionary:
	var result := blank()
	if not saved is Dictionary:
		return result
	for side in SIDES:
		var raids: Variant = saved.get("raids", {}).get(side, {}) if saved.get("raids") is Dictionary else {}
		for outcome in OUTCOMES:
			result.raids[side][outcome] = maxi(int(raids.get(outcome, 0)), 0) if raids is Dictionary else 0
	var kills: Variant = saved.get("kills", {})
	for kind in KILL_TYPES:
		result.kills[kind] = maxi(int(kills.get(kind, 0)), 0) if kills is Dictionary else 0
	for key in COUNTERS:
		result[key] = maxf(float(saved.get(key, 0.0)), 0.0)
	return result


static func get_value(key: String) -> float:
	return float(GameState.stats.get(key, 0))


## Adds `amount` to counter `key`.
static func add(key: String, amount: float = 1.0) -> void:
	if not key in COUNTERS or amount <= 0.0:
		return
	GameState.stats[key] = get_value(key) + amount


## Counter `key` becomes `value` if that's more (the longest kill, the best raid).
static func best(key: String, value: float) -> void:
	if key in COUNTERS and value > get_value(key):
		GameState.stats[key] = value


## Money in: `roubles` and `dollars` (at the dollar rate) earned.
static func earned(roubles: int, dollars := 0) -> void:
	add("roubles_earned", roubles + roundi(dollars * Progression.dollar_rate()))


## Money out: `roubles` and `dollars` (at the dollar rate) spent.
static func spent(roubles: int, dollars := 0) -> void:
	add("roubles_spent", roubles + roundi(dollars * Progression.dollar_rate()))


## A raid that went to the profile (RaidOutcome.settle(); plain values, so this class needs none of the
## raid's): `raid` {"side", "outcome" (one of OUTCOMES), "kills" (its kill list), "xp", "seconds",
## "loot_value" (what you got out with; 0 if you didn't)} and the counts RaidController.raid_stats() keeps
## ("shots", "hits", "damage_dealt", "damage_taken", "distance", "headshots", "longest_kill", "looted").
static func record_raid(raid: Dictionary, counts: Dictionary) -> void:
	var side := str(raid.get("side", "pmc")) if str(raid.get("side", "pmc")) in SIDES else "pmc"
	var key := str(raid.get("outcome", "survived")) if str(raid.get("outcome", "")) in OUTCOMES else "survived"
	GameState.stats.raids[side][key] = int(GameState.stats.raids[side][key]) + 1
	for kill: Dictionary in raid.get("kills", []):
		var kind := str(kill.get("role", "")) if str(kill.get("role", "")) in ["boss", "guard"] else str(kill.get("side", "scav"))
		if kind in KILL_TYPES:
			GameState.stats.kills[kind] = int(GameState.stats.kills[kind]) + 1
	for counter in ["shots", "hits", "headshots", "looted"]:
		add("items_looted" if counter == "looted" else counter, int(counts.get(counter, 0)))
	for counter in ["damage_dealt", "damage_taken", "distance"]:
		add(counter, snappedf(float(counts.get(counter, 0.0)), 0.1))
	add("raid_seconds", roundi(float(raid.get("seconds", 0.0))))
	best("longest_kill", snappedf(float(counts.get("longest_kill", 0.0)), 0.1))
	best("best_raid_xp", int(raid.get("xp", 0)))
	add("loot_value", int(raid.get("loot_value", 0)))
	best("best_raid_loot", int(raid.get("loot_value", 0)))


## Raids of `side` ("" both) in all.
static func raids(side := "") -> int:
	var total := 0
	for each in SIDES:
		if side == "" or side == each:
			for outcome in OUTCOMES:
				total += int(GameState.stats.raids[each][outcome])
	return total


## Share (0-1) of `side`'s raids ("" both) survived (extracted, a Run Through counting as survived);
## 0 with none.
static func survival_rate(side := "") -> float:
	var total := raids(side)
	if total == 0:
		return 0.0
	var survived := 0
	for each in SIDES:
		if side == "" or side == each:
			survived += int(GameState.stats.raids[each].survived) + int(GameState.stats.raids[each].run_through)
	return float(survived) / total


## The STATS tab: [[section or "", label, text]] in order.
static func rows() -> Array[Array]:
	var stats: Dictionary = GameState.stats
	var result: Array[Array] = []
	for side in SIDES:
		var raid_counts: Dictionary = stats.raids[side]
		result.append(["RAIDS", "%s raids" % ("PMC" if side == "pmc" else "Scav"), "%d  ·  %d survived, %d run through, %d killed, %d missing  ·  %d%% survival" % [raids(side),
			raid_counts.survived, raid_counts.run_through, raid_counts.killed, raid_counts.mia, roundi(survival_rate(side) * 100.0)]])
	result.append(["RAIDS", "Survival rate", "%d%% of %d raids" % [roundi(survival_rate() * 100.0), raids()]])
	result.append(["RAIDS", "Time in raids", "%d h %02d min" % [int(get_value("raid_seconds")) / 3600, int(get_value("raid_seconds")) / 60 % 60]])
	result.append(["RAIDS", "Distance moved", "%s km" % String.num(snappedf(get_value("distance") / 1000.0, 0.1))])
	result.append(["RAIDS", "Best raid", "%s XP  ·  best loot %s" % [UiFormat.thousands(int(get_value("best_raid_xp"))), UiFormat.money(int(get_value("best_raid_loot")))]])
	var kills: Dictionary = stats.kills
	var total_kills := 0
	for kind in KILL_TYPES:
		total_kills += int(kills[kind])
	result.append(["COMBAT", "Kills", "%d  ·  %d Scavs, %d PMCs, %d guards, %d bosses" % [total_kills, kills.scav, kills.pmc, kills.guard, kills.boss]])
	result.append(["COMBAT", "Headshot kills", "%d (%d%%)" % [int(get_value("headshots")), roundi(get_value("headshots") * 100.0 / maxi(total_kills, 1))]])
	result.append(["COMBAT", "Longest kill", "%s m" % String.num(snappedf(get_value("longest_kill"), 0.1))])
	result.append(["COMBAT", "Rounds fired / hit", "%s / %s  ·  %d%% accuracy" % [UiFormat.thousands(int(get_value("shots"))), UiFormat.thousands(int(get_value("hits"))),
		roundi(get_value("hits") * 100.0 / maxf(get_value("shots"), 1.0))]])
	result.append(["COMBAT", "Damage dealt / taken", "%s / %s" % [UiFormat.thousands(roundi(get_value("damage_dealt"))), UiFormat.thousands(roundi(get_value("damage_taken")))]])
	result.append(["COMBAT", "360 trick shots", "%d hits, %d kills" % [int(GameState.trick_shots.get("hits", 0)), int(GameState.trick_shots.get("kills", 0))]])
	result.append(["LOOT AND MONEY", "Items looted", "%s  ·  %s got out" % [UiFormat.thousands(int(get_value("items_looted"))), UiFormat.money(int(get_value("loot_value")))]])
	result.append(["LOOT AND MONEY", "Roubles earned / spent", "%s / %s" % [UiFormat.money(int(get_value("roubles_earned"))), UiFormat.money(int(get_value("roubles_spent")))]])
	result.append(["LOOT AND MONEY", "Quests completed", str(int(get_value("quests")))])
	result.append(["LOOT AND MONEY", "Crafts collected", str(int(get_value("crafts")))])
	return result
