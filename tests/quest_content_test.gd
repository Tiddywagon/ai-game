extends "res://tests/test_base.gd"
## The quest content (DESIGN.md §11, docs/plan/E12_quest_content.md): at least 60 quests, one file per
## trader plus the faction, Collector and boss files; every trader's intro chain startable at level 1
## (The Broker's at his unlock) and played through on the Test Yard and Factory with real triggers
## (live raids for kills, visits, placements, marks and extracts; hand-ins from the stash; crafts
## collected at the hideout); every map, boss and objective type used; the faction lines hidden from
## each other; nothing on an open map waiting for a map without a scene; Epic and Legendary rewards only
## late and never worth more than their hand-ins by a wide margin; flavour text on every quest; quest XP
## against the level curve (DESIGN §2.2's table), reputation reaching LL4 with every trader, and the
## quick-buy task counts reachable by the loyalty their cards need.

const QUESTS := "res://scripts/progression/quest_log.gd"
const TRADERS: Array[String] = ["bulat", "vera", "zoya", "stitch", "tinker", "mole", "broker"]
const MAPS: Array[String] = ["test_yard", "factory", "customs_yard", "woodland", "shoreline", "labs"]
## The traders whose chains go through every map (Mole and The Broker run shorter lines).
const EVERY_MAP: Array[String] = ["bulat", "vera", "zoya", "stitch", "tinker"]
const RAID_XP := 2000
## Where a raid leaves when no objective names an extract.
const DEFAULT_EXTRACT := {"test_yard": "north_east_gate", "factory": "gate_3"}

var quests: GDScript
var status: Dictionary
var _eff := {}
var _closed := {}
var _ll_level := {1: 1}


func run() -> void:
	quests = load(QUESTS)
	status = load("res://scripts/raid/raid_outcome.gd").Status
	var progression: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/config/progression.json"))
	for entry: Dictionary in progression.loyalty:
		_ll_level[int(entry.level)] = int(entry.player_level)
	fresh_profile()
	_counts_and_files()
	_intro_chains()
	_maps_and_bosses()
	_factions()
	_objective_types()
	_closed_maps()
	_rewards()
	_flavour()
	_xp_curve(progression)
	_reputation(progression)
	_quick_buy()
	await _map_note_shown()
	await _play_intro_chains()


# --- Helpers -------------------------------------------------------------------------------------

## The player level a quest really needs: its own, the one its loyalty levels need, and every quest
## before it in its chain.
func _effective_level(quest: Dictionary) -> int:
	if _eff.has(quest.id):
		return _eff[quest.id]
	var level := int(quest.get("level", 1))
	var loyalty: Dictionary = quest.get("loyalty", {})
	for trader: String in loyalty:
		if trader != "mole":  # His levels are Scav karma's, not the player's.
			level = maxi(level, int(_ll_level[int(loyalty[trader])]))
	for before: String in quest.get("requires", []):
		level = maxi(level, _effective_level(quests.find(before)))
	_eff[quest.id] = level
	return level


## True when `quest` or one before it needs a map without a scene: it can't be done today.
func _waits_closed(quest: Dictionary) -> bool:
	if not _closed.has(quest.id):
		_closed[quest.id] = not quests.closed_maps(quest).is_empty() or quest.get("requires", []).any(func(id: String) -> bool: return _waits_closed(quests.find(id)))
	return _closed[quest.id]


func _ids(list: Array) -> Array:
	return list.map(func(quest: Dictionary) -> String: return str(quest.id))


## The visible quests of `faction` ("bear" / "usec").
func _for(faction: String) -> Array[Dictionary]:
	return quests.shown(StringName(faction))


# --- The data ------------------------------------------------------------------------------------

