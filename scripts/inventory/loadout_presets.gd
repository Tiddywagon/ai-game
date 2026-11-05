class_name LoadoutPresets
extends RefCounted
## Loadout presets (DESIGN.md §16.6): up to MAX named loadouts kept in the profile
## (GameState.loadout_presets, saved). A preset records what you wear and carry by item id, not the items
## themselves: each slot's item with the parts fitted to it (by slot path), its upgrade level and, for a
## gun, the round loaded and how many; and what's in the pockets, rig and backpack (ids and counts). The
## secure container isn't part of it: a preset never touches it or what's in it.
##
## Loading one (apply()) dresses you from the stash. What you wear goes into the stash first, loose (the
## pockets, rig and backpack emptied into it too); if the stash can't hold all of it nothing changes and
## it says so. Then each slot takes the best match from the stash (at any depth, never from a container
## with something in it): the same item, then the most matching parts, then the best durability, then
## the nearest upgrade level. Parts the matched item lacks are fitted from loose parts in the stash (what
## they replace goes to the stash); rounds a smaller magazine no longer holds come out into the stash.
## Guns are loaded with the preset's round from the stash, up to the recorded count and the free room in
## the magazine, after any other rounds come out. Then the pockets, rig and backpack are filled; a piece
## with no room on you goes back where it was in the stash (inside a backpack there too). Whatever isn't
## found is listed ("Missing: 2 × Bandage, AK-74N rail handguard"; an id no longer in the game by its id),
## whatever has no room too, and the rest still loads. Nothing is ever lost or made up: the load runs on
## copies first, and if anything would have nowhere to go (the stash too full for the rounds out of a
## smaller magazine) nothing changes and it says so. Stacks never go over their max stack, and a gun
## never holds more than its magazine.

## Presets a profile keeps at most.
const MAX := 5
## A preset's name is cut to this many characters.
const NAME_LENGTH := 24
## The slots a preset records and loads, in the order apply() equips them (not the secure container).
const SLOTS: Array[String] = ["helmet", "headset", "face_cover", "armor", "rig", "backpack", "primary", "secondary",
	"pistol", "melee"]
## The grids a preset fills, in order: the pockets, then the worn rig's and backpack's.
const CONTAINERS: Array[String] = ["pockets", "rig", "backpack"]


# --- The presets in the profile --------------------------------------------------------------------

## The presets, as GameState keeps them.
static func all() -> Array:
	return GameState.loadout_presets


## Saves what `inventory` wears and carries as a new preset named `name` (an empty name gets "Preset 1",
## "Preset 2"...). "" on success, else why not (MAX presets already, the name taken).
static func add(name: String, inventory: Inventory) -> String:
	if all().size() >= MAX:
		return "%d presets already: overwrite or delete one" % MAX
	var cleaned := clean_name(name)
	if cleaned == "":
		cleaned = _free_name()
	if index_of(cleaned) >= 0:
		return "There's already a preset called %s" % cleaned
	all().append(record(inventory, cleaned))
	return ""


## Replaces preset `index` with what `inventory` wears and carries now, keeping its name.
static func overwrite(index: int, inventory: Inventory) -> String:
	if index < 0 or index >= all().size():
		return "No such preset"
	all()[index] = record(inventory, str(all()[index].get("name", "")))
	return ""


## Renames preset `index` to `name`. "" on success, else why not (empty, taken by another).
static func rename(index: int, name: String) -> String:
	if index < 0 or index >= all().size():
		return "No such preset"
	var cleaned := clean_name(name)
	if cleaned == "":
		return "Type a name first"
	var other := index_of(cleaned)
	if other >= 0 and other != index:
		return "There's already a preset called %s" % cleaned
	all()[index].name = cleaned
	return ""


## Deletes preset `index`.
static func remove(index: int) -> String:
	if index < 0 or index >= all().size():
		return "No such preset"
	all().remove_at(index)
	return ""


## The index of the preset called `name` (any case), or -1.
static func index_of(name: String) -> int:
	for i in all().size():
		if str(all()[i].get("name", "")).to_lower() == name.to_lower():
			return i
	return -1


