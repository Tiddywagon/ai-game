class_name BotKit
extends Resource
## What an AI bot spawns carrying (DESIGN.md §4): a gun rolled from its gun table (a rarity by weight,
## then a gun of that rarity by its item weight: a Scav's is mostly Common and Uncommon, rarely Rare,
## very rarely Ultra Rare) with its everyday round and a few magazines of spares, then each gear slot
## rolled from its own loot table with a chance (a Scav's tables are mostly Common and Uncommon with a
## small chance of Rare), some loot in its pockets, rig and backpack, always something to eat or drink,
## often a medkit that restores HP (so it can heal when it flees) and sometimes a bandage. One .tres per
## kind of bot in data/bots/: scav_kit.tres, and the AI PMCs' bear_kit.tres (Eastern gear) and
## usec_kit.tres (Western gear; Factions.ai_kit()), which add a better round (ammo_rarity), a sidearm,
## pocket meds and sometimes a stim, and roll Uncommon to Epic gear. build()'s `tier` scales the gear
## rolls' rarity. An AI PMC squad's gear tier (cheap to well-equipped, rolled by map difficulty:
## PmcAi, DESIGN.md §4.4) is its faction's kit with_tier(): its own rarity multipliers, round, chances,
## better meds and parts fitted to the gun (Factions.ai_kit(faction, tier)).

## The gun: one item of this table (its items list names the guns, item_weights weigh them within their
## rarity, rarity_weights pick the rarity).
@export var gun_table: LootTable
## Spare rounds: this many full magazines, in the rig (or pockets), and at least min_spare_rounds (a
## single-shot gun's three "magazines" would be three shells).
@export_range(0, 10) var spare_magazines := 3
@export_range(0, 60) var min_spare_rounds := 12
## The guns come this worn: durability between x and y.
@export var gun_durability := Vector2(50.0, 85.0)
## The round its guns are loaded with: x below 0, the caliber's everyday round (LootTable.ammo_for());
## else the most penetrating round of the caliber up to a rarity rolled from x to y (ItemData.Rarity:
## 2 Rare, 4 Epic).
@export var ammo_rarity := Vector2i(-1, -1)
@export_range(0.0, 1.0, 0.05) var armor_chance := 0.3
@export var armor_table: LootTable
@export_range(0.0, 1.0, 0.05) var helmet_chance := 0.3
@export var helmet_table: LootTable
@export_range(0.0, 1.0, 0.05) var rig_chance := 1.0
@export var rig_table: LootTable
## Off: the rig is never an armored one (rolled again; a player Scav's worst kit tiers carry no armor).
@export var armored_rigs := true
@export_range(0.0, 1.0, 0.05) var backpack_chance := 0.4
@export var backpack_table: LootTable
## A sidearm in the pistol slot this often (one gun of pistol_table), with pistol_magazines of spares.
@export_range(0.0, 1.0, 0.05) var pistol_chance := 0.0
@export var pistol_table: LootTable
@export_range(0, 6) var pistol_magazines := 2
## A melee weapon (item id) carried this often.
@export var melee_id := "hatchet"
@export_range(0.0, 1.0, 0.05) var melee_chance := 0.2
## Odds and ends put wherever they fit (its item_count says how many).
@export var loot_table: LootTable
## Something to eat or drink, always (one item of this table).
@export var food_table: LootTable
@export_range(0.0, 1.0, 0.05) var bandage_chance := 0.5
## Something that restores HP (one item of medkit_table: a small medkit) carried this often.
@export_range(0.0, 1.0, 0.05) var medkit_chance := 0.7
@export var medkit_table: LootTable
## Items always in its pockets (or rig): painkillers, a tourniquet.
@export var pocket_items: PackedStringArray = []
## A stim (one item of stim_table) carried this often.
@export_range(0.0, 1.0, 0.05) var stim_chance := 0.0
@export var stim_table: LootTable
## Multipliers on every gear roll on top of build()'s `tier` (a gear tier's: with_tier()); empty for none.
@export var rarity_boost := PackedFloat32Array()
## Multipliers on the medkit roll (a well-equipped kit carries better medkits); empty for none.
@export var medkit_boost := PackedFloat32Array()
## This many random parts fitted to the gun's empty slots (a modded gun; magazines left alone).
@export_range(0, 6) var gun_mods := 0
## A face cover (one item of face_cover_table: a balaclava or a shemagh) worn this often. Rolled last, on
## a stream of its own seeded from `rng`, so the rest of the kit rolls as it did before face covers.
@export_range(0.0, 1.0, 0.05) var face_cover_chance := 0.0
@export var face_cover_table: LootTable