func _counts_and_files() -> void:
	section("At least 60 quests, one file per trader")
	var all: Array[Dictionary] = quests.all()
	check(all.size() >= 60, "%d quests (60 or more)" % all.size())
	var files: Array = Array(DirAccess.get_files_at("res://data/quests")).filter(func(file: String) -> bool: return file.ends_with(".json"))
	check(files == ["01_bulat.json", "02_vera.json", "03_zoya.json", "04_stitch.json", "05_tinker.json", "06_mole.json", "07_broker.json",
		"08_collector.json", "09_faction_lines.json", "10_boss_hunts.json"], "the files: one per trader, then the Collector, faction and boss lines (%s)" % str(files))
	for index in 7:
		var file: String = files[index] if index < files.size() else ""
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + file)) if file != "" else []
		check(parsed is Array and not (parsed as Array).is_empty() and (parsed as Array).all(func(quest: Dictionary) -> bool: return quest.trader == TRADERS[index]),
			"%s holds only %s's quests" % [file, TRADERS[index]])
	var kinds := {}
	for quest in all:
		kinds[str(quest.get("chain", ""))] = int(kinds.get(str(quest.get("chain", "")), 0)) + 1
	check(all.all(func(quest: Dictionary) -> bool: return quests.CHAINS.has(str(quest.get("chain", "")))), "every quest names its chain kind (%s)" % str(kinds))
	var per_trader := {}
	for trader in TRADERS:
		per_trader[trader] = all.filter(func(quest: Dictionary) -> bool: return quest.trader == trader).size()
	print("  quests per trader: %s, per chain kind: %s" % [per_trader, kinds])
	check(quests.problems().is_empty(), "problems() is clean (%s)" % str(quests.problems().slice(0, 3)))
	for old: String in ["scrap_run", "shortage", "sanitary_standards", "textile", "gunsmith_0", "clinic_supplies", "server_room", "flare_path", "safe_harbour",
			"safekeeping", "collectors_case", "zoya_introduction", "due_diligence", "fine_print", "patchwork", "hard_plates", "yard_sweep", "clean_shot",
			"krane_yard", "signal_check", "dead_drop", "factory_walk", "carry_out", "trusted_hands", "bench_time", "range_day", "night_shift", "distant_tapes",
			"showboat", "around_the_world", "spin_doctor", "collector_shelf_talk", "collector_the_collector", "bear_old_unit", "bear_last_word",
			"usec_contract_renewal", "usec_clean_exfil"]:
		if quests.find(old).is_empty():
			check(false, "the quest id %s a save may hold still loads" % old)


## Each trader's intro chain: 3-4 quests, each after the one before, none on a closed map, none past
## level 5, the first available on a new profile (The Broker's once A Word in His Ear is done).
func _intro_chains() -> void:
	section("Every trader has an easy intro chain")
	for faction in [0, 1]:
		fresh_profile(faction)
		gs.quests["zoya_introduction"] = {"state": "completed", "progress": [1, 2, 150000]}  # The Broker's unlock.
		for trader in TRADERS:
			var chain: Array = quests.for_trader(trader).filter(func(quest: Dictionary) -> bool: return quest.get("chain", "") == "intro")
			var linked := true
			for i in range(1, chain.size()):
				linked = linked and chain[i].get("requires", []) == [chain[i - 1].id]
			var unlocked_at := 10 if trader == "broker" else 1  # The Broker opens with A Word in His Ear, from level 10.
			var easy: bool = chain.all(func(quest: Dictionary) -> bool:
				return _effective_level(quest) <= unlocked_at + 4 and quests.closed_maps(quest).is_empty() and not quest.has("loyalty"))
			check(chain.size() >= 3 and chain.size() <= 4 and linked and easy, "%s: %d intro quests, chained, easy, on open maps (%s)" % [trader, chain.size(), str(_ids(chain))])
			if not chain.is_empty():
				check(quests.state(chain[0]) == "available", "%s's first intro quest (%s) is available from the start (%s)" % [trader, chain[0].name, quests.lock_reason(chain[0])])
	fresh_profile()
	check(quests.lock_reason(quests.find("due_diligence")) == "Finish A Word in His Ear first", "The Broker's intro waits for his unlock")


