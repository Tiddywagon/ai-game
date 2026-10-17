class_name BossTable
extends RefCounted
## The maps' bosses (DESIGN.md §4.3), from data/config/bosses.json: one per map, each with an original
## name, title and theme, a chance to be in a raid (35%), 2-4 guards and their gear. A boss's body
## always holds Epic or Legendary loot (boss_loot.tres, themed by the boss's loot_focus tags) on top of
## its valuables and stims (boss_body.tres). BossSpawn puts them in a map.

const PATH := "res://data/config/bosses.json"
const LOOT := preload("res://data/loot_tables/boss_loot.tres")
const BODY_LOOT := preload("res://data/loot_tables/boss_body.tres")
const FIELDS := ["id", "name", "title", "theme", "chance", "guards", "guard_name", "loot_focus", "boss", "guard"]
const GEAR_SLOTS := ["armor", "helmet", "rig", "backpack"]
## Spare rounds a boss or guard carries: this many full magazines (at least 60 rounds).
const MAGAZINES := 4
## Tries at a guaranteed item that fits before giving up.
const LOOT_TRIES := 12

static var _maps := {}


## Every map's boss entry, by map id.
static func maps() -> Dictionary:
	if _maps.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_maps = parsed.get("maps", {})
	return _maps


## The boss of `map_id` ({} if the map has none).
static func for_map(map_id: String) -> Dictionary:
	return maps().get(map_id, {})


## "Iron Matvei, the Furnace King".
static func full_name(entry: Dictionary) -> String:
	return "%s, %s" % [entry.name, entry.title] if entry.get("title", "") != "" else str(entry.get("name", ""))


## For the raid setup's map stats: "Iron Matvei, the Furnace King · 35% · 2-4 Stokers" ("None").
static func summary(map_id: String) -> String:
	var entry := for_map(map_id)
	if entry.is_empty():
		return "None"
	var guards: Array = entry.guards
	return "%s · %d%% · %d-%d %ss" % [full_name(entry), roundi(float(entry.chance) * 100.0), int(guards[0]), int(guards[1]), entry.guard_name]


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


## The boss's guaranteed loot: boss_loot.tres (Epic and Legendary only) rolled with the boss's
## loot_focus, into its pack, rig and pockets; at least one item always goes in (rolled again until one
## fits). Then its valuables and stims (boss_body.tres). Returns the guaranteed items.
static func add_boss_loot(inventory: Inventory, entry: Dictionary, rng: RandomNumberGenerator) -> Array[ItemInstance]:
	var placed: Array[ItemInstance] = []
	var focus: Array = entry.get("loot_focus", [])
	for item in LOOT.roll_items(rng, null, PackedFloat32Array(), focus):
		if inventory.add(item):
			placed.append(item)
	var tries := 0
	while placed.is_empty() and tries < LOOT_TRIES:
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
## counts outside 2-4, unknown items, focus tags or slots. Empty if it's fine.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var table := maps()
	if table.is_empty():
		return ["%s: no bosses" % PATH]
	var map_ids := MapInfo.load_all().map(func(map: MapInfo) -> String: return map.id)
	for map_id: String in map_ids:
		if not table.has(map_id):
			found.append("%s has no boss" % map_id)
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
		for tag: String in entry.get("loot_focus", []):
			if not PoiTable.FOCUS.has(tag):
				found.append("%s: unknown loot focus %s" % [where, tag])
		for role in ["boss", "guard"]:
			found.append_array(_spec_problems("%s %s" % [map_id, role], entry[role]))
	return found


static func _spec_problems(where: String, spec: Dictionary) -> Array[String]:
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
	for id: String in spec.get("meds", []):
		if not ItemDB.has_item(id):
			found.append("%s: no item %s" % [where, id])
	return found
