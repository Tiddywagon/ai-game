extends "res://tests/test_base.gd"
## Gear: grids (placing, turning, stacking, sorting), character slots, magazines, loadout presets and
## auto-equip (LoadoutPlanner), with seeded random stashes for the "nothing is lost or made up" rules.

const OPTION_SETS := [{}, {"budget": 60000, "protect_legendary": true}]
const WORN_SLOTS := ["primary", "secondary", "pistol", "melee", "helmet", "headset", "face_cover", "armor", "rig", "backpack"]

## Game scripts, loaded in run() (the autoloads they use exist by then).
var grid_script: GDScript
var inventory_script: GDScript
var mods: GDScript
var presets: GDScript
var planner: GDScript
var categories: Dictionary
## Item ids in a fixed order, the ones auto-equip cares about, small things to carry and, per slot, what fits it.
var ids: Array = []
var gear_ids: Array = []
var small_ids: Array = []
var junk_ids: Array = []
var magazine_ids: Array = []
var by_slot := {}


func run() -> void:
	grid_script = load("res://scripts/inventory/inventory_grid.gd")
	inventory_script = load("res://scripts/inventory/inventory.gd")
	mods = load("res://scripts/inventory/weapon_mods.gd")
	presets = load("res://scripts/inventory/loadout_presets.gd")
	planner = load("res://scripts/inventory/loadout_planner.gd")
	categories = load("res://scripts/data/item_data.gd").Category
	_index()
	_grid()
	_slots()
	_magazines()
	_sorting()
	_presets()
	_preset_fuzz()
	_planner()
	_planner_fuzz()


func _index() -> void:
	for data in db.all_items():
		ids.append(data.id)
	ids.sort()
	var blank: RefCounted = inventory_script.new()
	var gear := [categories.WEAPON, categories.AMMO, categories.ATTACHMENT, categories.ARMOR, categories.RIG, categories.BACKPACK,
		categories.HELMET, categories.MEDS, categories.MELEE, categories.FACE_COVER]
	for slot: String in WORN_SLOTS:
		by_slot[slot] = []
	for id: String in ids:
		var data: Resource = db.get_item(id)
		if data.category in gear:
			gear_ids.append(id)
		if data.category in [categories.AMMO, categories.MEDS] and data.size == Vector2i.ONE:
			small_ids.append(id)
		if data.category == categories.JUNK and data.size == Vector2i.ONE:
			junk_ids.append(id)
		if mods.kind_of(data) == "magazine":
			magazine_ids.append(id)
		var sample := item(id)
		for slot: String in WORN_SLOTS:
			if blank.accepts(slot, sample):
				by_slot[slot].append(id)


# --- Helpers --------------------------------------------------------------------------------------

func _grid_of(width: int, height: int, kind := &"stash") -> RefCounted:
	return grid_script.new(Vector2i(width, height), kind)


## Every top-level item of `inventory` (worn and in the pockets) and `stash`; either may be null.
func _roots(inventory: RefCounted, stash: RefCounted) -> Array:
	var roots: Array = []
	if stash:
		roots.append_array(stash.items)
	if inventory:
		roots.append_array(inventory.pockets.items)
		for slot: String in inventory.equipment:
			if inventory.equipment[slot]:
				roots.append(inventory.equipment[slot])
	return roots


## {item id: how many}, counting everything at any depth: contents, parts and the rounds in magazines.
func _tally(inventory: RefCounted, stash: RefCounted) -> Dictionary:
	var counts := {}
	for root: RefCounted in _roots(inventory, stash):
		for each in root.all_items():
			counts[each.data.id] = int(counts.get(each.data.id, 0)) + each.count
	return counts


## How many stacks are over their max stack, guns over their magazine's capacity, and items out of their
## grid or on top of another, anywhere in `inventory` and `stash`.
func _faults(inventory: RefCounted, stash: RefCounted) -> Dictionary:
	var faults := {"stacks": 0, "magazines": 0, "layout": 0}
	var grids: Array = []
	if stash:
		grids.append(stash)
	if inventory:
		grids.append(inventory.pockets)
	for root: RefCounted in _roots(inventory, stash):
		for each in root.all_items():
			if each.contents:
				grids.append(each.contents)
			if each.is_gun() and each.rounds_loaded() > mods.capacity(each):
				faults.magazines += 1
	for grid: RefCounted in grids:
		var taken := {}
		for each in grid.items:
			if each.count > each.data.max_stack or each.count < 1:
				faults.stacks += 1
			var footprint: Vector2i = each.footprint()
			if not grid.in_bounds(each.cell, footprint):
				faults.layout += 1
			for x in footprint.x:
				for y in footprint.y:
					var cell: Vector2i = each.cell + Vector2i(x, y)
					if taken.has(cell):
						faults.layout += 1
					taken[cell] = true
	return faults