func _maps_and_bosses() -> void:
	section("Every map and every boss")
	var on_map := {}
	for quest: Dictionary in quests.all():
		for map_id: String in quests.maps_of(quest):
			if not on_map.has(map_id):
				on_map[map_id] = {}
			on_map[map_id][quest.trader] = true
	for map_id in MAPS:
		check(on_map.has(map_id) and on_map[map_id].size() >= 4, "%s has quests from %d traders" % [map_id, on_map.get(map_id, {}).size()])
	for trader in EVERY_MAP:
		var maps := {}
		for quest in quests.all().filter(func(each: Dictionary) -> bool: return each.trader == trader and each.get("chain", "") in ["intro", "mid"]):
			for map_id: String in quests.maps_of(quest):
				maps[map_id] = true
		check(MAPS.all(func(map_id: String) -> bool: return maps.has(map_id)), "%s's chain goes through every map (%s)" % [trader, str(maps.keys())])
	var bosses: Dictionary = load("res://scripts/data/boss_table.gd").maps()
	var hunts: Array = quests.all().filter(func(quest: Dictionary) -> bool: return quest.get("chain", "") == "boss")
	for map_id: String in bosses:
		var boss_id := str(bosses[map_id].id)
		var for_boss: Array = hunts.filter(func(quest: Dictionary) -> bool:
			return map_id in quests.maps_of(quest) and quest.id != "boss_the_six")
		var kills_boss: bool = for_boss.any(func(quest: Dictionary) -> bool:
			return quest.objectives.any(func(entry: Dictionary) -> bool: return str(entry.get("boss", "")) == boss_id))
		var second: bool = for_boss.any(func(quest: Dictionary) -> bool:
			return quest.objectives.any(func(entry: Dictionary) -> bool: return entry.get("target", "") == "guard" or entry.has("body_part")))
		check(for_boss.size() >= 2 and kills_boss and second, "%s: a hunt on %s and a second step for the guards or with a condition (%s)" % [boss_id, map_id, str(_ids(for_boss))])
	var six: Dictionary = quests.find("boss_the_six")
	var killed: Array = six.get("objectives", []).map(func(entry: Dictionary) -> String: return str(entry.get("boss", "")))
	check(bosses.values().all(func(entry: Dictionary) -> bool: return str(entry.id) in killed), "The Six asks for every boss (%s)" % str(killed))
	check(hunts.all(func(quest: Dictionary) -> bool: return not quest.rewards.get("items", []).is_empty()), "every boss hunt rewards gear")


func _factions() -> void:
	section("The BEAR and USEC lines")
	for faction in ["bear", "usec"]:
		var other := "usec" if faction == "bear" else "bear"
		var own: Array = quests.all().filter(func(quest: Dictionary) -> bool: return str(quest.get("faction", "")) == faction)
		check(own.size() >= 7 and own.size() <= 8, "%s: %d quests of its own (7-8)" % [faction, own.size()])
		check(not _for(other).any(func(quest: Dictionary) -> bool: return str(quest.get("faction", "")) == faction) and own.all(func(quest: Dictionary) -> bool: return quest in _for(faction)),
			"%s's line is shown to %s and hidden from %s" % [faction, faction, other])
		check(own.any(func(quest: Dictionary) -> bool: return _effective_level(quest) >= 30), "%s's line ends late (level 30+)" % faction)
		var barters: GDScript = load("res://scripts/data/barter_table.gd")
		var unlocks: Array = own.filter(func(quest: Dictionary) -> bool: return barters.all().any(func(barter: Dictionary) -> bool: return barters.quest(barter) == quest.id))
		check(not unlocks.is_empty() and unlocks.all(func(quest: Dictionary) -> bool: return not _waits_closed(quest)),
			"%s's faction barter unlocks with %s, which can be done on today's maps" % [faction, str(_ids(unlocks))])
		var open: Array = own.filter(func(quest: Dictionary) -> bool: return not _waits_closed(quest))
		check(own.size() - open.size() <= 1 and open.any(func(quest: Dictionary) -> bool: return _effective_level(quest) >= 30),
			"%s's line can be finished on today's maps, its last quest too (only a side branch waits: %s)" % [faction, str(_ids(own.filter(func(quest: Dictionary) -> bool: return _waits_closed(quest))))])


