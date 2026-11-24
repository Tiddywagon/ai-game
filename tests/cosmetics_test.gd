extends "res://tests/test_base.gd"
## Drip, the cosmetic slot machine and skins (DESIGN.md §6.7; plan E15): the data files and their checks,
## Drip earned through real events (extracts by loot value, kills, Scav runs, practice paying nothing,
## quests, daily and weekly tasks, levels), the odds over many seeded spins, pity at 80, the ten-spin
## price, the free daily spin, no re-roll on reload, duplicates and better wear, seasons by date,
## applying / removing / what fits, skins lost with an item unless bound, skins back before a sale,
## barter, hand-in or listing, no stat ever changing, the save round trip and older saves, the one money
## sign, and the tables in DESIGN.md.

const DAY := 86400.0
## 2026-11-24 12:00 UTC: the clock the suite runs on (the Scorched Earth season, 13 days left).
const NOW := 1795521600.0

var skins: GDScript
var cos: GDScript
var outcome_script: GDScript
var quests: GDScript
var ops: GDScript
var work: GDScript
var figs: GDScript


func run() -> void:
	skins = load("res://scripts/data/skin_table.gd")
	cos = load("res://scripts/progression/cosmetics.gd")
	outcome_script = load("res://scripts/raid/raid_outcome.gd")
	quests = load("res://scripts/progression/quest_log.gd")
	ops = load("res://scripts/progression/operations.gd")
	work = load("res://scripts/progression/hideout_work.gd")
	figs = load("res://scripts/progression/figures.gd")
	work.now_override = NOW
	_data()
	_broken()
	_earning()
	_odds()
	_pity_and_prices()
	_free_spins()
	_no_reroll()
	_duplicates()
	_seasons()
	_applying()
	_lost_in_raid()
	_given_back()
	_no_stats()
	_saves()
	_money_sign()
	work.now_override = -1.0


## A new BEAR (USEC: `faction` 1) profile on the suite's clock, with skin roll seed `seed`.
func _profile(seed := 11, faction := 0) -> void:
	work.now_override = NOW
	gs.raid = {}
	fresh_profile(faction)
	gs.cosmetics = cos.blank(seed)


func _data() -> void:
	section("The skins and the machine's files")
	skins.reload()
	check(skins.problems().is_empty(), "no problems (%s)" % str(skins.problems().slice(0, 3)))
	var core := 0
	var kinds := {}
	var rarities := {}
	for collection: Dictionary in skins.collections():
		if not collection.season:
			core += collection.skins.size()
		for skin: Dictionary in collection.skins:
			kinds[skin.kind] = int(kinds.get(skin.kind, 0)) + 1
			rarities[skin.rarity] = int(rarities.get(skin.rarity, 0)) + 1
	var seasons: Array = skins.collections().filter(func(each: Dictionary) -> bool: return each.season)
	check(core >= 85 and core <= 100, "about 90 skins in the core collection (%d)" % core)
	check(seasons.size() == 3 and seasons.all(func(each: Dictionary) -> bool: return each.skins.size() >= 10 and each.skins.size() <= 14),
		"three seasonal collections of about 12 (%s)" % str(seasons.map(func(each: Dictionary) -> int: return each.skins.size())))
	check(skins.KINDS.all(func(kind: String) -> bool: return int(kinds.get(kind, 0)) > 0), "every kind has skins: %s" % str(kinds))
	check(int(rarities.get("legendary", 0)) <= 8 and int(rarities.get("legendary", 0)) < int(rarities.get("epic", 0)) and int(rarities.get("common", 0)) > int(rarities.get("rare", 0)),
		"Legendary ones are rare: %s" % str(rarities))
	var outfits: Array = skins.skins().filter(func(skin: Dictionary) -> bool: return skin.kind == "outfit")
	check(outfits.any(func(skin: Dictionary) -> bool: return skin.faction == "bear") and outfits.any(func(skin: Dictionary) -> bool: return skin.faction == "usec")
		and outfits.all(func(skin: Dictionary) -> bool: return skins.is_bound(skin)), "outfits for BEAR and USEC, all bound")
	var by_fit := {"weapon": 0, "class": 0, "universal": 0}
	for skin: Dictionary in skins.skins().filter(func(each: Dictionary) -> bool: return each.kind == "weapon"):
		by_fit["weapon" if skin.has("weapon") else "class" if skin.has("class") else "universal"] += 1
	check(by_fit.values().all(func(n: int) -> bool: return n > 0), "weapon skins for one gun, a class and every gun: %s" % str(by_fit))
	var odds: Array = skins.odds()
	check(is_equal_approx(odds[0], 0.52) and is_equal_approx(odds[1], 0.27) and is_equal_approx(odds[2], 0.13) and is_equal_approx(odds[3], 0.05)
		and is_equal_approx(odds[4], 0.024) and is_equal_approx(odds[5], 0.006), "the odds: 52 / 27 / 13 / 5 / 2.4 / 0.6 %")
	check(skins.price(1) == 100 and skins.price(10) == 900 and skins.pity_spins() == 80, "100 Drip a spin, 900 for ten, pity at 80")
	var bands: Array = skins.wear_bands()
	check(bands.map(func(band: Dictionary) -> String: return band.name) == ["Factory New", "Minimal Wear", "Field-Tested", "Well-Worn", "Battle-Scarred"],
		"five wear bands, Factory New to Battle-Scarred")
	check(skins.wear_name(0.01) == "Factory New" and skins.wear_name(0.2) == "Field-Tested" and skins.wear_name(0.99) == "Battle-Scarred", "wear names by value")
	check(skins.is_bound(skins.find("core_gold_leaf")) and skins.is_bound(skins.find("core_neon_vein")) and not skins.is_bound(skins.find("core_ash_camo"))
		and not skins.is_bound(skins.find("core_red_line")), "Epic and Legendary skins are bound, lower ones aren't")
	var ak: Resource = db.get_item("ak_74n")
	var mosin: Resource = db.get_item("mosin_rifle")
	check(skins.fits(skins.find("core_red_october"), ak) and not skins.fits(skins.find("core_red_october"), mosin), "a one-gun skin fits only that gun")
	check(skins.fits(skins.find("core_patrol_green"), ak) and not skins.fits(skins.find("core_patrol_green"), mosin), "a class skin fits its class")
	check(skins.fits(skins.find("core_ash_camo"), ak) and skins.fits(skins.find("core_ash_camo"), mosin) and not skins.fits(skins.find("core_ash_camo"), db.get_item("paca_armor")),
		"a universal weapon skin fits every gun and no armor")
	check(skins.fits(skins.find("core_smiley"), ak) and skins.fits(skins.find("core_smiley"), db.get_item("paca_armor")) and not skins.fits(skins.find("core_smiley"), db.get_item("scav_vest")),
		"a sticker fits items with a sticker slot (a gun, armor), not a rig")
	check(skins.fits(skins.find("core_rabbit_foot"), ak) and skins.fits(skins.find("core_rabbit_foot"), db.get_item("raid_pack")) and not skins.fits(skins.find("core_rabbit_foot"), db.get_item("paca_armor")),
		"a charm fits a gun or a backpack, not armor")
	check(skins.fits(skins.find("core_bone_handle"), db.get_item("hatchet")) and not skins.fits(skins.find("core_taiga_fatigues"), ak), "a knife skin fits the hatchet; an outfit no item")
	check(skins.item_slots(db.get_item("bandage")).is_empty(), "a bandage takes no skin")