func _clean(faults: Dictionary) -> bool:
	return faults.stacks == 0 and faults.magazines == 0 and faults.layout == 0


## The whole state as text, each grid's items in cell order (the order they're kept in doesn't matter).
func _state(inventory: RefCounted, stash: RefCounted) -> String:
	return JSON.stringify(_ordered({"inventory": inventory.to_dict() if inventory else null, "stash": stash.to_array() if stash else null}), "", true, true)


func _ordered(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _ordered(value[key])
		return result
	if value is Array:
		var list: Array = value.map(_ordered)
		if not list.is_empty() and list.all(func(entry: Variant) -> bool: return entry is Dictionary and entry.has("x") and entry.has("y")):
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return [int(a.y), int(a.x), str(a.id)] < [int(b.y), int(b.x), str(b.id)])
		return list
	return value


func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return list[rng.randi_range(0, list.size() - 1)]


## A random stack or piece of `id`: found in raid or not, worn, a gun maybe with another magazine and
## rounds in it, a rig or pack maybe with things inside (picked from `filler`).
func _random_item(rng: RandomNumberGenerator, id: String, single := false, filler: Array = small_ids) -> RefCounted:
	var data: Resource = db.get_item(id)
	var made := item(id, 1 if single else rng.randi_range(1, data.max_stack))
	made.fir = rng.randf() < 0.3
	if made.is_gun():
		made.durability = rng.randf_range(40.0, 100.0)
		if not mods.slot_on(made, "magazine").is_empty() and rng.randf() < 0.4:
			var magazine := item(_pick(rng, magazine_ids))
			if mods.install_block_reason(made, "magazine", magazine) == "":
				mods.install(made, "magazine", magazine)
		var rounds: Array = db.ammo_of(data.weapon.caliber)
		var room: int = mods.capacity(made)
		if not rounds.is_empty() and room > 0 and rng.randf() < 0.7:
			var first := rng.randi_range(1, room)
			made.load_rounds(made.full_rounds(rounds[rng.randi_range(0, rounds.size() - 1)].id, first))
			if first < room and rng.randf() < 0.3:
				made.load_rounds(made.full_rounds(rounds[rng.randi_range(0, rounds.size() - 1)].id, rng.randi_range(1, room - first)))
	elif made.is_armor():
		made.durability = made.max_durability * rng.randf_range(0.3, 1.0)
	if made.contents and made.contents.kind != &"secure" and rng.randf() < 0.5:
		for i in rng.randi_range(1, 3):
			made.contents.add(_random_item(rng, _pick(rng, filler)))
	return made


## A stash of `size` with `amount` random items (mostly gear), and rounds for every gun in it. The rigs
## and packs in it hold things from `filler` (rounds and meds unless it says).
func _random_stash(rng: RandomNumberGenerator, size: Vector2i, amount: int, filler: Array = small_ids) -> RefCounted:
	var stash := _grid_of(size.x, size.y)
	for i in amount:
		var made := _random_item(rng, _pick(rng, gear_ids) if rng.randf() < 0.7 else _pick(rng, ids), false, filler)
		stash.add(made)
		if made.is_gun() and made in stash.items:
			var rounds: Array = db.ammo_of(made.data.weapon.caliber)
			for n in rng.randi_range(0, 3):
				if not rounds.is_empty():
					stash.add(_random_item(rng, rounds[rng.randi_range(0, rounds.size() - 1)].id))
	return stash