func _objective_types() -> void:
	section("Every objective type is used")
	var used := {}
	for quest: Dictionary in quests.all():
		for i in quest.objectives.size():
			used[quests.objective_type(quest, i)] = int(used.get(quests.objective_type(quest, i), 0)) + 1
	for type: String in quests.OBJECTIVE_TYPES:
		check(used.has(type), "%s objectives: %d" % [type, int(used.get(type, 0))])
	var mixed := true
	for trader in TRADERS:
		var mine: Array = quests.all().filter(func(quest: Dictionary) -> bool: return quest.trader == trader)
		var raid: bool = mine.any(func(quest: Dictionary) -> bool: return quest.objectives.any(func(entry: Dictionary) -> bool: return str(entry.get("type", "hand_in")) in quests.RAID_TYPES))
		var home: bool = mine.any(func(quest: Dictionary) -> bool: return quest.objectives.any(func(entry: Dictionary) -> bool: return not str(entry.get("type", "hand_in")) in quests.RAID_TYPES))
		mixed = mixed and raid and home
		check(raid and home, "%s mixes raid objectives with hand-ins, crafts or upgrades" % trader)


func _closed_maps() -> void:
	section("Nothing reachable today waits for a map without a scene")
	var open := 0
	for quest: Dictionary in quests.all():
		if quests.closed_maps(quest).is_empty():
			open += 1
			check(not _waits_closed(quest), "%s is on open maps and nothing before it is on a closed one" % quest.id) if _waits_closed(quest) else null
	check(not quests.problems().any(func(line: String) -> bool: return "waits for a map" in line), "problems() finds nothing waiting on a closed map")
	var closed: Array = quests.all().filter(func(quest: Dictionary) -> bool: return not quests.closed_maps(quest).is_empty())
	check(closed.all(func(quest: Dictionary) -> bool: return quests.map_note(quest).begins_with("Map not open yet: ")), "the %d quests on closed maps say \"Map not open yet\"" % closed.size())
	print("  %d quests on open maps or none, %d on maps not open yet" % [open, closed.size()])


## Epic and Legendary rewards only from player level 30 (or the loyalty that needs it), and unless it's
## a boss hunt, their hand-ins sell for at least half what the rewarded items sell for.
func _rewards() -> void:
	section("Rewards: Epic and Legendary only late, inside the economy")
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	var top_rewards := 0
	for quest: Dictionary in quests.all():
		var reward_worth := 0
		var top := []
		for entry: Dictionary in quest.rewards.get("items", []):
			var piece: RefCounted = item(str(entry.item), int(entry.get("count", 1)))
			reward_worth += selling.best_resale(piece)
			if int(piece.data.rarity) >= 4:
				top.append(str(entry.item))
		if top.is_empty():
			continue
		top_rewards += 1
		check(_effective_level(quest) >= 30, "%s rewards %s at level %d: late (30+)" % [quest.id, str(top), _effective_level(quest)])
		if quest.get("chain", "") == "boss":
			continue
		var cost := 0
		for entry: Dictionary in quest.objectives:
			if str(entry.get("type", "hand_in")) == "hand_in":
				cost += selling.best_resale(item(str(entry.item), int(entry.get("count", 1))))
			elif str(entry.get("type", "")) == "roubles":
				cost += int(entry.count)
		check(reward_worth <= 2 * cost, "%s: its items sell for %d, its hand-ins for %d (no more than twice)" % [quest.id, reward_worth, cost])
	check(top_rewards >= 10, "%d quests reward Epic or Legendary items" % top_rewards)
	var late: Array = quests.all().filter(func(quest: Dictionary) -> bool: return quest.get("chain", "") == "late")
	check(late.size() >= 10 and late.all(func(quest: Dictionary) -> bool: return _effective_level(quest) >= 30 and quest.has("loyalty") or quest.id == "safekeeping"),
		"%d late-game quests, from level 30 with a loyalty level 3-4 gate (Safekeeping after Old Debts)" % late.size())


func _flavour() -> void:
	section("Every quest has its trader's own words")
	var seen := {}
	for quest: Dictionary in quests.all():
		var briefing := str(quest.get("description", ""))
		var turn_in := str(quest.get("success", ""))
		check(briefing.length() >= 40 and turn_in.length() >= 15 and briefing != turn_in, "%s has a briefing and a turn-in line" % quest.id) if briefing.length() < 40 or turn_in.length() < 15 else null
		if seen.has(briefing) or seen.has(turn_in):
			check(false, "%s's text is its own" % quest.id)
		seen[briefing] = true
		seen[turn_in] = true
	check(quests.all().all(func(quest: Dictionary) -> bool: return str(quest.get("description", "")).length() >= 40 and str(quest.get("success", "")).length() >= 15),
		"all %d quests have a briefing and a turn-in line" % quests.all().size())