## Broken copies of the files: each fault is named.
func _broken() -> void:
	section("Broken files are caught")
	var config: Dictionary = skins.config().duplicate(true)
	config.odds.common = 0.6
	config.wear.pop_back()
	config.seasons.order.append("nowhere")
	config.price = 0
	var broken_slots := "user://broken_slots.json"
	_write(broken_slots, JSON.stringify(config))
	var dir := "user://broken_skins"
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir + "/a.json", JSON.stringify({"collection": {"id": "core", "name": "Core"}, "skins": [
		{"id": "x", "name": "X", "rarity": "mythic", "kind": "weapon", "look": {"base": "#000000", "accent": "#ffffff", "pattern": "solid"}},
		{"id": "x", "name": "X2", "rarity": "common", "kind": "hat", "look": {"base": "#000000", "accent": "#ffffff", "pattern": "plaid"}},
		{"id": "y", "name": "Y", "rarity": "common", "kind": "weapon", "weapon": "bandage", "look": {"base": "nope", "accent": "#ffffff", "pattern": "solid"}},
		{"id": "z", "name": "Z", "rarity": "rare", "kind": "outfit", "look": {"base": "#000000", "accent": "#ffffff", "pattern": "solid"}}]}))
	skins.slots_path = broken_slots
	skins.dir = dir
	var found: Array = skins.problems()
	var text := "\n".join(found)
	for fault: String in ["mythic", "used twice", "kind hat", "pattern", "bandage isn't a gun", "colours", "an outfit fits a faction", "odds add up",
			"five wear bands", "season nowhere", "price above 0", "no epic skin"]:
		check(fault in text, "caught: %s" % fault)
	skins.slots_path = skins.SLOTS_PATH
	skins.dir = skins.DIR
	skins.reload()
	check(skins.problems().is_empty(), "the real files again: no problems")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## An inventory like the player's at the end of a raid, carrying `loot` (found this raid) in the pockets.
func _carrying(loot: Array) -> RefCounted:
	var inventory: RefCounted = gs.inventory.duplicate_deep()
	for each: RefCounted in loot:
		each.fir_pending = true
		inventory.pockets.add(each)
	return inventory


func _settle(end: int, side: String, inventory: RefCounted, kill_list: Array, to_profile := true, tricks := {}) -> RefCounted:
	return outcome_script.settle(end, side, inventory, 900.0, 0, kill_list.size(), to_profile, tricks, {"kill_list": kill_list, "map": "test_yard"})