## A character with the Alpha container (two things in it), random gear in about half the slots and a
## few small things carried.
func _random_inventory(rng: RandomNumberGenerator) -> RefCounted:
	var inventory: RefCounted = inventory_script.new()
	inventory.equip("secure", item("secure_alpha"))
	inventory.equipment.secure.contents.add(item("gold_chain"))
	inventory.equipment.secure.contents.add(item("ammo_545_ps", 17))
	for slot: String in WORN_SLOTS:
		if rng.randf() < 0.55:
			inventory.equip(slot, _random_item(rng, _pick(rng, by_slot[slot]), true))
	for i in rng.randi_range(0, 6):
		inventory.add(_random_item(rng, _pick(rng, small_ids)))
	return inventory


# --- Grids ----------------------------------------------------------------------------------------

func _grid() -> void:
	section("InventoryGrid")
	var grid := _grid_of(4, 3)
	var bag := item("sling_bag")
	check(bag.data.size == Vector2i(2, 3) and grid.place(bag, Vector2i(0, 0), false) and bag.cell == Vector2i.ZERO and grid.items == [bag],
		"a 2x3 bag goes in the corner of a 4x3 grid")
	check(grid.item_at(Vector2i(1, 2)) == bag and grid.item_at(Vector2i(2, 0)) == null, "item_at() finds it in its cells only")
	var belt := item("rig_belt")
	check(not grid.can_place(belt, Vector2i(1, 1), false) and not grid.place(belt, Vector2i(1, 1), false) and grid.items.size() == 1, "nothing goes on top of it")
	check(not grid.can_place(belt, Vector2i(3, 0), false) and grid.can_place(belt, Vector2i(3, 0), true), "a 2x1 belt at the edge only fits turned")
	check(grid.place(belt, Vector2i(3, 0), true) and belt.rotated and belt.footprint() == Vector2i(1, 2), "turned, it takes 1x2")
	check(grid.place(bag, Vector2i(0, 1), true) and bag.footprint() == Vector2i(3, 2) and grid.items.size() == 2, "an item moves and turns within its grid")
	check(grid.find_space(item("secure_alpha")).is_empty() and grid.find_space(item("bandage")) == {"cell": Vector2i(0, 0), "rotated": false},
		"find_space(): no room for a 2x2, the first free cell for a 1x1")
	grid.remove(bag)
	check(grid.items == [belt] and grid.used_cells() == 2, "remove() takes it out")
	var low := _grid_of(3, 2)
	check(low.find_space(item("sling_bag")) == {"cell": Vector2i(0, 0), "rotated": true}, "find_space() turns an item that only fits turned")

	var rounds := _grid_of(4, 2)
	check(rounds.add(item("ammo_545_ps", 40)) and rounds.add(item("ammo_545_ps", 30)) and rounds.items.size() == 2
		and rounds.items[0].count == 60 and rounds.items[1].count == 10, "add() tops up a stack to 60 and starts another")
	var found := item("ammo_545_ps", 10)
	found.fir = true
	check(rounds.add(found) and rounds.items.size() == 3 and rounds.count_of("ammo_545_ps") == 80, "found-in-raid rounds don't merge with bought ones")
	check(rounds.take("ammo_545_ps", 65) == 65 and rounds.items.size() == 2 and rounds.count_of("ammo_545_ps") == 15 and found.count == 10,
		"take() uses the bought rounds first")
	var belted := _grid_of(4, 1)
	var big: RefCounted = found.full_rounds("ammo_545_ps", 150)
	check(belted.add(big) and belted.items.size() == 3 and belted.count_of("ammo_545_ps") == 150
		and belted.items.all(func(each: RefCounted) -> bool: return each.count <= 60), "add() splits 150 rounds into stacks of 60, 60 and 30")
	var tiny := _grid_of(2, 1)
	var left: RefCounted = found.full_rounds("ammo_545_ps", 150)
	check(not tiny.add(left) and left.count == 30 and tiny.count_of("ammo_545_ps") == 120, "with room for two stacks 30 rounds are left over, none lost")
	var loaded := _grid_of(3, 1)
	loaded.load_array([{"id": "ammo_545_ps", "count": 150, "x": 0, "y": 0}])
	check(loaded.count_of("ammo_545_ps") == 150 and loaded.items.size() == 3 and loaded.items.all(func(each: RefCounted) -> bool: return each.count <= 60),
		"load_array() splits a saved stack of 150 the same way")

	var secure: RefCounted = item("secure_alpha").contents
	var pack: RefCounted = item("sling_bag")
	var full_rig := item("rig_belt")
	full_rig.contents.add(item("bandage"))
	check(not secure.accepts(item("rig_belt")) and secure.accepts(item("bandage")), "a secure container takes no rig, pack or case")
	check(pack.contents.accepts(item("rig_belt")) and not pack.contents.accepts(full_rig), "a pack takes an empty rig, not one with something in it")
	check(not pack.contents.accepts(pack) and _grid_of(4, 4).accepts(full_rig), "nothing goes inside itself; the stash takes anything")
	var growing := _grid_of(10, 30)
	var corner := item("bandage")
	growing.place(corner, Vector2i(9, 29), false)
	check(not growing.resize(Vector2i(10, 20)) and growing.size == Vector2i(10, 30) and growing.resize(Vector2i(10, 40))
		and growing.size == Vector2i(10, 40) and corner.cell == Vector2i(9, 29), "resize() only grows, and items stay put")