## `name` without spaces around it, at most NAME_LENGTH characters.
static func clean_name(name: String) -> String:
	return name.strip_edges().left(NAME_LENGTH).strip_edges()


## "Preset N" with the lowest N no preset is called.
static func _free_name() -> String:
	var number := 1
	while index_of("Preset %d" % number) >= 0:
		number += 1
	return "Preset %d" % number


# --- Recording ------------------------------------------------------------------------------------

## A preset named `name` of what `inventory` wears (every slot but the secure container) and carries in
## its pockets, rig and backpack.
static func record(inventory: Inventory, name: String) -> Dictionary:
	var slots := {}
	for slot in SLOTS:
		var item: ItemInstance = inventory.equipment.get(slot)
		if item == null:
			continue
		var entry := {"id": item.data.id}
		var parts := {}
		for each in WeaponMods.walk(item):
			if each.mod:
				parts[str(each.path)] = (each.mod as ItemInstance).data.id
		if not parts.is_empty():
			entry.parts = parts
		if item.upgrade_level > 0:
			entry.upgrade = item.upgrade_level
		if item.is_gun() and item.loaded_ammo != "":
			entry.ammo = item.loaded_ammo
			entry.rounds = item.rounds_loaded()
		slots[slot] = entry
	var preset := {"name": name, "slots": slots}
	for container in CONTAINERS:
		var grid := _grid_of(inventory, container)
		preset[container] = _counts(grid.items) if grid else []
	return preset


## [{"id", "count"}] for `items`, one entry per item id in the order they come.
static func _counts(items: Array[ItemInstance]) -> Array:
	var result := []
	var at := {}
	for item in items:
		if at.has(item.data.id):
			result[at[item.data.id]].count += item.count
		else:
			at[item.data.id] = result.size()
			result.append({"id": item.data.id, "count": item.count})
	return result


## The pockets, or the grid of the worn rig or backpack (null without one).
static func _grid_of(inventory: Inventory, container: String) -> InventoryGrid:
	if container == "pockets":
		return inventory.pockets
	var item: ItemInstance = inventory.equipment.get(container)
	return item.contents if item else null


## Saved presets (from JSON) made safe to use: at most MAX, each with a name, its slots ({"id", "parts",
## "upgrade", "ammo", "rounds"}, whole numbers back to ints) and its container lists; anything else is
## dropped.
static func sanitize(saved: Variant) -> Array:
	var result := []
	if not saved is Array:
		return result
	for entry: Variant in saved:
		if result.size() >= MAX:
			break
		if not entry is Dictionary:
			continue
		var preset := {"name": clean_name(str(entry.get("name", ""))), "slots": {}}
		if preset.name == "":
			preset.name = "Preset %d" % (result.size() + 1)
		var slots: Variant = entry.get("slots", {})
		if slots is Dictionary:
			for slot in SLOTS:
				var saved_slot: Variant = slots.get(slot)
				if not saved_slot is Dictionary or str(saved_slot.get("id", "")) == "":
					continue
				var clean := {"id": str(saved_slot.id)}
				if saved_slot.get("parts") is Dictionary:
					var parts := {}
					for path: Variant in saved_slot.parts:
						parts[str(path)] = str(saved_slot.parts[path])
					clean.parts = parts
				if int(saved_slot.get("upgrade", 0)) > 0:
					clean.upgrade = int(saved_slot.upgrade)
				if str(saved_slot.get("ammo", "")) != "":
					clean.ammo = str(saved_slot.ammo)
					clean.rounds = maxi(int(saved_slot.get("rounds", 0)), 0)
				preset.slots[slot] = clean
		for container in CONTAINERS:
			var list := []
			var saved_list: Variant = entry.get(container, [])
			if saved_list is Array:
				for each: Variant in saved_list:
					if each is Dictionary and str(each.get("id", "")) != "" and int(each.get("count", 0)) > 0:
						list.append({"id": str(each.id), "count": int(each.count)})
			preset[container] = list
		result.append(preset)
	return result


