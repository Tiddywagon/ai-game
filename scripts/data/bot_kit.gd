class_name BotKit
extends Resource
## What an AI bot spawns carrying (DESIGN.md §4): a gun rolled from its gun table (a rarity by weight,
## then a gun of that rarity by its item weight: a Scav's is mostly Common and Uncommon, rarely Rare,
## very rarely Ultra Rare) with its everyday round and a few magazines of spares, then each gear slot
## rolled from its own loot table with a chance (a Scav's tables are mostly Common and Uncommon with a
## small chance of Rare), some loot in its pockets, rig and backpack, always something to eat or drink,
## often a medkit that restores HP (so it can heal when it flees) and sometimes a bandage. One .tres per
## kind of bot in data/bots/ (scav_kit.tres).

## The gun: one item of this table (its items list names the guns, item_weights weigh them within their
## rarity, rarity_weights pick the rarity).
@export var gun_table: LootTable
## Spare rounds: this many full magazines, in the rig (or pockets), and at least min_spare_rounds (a
## single-shot gun's three "magazines" would be three shells).
@export_range(0, 10) var spare_magazines := 3
@export_range(0, 60) var min_spare_rounds := 12
@export_range(0.0, 1.0, 0.05) var armor_chance := 0.3
@export var armor_table: LootTable
@export_range(0.0, 1.0, 0.05) var helmet_chance := 0.3
@export var helmet_table: LootTable
@export_range(0.0, 1.0, 0.05) var rig_chance := 1.0
@export var rig_table: LootTable
@export_range(0.0, 1.0, 0.05) var backpack_chance := 0.4
@export var backpack_table: LootTable
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


## A full kit, rolled with `rng`.
func build(rng: RandomNumberGenerator) -> Inventory:
	var inventory := Inventory.new()
	if rng.randf() < rig_chance and rig_table:
		_equip(inventory, "rig", rig_table, rng)
	if rng.randf() < armor_chance and armor_table:
		_equip(inventory, "armor", armor_table, rng)
	if rng.randf() < helmet_chance and helmet_table:
		_equip(inventory, "helmet", helmet_table, rng)
	if rng.randf() < backpack_chance and backpack_table:
		_equip(inventory, "backpack", backpack_table, rng)
	if rng.randf() < melee_chance and ItemDB.has_item(melee_id):
		inventory.equip("melee", ItemInstance.create(melee_id))
	var gun_id := pick_weapon(rng)
	if gun_id != "":
		var data := ItemDB.get_item(gun_id)
		var ammo := LootTable.ammo_for(data.weapon.caliber) if data.weapon else ""
		var gun := Inventory.loaded_gun(gun_id, ammo, rng.randf_range(50.0, 85.0))
		var slot := "pistol" if str(data.stats.get("class", "")) == "pistol" else "primary"
		inventory.equip(slot, gun)
		if ammo != "" and data.weapon:
			var spare := maxi(data.weapon.magazine_size * spare_magazines, min_spare_rounds)
			var stack := ItemDB.get_item(ammo).max_stack
			while spare > 0:
				var rounds := ItemInstance.create(ammo, mini(spare, stack))
				spare -= rounds.count
				inventory.add(rounds)
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
	if loot_table:
		for item in loot_table.roll_items(rng):
			inventory.add(item)
	return inventory


## A gun id rolled from the gun table ("" if there's none).
func pick_weapon(rng: RandomNumberGenerator) -> String:
	if gun_table == null:
		return ""
	var gun := gun_table.roll_item(rng)
	return gun.id if gun and gun.weapon else ""


static func _equip(inventory: Inventory, slot: String, table: LootTable, rng: RandomNumberGenerator) -> void:
	var item := table.roll_item(rng)
	if item:
		inventory.equip(slot, ItemInstance.create(item.id))