# --- Character slots ------------------------------------------------------------------------------

func _slots() -> void:
	section("Character slots")
	var slot_ids: Array = inventory_script.SLOTS.map(func(slot: Array) -> String: return slot[0])
	check(slot_ids == ["primary", "secondary", "pistol", "melee", "helmet", "headset", "face_cover", "armor", "rig", "backpack", "secure"], "there are 11 slots")
	# An item and the slots that take it.
	var samples := {"ak_74n": ["primary", "secondary"], "pm_pistol": ["pistol"], by_slot.melee[0]: ["melee"], "ssh68_helmet": ["helmet"],
		by_slot.headset[0]: ["headset"], by_slot.face_cover[0]: ["face_cover"], "paca_armor": ["armor"], "rig_belt": ["rig"],
		"rig_6b5": ["rig"], "sling_bag": ["backpack"], "secure_alpha": ["secure"], "bandage": [], "red_dot": []}
	for id: String in samples:
		var blank: RefCounted = inventory_script.new()
		var sample := item(id)
		var taking: Array = slot_ids.filter(func(slot: String) -> bool: return blank.accepts(slot, sample))
		check(taking == samples[id], "%s goes in: %s" % [sample.data.display_name, ", ".join(taking) if not taking.is_empty() else "no slot"])
	var inventory: RefCounted = inventory_script.new()
	check(not inventory.accepts("melee", item("ammo_545_ps", 2)) and not inventory.equip("backpack", item("bandage")), "a stack or the wrong item isn't equipped")
	var armor := item("paca_armor")
	check(inventory.equip("armor", armor) and inventory.equipment.armor == armor and inventory.slot_of(armor) == "armor", "body armor is equipped")
	check(not inventory.equip("armor", item("armor_module3m")) and inventory.equipment.armor == armor, "a taken slot takes nothing more")
	check(not inventory.accepts("rig", item("rig_6b5")) and inventory.accepts("rig", item("rig_belt")), "over body armor: a plain rig, not an armored one")
	check(inventory.unequip("armor") == armor and inventory.equipment.armor == null and inventory.equip("rig", item("rig_6b5")), "without it the armored rig goes on")
	check(not inventory.accepts("armor", armor) and not inventory.equip("armor", armor), "and body armor doesn't go over the armored rig")
	check(inventory.grids().size() == 2 and inventory.grids()[1] == inventory.equipment.rig.contents, "the rig's grid is one of the character's")


# --- Magazines ------------------------------------------------------------------------------------