# --- Balance -------------------------------------------------------------------------------------

## Raids of RAID_XP each, every quest done as soon as its level and chain allow: the raids each level
## takes, for `faction`, on the open maps only or on every map. {level: raids}.
func _raids_to_levels(faction: String, open_only: bool, levels: Array) -> Dictionary:
	var progression: GDScript = load("res://scripts/progression/progression.gd")
	var pool: Array = _for(faction).filter(func(quest: Dictionary) -> bool: return not (open_only and _waits_closed(quest)))
	var xp := 0
	var done := {}
	var result := {}
	var raids := 0
	while raids < 1000 and result.size() < levels.size():
		raids += 1
		xp += RAID_XP
		var more := true
		while more:
			more = false
			var level: int = progression.level_for_xp(xp)
			for quest: Dictionary in pool:
				if not done.has(quest.id) and _effective_level(quest) <= level and quest.get("requires", []).all(func(id: String) -> bool: return done.has(id)):
					done[quest.id] = true
					xp += int(quest.rewards.get("xp", 0))
					more = true
		for level: int in levels:
			if not result.has(level) and progression.level_for_xp(xp) >= level:
				result[level] = raids
	return result


func _xp_curve(config: Dictionary) -> void:
	section("Quest XP against the level curve (DESIGN §2.2)")
	var curve: Array = config.level_xp
	var levels := [2, 5, 10, 15, 20, 25, 30, 35, 40, 50, 60]
	var design := FileAccess.get_file_as_string("res://DESIGN.md")
	for faction in ["bear", "usec"]:
		var all_xp := 0
		var open_xp := 0
		for quest in _for(faction):
			all_xp += int(quest.rewards.get("xp", 0))
			if not _waits_closed(quest):
				open_xp += int(quest.rewards.get("xp", 0))
		print("  %s: quests give %d XP on every map, %d on the maps open today" % [faction, all_xp, open_xp])
		check(all_xp <= int(curve[-1]) * 0.4 and open_xp >= 80000, "%s: the quests give %d XP in all (at most 40%% of the top level's %d), %d today" % [faction, all_xp, int(curve[-1]), open_xp])
		var today := _raids_to_levels(faction, true, levels)
		var every := _raids_to_levels(faction, false, levels)
		print("  %s raids to each level, today: %s, every map: %s" % [faction, today, every])
		check(every.get(10, 0) >= 5 and every.get(15, 0) >= 12 and every.get(25, 0) >= 35 and every.get(35, 0) >= 70 and every.get(50, 0) >= 150,
			"%s: with every map, level 10 takes 5+ raids, 15 12+, 25 35+, 35 70+, 50 150+ (%s)" % [faction, every])
		if faction == "bear":
			var format: GDScript = load("res://scripts/ui/ui_format.gd")
			for level: int in levels:
				var row := "| %d | %s | %d | %d |" % [level, format.thousands(int(curve[level - 1])), int(today.get(level, 0)), int(every.get(level, 0))]
				check(row in design, "DESIGN §2.2 has the row %s" % row)


## Reputation for LL3 and LL4 from each trader's quests that can be done today (and the barter cap):
## enough with every trader but Mole, for both factions.
func _reputation(config: Dictionary) -> void:
	section("Reputation reaches LL4 with every trader")
	var cap := float(config.reputation.barter_cap)
	var need := {}
	for entry: Dictionary in config.loyalty:
		need[int(entry.level)] = float(entry.reputation)
	for faction in ["bear", "usec"]:
		var sums := {}
		for trader in TRADERS:
			sums[trader] = [0.0, 0.0]
		for quest in _for(faction):
			if _waits_closed(quest):
				continue
			var gate := int(quest.get("loyalty", {}).get(quest.trader, 1))
			var gains := {quest.trader: float(quest.rewards.get("reputation", 0.0))}
			gains.merge(quest.rewards.get("reputation_with", {}))
			for trader: String in gains:
				var gate_here := gate if trader == quest.trader else int(quest.get("loyalty", {}).get(trader, 1))
				if gate_here < 3:
					sums[trader][0] += float(gains[trader])
				if gate_here < 4:
					sums[trader][1] += float(gains[trader])
		var text := []
		for trader in TRADERS:
			text.append("%s %.2f / %.2f" % [trader, sums[trader][0], sums[trader][1]])
			if trader != "mole":
				check(sums[trader][0] + cap >= need[3] - 0.0001 and sums[trader][1] + cap >= need[4] - 0.0001,
					"%s, %s: %.2f before the LL3 quests and %.2f before the LL4 ones, + %.2f from barters, reach %.2f and %.2f" % [faction, trader, sums[trader][0], sums[trader][1], cap, need[3], need[4]])
		print("  %s reputation from quests open today (before LL3 gates / before LL4 gates): %s" % [faction, ", ".join(text)])


