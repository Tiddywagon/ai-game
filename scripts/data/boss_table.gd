class_name BossTable
extends RefCounted
## The maps' bosses (DESIGN.md §4.3), from data/config/bosses.json (checked when it loads: problems()):
## one per map, each with an original name, title and theme, a chance to be in a raid (35%), 2-4 guards
## and their gear (class 5-6 armor for a boss, 4-5 for guards). A boss's body always holds its unique (a
## Legendary item only it carries, never found anywhere else) and Epic or Legendary loot (boss_loot.tres,
## themed by the boss's loot_focus tags) on top of its valuables and stims (boss_body.tres). BossSpawn
## puts them in a map.

const PATH := "res://data/config/bosses.json"
const LOOT := preload("res://data/loot_tables/boss_loot.tres")
const BODY_LOOT := preload("res://data/loot_tables/boss_body.tres")
const FIELDS := ["id", "name", "title", "theme", "chance", "guards", "guard_name", "loot_focus", "unique", "boss", "guard"]
const GEAR_SLOTS := ["armor", "helmet", "rig", "backpack"]
## The lowest armor class a boss's and a guard's armor and helmet (and an armored rig) may have.
const MIN_ARMOR_CLASS := {"boss": 5, "guard": 4}
## Spare rounds a boss or guard carries: this many full magazines (at least 60 rounds).
const MAGAZINES := 4
## Tries at a guaranteed item that fits before giving up.
const LOOT_TRIES := 12

## The file maps() loads (tests point it at a broken copy), and what was wrong with it when it last
## loaded (problems(); each one also an error).
static var path := PATH
static var load_problems: Array[String] = []
static var _maps := {}


## Every map's boss entry, by map id. Checked the first time it loads (each problem is an error).
static func maps() -> Dictionary:
	if _maps.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("maps") is Dictionary:
			_maps = parsed.maps
			load_problems = problems()
		else:
			load_problems = ["%s isn't valid JSON with a \"maps\" object" % path]
		for problem in load_problems:
			push_error("BossTable: %s" % problem)
	return _maps


## The boss of `map_id` ({} if the map has none).
static func for_map(map_id: String) -> Dictionary:
	return maps().get(map_id, {})


## "Iron Matvei, the Furnace King"; just the name when it already carries the title as a nickname
## ('Bogdan "Tollkeeper" Varga').
static func full_name(entry: Dictionary) -> String:
	var boss_name := str(entry.get("name", ""))
	var title := str(entry.get("title", ""))
	if title == "" or title.trim_prefix("the ").to_lower() in boss_name.to_lower():
		return boss_name
	return "%s, %s" % [boss_name, title]


## The guards' name for more than one: "Stokers", "Toll men" (guard_plural, else guard_name + "s").
static func guard_plural(entry: Dictionary) -> String:
	var plural := str(entry.get("guard_plural", ""))
	return plural if plural != "" else "%ss" % entry.get("guard_name", "guard")


## For the raid setup's map stats: "Iron Matvei, the Furnace King · 35% · 2-4 Stokers" ("None").
static func summary(map_id: String) -> String:
	var entry := for_map(map_id)
	if entry.is_empty():
		return "None"
	var guards: Array = entry.guards
	return "%s · %d%% · %d-%d %s" % [full_name(entry), roundi(float(entry.chance) * 100.0), int(guards[0]), int(guards[1]), guard_plural(entry)]


## A boss's or guard's kit from `spec` (its "boss" or "guard" entry): a gun picked from its weapons,
## loaded with its round, MAGAZINES of spares in the rig, its sidearm, armor, helmet, rig, backpack,
## melee weapon and meds.
static func kit(spec: Dictionary, rng: RandomNumberGenerator) -> Inventory:
	var inventory := Inventory.new()
	for slot in GEAR_SLOTS:
		var options: Variant = spec.get(slot)
		var id: String = options[rng.randi_range(0, options.size() - 1)] if options is Array and not options.is_empty() else str(options) if options else ""
		if id != "" and ItemDB.has_item(id):
			inventory.equip(slot, ItemInstance.create(id))
	if ItemDB.has_item(str(spec.get("melee", ""))):
		inventory.equip("melee", ItemInstance.create(spec.melee))
	var weapons: Dictionary = spec.get("weapons", {})
	if not weapons.is_empty():
		var gun_id: String = weapons.keys()[rng.randi_range(0, weapons.size() - 1)]
		_arm(inventory, gun_id, str(weapons[gun_id]), "primary", MAGAZINES, rng)
	var sidearm: Dictionary = spec.get("sidearm", {})
	for gun_id: String in sidearm:
		_arm(inventory, gun_id, str(sidearm[gun_id]), "pistol", 2, rng)
	for id: String in spec.get("meds", []):
		if ItemDB.has_item(id):
			inventory.add(ItemInstance.create(id))
	return inventory