func _magazines() -> void:
	section("Magazines")
	var gun: RefCounted = inventory_script.loaded_gun("anvil_pk", db.ammo_of(db.get_item("anvil_pk").weapon.caliber)[0].id)
	var capacity: int = mods.capacity(gun)
	var max_stack: int = gun.magazine[0].data.max_stack
	check(capacity == 100 and gun.rounds_loaded() == 100 and max_stack < 100, "a PK holds 100 rounds, more than a stack (%d)" % max_stack)
	var out: Array = gun.unload()
	var total := 0
	for stack: RefCounted in out:
		total += stack.count
	check(total == 100 and gun.rounds_loaded() == 0 and out.all(func(stack: RefCounted) -> bool: return stack.count <= max_stack),
		"unload() gives all 100 back in stacks within the max stack (%s)" % " + ".join(out.map(func(stack: RefCounted) -> String: return str(stack.count))))
	var rifle := item("ak_74n")
	var found: RefCounted = rifle.full_rounds("ammo_545_ps", 10)
	found.fir = true
	rifle.load_rounds(rifle.full_rounds("ammo_545_ps", 12))
	rifle.load_rounds(found)
	rifle.load_rounds(rifle.full_rounds("ammo_545_bt", 8))
	check(rifle.rounds_loaded() == 30 and rifle.magazine.size() == 3 and rifle.loaded_ammo == "ammo_545_bt" and rifle.rounds_with_status(true) == 10,
		"rounds load in runs by kind and status, the last on top")
	rifle.fire_round()
	check(rifle.rounds_loaded() == 29 and rifle.magazine.back().count == 7, "firing takes the top round")
	var trimmed: Array = rifle.trim_magazine(20)
	check(rifle.rounds_loaded() == 20 and trimmed.size() == 2 and trimmed[0].data.id == "ammo_545_bt" and trimmed[0].count == 7
		and trimmed[1].data.id == "ammo_545_ps" and trimmed[1].count == 2 and trimmed[1].fir, "trim_magazine(20) takes 9 rounds off the top, by kind and status")
	check(rifle.trim_magazine(30).is_empty() and rifle.rounds_loaded() == 20, "trimming to more than is loaded takes nothing")
	var rest: Array = rifle.trim_magazine(0)
	check(rifle.rounds_loaded() == 0 and rifle.magazine.is_empty() and rest.size() == 2 and rest[0].count + rest[1].count == 20, "trim_magazine(0) empties it")
	var belt: RefCounted = inventory_script.loaded_gun("anvil_pk", gun.loaded_ammo)
	var cut: Array = belt.trim_magazine(5)
	check(belt.rounds_loaded() == 5 and cut.size() == 3 and cut.all(func(stack: RefCounted) -> bool: return stack.count <= max_stack),
		"95 trimmed rounds come out in stacks within the max stack")
	var big := item("ak_74n")
	mods.install(big, "magazine", item("ak_mag_60"))
	check(mods.capacity(big) == 60 and mods.capacity(item("ak_74n")) == 30, "a 60-round magazine doubles an AK's capacity")


# --- Sorting --------------------------------------------------------------------------------------

func _sorting() -> void:
	section("Sorting a crowded stash")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260
	var stash := _random_stash(rng, Vector2i(10, 40), 90)
	for i in 6:  # Loose partial stacks that can merge.
		stash.add(item("ammo_545_ps", 7))
		stash.place(item("bandage"), stash.find_space(item("bandage")).cell, false)
	var before := _tally(null, stash)
	var filled: float = float(stash.used_cells()) / stash.cell_count()
	check(stash.items.size() >= 90 and filled > 0.5 and _clean(_faults(null, stash)), "the stash holds %d items, %d%% full" % [stash.items.size(), roundi(filled * 100)])
	var names: Array = grid_script.SORT_NAMES
	check(names == ["Type", "Rarity", "Value", "Name", "Size"], "there are five sort modes")
	for mode in names.size():
		var sorted: bool = stash.sort(mode)
		var unique := {}
		for each in stash.items:
			unique[each] = true
		check(sorted and _tally(null, stash) == before and unique.size() == stash.items.size() and _clean(_faults(null, stash)),
			"by %s: every item is kept exactly once, nothing overlaps, no stack is over" % names[mode])
		var layout := _state(null, stash)
		check(stash.sort(mode) and _state(null, stash) == layout, "by %s: a second sort changes nothing" % names[mode])
	stash.sort(grid_script.SortMode.VALUE)
	var falling := true
	for i in range(1, stash.items.size()):
		falling = falling and stash.items[i - 1].value() >= stash.items[i].value()
	check(falling and stash.items[0].cell == Vector2i.ZERO, "by Value the dearest item comes first, in the corner")
	var cramped := _grid_of(2, 2)
	cramped.place(item("bandage"), Vector2i(1, 1), false)
	cramped.place(item("bandage"), Vector2i(0, 0), false)
	check(cramped.sort(grid_script.SortMode.NAME) and cramped.item_at(Vector2i(0, 0)) != null and cramped.item_at(Vector2i(1, 0)) != null
		and cramped.item_at(Vector2i(1, 1)) == null, "sorting packs items from the top left")


# --- Loadout presets ------------------------------------------------------------------------------

