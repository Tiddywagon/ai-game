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
## rolls' rarity (a map's difficulty tier can pass one).

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


## A full kit, rolled with `rng`. `tier`: rarity multipliers (LootTable boost) on every gear roll (gun,
## sidearm, armor, helmet, rig, backpack and loot); empty for none.
func build(rng: RandomNumberGenerator, tier := PackedFloat32Array()) -> Inventory:
	var inventory := Inventory.new()
	if rng.randf() < rig_chance and rig_table:
		_equip(inventory, "rig", rig_table, rng, tier)
	if rng.randf() < armor_chance and armor_table:
		_equip(inventory, "armor", armor_table, rng, tier)
	if rng.randf() < helmet_chance and helmet_table:
		_equip(inventory, "helmet", helmet_table, rng, tier)
	if rng.randf() < backpack_chance and backpack_table:
		_equip(inventory, "backpack", backpack_table, rng, tier)
	if rng.randf() < melee_chance and ItemDB.has_item(melee_id):
		inventory.equip("melee", ItemInstance.create(melee_id))
	var gun_id := pick_weapon(rng, tier)
	if gun_id != "":
		_arm(inventory, gun_id, spare_magazines, min_spare_rounds, rng)
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
		var medkit := medkit_table.roll_item(rng)
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
## the pockets, rig and backpack.
func _arm(inventory: Inventory, gun_id: String, magazines: int, min_rounds: int, rng: RandomNumberGenerator) -> void:
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


static func _equip(inventory: Inventory, slot: String, table: LootTable, rng: RandomNumberGenerator, tier := PackedFloat32Array()) -> void:
	var item := table.roll_item(rng, null, tier)
	if item:
		inventory.equip(slot, ItemInstance.create(item.id))