func _earning() -> void:
	section("Drip earned")
	_profile()
	var start: int = gs.drip
	var chain: RefCounted = item("gold_chain")
	var loot := [chain]
	var value: int = chain.data.base_value
	var due: Vector2i = skins.extract_drip(value)
	var kills := [{"side": "scav"}, {"side": "pmc", "faction": "usec"}, {"side": "scav", "role": "boss", "name": "Boss"}, {"side": "scav", "role": "guard"}]
	var outcome: RefCounted = _settle(outcome_script.Status.SURVIVED, "pmc", _carrying(loot), kills)
	var kill_drip: int = skins.kill_drip("scav") + skins.kill_drip("pmc") + skins.kill_drip("boss") + skins.kill_drip("guard")
	check(kill_drip == 3 + 15 + 50 + 8, "kills: 3 a Scav, 15 a PMC, 50 a boss, 8 a guard")
	check(gs.drip - start == due.x + due.y + kill_drip and outcome.drip_total() == gs.drip - start,
		"getting out with %d roubles of loot and four kills: %d (base %d, loot %d, kills %d)" % [value, gs.drip - start, due.x, due.y, kill_drip])
	check(skins.extract_drip(0) == Vector2i(20, 0) and skins.extract_drip(100000) == Vector2i(20, 25) and skins.extract_drip(1500000) == Vector2i(20, 100),
		"bigger loot pays more: 20 + 0 / 25 / 100")
	check("extract 20" in outcome.drip_text() and "kills %d" % kill_drip in outcome.drip_text(), "the summary's line: %s" % outcome.drip_text())
	var rich := [item("bitcoin")]
	var rich_value: int = rich[0].data.base_value
	start = gs.drip
	_settle(outcome_script.Status.SURVIVED, "pmc", _carrying(rich), [])
	check(gs.drip - start == skins.extract_drip(rich_value).x + skins.extract_drip(rich_value).y and skins.extract_drip(rich_value).y > due.y,
		"more loot (a bitcoin, %d roubles) pays more: %d" % [rich_value, gs.drip - start])
	start = gs.drip
	_settle(outcome_script.Status.RUN_THROUGH, "pmc", _carrying([item("bolts")]), [{"side": "scav"}])
	check(gs.drip - start == skins.kill_drip("scav"), "a Run Through pays the kills, not the extract")
	start = gs.drip
	_settle(outcome_script.Status.KILLED, "pmc", _carrying([item("bolts")]), [{"side": "pmc", "faction": "usec"}])
	check(gs.drip - start == skins.kill_drip("pmc"), "killed: the kills only")
	start = gs.drip
	var scav_kit: RefCounted = load("res://scripts/inventory/inventory.gd").new()
	var scav_loot: RefCounted = item("bolts")
	scav_loot.fir_pending = true
	scav_kit.pockets.add(scav_loot)
	_settle(outcome_script.Status.SURVIVED, "scav", scav_kit, [{"side": "pmc", "faction": "usec"}])
	var scav_due: Vector2i = skins.extract_drip(scav_loot.data.base_value)
	check(gs.drip - start == scav_due.x + scav_due.y + skins.kill_drip("pmc"), "a Scav run pays for getting out and the kills too (%d)" % (gs.drip - start))
	start = gs.drip
	_settle(outcome_script.Status.SURVIVED, "pmc", _carrying([item("bolts")]), [{"side": "scav"}], false, {"drip": 25})
	check(gs.drip == start, "practice (nothing goes to the profile) pays nothing")
	start = gs.drip
	_settle(outcome_script.Status.SURVIVED, "pmc", _carrying([]), [], true, {"hits": 2, "kills": [{"side": "scav", "weapon_class": "bolt_action"}], "drip": 25})
	check(gs.drip - start == 25 + skins.extract_drip(0).x, "trick shots as before (25) plus the extract")

	section("Drip from quests, tasks and levels")
	_profile()
	start = gs.drip
	var level: int = gs.level
	gs.add_xp(load("res://scripts/progression/progression.gd").xp_for_level(level + 2) - gs.xp)
	check(gs.level == level + 2 and gs.drip - start == 2 * skins.level_drip() and skins.level_drip() == 50, "two levels gained: 2 × 50 Drip")
	_profile()
	var quest: Dictionary = quests.find("scrap_run")
	quests.accept(quest)
	for i in quest.objectives.size():
		gs.quests[quest.id].progress[i] = quests.objective_count(quest, i)
	start = gs.drip
	level = gs.level
	check(quests.complete(quest) == "", "a quest completed")
	check(gs.drip - start == int(quest.get("rewards", {}).get("drip", 0)) + skins.quest_drip() + skins.level_drip() * (gs.level - level) and skins.quest_drip() == 25,
		"it pays 25 Drip on top of its own (%d)" % (gs.drip - start))
	check(quests.reward_lines(quest).has("%d Drip" % (int(quest.get("rewards", {}).get("drip", 0)) + skins.quest_drip())), "and its reward lines say so: %s" % str(quests.reward_lines(quest)))
	ops.now_override = NOW
	_profile()
	gs.operations = ops.blank(5)
	ops.update()
	var task: Dictionary = ops.tasks("daily")[0]
	task.progress = [quests.objective_count(task, 0)]
	start = gs.drip
	level = gs.level
	check(ops.claim(task) == "" and gs.drip - start == 15 + skins.level_drip() * (gs.level - level), "a daily task claimed pays 15 Drip")
	var weekly: Dictionary = ops.tasks("weekly")[0]
	weekly.progress = [quests.objective_count(weekly, 0)]
	start = gs.drip
	level = gs.level
	check(ops.claim(weekly) == "" and gs.drip - start == 60 + skins.level_drip() * (gs.level - level), "a weekly 60")
	check(ops.reward_lines(weekly).has("60 Drip"), "shown on the board: %s" % str(ops.reward_lines(weekly)))
	ops.now_override = -1.0