## Puts `gun_id` loaded with `ammo` in `slot` and `magazines` full magazines of spares in the rig and
## pockets.
static func _arm(inventory: Inventory, gun_id: String, ammo: String, slot: String, magazines: int, rng: RandomNumberGenerator) -> void:
	if not ItemDB.has_item(gun_id):
		return
	var data := ItemDB.get_item(gun_id)
	if not ItemDB.has_item(ammo) and data.weapon:
		ammo = LootTable.ammo_for(data.weapon.caliber)
	inventory.equip(slot, Inventory.loaded_gun(gun_id, ammo, rng.randf_range(80.0, 100.0)))
	if data.weapon == null or ammo == "":
		return
	var spare := maxi(data.weapon.magazine_size * magazines, 60 if slot == "primary" else 0)
	var stack := ItemDB.get_item(ammo).max_stack
	while spare > 0:
		var rounds := ItemInstance.create(ammo, mini(spare, stack))
		spare -= rounds.count
		if not inventory.add(rounds):
			break


## The boss's guaranteed loot: its unique first (it always has room), then boss_loot.tres (Epic and
## Legendary only) rolled with the boss's loot_focus, into its pack, rig and pockets; at least one rolled
## item always goes in (rolled again until one fits). Then its valuables and stims (boss_body.tres).
## Returns the guaranteed items: the unique, then the rolled ones.
static func add_boss_loot(inventory: Inventory, entry: Dictionary, rng: RandomNumberGenerator) -> Array[ItemInstance]:
	var placed: Array[ItemInstance] = []
	var unique_id := str(entry.get("unique", ""))
	if ItemDB.has_item(unique_id):
		var unique := ItemInstance.create(unique_id)
		if inventory.add(unique):
			placed.append(unique)
	var uniques_placed := placed.size()
	var focus: Array = entry.get("loot_focus", [])
	for item in LOOT.roll_items(rng, null, PackedFloat32Array(), focus):
		if inventory.add(item):
			placed.append(item)
	var tries := 0
	while placed.size() == uniques_placed and tries < LOOT_TRIES:
		tries += 1
		var data := LOOT.roll_item(rng, null, PackedFloat32Array(), focus)
		if data:
			var item := ItemInstance.create(data.id)
			if data.weapon:
				item = Inventory.loaded_gun(data.id, LootTable.ammo_for(data.weapon.caliber), rng.randf_range(80.0, 100.0))
			if inventory.add(item):
				placed.append(item)
	inventory.add_loot(BODY_LOOT, rng)
	return placed


