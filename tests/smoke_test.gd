extends "res://tests/test_base.gd"
## Smoke: the item database and every data validator, new profiles, and the save file (round trip,
## upgrade from version 8, a missing or corrupt file).

const VALIDATORS := {
	"Progression": "res://scripts/progression/progression.gd", "Selling": "res://scripts/progression/selling.gd",
	"Hideout": "res://scripts/progression/hideout.gd", "Trading": "res://scripts/progression/trading.gd",
	"LoadoutPlanner": "res://scripts/inventory/loadout_planner.gd", "ExtractTable": "res://scripts/data/extract_table.gd",
	"Factions": "res://scripts/data/factions.gd", "BossTable": "res://scripts/data/boss_table.gd",
	"BarterTable": "res://scripts/data/barter_table.gd", "PmcAi": "res://scripts/data/pmc_ai.gd",
	"PoiTable": "res://scripts/data/poi_table.gd", "TraderTable": "res://scripts/data/trader_table.gd",
	"ScavRuns": "res://scripts/raid/scav_runs.gd",
}


func run() -> void:
	_items()
	_validators()
	_new_profiles()
	_round_trip()
	_upgrade()
	_bad_files()


func _items() -> void:
	section("ItemDB")
	var all: Array = db.all_items()
	check(all.size() == 505, "505 items load (got %d)" % all.size())
	var ItemDataScript: GDScript = load("res://scripts/data/item_data.gd")
	var categories: int = ItemDataScript.Category.size()
	var bad_category := 0
	var bad_size := 0
	var unnamed := 0
	var ids := {}
	for data in all:
		ids[data.id] = true
		if data.category < 0 or data.category >= categories or data.category_name() == "":
			bad_category += 1
		if data.size.x < 1 or data.size.y < 1:
			bad_size += 1
		if data.id == "" or data.display_name == "" or data.max_stack < 1:
			unnamed += 1
	check(bad_category == 0, "every item has a category")
	check(bad_size == 0, "every item has a size of at least 1x1")
	check(unnamed == 0, "every item has an id, a name and a max stack")
	check(ids.size() == all.size(), "item ids are unique")
	check(db.has_item("bandage") and db.get_item("bandage").display_name != "", "get_item() finds the bandage")
	check(not db.has_item("no_such_item"), "has_item() is false for an unknown id")


func _validators() -> void:
	section("Data validators")
	for name: String in VALIDATORS:
		var problems: Array = Array(load(VALIDATORS[name]).problems())
		check(problems.is_empty(), "%s.problems() is empty%s" % [name, "" if problems.is_empty() else ": " + str(problems.slice(0, 3))])
	var kit_problems: Array = load("res://scripts/raid/scav_runs.gd").item_problems()
	check(kit_problems.is_empty(), "ScavRuns.item_problems() is empty")
	var groups: GDScript = load("res://scripts/data/item_groups.gd")
	var group_problems: Array = []
	for data in db.all_items():
		group_problems.append_array(Array(groups.problems(data)))
	check(group_problems.is_empty(), "ItemGroups.problems() is empty for every item%s" % ("" if group_problems.is_empty() else ": " + str(group_problems.slice(0, 3))))


func _new_profiles() -> void:
	section("New profiles")
	var kits := {gs.Faction.BEAR: ["ak_74n", "ammo_545_ps", "armor_module3m", "bulat"],
		gs.Faction.USEC: ["kestrel_ar", "ammo_556_fmj", "paca_armor", "tinker"]}
	for faction: int in kits:
		var kit: Array = kits[faction]
		var name: String = gs.Faction.find_key(faction)
		sm.delete_save()
		gs.new_profile(faction)
		var worn: Dictionary = gs.inventory.equipment
		check(gs.has_profile() and gs.level == 1 and gs.xp == 0, "%s: a level 1 profile" % name)
		check(gs.roubles == 500000 and gs.dollars == 0, "%s: 500,000 roubles, no dollars" % name)
		check(worn.primary != null and worn.primary.data.id == kit[0] and worn.primary.loaded_ammo == kit[1]
			and worn.primary.rounds_loaded() == 30, "%s: a %s loaded with 30 %s" % [name, kit[0], kit[1]])
		check(worn.armor != null and worn.armor.data.id == kit[2] and worn.secure != null
			and worn.secure.data.id == "secure_alpha", "%s: %s and the Alpha container worn" % [name, kit[2]])
		check(gs.inventory.pockets.count_of(kit[1]) == 60 and gs.inventory.pockets.count_of("bandage") == 1,
			"%s: 60 spare rounds and a bandage in the pockets" % name)
		check(gs.stash.count_of(kit[0]) == 1 and gs.stash.count_of(kit[1]) == 120 and gs.stash.items.size() == 16,
			"%s: the starter stash (a spare gun, 120 rounds, 16 items)" % name)
		check(gs.hideout == {"stash": 1} and gs.stash.size == Vector2i(10, 30), "%s: Stash station level 1, a 10x30 stash" % name)
		check(is_equal_approx(gs.trader_loyalty[kit[3]].reputation, 0.05), "%s: 0.05 starting reputation with %s" % [name, kit[3]])