## A list of the rolls `from` to `to` (exclusive) would give, with no pity and the suite's clock.
func _rolls(from: int, to: int) -> Array:
	var result := []
	for number in range(from, to):
		result.append(cos.roll(number, 0, NOW))
	return result


func _odds() -> void:
	section("The odds over 20,000 seeded rolls")
	_profile(21)
	var counts := [0, 0, 0, 0, 0, 0]
	var seasonal := {}
	var core_ids := {}
	for skin: Dictionary in skins.collection("core").skins:
		core_ids[skin.id] = true
	var rolls := _rolls(0, 20000)
	for result: Dictionary in rolls:
		counts[int(result.rarity)] += 1
		var collection: String = skins.find(result.skin).collection
		if collection != "core":
			seasonal[collection] = int(seasonal.get(collection, 0)) + 1
	var odds: Array = skins.odds()
	var near := true
	for index in 6:
		var share := float(counts[index]) / rolls.size()
		var allowed := maxf(odds[index] * 0.15, 0.0025)
		near = near and absf(share - odds[index]) <= allowed
	check(near, "each rarity within 15%% of its odds: %s" % str(counts.map(func(n: int) -> String: return "%.2f%%" % (100.0 * n / rolls.size()))))
	check(seasonal.keys() == ["scorched_earth"], "the season in the machine (Scorched Earth on 24 November 2026) is the only seasonal one rolled: %s" % str(seasonal))
	check(_rolls(0, 50) == _rolls(0, 50), "the same roll numbers roll the same")
	gs.cosmetics = cos.blank(22)
	check(_rolls(0, 50) != rolls.slice(0, 50), "another seed rolls differently")
	var wear_counts := [0, 0, 0, 0, 0]
	for result: Dictionary in rolls:
		wear_counts[skins.wear_band(result.wear)] += 1
	var bands: Array = skins.wear_bands()
	var wear_ok := true
	for index in 5:
		wear_ok = wear_ok and absf(float(wear_counts[index]) / rolls.size() - bands[index].chance) <= 0.015
	check(wear_ok, "wear bands by their chances (10 / 22 / 38 / 17 / 13 %%): %s" % str(wear_counts))
	check(rolls.all(func(result: Dictionary) -> bool: return result.wear >= 0.0 and result.wear <= 1.0), "wear between 0 and 1")
	var teased: Array = rolls.filter(func(result: Dictionary) -> bool: return result.near_miss)
	check(not teased.is_empty() and teased.all(func(result: Dictionary) -> bool: return int(result.rarity) < 3), "near misses only on results below Ultra Rare (%d)" % teased.size())


func _pity_and_prices() -> void:
	section("Pity at 80, prices")
	_profile(5)
	gs.cosmetics.pity = 79
	var forced: Dictionary = cos.roll(0, 79, NOW)
	check(int(forced.rarity) >= 4 and forced.pity, "the 80th spin without an Epic is at least Epic (%s)" % forced.skin)
	check(int(cos.roll(0, 78, NOW).rarity) == int(cos.roll(0, 0, NOW).rarity), "the 79th isn't forced")
	gs.drip = 1000000
	var longest := 0
	var run := 0
	var epics := 0
	for i in 100:
		for result: Dictionary in cos.spin(10):
			if int(result.rarity) >= 4:
				epics += 1
				run = 0
			else:
				run += 1
				longest = maxi(longest, run)
	check(longest <= 79 and epics > 0, "1,000 spins: never 80 in a row without an Epic or better (longest %d, %d Epic+)" % [longest, epics])
	check(int(gs.cosmetics.pity) == run and cos.pity_left() == 80 - run, "the counter is saved with the profile: %d (Epic or better within %d)" % [gs.cosmetics.pity, cos.pity_left()])
	check(int(gs.cosmetics.spins) == 1000 and int(gs.cosmetics.rolls) == 1000, "1,000 spins counted")
	_profile(6)
	gs.drip = 1000
	var results: Array = cos.spin(10)
	var back := 0
	for result: Dictionary in results:
		back += int(result.drip)
	check(results.size() == 10 and gs.drip == 1000 - 900 + back, "ten spins for 900 Drip (%d paid back for duplicates)" % back)
	var before: int = gs.drip
	results = cos.spin(1)
	check(results.size() == 1 and gs.drip == before - 100 + int(results[0].drip), "one spin for 100")
	gs.drip = 99
	check(cos.spin_block_reason(1) != "" and cos.spin(1).is_empty() and gs.drip == 99, "99 Drip doesn't spin")
	gs.drip = 899
	check(cos.spin(10).is_empty() and gs.drip == 899, "899 doesn't spin ten")
	check(cos.spin(3).is_empty(), "only one or ten at a time")