## Each quick-buy card's task count can be met by the time its loyalty levels can (the quests open today
## up to that player level, for each faction that sees it), and asks more of cards that need more loyalty.
func _quick_buy() -> void:
	section("Quick-buy task counts")
	var table: GDScript = load("res://scripts/data/quick_buy_table.gd")
	var most := {}
	var least := {}
	for card: Dictionary in table.all():
		var level := int(_ll_level[maxi(table.top_level(card), 1)])
		var tasks := int(card.unlock.get("tasks", 0))
		for faction in ["bear", "usec"]:
			if str(card.get("faction", faction)) != faction:
				continue
			var reachable: int = _for(faction).filter(func(quest: Dictionary) -> bool: return not _waits_closed(quest) and _effective_level(quest) <= level).size()
			check(tasks <= reachable, "%s (%s): %d tasks, %d quests open by level %d" % [card.name, faction, tasks, reachable, level])
		var top: int = table.top_level(card)
		most[top] = maxi(int(most.get(top, 0)), tasks)
		least[top] = mini(int(least.get(top, 9999)), tasks)
	for top: int in most:
		if most.has(top + 1):
			check(int(most[top]) <= int(least[top + 1]), "cards needing LL%d ask for no more tasks (%d) than those needing LL%d (%d)" % [top, most[top], top + 1, least[top + 1]])


# --- The quest log -------------------------------------------------------------------------------

func _map_note_shown() -> void:
	section("Quests on closed maps show \"Map not open yet\"")
	fresh_profile()
	var screen: Control = load("res://scripts/ui/quests_screen.gd").create(null, "bulat")
	root.add_child(screen)
	await frames(2)
	screen.show_tab(1)  # AVAILABLE: available and locked quests.
	screen.select("bulat_toll_road")
	await frames(2)
	var note := screen.find_child("MapNote", true, false) as Label
	check(note != null and note.text == "Map not open yet: Customs Yard.", "Toll Road's panel: %s" % (note.text if note else "no note"))
	screen.select("scrap_run")
	await frames(2)
	check(screen.find_child("MapNote", true, false) == null and (screen.find_child("QuestTitle", true, false) as Label).text == "SCRAP RUN", "Scrap Run's panel has no such note")
	screen.queue_free()
	await frames(2)


# --- Played through --------------------------------------------------------------------------------

## Every trader's intro chain played quest by quest at the same time: each round accepts the next quest
## of every chain, does its hideout work and hand-ins, runs the live raids its objectives need on the
## Test Yard and Factory, and turns it in.
func _play_intro_chains() -> void:
	section("Each trader's intro chain, played through with real triggers")
	fresh_profile()
	gs.roubles = 5000000
	gs.quests["zoya_introduction"] = {"state": "completed", "progress": [1, 2, 150000]}  # The Broker's door.
	var chains := {}
	for trader in TRADERS:
		chains[trader] = _ids(quests.for_trader(trader).filter(func(quest: Dictionary) -> bool: return quest.get("chain", "") == "intro"))
	for round in 5:
		var open: Array[Dictionary] = []
		for trader: String in chains:
			for id: String in chains[trader]:
				var quest: Dictionary = quests.find(id)
				if quests.state(quest) == "completed":
					continue
				var level := int(quest.get("level", 1))
				if gs.level < level:  # The XP a few raids would have earned.
					gs.add_xp(load("res://scripts/progression/progression.gd").xp_for_level(level) - gs.xp)
				if quests.state(quest) == "available":
					quests.accept(quest)
				if quests.state(quest) in ["active", "ready"]:
					open.append(quest)
				break
		if open.is_empty():
			break
		for quest in open:
			_hideout_work(quest)
		for map_id: String in DEFAULT_EXTRACT:
			await _raids_on(map_id, open)
		for quest in open:
			for i in quest.objectives.size():
				if quests.objective_type(quest, i) in quests.HAND_TYPES:
					_give_for(quest.objectives[i])
					quests.hand_in(quest, i)
			var missing := []
			for i in quest.objectives.size():
				if quests.progress(quest, i) < quests.objective_count(quest, i):
					missing.append("%s %d/%d" % [quests.objective_text(quest, i), quests.progress(quest, i), quests.objective_count(quest, i)])
			check(quests.state(quest) == "ready" and quests.complete(quest) == "", "%s (%s): done and turned in %s" % [quest.name, quest.trader, str(missing) if not missing.is_empty() else ""])
	for trader: String in chains:
		check(chains[trader].all(func(id: String) -> bool: return quests.is_completed(id)), "%s's intro chain is complete (%s)" % [trader, str(chains[trader])])