## Rolls for a plain rig before giving up on one (armored_rigs off).
const UNARMORED_TRIES := 20


## A full kit, rolled with `rng`: gun, sidearm, armor, helmet, rig, backpack, loot and, last (on a stream
## of its own), a face cover. `tier`: rarity multipliers (LootTable boost) on every gear roll but the face
## cover's (gun, sidearm, armor, helmet, rig, backpack and loot); empty for none.
func build(rng: RandomNumberGenerator, tier := PackedFloat32Array()) -> Inventory:
	tier = LootTable.combine_boosts(rarity_boost, tier)
	var inventory := Inventory.new()
	if rng.randf() < rig_chance and rig_table:
		_equip(inventory, "rig", rig_table, rng, tier, not armored_rigs)
	if rng.randf() < armor_chance and armor_table:
		_equip(inventory, "armor", armor_table, rng, tier)
	if rng.randf() < helmet_chance and helmet_table:
		_equip(inventory, "helmet", helmet_table, rng, tier)
	if rng.randf() < backpack_chance and backpack_table:
		_equip(inventory, "backpack", backpack_table, rng, tier)
	if rng.randf() < melee_chance and ItemDB.has_item(melee_id):
		inventory.equip("melee", ItemInstance.create(melee_id))
	var gun_id := pick_weapon(rng, tier)
	if gun_id == "" and not tier.is_empty():
		gun_id = pick_weapon(rng)  # Nothing of those rarities in its gun table: it still carries a gun.
	if gun_id != "":
		var gun := _arm(inventory, gun_id, spare_magazines, min_spare_rounds, rng)
		if gun_mods > 0:
			fit_mods(gun, gun_mods, rng)
	if pistol_table and pistol_chance > 0.0 and rng.randf() < pistol_chance:
		var pistol := pistol_table.roll_item(rng, null, tier)
		if pistol and pistol.weapon and inventory.equipment.pistol == null:
			_arm(inventory, pistol.id, pistol_magazines, 0, rng)
	if food_table:
		for item in food_table.roll_items(rng):
			inventory.add(item)
			break
	if rng.randf() < bandage_chance:
		inventory.add(ItemInstance.create("bandage"))
	if rng.randf() < medkit_chance and medkit_table:
		var medkit := medkit_table.roll_item(rng, null, medkit_boost)
		if medkit:
			inventory.add(ItemInstance.create(medkit.id))
	for id in pocket_items:
		if ItemDB.has_item(id):
			inventory.add(ItemInstance.create(id))
	if stim_table and stim_chance > 0.0 and rng.randf() < stim_chance:
		var stim := stim_table.roll_item(rng)
		if stim:
			inventory.add(ItemInstance.create(stim.id))
	if loot_table:
		for item in loot_table.roll_items(rng, null, tier):
			inventory.add(item)
	if face_cover_table and face_cover_chance > 0.0:
		var cover_rng := RandomNumberGenerator.new()
		cover_rng.seed = hash([rng.state, "face_cover"])
		if cover_rng.randf() < face_cover_chance:
			_equip(inventory, "face_cover", face_cover_table, cover_rng)
	return inventory


## A gun id rolled from the gun table ("" if there's none).
func pick_weapon(rng: RandomNumberGenerator, tier := PackedFloat32Array()) -> String:
	if gun_table == null:
		return ""
	var gun := gun_table.roll_item(rng, null, tier)
	return gun.id if gun and gun.weapon else ""


## The round a gun of `caliber` is loaded with (ammo_rarity), "" if the caliber has none.
func pick_ammo(caliber: String, rng: RandomNumberGenerator) -> String:
	if ammo_rarity.x < 0:
		return LootTable.ammo_for(caliber)
	var top := rng.randi_range(ammo_rarity.x, maxi(ammo_rarity.x, ammo_rarity.y))
	var best: ItemData = null
	for round_data in ItemDB.ammo_of(caliber):
		if round_data.rarity <= top and (best == null
				or float(round_data.stats.get("penetration", 0)) > float(best.stats.get("penetration", 0))):
			best = round_data
	return best.id if best else LootTable.ammo_for(caliber)