func _free_spins() -> void:
	section("The Oddities set's free spin a day")
	_profile(7)
	gs.drip = 0
	check(figs.free_spins_left() == 0 and cos.spin_block_reason(1, true) != "", "no Oddities set: no free spin")
	gs.hideout[load("res://scripts/data/figure_table.gd").station_id()] = 3
	for data: Resource in load("res://scripts/data/figure_table.gd").in_set("oddities"):
		var figure: RefCounted = item(data.id)
		gs.stash.add(figure)
		figs.place(figure, figs.free_slot())
	check(figs.free_spins_left() == 1, "the Oddities set on display: one free spin today")
	var results: Array = cos.spin(1, true)
	check(results.size() == 1 and results[0].free and gs.drip == int(results[0].drip), "a free spin costs no Drip")
	check(figs.free_spins_left() == 0 and cos.spin(1, true).is_empty(), "one a day")
	work.now_override = NOW + DAY
	check(figs.free_spins_left() == 1, "the next day, another")
	work.now_override = NOW


func _no_reroll() -> void:
	section("A spin is saved before the reels move: no re-roll")
	_profile(8)
	gs.drip = 500
	sm.save_game()
	var before := FileAccess.get_file_as_string(sm.SAVE_PATH)
	var first: Dictionary = cos.spin(1)[0]
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sm.SAVE_PATH))
	check(saved.profile.cosmetics.owned.has(first.skin) and int(saved.profile.drip) == gs.drip and saved.profile.cosmetics.last[0].skin == first.skin,
		"the save already has the skin, the Drip paid and the result (%s)" % first.skin)
	check(sm.load_game() and gs.cosmetics.owned.has(first.skin) and int(gs.cosmetics.rolls) == 1, "loading it keeps the skin")
	var file := FileAccess.open(sm.SAVE_PATH, FileAccess.WRITE)
	file.store_string(before)
	file.close()
	sm.load_game()
	check(not gs.cosmetics.owned.has(first.skin) or skins.find(first.skin).is_empty(), "the save from before the spin has no skin")
	var again: Dictionary = cos.spin(1)[0]
	check(again.skin == first.skin and is_equal_approx(again.wear, first.wear), "spinning again from it rolls the very same skin and wear")


func _duplicates() -> void:
	section("Duplicates pay Drip back, and lend a better wear")
	_profile(9)
	var result: Dictionary = cos.roll(0, 0, NOW)
	gs.cosmetics.owned[result.skin] = minf(result.wear + 0.2, 1.0)
	gs.drip = 100
	var got: Dictionary = cos.spin(1)[0]
	var refund: int = skins.duplicate_drip(int(got.rarity))
	check(got.skin == result.skin and got.duplicate and got.drip == refund and gs.drip == refund, "rolling a skin you own: %d Drip back, no second copy" % refund)
	check(got.better and is_equal_approx(cos.wear_of(result.skin), got.wear), "its better wear (%.3f) replaces yours" % got.wear)
	check([10, 20, 40, 80, 200, 500] == range(6).map(func(index: int) -> int: return skins.duplicate_drip(index)), "duplicates: 10 / 20 / 40 / 80 / 200 / 500 by rarity")
	_profile(9)
	var gun: RefCounted = gs.inventory.equipment.get("primary")
	var fitting := ""
	for number in 400:
		var roll: Dictionary = cos.roll(number, 0, NOW)
		if skins.find(roll.skin).kind == "weapon" and skins.fits(skins.find(roll.skin), gun.data):
			fitting = roll.skin
			gs.cosmetics.rolls = number
			gs.cosmetics.owned[fitting] = 0.99
			check(cos.apply(fitting, gun) == "", "a skin that roll %d gives is on the worn gun" % number)
			break
	gs.drip = 100
	var dupe: Dictionary = cos.spin(1)[0]
	check(dupe.skin == fitting and dupe.duplicate and is_equal_approx(gun.cosmetics.skin.wear, dupe.wear) and is_equal_approx(gs.cosmetics.applied[fitting], dupe.wear),
		"one on an item counts as owned, and the item's skin takes the better wear")
	var worse: Dictionary = cos.roll(0, 0, NOW)
	gs.cosmetics.owned[worse.skin] = 0.0
	gs.cosmetics.rolls = 0
	gs.drip = 100
	var no_better: Dictionary = cos.spin(1)[0]
	check(not no_better.better and cos.wear_of(worse.skin) == 0.0, "a worse wear changes nothing")


func _seasons() -> void:
	section("Seasons by date")
	check(skins.season_at(NOW) == "scorched_earth", "24 November 2026: Scorched Earth")
	var ends: float = skins.season_ends(NOW)
	check(is_equal_approx((ends - NOW) / DAY, 12.5), "ends in 12 days 12 hours (%.1f days)" % ((ends - NOW) / DAY))
	check(skins.season_at(ends) == "frostbite" and skins.season_at(ends + 28 * DAY) == "neon_nights" and skins.season_at(ends + 56 * DAY) == "scorched_earth",
		"then Frostbite, Neon Nights, and round again")
	check(skins.season_at(ends - 1.0) == "scorched_earth", "changing on a fixed calendar (UTC midnight)")
	check(is_equal_approx(skins.season_next("frostbite", NOW), ends) and skins.season_next("scorched_earth", NOW) == NOW, "when each is next in the machine")
	check(skins.season_at(Time.get_unix_time_from_datetime_string("2026-01-05T00:00:00")) == "frostbite", "the rotation starts on 5 January 2026")
	_profile(30)
	var later := []
	for number in 4000:
		later.append(cos.roll(number, 0, ends + 1.0))
	var collections := {}
	for result: Dictionary in later:
		collections[skins.find(result.skin).collection] = true
	check(collections.has("frostbite") and not collections.has("scorched_earth"), "the next season's skins in the machine once it changes: %s" % str(collections.keys()))