## What's wrong with bosses.json: missing fields, maps that don't exist, chances out of range, guard
## counts outside 2-4, unknown items, focus tags or slots, armor below its class (MIN_ARMOR_CLASS), a
## unique that isn't a Legendary kept out of loot (loot_weight 0) or is shared, a loot focus tag with
## nothing Epic or Legendary to theme (in boss_loot.tres, or the boss's unique). Empty if it's fine.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var table := maps()
	if table.is_empty():
		return ["%s: no bosses" % PATH]
	var map_ids := MapInfo.load_all().map(func(map: MapInfo) -> String: return map.id)
	for map_id: String in map_ids:
		if not table.has(map_id):
			found.append("%s has no boss" % map_id)
	var pool := loot_pool()
	var uniques := []
	var names := []
	for map_id: String in table:
		var entry: Dictionary = table[map_id]
		var where := "%s boss" % map_id
		if not map_id in map_ids:
			found.append("%s: no such map" % where)
		for field in FIELDS:
			if not entry.has(field):
				found.append("%s: no %s" % [where, field])
		if not entry.has("guards") or not entry.has("boss") or not entry.has("guard"):
			continue
		if entry.name in names:
			found.append("%s: the name %s is taken" % [where, entry.name])
		names.append(entry.name)
		var chance := float(entry.get("chance", 0.0))
		if chance <= 0.0 or chance > 1.0:
			found.append("%s: chance %s isn't in (0, 1]" % [where, chance])
		var guards: Array = entry.guards
		if guards.size() != 2 or int(guards[0]) < 2 or int(guards[1]) > 4 or int(guards[0]) > int(guards[1]):
			found.append("%s: guards %s aren't 2-4" % [where, guards])
		var unique_id := str(entry.get("unique", ""))
		var unique := ItemDB.get_item(unique_id) if ItemDB.has_item(unique_id) else null
		if unique == null:
			found.append("%s: no item %s for its unique" % [where, unique_id])
		elif unique.rarity != ItemData.Rarity.LEGENDARY or unique.loot_weight > 0.0:
			found.append("%s: its unique %s isn't a Legendary with loot_weight 0" % [where, unique_id])
		if unique_id in uniques:
			found.append("%s: the unique %s is taken" % [where, unique_id])
		uniques.append(unique_id)
		for tag: String in entry.get("loot_focus", []):
			if not PoiTable.FOCUS.has(tag):
				found.append("%s: unknown loot focus %s" % [where, tag])
			elif not pool.any(func(item: ItemData) -> bool: return PoiTable.matches_focus(item, [tag])) \
					and not (unique and PoiTable.matches_focus(unique, [tag])):
				found.append("%s: loot focus %s has nothing Epic or Legendary to theme (boss_loot.tres or its unique)" % [where, tag])
		for role in ["boss", "guard"]:
			found.append_array(_spec_problems("%s %s" % [map_id, role], entry[role], int(MIN_ARMOR_CLASS[role])))
	return found


## Every item boss_loot.tres can roll (its Epic and Legendary candidates).
static func loot_pool() -> Array[ItemData]:
	var pool: Array[ItemData] = []
	for rarity in LootTable.RARITY_COUNT:
		if rarity < LOOT.rarity_weights.size() and LOOT.rarity_weights[rarity] > 0.0:
			pool.append_array(LOOT.candidates(rarity))
	return pool


static func _spec_problems(where: String, spec: Dictionary, min_class: int) -> Array[String]:
	var found: Array[String] = []
	var weapons: Dictionary = spec.get("weapons", {})
	if weapons.is_empty():
		found.append("%s: no weapons" % where)
	var guns := weapons.duplicate()
	guns.merge(spec.get("sidearm", {}))
	for gun_id: String in guns:
		var gun := ItemDB.get_item(gun_id) if ItemDB.has_item(gun_id) else null
		var ammo := ItemDB.get_item(str(guns[gun_id])) if ItemDB.has_item(str(guns[gun_id])) else null
		if gun == null or gun.weapon == null:
			found.append("%s: %s isn't a gun" % [where, gun_id])
		elif ammo == null or str(ammo.stats.get("caliber", "")) != gun.weapon.caliber:
			found.append("%s: %s doesn't fire %s" % [where, gun_id, guns[gun_id]])
	var categories := {"armor": ItemData.Category.ARMOR, "helmet": ItemData.Category.HELMET, "rig": ItemData.Category.RIG,
		"backpack": ItemData.Category.BACKPACK}
	for slot: String in categories:
		var options: Variant = spec.get(slot, [])
		for id in (options if options is Array else [options]):
			if not ItemDB.has_item(str(id)) or ItemDB.get_item(str(id)).category != categories[slot]:
				found.append("%s: %s isn't a %s" % [where, id, slot])
				continue
			var stats := ItemDB.get_item(str(id)).stats
			var armored := slot in ["armor", "helmet"] or stats.has("class")
			if armored and int(stats.get("class", 0)) < min_class:
				found.append("%s: %s is armor class %d, below %d" % [where, id, int(stats.get("class", 0)), min_class])
	for id: String in spec.get("meds", []):
		if not ItemDB.has_item(id):
			found.append("%s: no item %s" % [where, id])
	return found