func _round_trip() -> void:
	section("Save and load")
	check(sm.SAVE_VERSION == 14, "SAVE_VERSION is 14")
	sm.delete_save()
	gs.new_profile(gs.Faction.BEAR)
	var mods: GDScript = load("res://scripts/inventory/weapon_mods.gd")
	var gun: RefCounted = load("res://scripts/inventory/inventory.gd").loaded_gun("ak_74n", "ammo_545_ps", 87.5)
	mods.install(gun, "sight", item("red_dot"))
	gs.stash.add(gun)
	var pack := item("tourist_pack")
	pack.contents.add(item("ammo_545_ps", 40))
	pack.contents.add(item("bandage"))
	gs.stash.add(pack)
	var found := item("bolts")
	load("res://scripts/inventory/found_in_raid.gd").set_found(found, true)
	gs.stash.place(found, Vector2i(9, 29), false)
	var insured := item("paca_armor")
	check(load("res://scripts/progression/insurance.gd").insure([insured]) == "", "an item is insured")
	gs.stash.add(insured)
	var quests: GDScript = load("res://scripts/progression/quest_log.gd")
	gs.stash.add(item("duct_tape"))
	check(quests.accept(quests.find("textile")) and quests.hand_in(quests.find("textile"), 0) == 1, "a quest is accepted and partly handed in")
	check(load("res://scripts/inventory/loadout_presets.gd").add("Raid kit", gs.inventory) == "", "a loadout preset is saved")
	gs.inventory.equip("backpack", item("sling_bag"))
	gs.inventory.equipment.backpack.contents.add(item("water_bottle"))
	gs.add_xp(2500)
	gs.dollars = 321
	gs.scav_karma = 1.5
	load("res://scripts/progression/trading.gd").update_all_loyalty()  # Mole's level follows the karma.
	gs.explore("test_yard", "somewhere")
	gs.set_hotkey(0, "splint")
	gs.auto_equip = {"budget": 150000, "protect_legendary": true}

	var before: Dictionary = gs.to_dict()
	check(sm.save_game() and sm.has_save(), "save_game() writes the file")
	gs.new_profile(gs.Faction.USEC)
	check(_text(gs.to_dict()) != _text(before), "the profile in memory is replaced before loading")
	check(sm.load_game(), "load_game() reads it back")
	var after: Dictionary = gs.to_dict()
	check(_text(after) == _text(before), "the loaded profile's to_dict() is identical%s" % _difference(before, after, ""))
	var loaded_gun: RefCounted = null
	for each in gs.stash.items:
		if each.data.id == "ak_74n" and each.mods.has("sight"):
			loaded_gun = each
	check(loaded_gun != null and loaded_gun.mods.sight.data.id == "red_dot" and loaded_gun.rounds_loaded() == 30
		and is_equal_approx(loaded_gun.durability, 87.5), "the modded gun is back: red dot, 30 rounds, 87.5 durability")
	var loaded_pack: RefCounted = gs.stash.items.filter(func(each: RefCounted) -> bool: return each.data.id == "tourist_pack")[0]
	check(loaded_pack.contents.count_of("ammo_545_ps") == 40 and loaded_pack.contents.count_of("bandage") == 1, "the pack in the stash keeps its contents")
	check(gs.stash.item_at(Vector2i(9, 29)) != null and gs.stash.item_at(Vector2i(9, 29)).fir, "the found-in-raid item is back in its cell, still found in raid")
	var armor: Array = gs.stash.items.filter(func(each: RefCounted) -> bool: return each.data.id == "paca_armor")
	check(armor.size() == 1 and armor[0].insured and armor[0].insurer == "bulat", "the insured item is still insured with Bulat")
	check(gs.quests.get("textile", {}).get("state") == "active" and gs.quests.textile.progress == [1, 0], "the quest is still in progress")
	check(gs.loadout_presets.size() == 1 and gs.loadout_presets[0].name == "Raid kit", "the loadout preset is back")
	check(gs.faction == gs.Faction.BEAR and gs.xp == 2500 and gs.level == load("res://scripts/progression/progression.gd").level_for_xp(2500)
		and gs.dollars == 321, "faction, experience, level and dollars are back")