func _applying() -> void:
	section("Applying, removing, what fits")
	_profile(12)
	var gun: RefCounted = gs.inventory.equipment.get("primary")
	var armor: RefCounted = gs.inventory.equipment.get("armor")
	for id in ["core_ash_camo", "core_tiger_lines", "core_smiley", "core_rabbit_foot", "core_flecktarn", "core_red_october", "core_tsarina", "core_taiga_fatigues", "core_coyote_combat"]:
		gs.cosmetics.owned[id] = 0.2
	check(cos.apply("core_tsarina", gun) != "" and cos.in_collection("core_tsarina"), "a Mosin skin doesn't go on the AK")
	check(cos.apply("core_flecktarn", gun) != "", "an armor skin doesn't go on a gun")
	check(cos.apply("core_ash_camo", gun) == "" and gun.cosmetics.skin.id == "core_ash_camo" and not cos.in_collection("core_ash_camo") and cos.owns("core_ash_camo"),
		"Ash Camo on the AK: off the collection, still yours")
	check(cos.apply("core_ash_camo", armor) != "", "a skin on one item can't go on another too")
	check(cos.apply("core_red_october", gun) == "" and gun.cosmetics.skin.id == "core_red_october" and cos.in_collection("core_ash_camo"),
		"another skin on the same slot: the first back to the collection")
	check(cos.apply("core_smiley", gun) == "" and cos.apply("core_rabbit_foot", gun) == "" and gun.cosmetics.size() == 3, "a sticker and a charm on their own slots")
	check(cos.apply("core_flecktarn", armor) == "" and armor.cosmetics.skin.id == "core_flecktarn", "Flecktarn on the armor")
	check(cos.remove(gun, "sticker") == "" and cos.in_collection("core_smiley") and not gun.cosmetics.has("sticker"), "REMOVE puts the sticker back")
	check(cos.remove(gun, "sticker") != "", "nothing to remove twice")
	var copy: RefCounted = load(ITEM).from_dict(gun.to_dict())
	check(copy.cosmetics == gun.cosmetics, "the skins are saved with the item")
	var stranger: RefCounted = item("ak_74n")
	check(cos.apply("core_ash_camo", stranger) == "Only on your own items", "only on your own items")
	check(cos.wear_outfit("core_taiga_fatigues") == "" and cos.outfit() == "core_taiga_fatigues" and cos.in_collection("core_taiga_fatigues"),
		"a BEAR outfit on a BEAR, still in the collection")
	check(cos.wear_outfit("core_coyote_combat") != "" and cos.outfit() == "core_taiga_fatigues", "a USEC outfit doesn't go on a BEAR")
	check(cos.wear_outfit("") == "" and cos.outfit() == "", "back to the plain uniform")
	check(cos.apply("core_taiga_fatigues", gun) != "", "an outfit goes on no item")


func _skinned_kit() -> Dictionary:
	_profile(13)
	var gun: RefCounted = gs.inventory.equipment.get("primary")
	var armor: RefCounted = gs.inventory.equipment.get("armor")
	for id in ["core_ash_camo", "core_flecktarn", "core_gold_leaf", "core_smiley"]:
		gs.cosmetics.owned[id] = 0.1
	cos.apply("core_ash_camo", gun)  # Common: not bound.
	cos.apply("core_smiley", gun)
	cos.apply("core_flecktarn", armor)
	return {"gun": gun, "armor": armor}