## Puts gun `gun_id` in its slot (the pistol slot for a pistol) loaded with its round (pick_ammo()),
## somewhat worn (gun_durability), and `magazines` full magazines of spares (at least `min_rounds`) in
## the pockets, rig and backpack. Returns the gun.
func _arm(inventory: Inventory, gun_id: String, magazines: int, min_rounds: int, rng: RandomNumberGenerator) -> ItemInstance:
	var data := ItemDB.get_item(gun_id)
	var ammo := pick_ammo(data.weapon.caliber, rng) if data.weapon else ""
	var gun := Inventory.loaded_gun(gun_id, ammo, rng.randf_range(gun_durability.x, gun_durability.y))
	var slot := "pistol" if str(data.stats.get("class", "")) == Inventory.PISTOL_CLASS else "primary"
	inventory.equip(slot, gun)
	if ammo != "" and data.weapon:
		var spare := maxi(data.weapon.magazine_size * magazines, min_rounds)
		var stack := ItemDB.get_item(ammo).max_stack
		while spare > 0:
			var rounds := ItemInstance.create(ammo, mini(spare, stack))
			spare -= rounds.count
			inventory.add(rounds)
	return gun


## Fits up to `count` random weapon parts (any that fit, not magazines) into empty slots of `gun`.
## Returns how many went on.
static func fit_mods(gun: ItemInstance, count: int, rng: RandomNumberGenerator) -> int:
	if gun == null or gun.data.weapon == null:
		return 0
	var parts: Array[ItemData] = ItemDB.all_items().filter(func(data: ItemData) -> bool:
		return WeaponMods.is_mod(data) and not WeaponMods.is_gear_mod(data) and WeaponMods.kind_of(data) != "magazine" and data.loot_weight > 0.0)
	for i in range(parts.size() - 1, 0, -1):  # Shuffled with `rng`, so seeded kits repeat.
		var j := rng.randi_range(0, i)
		var swap := parts[i]
		parts[i] = parts[j]
		parts[j] = swap
	var fitted := 0
	for data in parts:
		if fitted >= count:
			break
		var part := ItemInstance.create(data.id)
		var path := WeaponMods.slot_for(gun, part, true)
		if path != "" and WeaponMods.install(gun, path, part) == null and WeaponMods.mod_at(gun, path) == part:
			fitted += 1
	return fitted


## A copy of this kit dressed for a gear tier (PmcAi.tier(): cheap to well-equipped; a player Scav's kit
## tier by karma, ScavRuns.kit_tier()): `overrides`' rarity (multipliers on every gear roll),
## ammo_rarity, armor / helmet / backpack / melee / bandage / medkit / pistol / stim chances, gun_mods,
## medkit_rarity, gun_durability, pocket_items and armored_rigs replace the kit's; whatever it leaves
## out stays.
func with_tier(overrides: Dictionary) -> BotKit:
	var kit := duplicate() as BotKit
	if overrides.get("rarity") is Array:
		kit.rarity_boost = PackedFloat32Array(overrides.rarity)
	if overrides.get("medkit_rarity") is Array:
		kit.medkit_boost = PackedFloat32Array(overrides.medkit_rarity)
	if overrides.get("ammo_rarity") is Array and overrides.ammo_rarity.size() == 2:
		kit.ammo_rarity = Vector2i(int(overrides.ammo_rarity[0]), int(overrides.ammo_rarity[1]))
	if overrides.get("gun_durability") is Array and overrides.gun_durability.size() == 2:
		kit.gun_durability = Vector2(float(overrides.gun_durability[0]), float(overrides.gun_durability[1]))
	for key in ["armor_chance", "helmet_chance", "backpack_chance", "melee_chance", "bandage_chance", "medkit_chance", "pistol_chance", "stim_chance"]:
		if overrides.has(key):
			kit.set(key, clampf(float(overrides[key]), 0.0, 1.0))
	if overrides.has("gun_mods"):
		kit.gun_mods = maxi(int(overrides.gun_mods), 0)
	if overrides.get("pocket_items") is Array:
		kit.pocket_items = PackedStringArray(overrides.pocket_items)
	if overrides.get("armored_rigs") is bool:
		kit.armored_rigs = overrides.armored_rigs
	return kit


## Equips one item of `table` in `slot`; `unarmored`: rolled again (up to UNARMORED_TRIES times) while
## it's armor, and nothing if it still is.
static func _equip(inventory: Inventory, slot: String, table: LootTable, rng: RandomNumberGenerator, tier := PackedFloat32Array(),
		unarmored := false) -> void:
	var item := table.roll_item(rng, null, tier)
	var tries := 0
	while unarmored and item and item.stats.has("class") and tries < UNARMORED_TRIES:
		item = table.roll_item(rng, null, tier)
		tries += 1
	if unarmored and item and item.stats.has("class"):
		return
	if item:
		inventory.equip(slot, ItemInstance.create(item.id))