func _presets() -> void:
	section("Loadout presets")
	sm.delete_save()
	gs.new_profile(gs.Faction.BEAR)
	check(presets.add("Raid kit", gs.inventory) == "" and presets.all().size() == 1 and gs.loadout_presets[0].name == "Raid kit", "a preset is saved")
	var preset: Dictionary = presets.all()[0]
	check(preset.slots.primary.id == "ak_74n" and preset.slots.primary.ammo == "ammo_545_ps" and preset.slots.primary.rounds == 30
		and preset.slots.armor.id == "armor_module3m" and not preset.slots.has("secure"), "it records the gun, its rounds and the armor, not the secure container")
	check(preset.pockets == [{"id": "ammo_545_ps", "count": 60}, {"id": "bandage", "count": 1}], "and what's in the pockets")
	check(presets.add("Raid kit", gs.inventory) == "There's already a preset called Raid kit" and presets.all().size() == 1, "a name is used once")
	for i in 4:
		presets.add("", gs.inventory)
	check(presets.all().size() == 5 and presets.all()[4].name == "Preset 4" and presets.add("Sixth", gs.inventory) != "" and presets.all().size() == 5,
		"unnamed presets are numbered, and five is the most")
	check(presets.remove(1) == "" and presets.all().size() == 4 and presets.index_of("Raid kit") == 0, "a preset is deleted")

	# Dressed in nothing but the secure container, with the starter stash to load from.
	var bare: RefCounted = inventory_script.new()
	var secure: RefCounted = gs.inventory.unequip("secure")
	secure.contents.add(item("gold_chain"))
	bare.equip("secure", secure)
	var secure_before := JSON.stringify(secure.to_dict())
	var before := _tally(bare, gs.stash)
	var result: Dictionary = presets.apply(preset, bare, gs.stash)
	check(result.ok and bare.equipment.primary != null and bare.equipment.primary.data.id == "ak_74n", "loading it takes the AK-74N from the stash")
	check(bare.equipment.primary.rounds_loaded() == 30 and bare.equipment.primary.loaded_ammo == "ammo_545_ps", "loaded with 30 PS rounds")
	check(bare.pockets.count_of("ammo_545_ps") == 60 and bare.pockets.count_of("bandage") == 1, "60 rounds and a bandage go in the pockets")
	check(gs.stash.count_of("ak_74n") == 0 and gs.stash.count_of("ammo_545_ps") == 30 and gs.stash.count_of("bandage") == 2, "all of it comes out of the stash")
	check(result.missing == ["Module-3M body armor"] and bare.equipment.armor == null and "Missing: Module-3M body armor" in result.message,
		"the armor the stash doesn't have is listed as missing (%s)" % str(result.missing))
	check(_tally(bare, gs.stash) == before and _clean(_faults(bare, gs.stash)), "nothing is lost or made up")
	check(bare.equipment.secure == secure and JSON.stringify(secure.to_dict()) == secure_before, "the secure container is untouched")
	var again: Dictionary = presets.apply(preset, bare, gs.stash)
	check(again.ok and bare.equipment.primary.rounds_loaded() == 30 and bare.pockets.count_of("ammo_545_ps") == 60 and _tally(bare, gs.stash) == before,
		"loading it again gives the same kit")
	var cramped := _grid_of(1, 1)
	var refused: Dictionary = presets.apply(preset, bare, cramped)
	check(not refused.ok and bare.equipment.primary != null and cramped.items.is_empty(), "a stash with no room for what you wear refuses the load")


func _preset_fuzz() -> void:
	section("Preset loads over 30 random stashes")
	var rng := RandomNumberGenerator.new()
	var others: Array = []
	for index in 30:
		rng.seed = 5000 + index
		others.append(presets.record(_random_inventory(rng), "Other %d" % index))
	var loads := 0
	var lost := 0
	var faulty := 0
	var secure_touched := 0
	var equipped := 0
	for index in 30:
		rng.seed = 7000 + index
		var stash := _random_stash(rng, Vector2i(10, 60), 60)
		var inventory := _random_inventory(rng)
		var own: Dictionary = presets.record(inventory, "Own")
		var before := _tally(inventory, stash)
		var secure := JSON.stringify(inventory.equipment.secure.to_dict())
		for preset: Dictionary in [others[index], own, others[(index + 7) % 30]]:
			var result: Dictionary = presets.apply(preset, inventory, stash)
			loads += 1 if result.ok else 0
			lost += 0 if _tally(inventory, stash) == before else 1
			faulty += 0 if _clean(_faults(inventory, stash)) else 1
			secure_touched += 0 if JSON.stringify(inventory.equipment.secure.to_dict()) == secure else 1
			for slot: String in WORN_SLOTS:
				equipped += 1 if inventory.equipment[slot] else 0
	check(loads == 90, "all 90 loads go through (%d)" % loads)
	check(equipped > 100, "they dress slots from the stash (%d filled)" % equipped)
	check(lost == 0, "no load changes how many of any item there are, at any depth")
	check(faulty == 0, "no load leaves a gun over its magazine's capacity, a stack over its max or items overlapping")
	check(secure_touched == 0, "no load touches the secure container")