func _lost_in_raid() -> void:
	section("Lost with the item, unless bound")
	var kit := _skinned_kit()
	gs.cosmetics.owned["core_neon_vein"] = 0.3
	cos.remove(kit.armor, "skin")
	cos.apply("core_gold_leaf", kit.gun)  # Legendary on the gun: bound. Ash Camo back to the collection.
	cos.apply("core_flecktarn", kit.armor)
	var raid_inventory: RefCounted = gs.inventory.duplicate_deep()
	var outcome: RefCounted = _settle(outcome_script.Status.KILLED, "pmc", raid_inventory, [])
	check(not cos.owns("core_flecktarn") and not cos.owns("core_smiley"), "killed: the armor's Flecktarn and the gun's sticker are lost with them")
	check(cos.in_collection("core_gold_leaf"), "the gun's bound Gold Leaf is back in the collection, to put on again")
	check(cos.in_collection("core_ash_camo") and cos.in_collection("core_neon_vein"), "skins in the collection were never at risk")
	check(outcome.skins_lost.size() == 2 and outcome.skins_returned == ["core_gold_leaf"], "the summary names them: lost %s, back %s" % [outcome.skins_lost, outcome.skins_returned])
	kit = _skinned_kit()
	kit.armor.insured = true
	raid_inventory = gs.inventory.duplicate_deep()
	outcome = _settle(outcome_script.Status.MIA, "pmc", raid_inventory, [])
	check(cos.owns("core_flecktarn") and not cos.in_collection("core_flecktarn") and not cos.owns("core_ash_camo"),
		"insured armor on its way back keeps its skin; the uninsured gun's is lost")
	kit = _skinned_kit()
	raid_inventory = gs.inventory.duplicate_deep()
	var dropped: RefCounted = raid_inventory.unequip("primary")
	check(dropped.cosmetics.has("skin"), "a gun dropped in the raid and left there")
	outcome = _settle(outcome_script.Status.SURVIVED, "pmc", raid_inventory, [])
	check(not cos.owns("core_ash_camo") and cos.owns("core_flecktarn"), "getting out without it: its skin is lost, the armor kept its own")
	kit = _skinned_kit()
	raid_inventory = gs.inventory.duplicate_deep()
	_settle(outcome_script.Status.SURVIVED, "pmc", raid_inventory, [])
	check(cos.owns("core_ash_camo") and gs.inventory.equipment.primary.cosmetics.skin.id == "core_ash_camo", "getting out with it: the skin stays on")
	kit = _skinned_kit()
	_settle(outcome_script.Status.KILLED, "scav", load("res://scripts/inventory/inventory.gd").new(), [])
	check(cos.owns("core_ash_camo") and cos.owns("core_flecktarn"), "a Scav run never touches your PMC's skins")
	gs.cosmetics.outfits.bear = "core_taiga_fatigues"
	gs.cosmetics.owned["core_taiga_fatigues"] = 0.1
	_settle(outcome_script.Status.KILLED, "pmc", gs.inventory.duplicate_deep(), [])
	check(cos.outfit() == "core_taiga_fatigues" and cos.in_collection("core_taiga_fatigues"), "an outfit is never lost")


func _given_back() -> void:
	section("Skins back to the collection before an item leaves")
	var kit := _skinned_kit()
	var gun: RefCounted = gs.inventory.unequip("primary")
	gs.stash.add(gun)
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	var trader := "bulat"
	check(selling.sell(trader, items([gun])) == "", "the skinned AK sold to Bulat")
	check(cos.in_collection("core_ash_camo") and cos.in_collection("core_smiley") and gun.cosmetics.is_empty(), "its skin and sticker are back first")
	var armor: RefCounted = gs.inventory.unequip("armor")
	gs.stash.add(armor)
	var search: GDScript = load("res://scripts/progression/item_search.gd")
	check(search.take(armor.data.id, 1, false) == 1 and cos.in_collection("core_flecktarn"), "bartered, handed in or used up (ItemSearch): the skin is back")
	_profile(14)
	var listed: RefCounted = gs.inventory.unequip("armor")
	for each: RefCounted in listed.all_items():
		each.fir = true
	gs.stash.add(listed)
	gs.cosmetics.owned["core_flecktarn"] = 0.1
	cos.apply("core_flecktarn", listed)
	var flea: GDScript = load("res://scripts/progression/flea_market.gd")
	gs.level = 30
	var price: int = flea.market_price(listed)
	var reason: String = flea.put_up(listed, price)
	check(reason == "" and cos.in_collection("core_flecktarn") and not gs.flea.listings[-1].item.has("cosmetics"), "listed on the flea market: back first (%s)" % reason)
	_profile(15)
	var lone: RefCounted = gs.inventory.equipment.get("primary")
	lone.cosmetics.skin = {"id": "core_ash_camo", "wear": 0.4}
	gs.cosmetics.applied["core_ash_camo"] = 0.4
	gs.inventory.unequip("primary")
	cos.reconcile(false)
	check(cos.in_collection("core_ash_camo"), "a skin whose item went some other way out of a raid is never lost: back to the collection")


## Every number of `entry` (an item) that the game shows or uses, with no cosmetics.
func _numbers(entry: RefCounted, gear: RefCounted) -> Dictionary:
	var saved: Dictionary = entry.to_dict()
	saved.erase("cosmetics")
	var result := {"saved": saved, "value": entry.value(), "weight": entry.weight(), "stats": entry.data.stats.duplicate(true)}
	var selling: GDScript = load("res://scripts/progression/selling.gd")
	for trader in ["bulat", "vera", "tinker", "mole"]:
		result["sells_to_" + trader] = selling.quote(trader, items([entry]))
	result.market = load("res://scripts/progression/flea_market.gd").market_price(entry)
	if entry.is_gun():
		var weapon_stats: GDScript = load("res://scripts/combat/weapon_stats.gd")
		var built: Resource = weapon_stats.build(entry)
		var props := {}
		for property: Dictionary in built.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				props[property.name] = built.get(property.name)
		result.weapon = props
		result.rows = weapon_stats.rows(entry)
	var config: Resource = load("res://data/config/inventory.tres")
	result.loadout = load("res://scripts/inventory/loadout_stats.gd").rows(gear, config)
	return result