## What a hand-in objective asks for, put in the stash (found in raid when it must be).
func _give_for(entry: Dictionary) -> void:
	if str(entry.get("type", "")) == "roubles":
		gs.roubles += int(entry.count)
		return
	for i in int(entry.get("count", 1)):
		var piece: RefCounted = item(str(entry.item))
		piece.fir = bool(entry.get("fir", false))
		gs.stash.add(piece)


## Builds the stations and collects the crafts a quest asks for at the hideout.
func _hideout_work(quest: Dictionary) -> void:
	var hideout: GDScript = load("res://scripts/progression/hideout.gd")
	var work: GDScript = load("res://scripts/progression/hideout_work.gd")
	for entry: Dictionary in quest.objectives:
		match str(entry.get("type", "")):
			"upgrade":
				gs.hideout[str(entry.station)] = maxi(int(gs.hideout.get(str(entry.station), 0)), int(entry.level))
			"craft":
				var found: Dictionary = quests.find_recipe(str(entry.recipe))
				var station := str(found.station)
				gs.hideout[station] = maxi(int(gs.hideout.get(station, 0)), int(found.level))
				var ready := []
				for i in int(entry.get("count", 1)):
					ready.append({"id": str(entry.recipe), "output": found.recipe.output.duplicate()})
				gs.hideout_state.ready = {station: ready}
				var count := ready.size()
				check(work.collect(hideout.find(station)) == "", "%s: %d %s collected at the %s" % [quest.name, count, entry.recipe, station])


## The live raids `open`'s objectives need on `map_id`: one for the kills, visits and placements, out
## through the extract an objective names (one raid per named extract).
func _raids_on(map_id: String, open: Array[Dictionary]) -> void:
	var work := []  # [quest, index] of raid objectives on this map.
	var exits := {}
	for quest in open:
		for i in quest.objectives.size():
			var entry: Dictionary = quest.objectives[i]
			var type: String = quests.objective_type(quest, i)
			if not type in quests.RAID_TYPES or str(entry.get("map", map_id)) != map_id or quests.progress(quest, i) >= quests.objective_count(quest, i):
				continue
			if not entry.has("map") and map_id != "test_yard":
				continue  # Map-less raid objectives are done on the Test Yard.
			work.append([quest, i])
			if type == "extract" and entry.has("extract"):
				exits[str(entry.extract)] = true
	if work.is_empty():
		return
	if exits.is_empty():
		exits[DEFAULT_EXTRACT[map_id]] = true
	var first := true
	for exit: String in exits:
		await _raid(map_id, work if first else [], exit)
		first = false