# --- Auto-equip -----------------------------------------------------------------------------------

func _planner() -> void:
	section("Auto-equip")
	var bare: RefCounted = inventory_script.new()
	bare.equip("secure", item("secure_alpha"))
	bare.equipment.secure.contents.add(item("ammo_545_bs", 30))
	var stash := _grid_of(10, 20)
	var rifle := item("ak_74n")
	for stack: RefCounted in [rifle, item("ammo_545_ps", 60), item("ammo_545_ps", 60), item("ammo_545_bt", 20), item("armor_module3m"), item("paca_armor"),
			item("armor_atlas"), item("ssh68_helmet"), item("vulkan_helmet"), item("sling_bag"), item("bandage")]:
		stash.add(stack)
	var before := _tally(bare, stash)
	var start := _state(bare, stash)
	var preview: Dictionary = planner.plan(bare, stash, {})
	check(preview.preview and int(preview.changes) > 0 and _state(bare, stash) == start, "plan() says what it would do and changes nothing")
	check(not planner.undo(preview, bare, stash).ok and _state(bare, stash) == start, "a preview can't be undone")
	var plan: Dictionary = planner.apply(bare, stash, {})
	check(bare.equipment.primary == rifle and rifle.rounds_loaded() == 30, "the gun from the stash is equipped and loaded to capacity")
	check(rifle.magazine.back().data.id == "ammo_545_bt" and rifle.magazine.back().count == 20 and rifle.magazine[0].data.id == "ammo_545_ps"
		and rifle.magazine[0].count == 10, "the best rounds owned go on top: 20 BT over 10 PS")
	check(bare.equipment.armor != null and bare.equipment.armor.data.id == "armor_atlas" and bare.equipment.helmet.data.id == "vulkan_helmet"
		and bare.equipment.backpack.data.id == "sling_bag", "with no options the best armor, helmet and the pack are worn")
	check(bare.pockets.count_of("bandage") + bare.equipment.backpack.contents.count_of("bandage") == 1 and stash.count_of("bandage") == 0, "the bandage is packed")
	check(bare.pockets.count_of("ammo_545_ps") + bare.equipment.backpack.contents.count_of("ammo_545_ps") > 0, "spare rounds are packed")
	check(_tally(bare, stash) == before and _clean(_faults(bare, stash)), "nothing is lost or made up")
	check(bare.equipment.secure.contents.count_of("ammo_545_bs") == 30, "the rounds in the secure container stay there")
	var dressed := _state(bare, stash)
	var second: Dictionary = planner.apply(bare, stash, {})
	check(int(second.changes) == 0 and _state(bare, stash) == dressed, "a second run changes nothing")
	var undone: Dictionary = planner.undo(plan, bare, stash)
	check(undone.ok and undone.message == "Undone: everything is back as it was" and _state(bare, stash) == start, "undo() puts everything back exactly")
	check(not planner.undo(plan, bare, stash).ok, "a plan is undone once")

	var limited: Dictionary = planner.apply(bare, stash, {"budget": 60000})
	check(bare.equipment.armor != null and bare.equipment.armor.data.id == "armor_module3m" and bare.equipment.helmet.data.id == "ssh68_helmet"
		and stash.count_of("armor_atlas") == 1 and stash.count_of("vulkan_helmet") == 1, "with a 60,000 budget: the Module-3M and the SSh-68, not the gear worth more")
	check(bare.equipment.primary == rifle and planner.worth(rifle) <= 60000, "the AK-74N is within it")
	planner.undo(limited, bare, stash)
	var protected: Dictionary = planner.apply(bare, stash, {"protect_legendary": true})
	check(bare.equipment.armor != null and bare.equipment.armor.data.id == "armor_module3m" and bare.equipment.helmet.data.id == "ssh68_helmet"
		and stash.count_of("armor_atlas") == 1 and stash.count_of("vulkan_helmet") == 1, "with Protect Legendary the Legendary armor and helmet stay in the stash")
	planner.undo(protected, bare, stash)
	var worn := item("armor_atlas")
	stash.take("armor_atlas", 1)
	bare.equip("armor", worn)
	planner.apply(bare, stash, {"budget": 60000, "protect_legendary": true})
	check(bare.equipment.armor == worn, "what you already wear is never taken off because of the options")
	check(planner.clean_options({"budget": -5, "protect_legendary": "yes"}) == {"budget": 0, "protect_legendary": false}
		and planner.clean_options({"budget": 1500.0, "protect_legendary": true}) == {"budget": 1500, "protect_legendary": true}, "options are made safe")