## A short line for the presets list: "AK-74N · 6B23-1 body armor · 124 items carried" (every item and
## round in the pockets, rig and backpack).
static func summary(preset: Dictionary) -> String:
	var parts: Array[String] = []
	var slots: Dictionary = preset.get("slots", {})
	for slot in ["primary", "secondary", "pistol", "armor", "rig"]:
		if slots.has(slot) and ItemDB.has_item(str(slots[slot].id)):
			parts.append(ItemDB.get_item(str(slots[slot].id)).display_name)
		if parts.size() >= 2:
			break
	var carried := 0
	for container in CONTAINERS:
		for entry: Dictionary in preset.get(container, []):
			carried += int(entry.get("count", 0))
	if parts.is_empty() and carried == 0:
		return "Nothing worn"
	parts.append("%d item%s carried" % [carried, "" if carried == 1 else "s"])
	return "  ·  ".join(parts)


# --- Loading --------------------------------------------------------------------------------------

## Loads `preset` onto `inventory` from `stash` (see the class notes). Returns {"ok": false, "message"}
## when the stash can't hold what you wear, or the rounds a smaller magazine leaves over (nothing
## changed), else {"ok": true, "missing": [names], "no_room": [names], "stranded": [] (see _dress()),
## "message": "Loaded Raid kit. Missing: 2 × Bandage"}.
static func apply(preset: Dictionary, inventory: Inventory, stash: InventoryGrid) -> Dictionary:
	if not _room_to_strip(inventory, stash):
		return {"ok": false, "message": "Not enough room in the stash for what you're wearing: make room first",
			"missing": [], "no_room": []}
	# A trial on copies first: anything that would be left with nowhere to go stops the load before
	# anything moves (the trial and the real load do exactly the same).
	var trial := _dress(preset, inventory.duplicate_deep(), _copy_of(stash))
	if not trial.stranded.is_empty():
		return {"ok": false, "message": "Not enough room in the stash for %s: make room first" % ", ".join(trial.stranded),
			"missing": [], "no_room": []}
	return _dress(preset, inventory, stash)


## The load itself (apply() checks first): {"ok": true, "missing", "no_room", "stranded" (names of what
## nothing could take: a trial's reason to refuse), "message"}.
static func _dress(preset: Dictionary, inventory: Inventory, stash: InventoryGrid) -> Dictionary:
	_strip(inventory, stash)
	var order: Array[String] = []
	var notes := {"missing": {}, "no_room": {}, "stranded": {}, "order": order}
	var slots: Dictionary = preset.get("slots", {})
	for slot in SLOTS:
		if slots.has(slot):
			_equip(slots[slot], slot, inventory, stash, notes)
	for container in CONTAINERS:
		for entry: Dictionary in preset.get(container, []):
			_pack(str(entry.get("id", "")), int(entry.get("count", 0)), _grid_of(inventory, container), inventory, stash, notes)
	inventory.changed.emit()
	stash.changed.emit()
	var missing_names := _names(notes.missing, order)
	var no_room_names := _names(notes.no_room, order)
	var message := "Loaded %s." % str(preset.get("name", "the preset"))
	if not missing_names.is_empty():
		message += " Missing: %s." % ", ".join(missing_names)
	if not no_room_names.is_empty():
		message += " No room for: %s." % ", ".join(no_room_names)
	return {"ok": true, "missing": missing_names, "no_room": no_room_names, "stranded": _names(notes.stranded, order),
		"message": message}


## A copy of `grid` and everything in it, in the same places (for apply()'s trial).
static func _copy_of(grid: InventoryGrid) -> InventoryGrid:
	var copy := InventoryGrid.new(grid.size, grid.kind)
	copy.load_array(grid.to_array())
	return copy


## Everything worn (but the secure container) and carried in the pockets, rig and backpack, loose: what
## _strip() puts in the stash.
static func _worn_and_carried(inventory: Inventory) -> Array[ItemInstance]:
	var loose: Array[ItemInstance] = []
	loose.append_array(inventory.pockets.items)
	for grid in _worn_grids(inventory):
		loose.append_array(grid.items)
	for slot in SLOTS:
		if inventory.equipment.get(slot):
			loose.append(inventory.equipment[slot])
	return loose