func _raid(map_id: String, work: Array, exit: String) -> void:
	var loadout: RefCounted = gs.pmc_loadout()
	loadout.unequip("backpack")
	loadout.equip("backpack", item("raid_pack"))
	var boss := false
	for pair: Array in work:
		var entry: Dictionary = pair[0].objectives[pair[1]]
		match quests.objective_type(pair[0], pair[1]):
			"place", "mark":
				var carried := false
				for each: RefCounted in gs.stash.all_items().duplicate():
					if each.data.id == quests.place_item(pair[0], pair[1]) and not carried:
						gs.stash.remove(each)
						loadout.add(each)
						carried = true
				if not carried:
					loadout.add(item(quests.place_item(pair[0], pair[1]), int(entry.get("count", 1))))
			"extract_with":
				for i in int(entry.count):
					var piece: RefCounted = item(str(entry.item))
					piece.fir = bool(entry.get("fir", false))
					loadout.add(piece)
			"kill":
				boss = boss or str(entry.get("target", "")) in ["boss", "guard"] or entry.has("boss")
	if exit == "signal_point":
		loadout.add(item("signal_flare"))
	gs.raid = {"side": "pmc", "map": map_id, "loadout": loadout, "seed": 4, "boss": boss, "pmcs": 0}
	paused = false  # The last raid's summary paused the tree; leaving it unpauses, as the result screen does.
	change_scene_to_file(load("res://scripts/data/map_info.gd").find(map_id).scene_path)
	await frames(3)
	var controller: Node = root.get_tree().get_first_node_in_group("raid_controller")
	controller.next_wave = -1.0
	for bot: Node in root.get_tree().get_nodes_in_group("bots"):
		bot.ai_enabled = false
	var player: Node = controller.player
	for pair: Array in work:
		var quest: Dictionary = pair[0]
		var index: int = pair[1]
		var entry: Dictionary = quest.objectives[index]
		match quests.objective_type(quest, index):
			"kill":
				for i in int(entry.count):
					_kill_for(controller, entry)
			"visit":
				var place: Dictionary = controller.quest_raid.place_of(quest, index, root.get_tree())
				player.global_position = place.position
				await wait(0.4)
			"place", "mark":
				var sites := root.get_tree().get_nodes_in_group("quest_sites").filter(func(site: Node) -> bool: return site.quest.id == quest.id and site.index == index)
				for site: Node in sites:
					player.global_position = site.global_position
					await wait(0.2)
					site.interact(player)
					Input.action_press("interact")
					await wait(float(entry.get("seconds", quests.PLACE_SECONDS)) + 0.4)
					Input.action_release("interact")
					await wait(0.1)
	controller.xp = 1000  # Not a Run Through.
	var zone: Node = root.get_tree().get_nodes_in_group("extract_zones").filter(func(each: Node) -> bool: return each.extract_id == exit)[0]
	player.global_position = zone.global_position
	await wait(0.3)
	if zone.needs_flare:
		zone.interact(player)  # Fires the signal flare.
	var waited := 0.0
	while controller.outcome == null and waited < 15.0:
		await wait(0.5)
		waited += 0.5
	check(controller.outcome != null and controller.outcome.status == status.SURVIVED, "out of %s through %s" % [map_id, exit])


## One kill that fits `entry`: a boss or guard of the raid, else a Scav or PMC brought next to the
## player (far enough for a distance), hit where the objective asks.
func _kill_for(controller: Node, entry: Dictionary) -> void:
	var player: Node = controller.player
	var target := str(entry.get("target", "boss" if entry.has("boss") else "scav"))
	var bot: Node = null
	if target in ["boss", "guard"]:
		var found := root.get_tree().get_nodes_in_group("bots").filter(func(each: Node) -> bool: return not each.is_dead and String(each.role) == target)
		bot = found[0] if not found.is_empty() else null
	else:
		bot = load("res://scenes/actors/bot.tscn").instantiate()
		bot.profile = load("res://data/bots/pmc.tres" if target == "pmc" else "res://data/bots/scav.tres")
		controller.add_child(bot)
		bot.side = bot.Side.PMC if target == "pmc" else bot.Side.SCAV
		if target == "pmc":
			bot.faction = StringName(str(entry.get("faction", "usec")))
		bot.ai_enabled = false
		bot.global_position = player.global_position + Vector3(float(entry.get("min_distance", 0.0)) + 3.0, 0, 0)
	if bot == null:
		check(false, "a %s to kill for %s" % [target, str(entry)])
		return
	var part: int = quests.BODY_PARTS.get(str(entry.get("body_part", "thorax")), [1])[0]
	var hit: Dictionary = bot.take_blow(100000.0, player, "melee", "Test", bot.chest_point())
	hit.part = part
	player.on_hit_landed(bot, 100000.0, bot.chest_point(), hit)