func _planner_fuzz() -> void:
	section("Auto-equip over 40 random stashes x 2 option sets")
	var rng := RandomNumberGenerator.new()
	var runs := 0
	var changed := 0
	var lost := 0
	var faulty := 0
	var secure_touched := 0
	var over_options := 0
	var not_restored := 0
	for index in 40:
		for options: Dictionary in OPTION_SETS:
			rng.seed = 9000 + index
			var stash := _random_stash(rng, Vector2i(10, 60), 60)
			var inventory := _random_inventory(rng)
			var start := _state(inventory, stash)
			var before := _tally(inventory, stash)
			var secure := JSON.stringify(inventory.equipment.secure.to_dict())
			var worn: Dictionary = inventory.equipment.duplicate()
			var plan: Dictionary = planner.apply(inventory, stash, options)
			runs += 1
			changed += 1 if int(plan.changes) > 0 else 0
			lost += 0 if _tally(inventory, stash) == before else 1
			faulty += 0 if _clean(_faults(inventory, stash)) else 1
			secure_touched += 0 if JSON.stringify(inventory.equipment.secure.to_dict()) == secure else 1
			for slot: String in WORN_SLOTS:
				var now: RefCounted = inventory.equipment[slot]
				if now == null or now == worn[slot]:
					continue
				var picked: RefCounted = now.duplicate_deep()  # As it was picked: a rig or pack empty.
				if picked.contents:
					picked.contents.items.clear()
				if not planner.allowed(picked, planner.clean_options(options)):
					over_options += 1
			var undone: Dictionary = planner.undo(plan, inventory, stash)
			not_restored += 0 if undone.ok and _state(inventory, stash) == start else 1
	check(runs == 80 and changed >= 70, "auto-equip changes something in nearly every run (%d of %d)" % [changed, runs])
	check(lost == 0, "no run changes how many of any item there are, at any depth (%d)" % lost)
	check(faulty == 0, "no run leaves a stack over its max, a gun over its magazine's capacity or items overlapping (%d)" % faulty)
	check(secure_touched == 0, "no run touches the secure container (%d)" % secure_touched)
	check(over_options == 0, "nothing newly worn is over the budget or Legendary when the options rule it out (%d)" % over_options)
	check(not_restored == 0, "apply() then undo() always restores the exact state (%d)" % not_restored)

	# A second run. The rigs and packs lying in these stashes hold barter goods, nothing auto-equip takes
	# (one holding only rounds or meds is emptied by the first run, and then it's a candidate for the second).
	var again := 0
	var second_changes := 0
	for index in 40:
		for options: Dictionary in OPTION_SETS:
			rng.seed = 9000 + index
			var stash := _random_stash(rng, Vector2i(10, 60), 60, junk_ids)
			var inventory := _random_inventory(rng)
			var first: Dictionary = planner.apply(inventory, stash, options)
			again += 1 if int(first.changes) > 0 else 0
			var dressed := _state(inventory, stash)
			var second: Dictionary = planner.apply(inventory, stash, options)
			second_changes += 0 if int(second.changes) == 0 and _state(inventory, stash) == dressed else 1
	check(again >= 70 and second_changes == 0, "a second run never changes anything (%d of 80 first runs changed something, %d second runs)" % [again, second_changes])