func _no_stats() -> void:
	section("A skin changes no number")
	_profile(16)
	gs.level = 30
	var gear: RefCounted = gs.inventory
	var worn := ["primary", "armor", "helmet", "rig", "backpack", "melee"]
	for slot in ["helmet", "rig", "backpack", "melee"]:
		if gear.equipment.get(slot) == null:
			gear.equip(slot, item({"helmet": "zsh_helmet", "rig": "tactical_rig", "backpack": "pack_pilgrim", "melee": "hatchet"}[slot]))
	var plain := {}
	for slot in worn:
		plain[slot] = _numbers(gear.equipment[slot], gear)
	var dressed := 0
	for slot in worn:
		var target: RefCounted = gear.equipment[slot]
		for skin: Dictionary in skins.skins():
			if skins.fits(skin, target.data) and not target.cosmetics.has(skins.slot_of(skin)) and not cos.owns(skin.id):
				gs.cosmetics.owned[skin.id] = 0.95
				if cos.apply(skin.id, target) == "":
					dressed += 1
	check(dressed >= 10 and worn.all(func(slot: String) -> bool: return gear.equipment[slot].cosmetics.has("skin")), "every worn piece skinned (%d skins, stickers and charms)" % dressed)
	for slot in worn:
		var now := _numbers(gear.equipment[slot], gear)
		var same := true
		for key: String in plain[slot]:
			if str(plain[slot][key]) != str(now[key]):
				same = false
				print("    differs: %s %s" % [slot, key])
		check(same and now.keys() == plain[slot].keys(), "%s: every stat, price and loadout total the same skinned (%d groups compared)" % [slot, now.keys().size()])
	var wear_plain := _numbers(gear.equipment.primary, gear)
	gear.equipment.primary.cosmetics.skin.wear = 0.0
	check(str(_numbers(gear.equipment.primary, gear)) == str(wear_plain), "nor does the wear")


func _saves() -> void:
	section("Saved, and older saves")
	var kit := _skinned_kit()
	gs.cosmetics.pity = 33
	gs.cosmetics.rolls = 40
	gs.cosmetics.owned["core_taiga_fatigues"] = 0.12
	cos.wear_outfit("core_taiga_fatigues")
	gs.drip = 777
	var before: Dictionary = gs.cosmetics.duplicate(true)
	var data: Dictionary = gs.to_dict()
	gs.from_dict(JSON.parse_string(JSON.stringify(data)))
	check(gs.cosmetics.owned == before.owned and gs.cosmetics.applied == before.applied and int(gs.cosmetics.pity) == 33 and int(gs.cosmetics.rolls) == 40
		and gs.cosmetics.outfits == before.outfits and int(gs.cosmetics.seed) == int(before.seed) and gs.drip == 777, "collection, skins on items, pity, rolls, outfit and seed round trip")
	check(gs.inventory.equipment.primary.cosmetics.skin.id == "core_ash_camo" and gs.inventory.equipment.armor.cosmetics.skin.id == "core_flecktarn",
		"the skins are on the same items")
	var old: Dictionary = JSON.parse_string(JSON.stringify(data))
	old.version = 21
	old.profile.erase("cosmetics")
	gs.from_dict(old)
	check(gs.drip == 777 and gs.cosmetics.owned.has("core_ash_camo") == false and int(gs.cosmetics.rolls) == 0, "a version 21 save keeps its Drip and starts with an empty collection")
	var again: Dictionary = gs.cosmetics.duplicate(true)
	gs.from_dict(old)
	check(int(gs.cosmetics.seed) == int(again.seed), "seeded from the save itself: reloading it rolls the same")
	var gone: Dictionary = JSON.parse_string(JSON.stringify(data))
	gone.profile.cosmetics.owned["no_such_skin"] = 0.5
	gs.from_dict(gone)
	check(not gs.cosmetics.owned.has("no_such_skin"), "a skin that's gone is dropped")


func _money_sign() -> void:
	section("One money sign")
	var format: GDScript = load("res://scripts/ui/ui_format.gd")
	check(format.money(20000) == "RUB 20,000" and format.money(250, "USD") == "$ 250", "UiFormat.money(): RUB 20,000, $ 250")
	_profile()
	var lines: Array = quests.reward_lines(quests.find("scrap_run"))
	check(lines.has(format.money(25000)), "quest reward lines use it: %s" % str(lines))
	ops.now_override = NOW
	gs.operations = ops.blank(5)
	ops.update()
	check(ops.reward_lines(ops.tasks("daily")[0])[0].begins_with("RUB "), "task reward lines too: %s" % str(ops.reward_lines(ops.tasks("daily")[0])))
	ops.now_override = -1.0
	var found := []
	for path in _scripts("res://scripts"):
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			var code := line.strip_edges()
			if not code.begins_with("#") and "\u20bd" in code.split("##")[0]:
				found.append(path.get_file())
	check(found.is_empty(), "no script writes the rouble sign (₽) on screen: %s" % str(found))


func _scripts(dir: String) -> Array:
	var result := []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			result.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		result.append_array(_scripts(dir.path_join(sub)))
	return result
