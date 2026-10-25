class_name Inventory
extends RefCounted
## What a character carries (DESIGN.md §7): equipment slots and pockets. Rigs, backpacks and the
## secure container bring their own grids. Weight is everything here added up. GameState keeps the
## PMC's; a raid works on a copy; a Scav gets a random one.

## Anything in it changed: an item moved, was equipped, restacked or used up.
signal changed

## Equipment slots in display order, with their names.
const SLOTS := [
	["primary", "Primary weapon"], ["secondary", "Secondary weapon"], ["pistol", "Pistol"], ["melee", "Melee"],
	["helmet", "Helmet"], ["armor", "Body armor"], ["rig", "Tactical rig"], ["backpack", "Backpack"],
	["secure", "Secure container"],
]
## Four 1×1 pockets.
const POCKETS := Vector2i(4, 1)
## Guns that go in the pistol slot have this "class" stat.
const PISTOL_CLASS := "pistol"
## Slots the gun in hand comes from, in order of preference.
const WEAPON_SLOTS: Array[String] = ["primary", "secondary", "pistol"]

## Slot id -> ItemInstance, or null when empty.
var equipment: Dictionary = {}
var pockets := InventoryGrid.new(POCKETS, &"pockets")


func _init() -> void:
	for slot in SLOTS:
		equipment[slot[0]] = null
	pockets.changed.connect(changed.emit)


## True if `item` may go in `slot`: weapons in the weapon slots (pistols only in the pistol slot),
## armor in armor, and so on. One item at a time. Body armor and an armored rig don't go together.
func accepts(slot: String, item: ItemInstance) -> bool:
	if item.count != 1:
		return false
	var category := item.data.category
	var pistol := category == ItemData.Category.WEAPON and str(item.data.stats.get("class", "")) == PISTOL_CLASS
	match slot:
		"primary", "secondary":
			return category == ItemData.Category.WEAPON and not pistol
		"pistol":
			return category == ItemData.Category.WEAPON and pistol
		"melee":
			return category == ItemData.Category.MELEE
		"helmet":
			return category == ItemData.Category.HELMET
		"armor":
			# Not over an armored rig: it already is the armor.
			return category == ItemData.Category.ARMOR and not (equipment.get("rig") and equipment.rig.is_armor())
		"rig":
			# An armored rig doesn't go over body armor.
			return category == ItemData.Category.RIG and not (item.is_armor() and equipment.get("armor") != null)
		"backpack":
			return category == ItemData.Category.BACKPACK
		"secure":
			return category == ItemData.Category.CONTAINER and item.data.stats.get("secure", false)
	return false


## Puts `item` in an empty `slot`. Returns false if the slot is taken or doesn't take that item.
func equip(slot: String, item: ItemInstance) -> bool:
	if not equipment.has(slot) or equipment[slot] != null or not accepts(slot, item):
		return false
	equipment[slot] = item
	if item.contents:
		item.contents.changed.connect(changed.emit)
	changed.emit()
	return true


## Takes the item out of `slot` and returns it (null if empty).
func unequip(slot: String) -> ItemInstance:
	var item: ItemInstance = equipment.get(slot)
	if item == null:
		return null
	equipment[slot] = null
	if item.contents and item.contents.changed.is_connected(changed.emit):
		item.contents.changed.disconnect(changed.emit)
	changed.emit()
	return item


func slot_of(item: ItemInstance) -> String:
	for slot: String in equipment:
		if equipment[slot] == item:
			return slot
	return ""


## Every grid on the character: pockets, then the rig, backpack and secure container.
func grids() -> Array[InventoryGrid]:
	var result: Array[InventoryGrid] = [pockets]
	for slot in ["rig", "backpack", "secure"]:
		if equipment[slot] and equipment[slot].contents:
			result.append(equipment[slot].contents)
	return result


## Grids you can reload from in a hurry: pockets, rig and backpack (not the secure container).
func ammo_grids() -> Array[InventoryGrid]:
	return grids().filter(func(grid: InventoryGrid) -> bool: return grid.kind != &"secure")


## Total carried weight: equipment (with what's inside it) and pockets.
func total_weight() -> float:
	var total := pockets.weight()
	for item in equipment.values():
		if item:
			total += item.weight()
	return total


func total_value() -> int:
	var total := pockets.value()
	for item in equipment.values():
		if item:
			total += item.value()
	return total


## Rounds (or any item) of `id` you can reload from.
func count_of(id: String) -> int:
	var total := 0
	for grid in ammo_grids():
		total += grid.count_of(id)
	return total


## Removes up to `amount` of item `id` from the pockets, rig and backpack. Returns how many.
func take(id: String, amount: int) -> int:
	var taken := 0
	for piece in take_pieces(id, amount):
		taken += piece.count
	return taken


## Like take(), but returns the pieces taken, each keeping its Found-in-Raid status (a reload puts
## them in the magazine as they are).
func take_pieces(id: String, amount: int) -> Array[ItemInstance]:
	var pieces: Array[ItemInstance] = []
	var taken := 0
	for grid in ammo_grids():
		for piece in grid.take_pieces(id, amount - taken):
			taken += piece.count
			pieces.append(piece)
		if taken >= amount:
			break
	return pieces


## Every item on the character: equipment, pockets, everything inside them and the rounds in guns.
func all_items() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for item in equipment.values():
		if item:
			result.append_array(item.all_items())
	result.append_array(pockets.all_items())
	return result


## The grid on the character holding `item` (pockets, rig, backpack, secure container or a case inside
## one of them), or null.
func holder_of(item: ItemInstance) -> InventoryGrid:
	for grid in grids():
		var holder := grid.find_holder(item)
		if holder:
			return holder
	return null