## True if the stash can hold everything _strip() puts in it.
static func _room_to_strip(inventory: Inventory, stash: InventoryGrid) -> bool:
	return stash.has_room_for_all(_worn_and_carried(inventory))


## Puts everything worn (but the secure container) and carried in the pockets, rig and backpack into
## the stash, loose (apply() checked that it all fits, the way add() puts it).
static func _strip(inventory: Inventory, stash: InventoryGrid) -> void:
	for grid: InventoryGrid in [inventory.pockets] + _worn_grids(inventory):
		for item in grid.items.duplicate():
			grid.remove(item)
			if not stash.add(item) and item.count > 0:
				grid.add(item)  # Never lost (has_room_for_all() said it fits).
	for slot in SLOTS:
		var item := inventory.unequip(slot)
		if item and not stash.add(item):
			inventory.equip(slot, item)  # Never lost (has_room_for_all() said it fits).


static func _worn_grids(inventory: Inventory) -> Array[InventoryGrid]:
	var result: Array[InventoryGrid] = []
	for container in ["rig", "backpack"]:
		var item: ItemInstance = inventory.equipment.get(container)
		if item and item.contents:
			result.append(item.contents)
	return result


## Equips the best match for preset slot `entry` in `slot`, fits its parts, trims and loads it.
static func _equip(entry: Dictionary, slot: String, inventory: Inventory, stash: InventoryGrid, notes: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if not ItemDB.has_item(id):
		_note(notes, "missing", _gone_name(id), 1)
		return
	var found := _best_match(stash, id, entry)
	if found.is_empty():
		_note(notes, "missing", ItemDB.get_item(id).display_name, 1)
		return
	var item: ItemInstance = found.item
	var taken := _taken_from(item, found.grid)
	(found.grid as InventoryGrid).remove(item)
	item.rotated = false
	if not inventory.equip(slot, item):
		item.rotated = taken.rotated
		_put_back(taken, inventory, stash, notes)
		_note(notes, "missing", item.data.display_name, 1)
		return
	_fit_parts(item, entry.get("parts", {}), stash, notes)
	if item.is_gun():
		_trim(item, stash, notes)
		if str(entry.get("ammo", "")) != "":
			_load(item, str(entry.ammo), int(entry.get("rounds", WeaponMods.capacity(item))), stash, notes)


## The stash's best item `id` for preset slot `entry`: {"item", "grid"}, or {} if there's none. Only
## whole, single items (a container only when empty); best: the most matching parts, then the best
## durability, then the upgrade level nearest the preset's, then the most uses left.
static func _best_match(stash: InventoryGrid, id: String, entry: Dictionary) -> Dictionary:
	var best := {}
	var best_key := []
	var parts: Dictionary = entry.get("parts", {})
	var upgrade := int(entry.get("upgrade", 0))
	for found in _stash_items(stash):
		var item: ItemInstance = found.item
		if item.data.id != id or item.count != 1 or not item.is_empty_container() or item.hidden:
			continue
		var matched := 0
		for path: String in parts:
			var part := WeaponMods.mod_at(item, path)
			if part and part.data.id == str(parts[path]):
				matched += 1
		var key := [matched, item.durability / maxf(item.max_durability, 1.0), -absi(item.upgrade_level - upgrade), item.charges]
		if best.is_empty() or _better(key, best_key):
			best = found
			best_key = key
	return best


static func _better(a: Array, b: Array) -> bool:
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return float(a[i]) > float(b[i])
	return false


## Every item in the stash's grids at any depth (inside rigs, backpacks and cases too, not fitted parts
## or loaded rounds): [{"item", "grid"}].
static func _stash_items(grid: InventoryGrid) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in grid.items:
		result.append({"item": item, "grid": grid})
		if item.contents:
			result.append_array(_stash_items(item.contents))
	return result


## Fits the preset's parts ({slot path: id}, parents first) that `item` lacks, from loose parts in the
## stash; the part it replaces goes to the stash (if there's no room for it, the swap is undone and the
## preset's part is listed missing). A part no longer in the game is listed missing too.
static func _fit_parts(item: ItemInstance, parts: Dictionary, stash: InventoryGrid, notes: Dictionary) -> void:
	var paths: Array = parts.keys()
	paths.sort_custom(func(a: String, b: String) -> bool: return a.count("/") < b.count("/"))
	for path: String in paths:
		var want := str(parts[path])
		if not ItemDB.has_item(want):
			_note(notes, "missing", _gone_name(want), 1)
			continue
		var fitted := WeaponMods.mod_at(item, path)
		if fitted and fitted.data.id == want:
			continue
		var found := {}
		for each in _stash_items(stash):
			var part: ItemInstance = each.item
			if part.data.id == want and part.count == 1 and WeaponMods.install_block_reason(item, path, part) == "":
				found = each
				break
		if found.is_empty():
			_note(notes, "missing", ItemDB.get_item(want).display_name, 1)
			continue
		var part: ItemInstance = found.item
		var holder: InventoryGrid = found.grid
		var cell := part.cell
		var turned := part.rotated
		holder.remove(part)
		var replaced := WeaponMods.install(item, path, part)
		if replaced and not stash.add(replaced):
			WeaponMods.install(item, path, replaced)
			holder.place(part, cell, turned)
			_note(notes, "missing", part.data.display_name, 1)
		elif replaced == null and WeaponMods.mod_at(item, path) != part:
			holder.place(part, cell, turned)
			_note(notes, "missing", part.data.display_name, 1)


## Takes the rounds `gun`'s magazine no longer holds (a smaller one fitted) out into the stash, in full
## stacks. Any the stash has no room for stay loaded and are noted as stranded: apply()'s trial then
## refuses the load, so a gun never ends up holding more than its magazine.
static func _trim(gun: ItemInstance, stash: InventoryGrid, notes: Dictionary) -> void:
	for rounds in gun.trim_magazine(WeaponMods.capacity(gun)):
		if not stash.add(rounds) and rounds.count > 0:
			_note(notes, "stranded", rounds.data.display_name, rounds.count)
			gun.load_rounds(rounds)


## Loads `gun` with `rounds` (at most its magazine) of `ammo` from the stash. Rounds of another kind come
## out into the stash first; any with no room stay loaded under the new ones, and the new ones that then
## don't fit are listed under no room. The shortfall in the stash is listed missing.
static func _load(gun: ItemInstance, ammo: String, rounds: int, stash: InventoryGrid, notes: Dictionary) -> void:
	if not ItemDB.has_item(ammo):
		_note(notes, "missing", _gone_name(ammo), maxi(rounds, 1))
		return
	if gun.magazine.any(func(each: ItemInstance) -> bool: return each.data.id != ammo):
		var kept: Array[ItemInstance] = []
		for stack in gun.unload():
			if stack.data.id == ammo or (not stash.add(stack) and stack.count > 0):
				kept.append(stack)
		for stack in kept:
			gun.load_rounds(stack)
	var capacity := WeaponMods.capacity(gun)
	var have := 0
	for each in gun.magazine:
		if each.data.id == ammo:
			have += each.count
	var wanted := maxi(mini(rounds, capacity) - have, 0)
	var need := clampi(wanted, 0, maxi(capacity - gun.rounds_loaded(), 0))
	if wanted > need:
		_note(notes, "no_room", ItemDB.get_item(ammo).display_name, wanted - need)
	for taken in _take(stash, ammo, need):
		gun.load_rounds(taken.piece)
		need -= (taken.piece as ItemInstance).count
	gun.loaded_ammo = ammo
	if need > 0:
		_note(notes, "missing", ItemDB.get_item(ammo).display_name, need)


## Up to `amount` of stackable item `id` taken out of the stash (the stash's own grid first, then the
## containers in it), each piece keeping its status and within a stack. Each comes with where it was
## (_taken_from(): its grid and spot, and the stack it was split off if it's part of one).
static func _take(stash: InventoryGrid, id: String, amount: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if amount <= 0:
		return result
	var grids: Array[InventoryGrid] = [stash]
	for each in _stash_items(stash):
		if (each.item as ItemInstance).contents:
			grids.append((each.item as ItemInstance).contents)
	var left := amount
	for grid in grids:
		var counts := {}
		for item in grid.items:
			if item.data.id == id:
				counts[item] = item.count
		for piece in grid.take_pieces(id, left):
			left -= piece.count
			var taken := _taken_from(piece, grid)
			if not counts.has(piece):  # Split off a stack that stays in the grid.
				for stack: ItemInstance in counts:
					if stack in grid.items and stack.count < int(counts[stack]):
						taken.stack = stack
			result.append(taken)
		if left <= 0:
			break
	return result


## Where `piece` (about to leave `grid`, or just split off a stack there) was: {"piece", "grid", "cell",
## "rotated", "stack"} for _put_back().
static func _taken_from(piece: ItemInstance, grid: InventoryGrid) -> Dictionary:
	return {"piece": piece, "grid": grid, "cell": piece.cell, "rotated": piece.rotated, "stack": null}


## Puts a piece taken from the stash (`taken`, from _taken_from()) back where it was: onto the stack it
## was split off, else its own spot, else anywhere in its grid, the stash or on the character. Its spot
## is always free (pieces go back in the reverse order they were taken), so nothing is ever dropped;
## what nothing takes is noted as stranded.
static func _put_back(taken: Dictionary, inventory: Inventory, stash: InventoryGrid, notes: Dictionary) -> void:
	var piece: ItemInstance = taken.piece
	var grid: InventoryGrid = taken.grid
	var stack: ItemInstance = taken.stack
	if stack and stack in grid.items and stack.same_status(piece) and stack.count + piece.count <= stack.data.max_stack:
		stack.count += piece.count
		grid.changed.emit()
		return
	if grid.place(piece, taken.cell, taken.rotated) or grid.add(piece) or stash.add(piece) or inventory.add(piece):
		return
	_note(notes, "stranded", piece.data.display_name, piece.count)


## Takes `count` of item `id` from the stash into `grid` (the pockets, or the worn rig's or backpack's;
## with no such grid, wherever it fits on the character). What isn't in the stash is listed missing;
## what doesn't fit goes back where it was in the stash and is listed under no room.
static func _pack(id: String, count: int, grid: InventoryGrid, inventory: Inventory, stash: InventoryGrid, notes: Dictionary) -> void:
	if count <= 0:
		return
	if not ItemDB.has_item(id):
		_note(notes, "missing", _gone_name(id), count)
		return
	var name := ItemDB.get_item(id).display_name
	var pieces: Array[Dictionary] = []
	if ItemDB.get_item(id).max_stack > 1:
		pieces = _take(stash, id, count)
	else:
		for i in count:
			var found := _best_match(stash, id, {})
			if found.is_empty():
				break
			pieces.append(_taken_from(found.item, found.grid))
			(found.grid as InventoryGrid).remove(found.item)
	var taken := 0
	var left_over: Array[Dictionary] = []
	for each in pieces:
		var piece: ItemInstance = each.piece
		taken += piece.count
		var placed := grid.add(piece) if grid else inventory.add(piece)
		if not placed and piece.count > 0:
			_note(notes, "no_room", name, piece.count)
			left_over.append(each)
	left_over.reverse()  # The last taken goes back first, so every spot is still free.
	for each in left_over:
		_put_back(each, inventory, stash, notes)
	if taken < count:
		_note(notes, "missing", name, count - taken)


## The name a preset's item id gets when the item is no longer in the game.
static func _gone_name(id: String) -> String:
	return "%s (no longer in the game)" % id


## Adds `count` of `name` to `notes[list]` ("missing", "no_room" or "stranded"), keeping the order names
## first came up in.
static func _note(notes: Dictionary, list: String, name: String, count: int) -> void:
	var into: Dictionary = notes[list]
	into[name] = int(into.get(name, 0)) + count
	var order: Array[String] = notes.order
	if not name in order:
		order.append(name)


## "2 × Bandage" (just the name for one) for each entry of `counts`, in `order`.
static func _names(counts: Dictionary, order: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for name in order:
		if counts.has(name):
			result.append("%d × %s" % [counts[name], name] if int(counts[name]) > 1 else name)
	return result