func _upgrade() -> void:
	section("Upgrade from version 8")
	var old := {"version": 8, "profile": {"faction": "USEC", "level": 2, "xp": 0, "roubles": 123456,
		"trader_loyalty": {"prapor": {"level": 2, "reputation": 0.1, "spent": 1000}, "jaeger": {"level": 1, "reputation": 0.2, "spent": 500},
			"peacekeeper": {"level": 1, "reputation": 0.05, "spent": 0}, "mechanic": {"level": 1, "reputation": 0.0, "spent": 70}},
		"insurer": "therapist", "insurance_pending": [{"item": {"id": "bandage"}, "due": 0.0, "insurer": "prapor"}]},
		"stash": [{"id": "ak_74n", "x": 0, "y": 0, "insured": true, "insurer": "prapor"}]}
	var original := _text(old)
	var result: Dictionary = sm.upgrade(old)
	check(_text(old) == original and int(old.version) == 8, "upgrade() leaves the original untouched")
	check(int(result.version) == 14, "the result is version 14")
	var loyalty: Dictionary = result.profile.trader_loyalty
	var ids: Array = loyalty.keys()
	ids.sort()
	check(ids == ["broker", "bulat", "tinker"], "old trader ids are renamed (got %s)" % str(ids))
	check(int(loyalty.bulat.level) == 2 and int(loyalty.bulat.spent) == 1500 and is_equal_approx(loyalty.bulat.reputation, 0.2),
		"Jaeger merges into Bulat: the higher level and reputation, the money added up")
	check(is_equal_approx(loyalty.tinker.reputation, 0.05) and is_equal_approx(loyalty.broker.reputation, 0.0),
		"USEC's starting reputation moves from The Broker to Tinker")
	check(result.profile.insurer == "vera" and result.profile.insurance_pending[0].insurer == "bulat"
		and result.stash[0].insurer == "bulat", "insurers are renamed on the profile, a pending return and a stash item")
	check(int(result.profile.hideout.stash) == 1, "the hideout gets the Stash at level 1")
	check(result.profile.scav is Dictionary and is_equal_approx(result.profile.scav.karma, 0.0) and result.profile.scav.kit == null
		and is_equal_approx(result.profile.scav.ready_at, 0.0), "the scav block is there: karma 0, ready, no kit")
	check(sm.upgrade(result) == result, "upgrading a current save returns it as it is")
	gs.from_dict(old)
	check(gs.faction == gs.Faction.USEC and gs.roubles == 123456 and gs.level == 2, "from_dict() loads the version 8 save")
	check(gs.hideout.stash == 1 and gs.stash.size == Vector2i(10, 30) and gs.stash.count_of("ak_74n") == 1
		and gs.stash.items[0].insurer == "bulat", "its stash is 10x30 with the insured gun in it")
	check(gs.trader_loyalty.size() == 7 and gs.trader_loyalty.bulat.spent == 1500 and gs.insurer == "vera",
		"all seven traders, Bulat's spending and the insurer are loaded")


func _bad_files() -> void:
	section("Missing and corrupt saves")
	gs.new_profile(gs.Faction.BEAR)
	gs.roubles = 777
	sm.delete_save()
	check(not sm.has_save() and not sm.load_game(), "no save file: load_game() is false")
	for text: String in ["{ this is not json", "[1, 2, 3]", "", "{\"version\": 99, \"profile\": {\"roubles\": 5}}"]:
		var file := FileAccess.open(sm.SAVE_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		check(not sm.load_game() and gs.roubles == 777 and gs.faction == gs.Faction.BEAR,
			"load_game() is false and the profile unchanged for a file holding '%s'" % text.left(20))
	sm.delete_save()
	check(not sm.has_save(), "delete_save() removes the file")


func _text(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


## " (first difference: path: a / b)" between two values, "" if none: what a failed comparison prints.
func _difference(a: Variant, b: Variant, path: String) -> String:
	if a is Dictionary and b is Dictionary:
		for key: Variant in a.keys() + b.keys():
			if not a.has(key) or not b.has(key):
				return " (first difference: %s/%s only on one side)" % [path, key]
			var inner := _difference(a[key], b[key], "%s/%s" % [path, key])
			if inner != "":
				return inner
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return " (first difference: %s has %d / %d entries)" % [path, a.size(), b.size()]
		for i in a.size():
			var inner := _difference(a[i], b[i], "%s/%d" % [path, i])
			if inner != "":
				return inner
		return ""
	return "" if _text(a) == _text(b) else " (first difference: %s: %s / %s)" % [path, _text(a), _text(b)]