## Takes `item` out of whichever grid on the character holds it (a used-up med). False if it isn't here.
func remove_item(item: ItemInstance) -> bool:
	var holder := holder_of(item)
	if holder == null:
		return false
	holder.remove(item)
	changed.emit()  # Also when it was inside a case, whose grid isn't watched.
	return true


## Puts `item` in the pockets, rig or backpack, wherever it fits. False if it didn't all fit.
func add(item: ItemInstance) -> bool:
	for grid in ammo_grids():
		if grid.add(item):
			return true
	return false


## The slot of the gun in hand: the primary weapon, else the secondary, else the pistol ("" for none).
func weapon_slot() -> String:
	for slot in WEAPON_SLOTS:
		if equipment[slot]:
			return slot
	return ""


## True if the character has an item of `category` equipped or anywhere in their grids.
func has_category(category: ItemData.Category) -> bool:
	for item in equipment.values():
		if item and item.data.category == category:
			return true
	for grid in grids():
		for item in grid.items:
			if item.data.category == category:
				return true
	return false


func to_dict() -> Dictionary:
	var slots := {}
	for slot: String in equipment:
		if equipment[slot]:
			slots[slot] = equipment[slot].to_dict()
	return {"equipment": slots, "pockets": pockets.to_array()}


static func from_dict(data: Dictionary) -> Inventory:
	var inventory := Inventory.new()
	var slots: Dictionary = data.get("equipment", {})
	for slot: String in slots:
		var item := ItemInstance.from_dict(slots[slot])
		if item and not inventory.equip(slot, item):
			push_warning("Inventory: %s can't go in %s, dropped" % [item.data.id, slot])
	inventory.pockets.load_array(data.get("pockets", []))
	return inventory


## Converts a version 2 save (slot -> item id, loaded ammo id, list of pocket stacks).
static func from_v2(slots: Dictionary, weapon_ammo: String, pocket_list: Array) -> Inventory:
	var inventory := Inventory.new()
	for slot: String in slots:
		var target := "pistol" if slot == "holster" else slot
		var item := ItemInstance.create(str(slots[slot])) if str(slots[slot]) != "" else null
		if item and inventory.equipment.has(target):
			if item.data.category == ItemData.Category.WEAPON and item.data.weapon:
				item.loaded_ammo = weapon_ammo
				item.load_rounds(ItemInstance.full_rounds(weapon_ammo, WeaponMods.capacity(item)))
			inventory.equip(target, item)
	for entry in pocket_list:
		var item := ItemInstance.create(str(entry.get("id", "")), int(entry.get("count", 1)))
		if item:
			inventory.pockets.add(item)
	return inventory


func duplicate_deep() -> Inventory:
	return from_dict(to_dict())


## A new character's kit for `faction` (DESIGN.md §16.4, data/config/factions.json: Factions.starter_kit();
## &"" gives the first faction's, BEAR): BEAR an AK-74N loaded with 5.45 PS and Module-3M armor, USEC a
## Kestrel AR loaded with 5.56 FMJ and PACA armor; both the Alpha secure container, 60 spare rounds and
## a bandage in the pockets.
static func starter(faction: StringName = &"") -> Inventory:
	return Factions.starter_kit(faction)


## A random Scav kit (DESIGN.md §4, §16.3), rolled from data/bots/scav_kit.tres (BotKit): a cheap gun
## (mostly a Common or Uncommon one: a sawn-off, a revolver, an SKS, a pump shotgun, a Mosin or a
## pistol; sometimes an AK-74N or another Rare gun, very rarely better) with its everyday round and three
## magazines of spares, a rig, sometimes armor, a helmet, a backpack or a hatchet (mostly Common and
## Uncommon, a small chance of Rare), something to eat or drink, often a small medkit and a bandage, and
## odds and ends. Nothing from the stash. Also what AI Scavs carry (and drop): Scav bodies are one of the best
## places for food (DESIGN.md §13.7).
static func scav(rng: RandomNumberGenerator = null) -> Inventory:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return (load("res://data/bots/scav_kit.tres") as BotKit).build(rng)


## Rolls `table` (LootTable.roll_items()) into the backpack, rig and pockets, wherever it fits: a boss's
## extra loot (BotProfile.extra_loot). What doesn't fit is skipped.
func add_loot(table: LootTable, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
	for item in table.roll_items(rng):
		add(item)


## A gun with its default parts and a full magazine of `ammo` (not found in raid), at `durability`.
static func loaded_gun(id: String, ammo: String, durability := 100.0) -> ItemInstance:
	var gun := ItemInstance.create(id)
	gun.loaded_ammo = ammo
	if gun.data.weapon:
		gun.load_rounds(ItemInstance.full_rounds(ammo, WeaponMods.capacity(gun)))
		gun.durability = clampf(durability, 0.0, gun.max_durability)
	return gun


## An AI PMC's kit (DESIGN.md §4, §4.4): rolled from its faction's BotKit (Factions.ai_kit(): BEAR
## Eastern gear, USEC Western; &"" the first faction's), Uncommon to Epic: a gun loaded with a good
## round and three magazines of spares, armor, mostly a helmet and a pack of finds, a rig, sometimes a
## sidearm and a stim, meds. `tier`: rarity multipliers for the gear rolls (BotKit.build()). What you
## can take off the body. Without a kit (a broken factions.json) it gets a Scav's, so it's still armed.
static func pmc_bot(rng: RandomNumberGenerator = null, faction: StringName = &"", tier := PackedFloat32Array()) -> Inventory:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var kit := Factions.ai_kit(faction)
	return kit.build(rng, tier) if kit else scav(rng)
