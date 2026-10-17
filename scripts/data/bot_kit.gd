class_name BotKit
extends Resource
## What an AI bot spawns carrying (DESIGN.md §4): a gun from a weighted list with its everyday round and
## a few magazines of spares, then each gear slot rolled from its own loot table with a chance (a Scav's
## tables are mostly Common and Uncommon with a small chance of Rare), some loot in its pockets, rig and
## backpack, always something to eat or drink, and sometimes a bandage. One .tres per kind of bot in
## data/bots/ (scav_kit.tres).

## Gun item id -> weight.
@export var weapons: Dictionary = {}
## Spare rounds: this many full magazines, in the rig (or pockets).
@export_range(0, 10) var spare_magazines := 3
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
			var spare := data.weapon.magazine_size * spare_magazines
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
	if loot_table:
		for item in loot_table.roll_items(rng):
			inventory.add(item)
	return inventory


## A gun id picked by weight ("" if the list is empty).
func pick_weapon(rng: RandomNumberGenerator) -> String:
	var ids: Array = weapons.keys().filter(func(id: String) -> bool: return ItemDB.has_item(id))
	var weights := PackedFloat32Array()
	for id in ids:
		weights.append(float(weapons[id]))
	var index := LootTable._pick(rng, weights)
	return ids[index] if index >= 0 else ""


static func _equip(inventory: Inventory, slot: String, table: LootTable, rng: RandomNumberGenerator) -> void:
	var item := table.roll_item(rng)
	if item:
		inventory.equip(slot, ItemInstance.create(item.id))
