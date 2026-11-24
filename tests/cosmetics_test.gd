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
