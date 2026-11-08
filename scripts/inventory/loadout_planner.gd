class_name LoadoutPlanner
extends RefCounted
## Auto-equip (DESIGN.md §16.6): dresses you in the best gear you own from the stash. Pure logic, no UI:
## the LOADOUT screen's AUTO-EQUIP calls apply() and shows the plan's summary lines; UNDO calls undo().
##
## What it does, in order:
## 1. Body armor and tactical rig as a pair: body armor with a plain rig is weighed against an armored rig
##    alone (they exclude each other), so the best combination wins, not the best piece per slot.
## 2. Helmet and face cover as a pair (only the piece that stops more takes a face hit, so a mask counts
##    for what it adds over a helmet's face shield), then headset, backpack and melee, each on its own.
## 3. Primary, secondary and pistol, in that order (pistols only in the pistol slot). Then each gun in
##    those slots gets the biggest magazine you own that fits (if its magazine slot is empty) and is
##    loaded to capacity with the best rounds you own for it, best on top: from the stash first, then
##    from the pockets, rig and backpack. Rounds it held of a worse kind go back to the stash (a new gun's
##    rounds the options rule out too; a gun you wore keeps those). A gun left short says so.
## 4. Meds: one of each kind (bandage, tourniquet, splint, medkit; by the med's "type") in the pockets or
##    rig, where quick treatment reaches, unless you carry that kind there already: the best you own,
##    else a smaller one that fits.
## 5. Spare rounds for each gun (spare_magazines magazines' worth) in the rig, then the pockets, then the
##    backpack, best rounds first. Rounds you carry of its caliber count when they're among the best you
##    own; worse ones you carry go back to the stash (whole stacks) to make room for better ones.
## An empty slot takes the best candidate in the stash (at any depth, never a container with something in
## it); a worn item is replaced only by one that scores clearly better (upgrade margin), and goes to the
## stash. A new rig or backpack takes what the old one held, as much as fits (the rest stays in the old
## one, in the stash). The secure container and what's in it are never touched.
##
## Scores (DESIGN.md §16.6; tunables in data/config/auto_equip.json, checked on load: problems()): armor
## (body armor, armored rigs, helmets with their face shields, ballistic face covers) by protection: over
## each zone it covers, the zone's weight × ArmorRules.resistance(class, durability left) (head and thorax
## weigh most, so a higher class wins), less a penalty per kg and a cost for the hearing it takes; a
## helmet and face cover together count each zone once, the piece that stops more; rigs and backpacks by room (cells at their upgrade level) less a smaller penalty per kg (an
## armored rig adds its protection); guns by WeaponStats with their parts (ergonomics, recoil, spread,
## durability, jam chance, fire rate) plus the best round you own for them (penetration and damage);
## headsets by hearing; melee by damage; cosmetic face covers score 0. Within rarity_epsilon the rarer
## item wins.
##
## Options (clean_options()): "budget" (roubles, 0 for no limit): nothing worth more is used (worth():
## value(), a gun with its parts but not its rounds, rounds and meds one at a time; a gun taken from the
## stash with the magazine it gets fitted); "protect_legendary":
## no Legendary item, round or med is used, and a gun or helmet with a Legendary part counts as Legendary.
## What you already wear is never taken off because of the options.
##
## Nothing is lost or made up: what has no room goes back where it came from and the plan says so ("No
## room for 20 × 5.45x39 BT (spare rounds)"); stacks stay within their max stack and a gun never holds
## more than its magazine. apply() returns the plan: its moves (the journal of everything it did) and its
## summary lines. undo() reverses exactly those moves, newest first, diff-based: items that reached the
## stash meanwhile (insurance returns land any time) stay; an item whose old spot is taken goes elsewhere
## in its grid, else the stash. Each move takes back only what it put somewhere (never what landed on the
## same stack since); a move that can't go back without leaving something with nowhere to go stays as
## auto-equip did it, and undo() says so. plan() works out the same on copies and changes nothing.

const CONFIG_PATH := "res://data/config/auto_equip.json"
## Single slots filled after the body armor and rig and the helmet and face cover, in order.
const GEAR_SLOTS: Array[String] = ["headset", "backpack", "melee"]
## Gun slots, in the order they're filled.
const GUN_SLOTS: Array[String] = ["primary", "secondary", "pistol"]
## Where spare rounds go, in order, and where meds go (quick treatment reaches them there).
const AMMO_GRIDS: Array[String] = ["rig", "pockets", "backpack"]
const MED_GRIDS: Array[String] = ["pockets", "rig"]
## Summary line tones: something changed, something stayed as it was, something didn't work out.
const CHANGE := "change"
const KEPT := "kept"
const WARNING := "warning"
## Config sections and the numbers each must have (problems()).
const SECTIONS := {
	"armor": ["weight_penalty", "hearing"],
	"carry": ["cell", "weight_penalty"],
	"gun": ["ergonomics", "vertical_recoil", "horizontal_recoil", "base_spread", "durability", "jam_chance", "fire_rate", "ammo"],
	"ammo": ["penetration", "damage", "pellet_exponent"],
	"upgrade": ["margin", "min"],
}
const NUMBERS: Array[String] = ["hearing", "melee_damage", "rarity_epsilon", "spare_magazines"]
## Every zone armor can cover (ArmorRules.zone_name()): each needs a weight.
const ZONES: Array[String] = ["head", "face", "thorax", "stomach", "left_arm", "right_arm", "left_leg", "right_leg"]

## The file config() loads (tests point it at a broken copy), and what was wrong with it when it last
## loaded (each problem is also an error).
static var path := CONFIG_PATH
static var load_problems: Array[String] = []
static var _config := {}
static var _loaded := false
## A character with nothing on: which slot an item could go in.
static var _blank: Inventory


# --- Config ---------------------------------------------------------------------------------------

## data/config/auto_equip.json, checked the first time it loads (problems()). {} if it's missing or broken:
## every score is then 0 and the rarer item wins.
static func config() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_config = parsed if parsed is Dictionary else {}
		load_problems = problems()
		for problem in load_problems:
			push_error("LoadoutPlanner: %s" % problem)
	return _config


## Forgets what was loaded (tests that point `path` elsewhere).
static func reload() -> void:
	_config = {}
	_loaded = false
	load_problems.clear()


## What's wrong with auto_equip.json: a section or number missing or negative, a zone without a weight,
## med kinds that aren't a list of {"id", "name", "types": [med types]} with unique ids. Empty if it's fine.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var data := config()
	if data.is_empty():
		found.append("%s isn't valid JSON" % path)
		return found
	for section: String in SECTIONS:
		var values: Variant = data.get(section)
		if not values is Dictionary:
			found.append("no %s object" % section)
			continue
		for key: String in SECTIONS[section]:
			if not _is_number(values.get(key)) or float(values[key]) < 0.0:
				found.append("%s.%s must be a number, 0 or more" % [section, key])
	var zones: Variant = data.get("armor", {}).get("zones") if data.get("armor") is Dictionary else null
	if not zones is Dictionary:
		found.append("armor.zones must be an object")
	else:
		for zone in ZONES:
			if not _is_number(zones.get(zone)) or float(zones[zone]) < 0.0:
				found.append("armor.zones.%s must be a number, 0 or more" % zone)
	for key in NUMBERS:
		if not _is_number(data.get(key)) or float(data[key]) < 0.0:
			found.append("%s must be a number, 0 or more" % key)
	var meds: Variant = data.get("meds")
	if not meds is Array or (meds as Array).is_empty():
		found.append("meds must be a list of med kinds")
	else:
		var ids := {}
		for kind: Variant in meds:
			if not kind is Dictionary or str(kind.get("id", "")) == "" or str(kind.get("name", "")) == "" \
					or not kind.get("types") is Array or (kind.types as Array).is_empty():
				found.append("each med kind needs an id, a name and a list of types")
				continue
			if ids.has(str(kind.id)):
				found.append("med kind %s is listed twice" % kind.id)
			ids[str(kind.id)] = true
	return found


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


## Number `key` of config section `section` ("" for a top-level number), or 0.
static func _num(section: String, key: String) -> float:
	var values: Variant = config() if section == "" else config().get(section)
	if not values is Dictionary:
		return 0.0
	var value: Variant = values.get(key)
	return float(value) if _is_number(value) else 0.0


## The med kinds, from the config: [{"id", "name", "types"}].
static func med_kinds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var meds: Variant = config().get("meds")
	if meds is Array:
		for kind: Variant in meds:
			if kind is Dictionary and kind.get("types") is Array:
				result.append(kind)
	return result


# --- Options --------------------------------------------------------------------------------------

## Auto-equip options from saved or typed data, made safe: {"budget": roubles, 0 for no limit,
## "protect_legendary": bool}.
static func clean_options(saved: Variant) -> Dictionary:
	var options := {"budget": 0, "protect_legendary": false}
	if saved is Dictionary:
		var budget: Variant = saved.get("budget", 0)
		options.budget = maxi(int(budget), 0) if _is_number(budget) else 0
		var protect: Variant = saved.get("protect_legendary", false)
		options.protect_legendary = protect is bool and protect
	return options


## What `item` is worth to the budget: its value() (a gun with its parts, without its rounds; a rig or
## backpack with what's in it), one at a time for a stack.
static func worth(item: ItemInstance) -> int:
	var total := item.value()
	for rounds in item.magazine:
		total -= rounds.value()
	return roundi(float(total) / item.count) if item.count > 1 else total


## True if `item` is Legendary or has a Legendary part fitted (a gun's, a helmet's face shield).
static func is_legendary(item: ItemInstance) -> bool:
	if item.data.rarity == ItemData.Rarity.LEGENDARY:
		return true
	for part in WeaponMods.installed(item):
		if part.data.rarity == ItemData.Rarity.LEGENDARY:
			return true
	return false


## True if `options` let auto-equip pick `item` (gear, a gun, a magazine, a med): within the budget and,
## with protect_legendary, not Legendary (a Legendary part counts).
static func allowed(item: ItemInstance, options: Dictionary) -> bool:
	if options.get("protect_legendary", false) and is_legendary(item):
		return false
	var budget := int(options.get("budget", 0))
	return budget <= 0 or worth(item) <= budget


## True if `options` let auto-equip load or pack rounds `ammo` (a round's own value against the budget).
static func ammo_allowed(ammo: ItemData, options: Dictionary) -> bool:
	if options.get("protect_legendary", false) and ammo.rarity == ItemData.Rarity.LEGENDARY:
		return false
	var budget := int(options.get("budget", 0))
	return budget <= 0 or ammo.base_value <= budget


# --- Scores ---------------------------------------------------------------------------------------

## Protection points of one armor piece: over each zone it covers, the zone's weight × its resistance
## now (ArmorRules.resistance(): its class, less as it wears). 0 for anything that isn't armor.
static func protection(piece: ItemInstance) -> float:
	if piece == null or not piece.is_armor():
		return 0.0
	var zones := _zone_weights()
	var resist := ArmorRules.resistance(int(piece.data.stats.get("class", 0)), piece.durability / maxf(piece.max_durability, 1.0))
	var total := 0.0
	for zone: Variant in piece.data.stats.get("zones", []):
		var weight: Variant = zones.get(str(zone), 0.0)
		total += resist * (float(weight) if _is_number(weight) else 0.0)
	return total


## Armor score of body armor, an armored rig, a helmet (with its face shield) or a ballistic face cover:
## protection, less weight_penalty per kg (the piece with its parts), plus armor.hearing points per +100%
## hearing (hearing(): most helmets and masks take some off, so they cost). 0 for anything that stops
## nothing.
static func armor_score(item: ItemInstance) -> float:
	if item == null:
		return 0.0
	var total := protection(item)
	for part in WeaponMods.installed(item):
		total += protection(part)
	if not _armored(item):
		return 0.0
	return total - _costs(item)


## A helmet and a face cover worn together (either may be null), as head_score() weighs them: over each
## zone the piece that stops more now (ArmorRules.armor_for() takes a face hit with the face shield or the
## mask, whichever stops more), the zone's weight × its resistance, less each armored piece's weight and
## hearing costs (_costs()). A cosmetic face cover adds nothing. head_score(helmet, null) == armor_score().
static func head_score(helmet: ItemInstance, face_cover: ItemInstance) -> float:
	var zones := _zone_weights()
	var total := 0.0
	var best := _zone_resistance([helmet, face_cover])
	for zone: String in best:
		total += float(best[zone]) * float(zones.get(zone, 0.0))
	for piece in [helmet, face_cover]:
		if piece and _armored(piece):
			total -= _costs(piece)
	return total


## True if `item` or a part fitted to it stops rounds (a helmet, its face shield, a ballistic mask).
static func _armored(item: ItemInstance) -> bool:
	if item.is_armor():
		return true
	for part in WeaponMods.installed(item):
		if part.is_armor():
			return true
	return false


## What wearing armored `item` costs in points: weight_penalty per kg (with its parts), less armor.hearing
## per +100% hearing of it and its parts (a helmet's -25% costs 0.25 × armor.hearing).
static func _costs(item: ItemInstance) -> float:
	return own_weight(item) * _num("armor", "weight_penalty") - hearing_of(item) * _num("armor", "hearing")


## The hearing `item` and its fitted parts add (GearUpgrades.hearing(): negative for most helmets and masks).
static func hearing_of(item: ItemInstance) -> float:
	var total := GearUpgrades.hearing(item)
	for part in WeaponMods.installed(item):
		total += GearUpgrades.hearing(part)
	return total


## The zone weights from the config ({} if they're missing).
static func _zone_weights() -> Dictionary:
	var armor: Variant = config().get("armor")
	var zones: Variant = armor.get("zones") if armor is Dictionary else null
	return zones if zones is Dictionary else {}


## Over each zone that `pieces` (and the parts fitted to them; nulls skipped) cover, the most any of them
## stops now: {zone: ArmorRules.resistance()}.
static func _zone_resistance(pieces: Array) -> Dictionary:
	var best := {}
	for piece: ItemInstance in pieces:
		if piece == null:
			continue
		for part: ItemInstance in WeaponMods.installed(piece) + [piece]:
			if not part.is_armor():
				continue
			var resist := ArmorRules.resistance(int(part.data.stats.get("class", 0)), part.durability / maxf(part.max_durability, 1.0))
			for zone: Variant in part.data.stats.get("zones", []):
				best[str(zone)] = maxf(float(best.get(str(zone), 0.0)), resist)
	return best


## Cells in a rig's or backpack's grid at its upgrade level (GearUpgrades.grid_size()); 0 without one.
static func cells(item: ItemInstance) -> int:
	if item == null or item.contents == null:
		return 0
	var size := GearUpgrades.grid_size(item.data, item.upgrade_level)
	return maxi(size.x * size.y, item.contents.cell_count())


## Room score of a rig or backpack: cell points per cell, less carry weight_penalty per kg.
static func carry_score(item: ItemInstance) -> float:
	if item == null or item.contents == null:
		return 0.0
	return cells(item) * _num("carry", "cell") - own_weight(item) * _num("carry", "weight_penalty")


## A piece's own weight: with its fitted parts, not what's inside it or loaded (as GearCompare weighs it).
static func own_weight(item: ItemInstance) -> float:
	var total := item.data.weight_kg * GearUpgrades.weight_multiplier(item)
	for part in WeaponMods.installed(item):
		total += part.data.weight_kg * WeaponStats.part_weight_multiplier(part.data)
	return total


## A round's score: penetration, plus damage × pellets^pellet_exponent (buckshot's eight pellets count
## less than eight slugs).
static func ammo_score(ammo: ItemData) -> float:
	var stats := ammo.stats
	var pellets := maxf(float(stats.get("pellets", 1)), 1.0)
	return float(stats.get("penetration", 0)) * _num("ammo", "penetration") \
		+ float(stats.get("damage", 0)) * pow(pellets, _num("ammo", "pellet_exponent")) * _num("ammo", "damage")


## A gun's score with `ammo` (null: none): its handling with its parts and your skills (WeaponStats.build():
## ergonomics, vertical and horizontal recoil, base spread, durability, jam chance, fire rate), plus the
## round's score.
static func gun_score(gun: ItemInstance, ammo: ItemData) -> float:
	var stats := WeaponStats.build(gun, GameState.skills)
	var total := stats.ergonomics * _num("gun", "ergonomics") - stats.vertical_recoil * _num("gun", "vertical_recoil") \
		- stats.horizontal_recoil * _num("gun", "horizontal_recoil") - stats.base_spread * _num("gun", "base_spread") \
		+ gun.durability / 100.0 * _num("gun", "durability") \
		- stats.malfunction_chance(gun.durability) * 100.0 * _num("gun", "jam_chance") + stats.fire_rate * _num("gun", "fire_rate")
	if ammo:
		total += ammo_score(ammo) * _num("gun", "ammo")
	return total


## The score of `item` worn in `slot` on its own (not guns: gun_score(); a helmet and a face cover are
## chosen as a pair: head_score()). A rig scores its room plus, when armored, its armor score; a helmet or
## face cover its armor score (cosmetic face covers 0).
static func score(slot: String, item: ItemInstance) -> float:
	if item == null:
		return 0.0
	match slot:
		"armor", "helmet", "face_cover":
			return armor_score(item)
		"rig":
			return carry_score(item) + armor_score(item)
		"backpack":
			return carry_score(item)
		"headset":
			return GearUpgrades.hearing(item) * _num("", "hearing")
		"melee":
			return float(item.data.stats.get("damage", 0)) * _num("", "melee_damage")
	return 0.0


## How much more than a worn item's `value` another must score to replace it: max(min, |value| × margin).
static func upgrade_margin(value: float) -> float:
	return maxf(_num("upgrade", "min"), absf(value) * _num("upgrade", "margin"))


## True if a score of `a` (rarity `rarity_a`) beats `b`: higher by more than rarity_epsilon, or within it
## and rarer.
static func beats(a: float, rarity_a: int, b: float, rarity_b: int) -> bool:
	if absf(a - b) > _num("", "rarity_epsilon"):
		return a > b
	return rarity_a > rarity_b


# --- Planning -------------------------------------------------------------------------------------

## What auto-equip would do with `options`, worked out on copies of `inventory` and `stash` (nothing
## changes): the plan apply() would return, marked "preview" (undo() won't take it).
static func plan(inventory: Inventory, stash: InventoryGrid, options: Dictionary) -> Dictionary:
	var result := _run(inventory.duplicate_deep(), _copy_grid(stash), clean_options(options))
	result.preview = true
	return result


## A deep copy of `grid` (each item as saved and loaded back, at its own spot). The spots are known to be
## free, so they go straight in: load_array() checks each against every other, slow for a full stash.
static func _copy_grid(grid: InventoryGrid) -> InventoryGrid:
	var copy := InventoryGrid.new(grid.size, grid.kind)
	for item in grid.items:
		copy.items.append(item.duplicate_deep())
	return copy


## Auto-equips `inventory` from `stash` with `options` (see the class notes). Returns the plan: {"moves":
## the journal of every move, for undo(), "lines": [{"text", "tone": CHANGE, KEPT or WARNING}], "changes":
## how many change lines, "message": a short line for the screen, "options"}.
static func apply(inventory: Inventory, stash: InventoryGrid, options: Dictionary) -> Dictionary:
	return _run(inventory, stash, clean_options(options))


static func _run(inventory: Inventory, stash: InventoryGrid, options: Dictionary) -> Dictionary:
	var ctx := {"inventory": inventory, "stash": stash, "options": options, "moves": [], "lines": [], "kept": [],
		"empty": [], "new": [], "changes": 0}
	_armor_and_rig(ctx)
	_helmet_and_face(ctx)
	for slot in GEAR_SLOTS:
		_fill_slot(ctx, slot)
	for slot in GUN_SLOTS:
		_fill_gun_slot(ctx, slot)
	_pack_meds(ctx)
	_pack_spare_rounds(ctx)
	_closing_lines(ctx)
	for grid in inventory.grids():
		grid.changed.emit()
	inventory.changed.emit()
	stash.changed.emit()
	var changes: int = ctx.changes
	var message := "Nothing better in the stash: you already wear the best you own" if changes == 0 \
		else "Auto-equipped: %d change%s" % [changes, "" if changes == 1 else "s"]
	return {"moves": ctx.moves, "lines": ctx.lines, "changes": changes, "message": message, "options": options}


static func _line(ctx: Dictionary, text: String, tone: String) -> void:
	ctx.lines.append({"text": text, "tone": tone})
	if tone == CHANGE:
		ctx.changes += 1


## Every item in `grid` at any depth (inside the containers in it too, not fitted parts or loaded rounds):
## [{"item", "grid"}].
static func _stash_items(grid: InventoryGrid) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in grid.items:
		result.append({"item": item, "grid": grid})
		if item.contents:
			result.append_array(_stash_items(item.contents))
	return result


## The stash's grid and the grids of every container in it, at any depth.
static func _stash_grids(stash: InventoryGrid) -> Array[InventoryGrid]:
	var result: Array[InventoryGrid] = [stash]
	for found in _stash_items(stash):
		if (found.item as ItemInstance).contents:
			result.append((found.item as ItemInstance).contents)
	return result


## Rounds (or any stackable) `id` in the stash, at any depth.
static func _stash_count(stash: InventoryGrid, id: String) -> int:
	var total := 0
	for grid in _stash_grids(stash):
		total += grid.count_of(id)
	return total


## The stash in one walk, for a step that looks at many guns (their rounds and magazines): {"counts":
## {id: how many at any depth}, "magazines": [{"item", "grid"}] (magazines that could be fitted)}.
static func _stash_index(stash: InventoryGrid) -> Dictionary:
	var counts := {}
	var magazines: Array[Dictionary] = []
	for found in _stash_items(stash):
		var item: ItemInstance = found.item
		counts[item.data.id] = int(counts.get(item.data.id, 0)) + item.count
		if item.count == 1 and not item.hidden and WeaponMods.kind_of(item.data) == "magazine":
			magazines.append(found)
	return {"counts": counts, "magazines": magazines}


## Stash items (at any depth) that could go in `slot` and the options allow: single, not hidden, empty
## containers only. [{"item", "grid"}].
static func _candidates(ctx: Dictionary, slot: String) -> Array[Dictionary]:
	if _blank == null:
		_blank = Inventory.new()
	var result: Array[Dictionary] = []
	for found in _stash_items(ctx.stash):
		var item: ItemInstance = found.item
		if item.count == 1 and not item.hidden and item.is_empty_container() and _blank.accepts(slot, item) \
				and allowed(item, ctx.options):
			result.append(found)
	return result


## The best of `candidates` for `slot` (rarity breaks a tie): {"item", "grid", "score"}, or {}.
static func _best(candidates: Array[Dictionary], slot: String) -> Dictionary:
	var best := {}
	for found in candidates:
		var value := score(slot, found.item)
		if best.is_empty() or beats(value, found.item.data.rarity, best.score, best.item.data.rarity):
			best = {"item": found.item, "grid": found.grid, "score": value}
	return best


# --- Slots ----------------------------------------------------------------------------------------

## Body armor and rig as a pair (see the class notes): every combination of nothing, what you wear and
## the stash's armor and rigs is scored (a worn piece with its upgrade margin), body armor never with an
## armored rig. A worn piece only goes when something takes its place: the armor slot may empty for an
## armored rig, an armored rig's slot for body armor.
static func _armor_and_rig(ctx: Dictionary) -> void:
	var inventory: Inventory = ctx.inventory
	var worn := {"armor": inventory.equipment.armor, "rig": inventory.equipment.rig}
	var choices := {}
	for slot: String in worn:
		var list: Array[Dictionary] = [{"item": null, "grid": null, "score": 0.0}]
		var now: ItemInstance = worn[slot]
		if now:
			var value := score(slot, now)
			list.append({"item": now, "grid": null, "score": value + upgrade_margin(value)})
		for found in _candidates(ctx, slot):
			list.append({"item": found.item, "grid": found.grid, "score": score(slot, found.item)})
		choices[slot] = list
	var best := {}
	var best_score := 0.0
	var best_rarity := 0
	for armor: Dictionary in choices.armor:
		for rig: Dictionary in choices.rig:
			var armor_item: ItemInstance = armor.item
			var rig_item: ItemInstance = rig.item
			var armored_rig := rig_item != null and rig_item.is_armor()
			if armor_item and armored_rig:
				continue
			if worn.armor and armor_item == null and not armored_rig:
				continue
			if worn.rig and rig_item == null and not ((worn.rig as ItemInstance).is_armor() and armor_item != null):
				continue
			var total: float = armor.score + rig.score
			var rarity := (armor_item.data.rarity + 1 if armor_item else 0) + (rig_item.data.rarity + 1 if rig_item else 0)
			if best.is_empty() or beats(total, rarity, best_score, best_rarity):
				best = {"armor": armor, "rig": rig}
				best_score = total
				best_rarity = rarity
	var changes: Array[Dictionary] = []
	for slot in ["armor", "rig"]:
		var chosen: Dictionary = best[slot]
		if chosen.item != worn[slot]:
			changes.append({"slot": slot, "item": chosen.item, "grid": chosen.grid})
		else:
			(ctx.kept if worn[slot] else ctx.empty).append(slot)
	if changes.is_empty():
		return
	var blocked := _dress(ctx, changes)
	if blocked != "":
		_line(ctx, "%s: kept your body armor and rig" % blocked, WARNING)
		for change in changes:
			(ctx.kept if worn[change.slot] else ctx.empty).append(change.slot)
		return
	for change in changes:
		var slot: String = change.slot
		var old: ItemInstance = worn[slot]
		if change.item == null:
			var reason := "the armored rig takes over" if slot == "armor" else "body armor instead"
			_line(ctx, "%s: %s → nothing (%s)" % [GearCompare.slot_name(slot), old.title(), reason], CHANGE)
		else:
			_line(ctx, _swap_text(slot, old, change.item), CHANGE)
	var new_rig: ItemInstance = inventory.equipment.rig
	if worn.rig and new_rig != worn.rig:
		_move_contents(ctx, worn.rig, new_rig)


## Helmet and face cover as a pair (head_score(): over the face only the piece that stops more counts,
## so a mask under a helmet with a better face shield adds only its weight and hearing cost): every
## combination of nothing, what you wear (with its upgrade margin) and the stash's helmets and face
## covers. A worn piece only goes when something takes its place; an empty slot stays empty rather than
## take a piece that scores below 0 (worn out) or adds nothing.
static func _helmet_and_face(ctx: Dictionary) -> void:
	var inventory: Inventory = ctx.inventory
	var worn := {"helmet": inventory.equipment.helmet, "face_cover": inventory.equipment.face_cover}
	var choices := {}
	var masks := false
	for slot: String in worn:
		var list: Array[Dictionary] = [{"item": null, "grid": null, "bonus": 0.0}]
		var now: ItemInstance = worn[slot]
		if now:
			list.append({"item": now, "grid": null, "bonus": upgrade_margin(score(slot, now))})
		for found in _candidates(ctx, slot):
			list.append({"item": found.item, "grid": found.grid, "bonus": 0.0})
			masks = masks or (slot == "face_cover" and _armored(found.item))
		choices[slot] = list
	var best := {}
	var best_score := 0.0
	var best_rarity := 0
	for helmet: Dictionary in choices.helmet:
		for face: Dictionary in choices.face_cover:
			if (worn.helmet and helmet.item == null) or (worn.face_cover and face.item == null):
				continue
			var total: float = head_score(helmet.item, face.item) + helmet.bonus + face.bonus
			var rarity := _rarity_sum([helmet.item, face.item])
			if best.is_empty() or beats(total, rarity, best_score, best_rarity):
				best = {"helmet": helmet, "face_cover": face}
				best_score = total
				best_rarity = rarity
	var changes: Array[Dictionary] = []
	var note := ""
	for slot in ["helmet", "face_cover"]:
		var chosen: Dictionary = best[slot]
		if chosen.item != worn[slot]:
			changes.append({"slot": slot, "item": chosen.item, "grid": chosen.grid})
		elif worn[slot]:
			ctx.kept.append(slot)
		elif slot == "face_cover" and masks and best.helmet.item and _zone_resistance([best.helmet.item]).has("face"):
			note = "Face cover: left empty (the face shield on your %s already covers the face)" % (best.helmet.item as ItemInstance).title()
		else:
			ctx.empty.append(slot)
	if not changes.is_empty():
		var blocked := _dress(ctx, changes)
		if blocked != "":
			_line(ctx, "%s: kept %s" % [blocked, "your helmet and face cover" if changes.size() > 1 else "it"], WARNING)
			for change in changes:
				(ctx.kept if worn[change.slot] else ctx.empty).append(change.slot)
			return
		for change in changes:
			_line(ctx, _swap_text(change.slot, worn[change.slot], change.item), CHANGE)
	if note != "":
		_line(ctx, note, KEPT)


## The rarity of `items` together, for beats() between combinations: each item's rarity + 1 (nulls 0).
static func _rarity_sum(items: Array) -> int:
	var total := 0
	for each: ItemInstance in items:
		if each:
			total += each.data.rarity + 1
	return total


## The headset, backpack or melee slot: an empty one takes the best candidate (if it doesn't score below
## 0), a worn item goes only for one clearly better.
static func _fill_slot(ctx: Dictionary, slot: String) -> void:
	var current: ItemInstance = ctx.inventory.equipment.get(slot)
	var best := _best(_candidates(ctx, slot), slot)
	if current:
		var value := score(slot, current)
		if best.is_empty() or best.score <= value + upgrade_margin(value):
			ctx.kept.append(slot)
			return
	elif best.is_empty() or best.score < 0.0:
		ctx.empty.append(slot)
		return
	var blocked := _dress(ctx, [{"slot": slot, "item": best.item, "grid": best.grid}])
	if blocked != "":
		_line(ctx, "%s: kept it" % blocked, WARNING)
		ctx.kept.append(slot)
		return
	_line(ctx, _swap_text(slot, current, best.item), CHANGE)
	if slot == "backpack" and current:
		_move_contents(ctx, current, best.item)


## A gun slot: the best gun in the stash that can fire with what you own (_gun_eval()) against the gun
## there (which goes only for one clearly better, or when it can't fire at all); then the gun in the slot
## gets its magazine and rounds (_ready_gun()). A gun is taken into an empty slot whatever it scores (a
## sawn-off beats no gun).
static func _fill_gun_slot(ctx: Dictionary, slot: String) -> void:
	var current: ItemInstance = ctx.inventory.equipment.get(slot)
	var index := _stash_index(ctx.stash)
	var best := {}
	var evals := {}  # _gun_key() -> _gun_eval(): a stash full of one pistol scores it once
	for found in _candidates(ctx, slot):
		var key := _gun_key(found.item)
		if not evals.has(key):
			evals[key] = _gun_eval(ctx, found.item, false, index)
		var eval: Dictionary = evals[key]
		if not eval.is_empty() and (best.is_empty() or beats(eval.score, found.item.data.rarity, best.score, best.item.data.rarity)):
			best = eval.duplicate()
			best.item = found.item
			best.grid = found.grid
	var gun := current
	var replace := false
	if current:
		var now := _gun_eval(ctx, current, true, index)
		replace = not best.is_empty() and (now.is_empty() or best.score > now.score + upgrade_margin(now.score))
		if not replace:
			ctx.kept.append(slot)
	elif best.is_empty():
		ctx.empty.append(slot)
	else:
		replace = true
	if replace:
		var blocked := _dress(ctx, [{"slot": slot, "item": best.item, "grid": best.grid}])
		if blocked == "":
			_line(ctx, _swap_text(slot, current, best.item), CHANGE)
			gun = best.item
		else:
			_line(ctx, "%s: kept it" % blocked, WARNING)
			ctx.kept.append(slot)
	if gun and gun.is_gun():
		_ready_gun(ctx, slot, gun, gun != current)


## What makes two guns score the same in one step (_gun_eval()): the gun, its durability, the part in each
## slot and the rounds in it.
static func _gun_key(gun: ItemInstance) -> String:
	var parts: Array[String] = []
	for entry in WeaponMods.walk(gun):
		parts.append("%s=%s" % [entry.path, (entry.mod as ItemInstance).data.id if entry.mod else ""])
	var rounds: Array[String] = []
	for each in gun.magazine:
		rounds.append(each.data.id)
	return "%s|%s|%s|%s" % [gun.data.id, gun.durability, ",".join(parts), ",".join(rounds)]


## How `gun` would do: {"score", "ammo": the best round you own for it}, or {} if it can't fire: a
## required part missing (the magazine may be one you own that fits, and for a gun from the stash keeps
## it within the budget) or no rounds you own for it that the options allow (for a gun you wear, `worn`,
## the rounds in it count). `index`: _stash_index().
static func _gun_eval(ctx: Dictionary, gun: ItemInstance, worn: bool, index: Dictionary) -> Dictionary:
	if gun.data.weapon == null:
		return {}
	var magazine := {}
	for entry in WeaponMods.walk(gun):
		if entry.mod == null and entry.slot.get("required", false):
			if str(entry.path) != "magazine":
				return {}
			magazine = _best_magazine(ctx, gun, index.magazines, not worn)
			if magazine.is_empty():
				return {}
	var kinds := _ammo_kinds(ctx, gun, index.counts)
	var ammo: ItemData = kinds[0] if not kinds.is_empty() else null
	if ammo == null and worn and not gun.magazine.is_empty():
		ammo = gun.magazine.back().data
	if ammo == null:
		return {}
	var rated := gun
	if not magazine.is_empty():
		rated = gun.duplicate_deep()
		WeaponMods.install(rated, "magazine", (magazine.item as ItemInstance).duplicate_deep())
	return {"score": gun_score(rated, ammo), "ammo": ammo}


## The rounds of `gun`'s caliber you own (in the stash, `counts` from _stash_index(); in the pockets, rig
## and backpack; or in the gun) that the options allow, best first (ammo_score(); rarity breaks a tie).
static func _ammo_kinds(ctx: Dictionary, gun: ItemInstance, counts: Dictionary) -> Array[ItemData]:
	var caliber := gun.data.weapon.caliber
	var result: Array[ItemData] = []
	for ammo in ItemDB.ammo_of(caliber):
		if not ammo_allowed(ammo, ctx.options):
			continue
		var owned := int(counts.get(ammo.id, 0)) + (ctx.inventory as Inventory).count_of(ammo.id)
		for rounds in gun.magazine:
			if rounds.data == ammo:
				owned += rounds.count
		if owned > 0:
			result.append(ammo)
	_sort_ammo(result)
	return result


## Sorts rounds best first (ammo_score(), then rarer).
static func _sort_ammo(list: Array[ItemData]) -> void:
	var epsilon := _num("", "rarity_epsilon")
	list.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		var score_a := ammo_score(a)
		var score_b := ammo_score(b)
		if absf(score_a - score_b) > epsilon:
			return score_a > score_b
		return a.rarity > b.rarity if a.rarity != b.rarity else score_a > score_b)


## Of `magazines` (_stash_index()), the one that fits `gun`'s magazine slot and the options allow, the
## biggest (then the rarest): {"item", "grid"}, or {}. `with_gun` (a gun taken from the stash): the gun
## with the magazine must be within the budget too, as worth() counts a gun with its parts.
static func _best_magazine(ctx: Dictionary, gun: ItemInstance, magazines: Array[Dictionary], with_gun: bool) -> Dictionary:
	var budget := int(ctx.options.get("budget", 0))
	var base := worth(gun) if with_gun and budget > 0 else 0
	var best := {}
	var best_key := []
	for found in magazines:
		var part: ItemInstance = found.item
		if not allowed(part, ctx.options) or (base > 0 and base + worth(part) > budget) \
				or WeaponMods.install_block_reason(gun, "magazine", part) != "":
			continue
		var key := [WeaponMods.capacity_of(part.data), part.data.rarity]
		if best.is_empty() or key[0] > best_key[0] or (key[0] == best_key[0] and key[1] > best_key[1]):
			best = found
			best_key = key
	return best


# --- Guns: magazine and rounds --------------------------------------------------------------------

## The gun in gun slot `slot` (`new`: just taken from the stash): a magazine if its slot is empty (the
## biggest you own that fits, within the budget with a new gun), then rounds; then a warning if it's
## still short of a full magazine.
static func _ready_gun(ctx: Dictionary, slot: String, gun: ItemInstance, new: bool) -> void:
	var index := _stash_index(ctx.stash)
	if not WeaponMods.slot_on(gun, "magazine").is_empty() and WeaponMods.mod_at(gun, "magazine") == null:
		var magazine := _best_magazine(ctx, gun, index.magazines, new)
		if magazine.is_empty():
			_line(ctx, "No magazine in the stash fits your %s: it can't be loaded" % gun.title(), WARNING)
			return
		var part: ItemInstance = magazine.item
		var grid: InventoryGrid = magazine.grid
		var move := {"op": "fit", "gun": gun, "path": "magazine", "part": part, "grid": grid, "cell": part.cell, "rotated": part.rotated,
			"index": grid.items.find(part)}
		grid.remove(part)
		WeaponMods.install(gun, "magazine", part)
		ctx.moves.append(move)
		_line(ctx, "Fitted to the %s: %s" % [gun.title(), part.title()], CHANGE)
	var missing := WeaponMods.missing_part(gun)
	if missing != "":
		_line(ctx, "Your %s can't fire: no %s" % [gun.title(), missing.to_lower()], WARNING)
		return
	_load(ctx, slot, gun, new, index.counts)
	var capacity := WeaponMods.capacity(gun)
	var held := gun.rounds_loaded()
	if held < capacity:
		var caliber := gun.data.weapon.caliber
		_line(ctx, ("Your %s%s is empty: no %s rounds you can use" % [gun.title(), _which(slot), caliber]) if held == 0
			else "Your %s%s holds only %d of %d rounds: no more %s rounds you can use" % [gun.title(), _which(slot), held, capacity, caliber], WARNING)


## " (primary weapon)" after a gun's name: two rifles could share a name; a pistol needs no telling apart.
static func _which(slot: String) -> String:
	return " (%s)" % GearCompare.slot_name(slot).to_lower() if slot != "pistol" else ""


## Loads `gun` (in `slot`) to capacity with the best rounds you own for it: from what's in it, the stash
## (`counts`: _stash_index()) and the pockets, rig and backpack, best first (_ammo_kinds()); each kind from
## the stash first, then from what you carry (never the secure container). Rounds it held that don't make
## the cut go back to the stash (a new gun's rounds the options rule out too; a gun you wore keeps those).
## If the stash has no room for what comes out, the gun is only topped up. Loaded worst first, so the best
## is on top and fired first; the gun reloads with the best.
static func _load(ctx: Dictionary, slot: String, gun: ItemInstance, new: bool, counts: Dictionary) -> void:
	var stash: InventoryGrid = ctx.stash
	var inventory: Inventory = ctx.inventory
	var capacity := WeaponMods.capacity(gun)
	if capacity <= 0:
		return
	var kinds := _ammo_kinds(ctx, gun, counts)
	if kinds.is_empty() and gun.magazine.is_empty():
		return
	var usable := {}
	for kind in kinds:
		usable[kind.id] = true
	var loaded := {}
	for rounds in gun.magazine:
		loaded[rounds.data.id] = int(loaded.get(rounds.data.id, 0)) + rounds.count
	var to_return := {}
	var kept_other := 0
	for id: String in loaded:
		if not usable.has(id):
			if new:
				to_return[id] = loaded[id]
			else:
				kept_other += int(loaded[id])
	var desired := {}
	var left := maxi(capacity - kept_other, 0)
	for kind in kinds:
		var count := mini(int(loaded.get(kind.id, 0)) + int(counts.get(kind.id, 0)) + inventory.count_of(kind.id), left)
		if count > 0:
			desired[kind.id] = count
			left -= count
	for id: String in loaded:
		if usable.has(id) and int(loaded[id]) > int(desired.get(id, 0)):
			to_return[id] = int(loaded[id]) - int(desired.get(id, 0))
	var to_take := {}
	for id: String in desired:
		if int(desired[id]) > int(loaded.get(id, 0)):
			to_take[id] = int(desired[id]) - int(loaded.get(id, 0))
	if to_return.is_empty() and to_take.is_empty():
		return
	var move := {"op": "load", "gun": gun, "before": _snapshot(gun), "ammo_before": gun.loaded_ammo, "returned": [], "taken": []}
	var pieces := gun.unload()
	var back: Array[ItemInstance] = []
	var keep: Array[ItemInstance] = []
	var returning := to_return.duplicate()
	for piece in pieces:
		var count := mini(piece.count, int(returning.get(piece.data.id, 0)))
		if count == piece.count:
			back.append(piece)
		elif count > 0:
			back.append(piece.copy_stack(count))
			piece.count -= count
			keep.append(piece)
		else:
			keep.append(piece)
		if count > 0:
			returning[piece.data.id] = int(returning[piece.data.id]) - count
	if not back.is_empty() and not stash.has_room_for_all(back):
		# No room for what would come out: the gun keeps its rounds and is topped up.
		_restore(gun, move.before)
		to_return.clear()
		keep.clear()
		to_take.clear()
		left = capacity - gun.rounds_loaded()
		for kind in kinds:
			var count := mini(_stash_count(stash, kind.id) + inventory.count_of(kind.id), left)
			if count > 0:
				to_take[kind.id] = count
				left -= count
		if to_take.is_empty():
			_line(ctx, "No room in the stash for the rounds in your %s: it keeps them" % gun.title(), WARNING)
			return
		_line(ctx, "No room in the stash for the rounds in your %s: topped it up instead" % gun.title(), WARNING)
		back.clear()
	for piece in back:
		var record := _add_tracked(stash, piece)
		move.returned.append(record)
	var taken := {}
	for id: String in to_take:
		taken[id] = []
		var records := _take(stash, id, int(to_take[id]))
		var got := 0
		for record in records:
			got += int(record.count)
		records.append_array(_take_from(inventory.ammo_grids(), id, int(to_take[id]) - got))
		for record in records:
			move.taken.append(record)
			taken[id].append(record.piece)
	for piece in keep:
		if not usable.has(piece.data.id):
			gun.load_rounds(piece)
	for i in range(kinds.size() - 1, -1, -1):
		var id := kinds[i].id
		for piece in keep:
			if piece.data.id == id:
				gun.load_rounds(piece)
		for piece: ItemInstance in taken.get(id, []):
			gun.load_rounds(piece)
	for kind in kinds:
		if desired.has(kind.id) or taken.has(kind.id):
			gun.loaded_ammo = kind.id
			break
	move.after = _snapshot(gun)
	ctx.moves.append(move)
	var which := _which(slot)
	var text := ""
	if not to_take.is_empty():
		var names: Array[String] = []
		for kind in kinds:
			if to_take.has(kind.id):
				names.append("%d × %s" % [to_take[kind.id], kind.display_name])
		text = "Loaded %s%s with %s" % [gun.title(), which, ", ".join(names)]
	if not to_return.is_empty():
		var names: Array[String] = []
		for id: String in to_return:
			names.append("%d × %s" % [to_return[id], ItemDB.get_item(id).display_name])
		var out := "%s back to the stash" % ", ".join(names)
		text = "%s; %s" % [text, out] if text != "" else "%s%s: %s" % [gun.title(), which, out]
	_line(ctx, text, CHANGE)


## The rounds in `gun`'s magazine, bottom first: [{"id", "count", "status"}].
static func _snapshot(gun: ItemInstance) -> Array:
	return gun.magazine.map(func(rounds: ItemInstance) -> Dictionary:
		return {"id": rounds.data.id, "count": rounds.count, "status": _status(rounds)})


## Puts `gun`'s magazine back as `snapshot` had it, less `missing` rounds ({"id|status": count}) that
## couldn't be found (so no round is made up).
static func _restore(gun: ItemInstance, snapshot: Array, missing := {}) -> void:
	gun.magazine.clear()
	for run: Dictionary in snapshot:
		var key := _key(run.id, run.status)
		var short := mini(int(missing.get(key, 0)), int(run.count))
		if short > 0:
			missing[key] = int(missing[key]) - short
		var rounds := _rounds(run.id, int(run.count) - short, run.status)
		if rounds:
			gun.magazine.append(rounds)


# --- Meds and spare rounds ------------------------------------------------------------------------

## One med of each kind (med_kinds()) in the pockets or rig, unless you carry that kind there already: the
## best you own in the stash (rarest, then the most uses or HP left), else a smaller one that fits. The
## summary lists what went in first, then (in kind order) what wasn't there or had no room.
static func _pack_meds(ctx: Dictionary) -> void:
	var targets := _worn_grids(ctx.inventory, MED_GRIDS)
	var added := {}
	var warnings: Array[String] = []
	for kind in med_kinds():
		var types: Array = kind.types
		var carried := false
		for grid in targets:
			for item in grid.items:
				if item.data.category == ItemData.Category.MEDS and str(item.data.stats.get("type", "")) in types:
					carried = true
		if carried:
			continue
		var candidates: Array[Dictionary] = []
		for found in _stash_items(ctx.stash):
			var item: ItemInstance = found.item
			if item.data.category == ItemData.Category.MEDS and str(item.data.stats.get("type", "")) in types and item.count == 1 \
					and not item.hidden and allowed(item, ctx.options):
				candidates.append(found)
		if candidates.is_empty():
			warnings.append("No %s in the stash to add" % kind.name)
			continue
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var x: ItemInstance = a.item
			var y: ItemInstance = b.item
			if x.data.rarity != y.data.rarity:
				return x.data.rarity > y.data.rarity
			if not is_equal_approx(x.charges, y.charges):
				return x.charges > y.charges
			return x.data.size.x * x.data.size.y < y.data.size.x * y.data.size.y)
		var placed := false
		for found in candidates:
			var into := _pack(ctx, found.item, found.grid, targets)
			if into:
				if not added.has(into):
					added[into] = []
				added[into].append(found.item.data.display_name)
				placed = true
				break
		if not placed:
			warnings.append("No room for a %s in your pockets or rig" % kind.name)
	for grid in targets:
		if added.has(grid):
			_line(ctx, "Added: %s → %s" % [", ".join(added[grid]), _grid_name(grid)], CHANGE)
	for text in warnings:
		_line(ctx, text, WARNING)


## Spare rounds for the guns in the gun slots: spare_magazines magazines' worth each, the best you own:
## what you carry of their caliber in the pockets, rig and backpack counts, unless a better kind is in the
## stash (_worse_spares()). Then, per caliber: whole stacks of worse rounds you carry go back to the stash
## first (their cells free up), the rounds still wanted come from the stash, best first, into the rig, then
## the pockets, then the backpack, and what you still carry of the worse ones beyond what's wanted goes
## back too (split off a stack if need be). Nothing goes back unless better rounds take its place, and what
## you carry never drops below what's wanted.
static func _pack_spare_rounds(ctx: Dictionary) -> void:
	var inventory: Inventory = ctx.inventory
	var wanted := {}
	var order: Array[String] = []
	for slot in GUN_SLOTS:
		var gun: ItemInstance = inventory.equipment.get(slot)
		if gun == null or not gun.is_gun() or WeaponMods.capacity(gun) <= 0 or WeaponMods.missing_part(gun) != "":
			continue
		var caliber := gun.data.weapon.caliber
		if not wanted.has(caliber):
			wanted[caliber] = 0
			order.append(caliber)
		wanted[caliber] = int(wanted[caliber]) + roundi(_num("", "spare_magazines")) * WeaponMods.capacity(gun)
	var targets := _worn_grids(inventory, AMMO_GRIDS)
	for caliber in order:
		var want: int = wanted[caliber]
		var worse := _worse_spares(ctx, caliber, want)
		var spare: Dictionary = worse.spare
		var sent := {}  # ammo id -> {grid: true}, what went back
		# Whole stacks first, as far as what stays and what the stash has still make `want`.
		var room: int = worse.allowance
		for found: Dictionary in worse.stacks:
			var stack: ItemInstance = found.item
			var id := stack.data.id
			if stack.count <= int(spare[id]) and stack.count <= room:
				var went := _send_back(ctx, found.grid, stack, stack.count, sent)
				spare[id] = int(spare[id]) - went
				room -= went
		var surplus := 0
		for id: String in spare:
			surplus += int(spare[id])
		var need := want - (_carried_rounds(inventory, caliber) - surplus)
		if need <= 0:
			if sent.is_empty():
				_line(ctx, "Spare rounds: you carry enough %s already (%d)" % [caliber, _carried_rounds(inventory, caliber)], KEPT)
			_sent_lines(ctx, sent)
			continue
		var kinds: Array[ItemData] = []
		for ammo in ItemDB.ammo_of(caliber):
			if ammo_allowed(ammo, ctx.options) and _stash_count(ctx.stash, ammo.id) > 0 and not sent.has(ammo.id):
				kinds.append(ammo)
		_sort_ammo(kinds)
		var no_room := {}
		for ammo in kinds:
			if need <= 0 or not no_room.is_empty():
				break
			var moved := 0
			var where := {}
			for taken in _take(ctx.stash, ammo.id, need):
				var piece: ItemInstance = taken.piece
				var count: int = taken.count
				var records: Array[Dictionary] = []
				for grid in targets:
					var record := _add_tracked(grid, piece)
					if int(record.count) > 0:
						records.append(record)
						where[grid] = true
					if record.placed:
						break
				var went := 0
				for record in records:
					went += int(record.count)
				var left := count - went
				if left > 0:
					# The rest goes back onto the stack it came off, or (a whole stack) into its spot, where
					# undo then puts the rest back onto it.
					piece.count = left
					var whole: bool = taken.stack == null
					_put_back(taken, piece, inventory, ctx.stash)
					if whole and (taken.grid as InventoryGrid).items.has(piece):
						taken.stack = piece
					no_room[ammo.display_name] = int(no_room.get(ammo.display_name, 0)) + left
				if went > 0:
					taken.count = went
					ctx.moves.append({"op": "pack", "take": taken, "added": records})
				moved += went
				need -= went  # A piece with no room went back; the others taken with it are tried (and go back) too.
			if moved > 0:
				var names: Array[String] = []
				for grid in targets:
					if where.has(grid):
						names.append(_grid_name(grid))
				_line(ctx, "Spare rounds: %d × %s → %s" % [moved, ammo.display_name, ", ".join(names)], CHANGE)
		# The worse rounds still carried beyond `want` go back (split off a stack if need be).
		var extra := _carried_rounds(inventory, caliber) - want
		for found: Dictionary in worse.stacks:
			var stack: ItemInstance = found.item
			var id := stack.data.id
			var amount := mini(mini(int(spare[id]), stack.count), extra)
			if amount > 0 and (found.grid as InventoryGrid).items.has(stack):
				var went := _send_back(ctx, found.grid, stack, amount, sent)
				spare[id] = int(spare[id]) - went
				extra -= went
		_sent_lines(ctx, sent)
		for name: String in no_room:
			_line(ctx, "No room for %d × %s (spare rounds)" % [no_room[name], name], WARNING)
		if need > 0 and no_room.is_empty():
			_line(ctx, "Not enough spare %s rounds in the stash: %d short" % [caliber, need], WARNING)


## Which spare rounds of `caliber` you carry should give way (the best `wanted` you own: what you carry
## counts first within a kind, but a better kind in the stash comes before a worse one you carry; rounds
## the options rule out stay and count): {"spare": {ammo id: rounds of it you carry that the best leave
## out}, "stacks": [{"grid", "item"}] of those kinds, the worst kind first, bigger stacks first (only
## kinds worse than one the stash brings), "allowance": how many can go back before what stays and what
## the stash has fall short of `wanted`}.
static func _worse_spares(ctx: Dictionary, caliber: String, wanted: int) -> Dictionary:
	var inventory: Inventory = ctx.inventory
	var result := {"spare": {}, "stacks": [], "allowance": 0}
	var carried := {}  # ammo id -> [{"grid", "item"}]
	var left := wanted
	for grid in inventory.ammo_grids():
		for item in grid.items:
			if item.data.category != ItemData.Category.AMMO or str(item.data.stats.get("caliber", "")) != caliber or item.hidden:
				continue
			if not ammo_allowed(item.data, ctx.options):
				left -= item.count
				continue
			if not carried.has(item.data.id):
				carried[item.data.id] = []
			carried[item.data.id].append({"grid": grid, "item": item})
	if carried.is_empty() or left <= 0:
		return result
	var kinds: Array[ItemData] = []
	var in_stash := {}
	for ammo in ItemDB.ammo_of(caliber):
		if ammo_allowed(ammo, ctx.options):
			in_stash[ammo.id] = _stash_count(ctx.stash, ammo.id)
			if carried.has(ammo.id) or int(in_stash[ammo.id]) > 0:
				kinds.append(ammo)
	_sort_ammo(kinds)
	var want := left
	var from_stash := 0
	var have_all := 0
	var first_from_stash := kinds.size()  # only kinds worse than this one give way
	for i in kinds.size():
		var ammo := kinds[i]
		var have := 0
		for found: Dictionary in carried.get(ammo.id, []):
			have += (found.item as ItemInstance).count
		have_all += have
		var kept := mini(have, maxi(left, 0))
		left -= kept
		result.spare[ammo.id] = have - kept
		var more := mini(int(in_stash[ammo.id]), maxi(left, 0))
		left -= more
		from_stash += more
		if more > 0:
			first_from_stash = mini(first_from_stash, i)
	for i in range(kinds.size() - 1, first_from_stash, -1):
		if int(result.spare[kinds[i].id]) <= 0:
			continue
		var stacks: Array = carried.get(kinds[i].id, []).duplicate()
		stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.item.count > b.item.count)
		result.stacks.append_array(stacks)
	for i in first_from_stash + 1:
		if i < kinds.size():
			result.spare[kinds[i].id] = 0
	result.allowance = from_stash + have_all - want
	return result


## Sends `amount` of `stack` (rounds you carry, in `grid`) back to the stash as a "pack" move (undo puts
## them back): the whole stack, or a piece split off it. Adds it to `sent` ({ammo id: {"count": rounds,
## grid: true for each grid they came from}}). Returns how many went (0: no room in the stash).
static func _send_back(ctx: Dictionary, grid: InventoryGrid, stack: ItemInstance, amount: int, sent: Dictionary) -> int:
	var whole := amount >= stack.count
	var piece := stack if whole else stack.copy_stack(amount)
	if not (ctx.stash as InventoryGrid).has_room_for(piece):
		return 0
	var taken := _taken(stack, grid, piece.count)
	if whole:
		grid.remove(stack)
	else:
		stack.count -= amount
		taken.piece = piece
		taken.stack = stack
		grid.changed.emit()
	var record := _add_tracked(ctx.stash, piece)
	ctx.moves.append({"op": "pack", "take": taken, "added": [record]})
	var id := stack.data.id
	if not sent.has(id):
		sent[id] = {"count": 0}
	sent[id][grid] = true
	sent[id].count = int(sent[id].count) + int(record.count)
	return int(record.count)


## "Spare rounds: 60 × 5.45x39 PS back to the stash from your pockets, for better ones", per kind in `sent`
## (_send_back()).
static func _sent_lines(ctx: Dictionary, sent: Dictionary) -> void:
	var inventory: Inventory = ctx.inventory
	for id: String in sent:
		var names: Array[String] = []
		for grid in inventory.ammo_grids():
			if sent[id].has(grid):
				names.append(_grid_name(grid))
		_line(ctx, "Spare rounds: %d × %s back to the stash from your %s, for better ones" % [int(sent[id].count), ItemDB.get_item(id).display_name,
			", ".join(names)], CHANGE)


## Rounds of `caliber` in the pockets, rig and backpack.
static func _carried_rounds(inventory: Inventory, caliber: String) -> int:
	var total := 0
	for grid in inventory.ammo_grids():
		for item in grid.items:
			if item.data.category == ItemData.Category.AMMO and str(item.data.stats.get("caliber", "")) == caliber:
				total += item.count
	return total


## The grids of `names` ("pockets", "rig", "backpack") on `inventory`, in that order (a slot with nothing
## worn has none).
static func _worn_grids(inventory: Inventory, names: Array[String]) -> Array[InventoryGrid]:
	var result: Array[InventoryGrid] = []
	for name in names:
		if name == "pockets":
			result.append(inventory.pockets)
		elif inventory.equipment.get(name) and (inventory.equipment[name] as ItemInstance).contents:
			result.append((inventory.equipment[name] as ItemInstance).contents)
	return result


static func _grid_name(grid: InventoryGrid) -> String:
	match grid.kind:
		&"pockets":
			return "pockets"
		&"rig":
			return "rig"
		&"backpack":
			return "backpack"
	return str(grid.kind)


## Moves `item` (a whole one, from `grid` in the stash) into the first of `targets` it fits. Returns that
## grid, or null (it stays where it was).
static func _pack(ctx: Dictionary, item: ItemInstance, grid: InventoryGrid, targets: Array[InventoryGrid]) -> InventoryGrid:
	var taken := _taken(item, grid, item.count)
	grid.remove(item)
	for target in targets:
		var record := _add_tracked(target, item)
		if record.placed:
			ctx.moves.append({"op": "pack", "take": taken, "added": [record]})
			return target
	_put_back(taken, item, ctx.inventory, ctx.stash)
	return null


## A worn rig or backpack was replaced: what `old` (now in the stash) held moves into `new` (now worn),
## each item to the first spot it fits; what doesn't stays in `old`.
static func _move_contents(ctx: Dictionary, old: ItemInstance, new: ItemInstance) -> void:
	if old.contents == null or old.contents.items.is_empty():
		return
	var moved := 0
	var left := 0
	for item in old.contents.items.duplicate():
		var spot := new.contents.find_space(item) if new and new.contents else {}
		if spot.is_empty():
			left += 1
			continue
		var move := {"op": "move", "item": item, "grid": old.contents, "cell": item.cell, "rotated": item.rotated, "to": new.contents,
			"index": old.contents.items.find(item)}
		old.contents.remove(item)
		new.contents.place(item, spot.cell, spot.rotated)
		ctx.moves.append(move)
		moved += 1
	if moved > 0:
		_line(ctx, "Moved %d item%s from your %s into the %s" % [moved, "" if moved == 1 else "s", old.title(), new.title()], CHANGE)
	if left > 0:
		_line(ctx, "Left %d item%s in your %s (now in the stash): no room for %s" % [left, "" if left == 1 else "s", old.title(),
			"them" if left > 1 else "it"], WARNING)


static func _closing_lines(ctx: Dictionary) -> void:
	if not ctx.kept.is_empty():
		_line(ctx, "Kept (nothing better in the stash): %s" % ", ".join(_slot_names(ctx.kept)), KEPT)
	if not ctx.empty.is_empty():
		_line(ctx, "Still empty (nothing for it in the stash): %s" % ", ".join(_slot_names(ctx.empty)), KEPT)
	var uninsured: Array[String] = []
	for item: ItemInstance in ctx.new:
		if Insurance.is_insurable(item) and not item.insured and (ctx.inventory as Inventory).slot_of(item) != "" \
				and not item.title() in uninsured:
			uninsured.append(item.title())
	if not uninsured.is_empty():
		_line(ctx, "Not insured: %s (INSURE GEAR before the raid covers them)" % ", ".join(uninsured), WARNING)


## Slot names in Inventory.SLOTS order.
static func _slot_names(slots: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Array in Inventory.SLOTS:
		if entry[0] in slots:
			result.append(entry[1])
	return result


## "Body armor: PACA body armor → 6B23-1 body armor (class 2 → 4)" (no arrow for an empty slot).
static func _swap_text(slot: String, old: ItemInstance, new: ItemInstance) -> String:
	var what := "%s → %s" % [old.title(), new.title()] if old else new.title()
	var detail := ""
	match slot:
		"armor", "helmet", "face_cover":
			if new.is_armor():
				detail = "class %d → %d" % [_class_of(old), _class_of(new)] if old and old.is_armor() else "class %d" % _class_of(new)
		"rig", "backpack":
			detail = "%d → %d cells" % [cells(old), cells(new)] if old else "%d cells" % cells(new)
			if new.is_armor():
				detail += ", class %d" % _class_of(new)
		"headset":
			detail = "hearing %+d%%" % roundi(GearUpgrades.hearing(new) * 100.0)
		"melee":
			detail = "damage %d" % int(new.data.stats.get("damage", 0))
		"primary", "secondary", "pistol":
			detail = new.data.weapon.caliber if new.data.weapon else ""
	return "%s: %s%s" % [GearCompare.slot_name(slot), what, " (%s)" % detail if detail != "" else ""]


static func _class_of(item: ItemInstance) -> int:
	return int(item.data.stats.get("class", 0)) if item and item.is_armor() else 0


# --- Moving things (journaled) --------------------------------------------------------------------

## Puts each change's item ({"slot", "item" (null: leave the slot empty), "grid" it's in}) on, what was
## in those slots going to the stash, as one move ("dress": {"entries": [{"slot", "old", "new", "grid",
## "cell", "rotated"}]}, where the new item came from). The new items are lifted out first (their room
## frees up) and every old one goes before any new one goes on (body armor and an armored rig exclude
## each other). "" when done; else why not ("No room in the stash for your PACA body armor"), and
## nothing has changed.
static func _dress(ctx: Dictionary, changes: Array[Dictionary]) -> String:
	var inventory: Inventory = ctx.inventory
	var entries: Array[Dictionary] = []
	for change in changes:
		var item: ItemInstance = change.item
		var old: ItemInstance = inventory.equipment.get(change.slot)
		entries.append({"slot": change.slot, "old": old, "new": item, "grid": change.grid, "cell": item.cell if item else Vector2i.ZERO,
			"rotated": item.rotated if item else false, "index": (change.grid as InventoryGrid).items.find(item) if item else -1,
			"old_cell": old.cell if old else Vector2i.ZERO, "old_rotated": old.rotated if old else false})
		if item:
			(change.grid as InventoryGrid).remove(item)
	var reason := ""
	var stashed: Array[Dictionary] = []
	for entry in entries:
		var old: ItemInstance = entry.old
		if old:
			inventory.unequip(entry.slot)
			if _add_tracked(ctx.stash, old).placed == null:
				inventory.equip(entry.slot, old)
				reason = "No room in the stash for your %s" % old.title()
				break
			stashed.append(entry)
	if reason == "":
		for entry in entries:
			var item: ItemInstance = entry.new
			if item:
				item.rotated = false
				if not inventory.equip(entry.slot, item):
					item.rotated = entry.rotated
					reason = "Your %s doesn't go on" % item.title()
					break
	if reason == "":
		ctx.moves.append({"op": "dress", "entries": entries})
		for entry in entries:
			if entry.new:
				ctx.new.append(entry.new)
		return ""
	# Back as it was: the new items off and into their spots, the old ones on again.
	for entry in entries:
		if entry.new and inventory.equipment.get(entry.slot) == entry.new:
			inventory.unequip(entry.slot)
	for i in range(stashed.size() - 1, -1, -1):
		var old: ItemInstance = stashed[i].old
		ctx.stash.find_holder(old).remove(old)
		_wear_again(inventory, stashed[i])
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].new:
			_put_back(entries[i], entries[i].new, inventory, ctx.stash)
	return reason


## Where `piece` (about to leave `grid`, `count` of it) was, for putting it back: {"piece", "id", "count",
## "status", "charges", "grid", "cell", "rotated", "index" (its place in the grid's list), "stack" (the
## stack it was split off, or null)}.
static func _taken(piece: ItemInstance, grid: InventoryGrid, count: int) -> Dictionary:
	return {"piece": piece, "id": piece.data.id, "count": count, "status": _status(piece), "charges": piece.charges, "grid": grid,
		"cell": piece.cell, "rotated": piece.rotated, "index": grid.items.find(piece), "stack": null}


## Takes up to `amount` of stackable `id` out of the stash (its own grid first, then the containers in it,
## at any depth): _take_from().
static func _take(stash: InventoryGrid, id: String, amount: int) -> Array[Dictionary]:
	return _take_from(_stash_grids(stash), id, amount)


## Takes up to `amount` of stackable `id` out of `grids`, in order (in each, stacks that aren't found in
## raid first, then the smallest, as InventoryGrid.take_pieces()), each piece within a stack and keeping
## its status: [_taken() records].
static func _take_from(grids: Array[InventoryGrid], id: String, amount: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var left := amount
	for grid in grids:
		if left <= 0:
			break
		var stacks := grid.items.filter(func(item: ItemInstance) -> bool: return item.data.id == id and not item.hidden)
		stacks.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.count < b.count if a.fir == b.fir else not a.fir)
		for stack: ItemInstance in stacks:
			if left <= 0:
				break
			var used := mini(stack.count, left)
			var record := _taken(stack, grid, used)
			if used == stack.count:
				grid.remove(stack)
			else:
				stack.count -= used
				record.piece = stack.copy_stack(used)
				record.stack = stack
				grid.changed.emit()
			left -= used
			result.append(record)
	return result


## Adds `piece` to `grid` as InventoryGrid.add() would (onto matching stacks first, then the first free
## spot), remembering what went where: {"grid", "id", "status", "charges", "count": how many went in,
## "merged": [[stack, amount]], "placed": the piece if it went in as its own stack, else null,
## "placed_count": how many it held then (later moves, or an arrival, may top it up)}. What didn't go in
## is left on `piece`.
static func _add_tracked(grid: InventoryGrid, piece: ItemInstance) -> Dictionary:
	var record := {"grid": grid, "id": piece.data.id, "status": _status(piece), "charges": piece.charges, "count": 0, "merged": [],
		"placed": null, "placed_count": 0}
	if not grid.accepts(piece):
		return record
	for other in grid.items:
		if piece.count > 0 and other.can_stack_with(piece):
			var moved := mini(piece.count, other.data.max_stack - other.count)
			if moved > 0:
				other.count += moved
				piece.count -= moved
				record.merged.append([other, moved])
				record.count += moved
	if piece.count > 0:
		var spot := grid.find_space(piece)
		if not spot.is_empty() and grid.place(piece, spot.cell, spot.rotated):
			record.placed = piece
			record.placed_count = piece.count
			record.count += piece.count
	if not record.merged.is_empty():
		grid.changed.emit()
	return record


## Takes back out of its grid what _add_tracked() put in (`record`), and no more: the stack it placed (as
## many as it held then: what later moves or an arrival put on top stays) and what it topped other
## stacks up with (from stacks of the same kind if those are gone). Returns it as one piece (the placed
## stack itself when all of it goes), or null.
static func _take_back(record: Dictionary) -> ItemInstance:
	var grid: InventoryGrid = record.grid
	var recovered := 0
	var placed: ItemInstance = record.placed
	var mine := int(record.get("placed_count", placed.count if placed else 0))
	if placed and grid.items.has(placed):
		if mine >= placed.count:
			grid.remove(placed)
			mine = placed.count
		else:
			placed.count -= mine
			grid.changed.emit()
			placed = null
		recovered += mine
	elif placed:
		recovered += _take_exact(grid, record.id, record.status, record.charges, mine)
		placed = null
	for pair: Array in record.merged:
		var stack: ItemInstance = pair[0]
		var amount: int = pair[1]
		var got := 0
		if grid.items.has(stack):
			got = mini(stack.count, amount)
			stack.count -= got
			if stack.count <= 0:
				grid.remove(stack)
		if got < amount:
			got += _take_exact(grid, record.id, record.status, record.charges, amount - got)
		recovered += got
	if not record.merged.is_empty():
		grid.changed.emit()
	if recovered <= 0:
		return null
	if placed:
		placed.count = recovered
		return placed
	return _piece(record.id, recovered, record.status, record.charges)


## Takes `amount` of `id` with `status` and `charges` out of `grid`, smallest stacks first. Returns how many.
static func _take_exact(grid: InventoryGrid, id: String, status: Array, charges: float, amount: int) -> int:
	var stacks := grid.items.filter(func(item: ItemInstance) -> bool:
		return item.data.id == id and _status(item) == status and is_equal_approx(item.charges, charges))
	stacks.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.count < b.count)
	var taken := 0
	for stack: ItemInstance in stacks:
		var used := mini(stack.count, amount - taken)
		stack.count -= used
		taken += used
		if stack.count <= 0:
			grid.remove(stack)
		if taken >= amount:
			break
	return taken


## Puts `piece` back where `record` (_taken()) says it was: onto the stack it was split off, else its own
## spot; unless `exact`, else anywhere in its grid, the stash or on the character. False if nothing took
## all of it (what's left is on `piece`; with `exact`, nothing moved). `piece` is within a stack.
static func _put_back(record: Dictionary, piece: ItemInstance, inventory: Inventory, stash: InventoryGrid, exact := false) -> bool:
	var grid: InventoryGrid = record.grid
	var stack: ItemInstance = record.get("stack")
	if stack and grid.items.has(stack) and _merges(stack, piece):
		stack.count += piece.count
		grid.changed.emit()
		return true
	if grid.place(piece, record.cell, record.rotated):
		_reorder(grid, piece, int(record.get("index", -1)))
		return true
	if exact:
		return false
	return grid.add(piece) or stash.add(piece) or inventory.add(piece)


## _put_back() without `exact`, remembering where each part went (_add_tracked() records, for
## _take_back()) so it can be taken out again: {"records", "left": how many had no room anywhere}.
static func _put_back_tracked(record: Dictionary, piece: ItemInstance, inventory: Inventory, stash: InventoryGrid) -> Dictionary:
	var grid: InventoryGrid = record.grid
	var stack: ItemInstance = record.get("stack")
	var done := {"grid": grid, "id": piece.data.id, "status": _status(piece), "charges": piece.charges, "count": piece.count, "merged": [],
		"placed": null, "placed_count": 0}
	if stack and grid.items.has(stack) and _merges(stack, piece):
		stack.count += piece.count
		grid.changed.emit()
		done.merged = [[stack, piece.count]]
		return {"records": [done], "left": 0}
	if grid.place(piece, record.cell, record.rotated):
		_reorder(grid, piece, int(record.get("index", -1)))
		done.placed = piece
		done.placed_count = piece.count
		return {"records": [done], "left": 0}
	var records: Array[Dictionary] = []
	var targets: Array[InventoryGrid] = [grid, stash]
	targets.append_array(inventory.ammo_grids())
	for target in targets:
		var added := _add_tracked(target, piece)
		if int(added.count) > 0:
			records.append(added)
		if added.placed or piece.count <= 0:
			return {"records": records, "left": 0}
	return {"records": records, "left": piece.count}


## Puts `piece` (what _take_back(record) just took out) back into `record`'s grid (onto its stacks, else
## a free spot), else the stash, else the pockets, rig or backpack: undoing an undo step that couldn't
## finish. False if some had no room at all (left on `piece`).
static func _give_back(record: Dictionary, piece: ItemInstance, inventory: Inventory, stash: InventoryGrid) -> bool:
	var grid: InventoryGrid = record.grid
	if _add_tracked(grid, piece).placed or piece.count <= 0:
		return true
	for target: InventoryGrid in [stash] + inventory.ammo_grids():
		if target.add(piece):
			return true
	return false


## Moves `item`, just put back in its own spot in `grid`, to `index` in the grid's list, where it was
## before auto-equip took it out (undone newest first, so the grid ends up as it was, down to the order
## a save lists it in). -1: leave it last.
static func _reorder(grid: InventoryGrid, item: ItemInstance, index: int) -> void:
	if index < 0 or grid.items.find(item) == index:
		return
	grid.items.erase(item)
	grid.items.insert(mini(index, grid.items.size()), item)


## True if `piece` can go back exactly where `record` (_taken()) says it was: onto the stack it was split
## off, or into its own spot.
static func _fits_back(record: Dictionary, piece: ItemInstance) -> bool:
	var grid: InventoryGrid = record.grid
	var stack: ItemInstance = record.get("stack")
	if stack and grid.items.has(stack) and _merges(stack, piece):
		return true
	return grid.can_place(piece, record.cell, record.rotated)


## True if `piece` can go onto `stack` whole: the same item, status and uses left, within a stack.
static func _merges(stack: ItemInstance, piece: ItemInstance) -> bool:
	return stack.data == piece.data and stack.same_status(piece) and is_equal_approx(stack.charges, piece.charges) \
		and stack.count + piece.count <= stack.data.max_stack


## [fir, fir_pending, brought_in]: what stacks must share to merge.
static func _status(item: ItemInstance) -> Array:
	return [item.fir, item.fir_pending, item.brought_in]


static func _key(id: String, status: Array) -> String:
	return "%s|%s" % [id, status]


static func _set_status(item: ItemInstance, status: Array) -> void:
	item.fir = status[0]
	item.fir_pending = status[1]
	item.brought_in = status[2]


## `count` rounds of `id` as one magazine run (not capped to a stack) with `status`, or null.
static func _rounds(id: String, count: int, status: Array) -> ItemInstance:
	var rounds := ItemInstance.full_rounds(id, count)
	if rounds:
		_set_status(rounds, status)
	return rounds


## A stack of `count` of `id` with `status` and `charges` (null for none). The caller keeps it within a
## stack: it's never cut down, so no round is lost.
static func _piece(id: String, count: int, status: Array, charges: float) -> ItemInstance:
	if count <= 0:
		return null
	var piece := ItemInstance.create(id, 1)
	if piece:
		piece.count = count
		_set_status(piece, status)
		piece.charges = charges
	return piece


# --- Undo -----------------------------------------------------------------------------------------

## Reverses `plan` (from apply()): each of its moves, newest first, diff-based (see the class notes). Each
## item goes back to its own spot first; one whose spot something else took meanwhile (an insurance
## return) waits until everything else is back, then goes wherever there's room in its grid, else the
## stash, so one arrival never pushes the rest about. A move something has changed since (an item no
## longer where the plan put it) is left as it is. Once only; a preview (plan()) can't be undone. Returns
## {"ok", "message", "lines": [what couldn't go back as it was]}.
static func undo(plan: Dictionary, inventory: Inventory, stash: InventoryGrid) -> Dictionary:
	if plan.get("preview", false) or plan.get("undone", false) or not plan.get("moves") is Array:
		return {"ok": false, "message": "Nothing to undo", "lines": []}
	var report: Array[String] = []
	_undo_moves(plan.moves, 0, inventory, stash, report)
	plan.undone = true
	for grid in inventory.grids():
		grid.changed.emit()
	inventory.changed.emit()
	stash.changed.emit()
	var message := "Undone: everything is back as it was" if report.is_empty() else "Undone. %s" % " ".join(report)
	return {"ok": true, "message": message, "lines": report}


## Undoes `moves` from index `from` on, newest first: those that can go back exactly at once, then the
## rest (still newest first) wherever there's room.
static func _undo_moves(moves: Array, from: int, inventory: Inventory, stash: InventoryGrid, report: Array[String]) -> void:
	var waiting: Array = []
	for i in range(moves.size() - 1, from - 1, -1):
		if not _undo_move(moves[i], inventory, stash, report, true):
			waiting.append(moves[i])
	for move: Dictionary in waiting:
		_undo_move(move, inventory, stash, report, false)


## Undoes one move. With `exact`, only if everything goes back exactly where it was: false (nothing done)
## if not. Without, wherever there's room; what can't move at all stays and is reported.
static func _undo_move(move: Dictionary, inventory: Inventory, stash: InventoryGrid, report: Array[String], exact: bool) -> bool:
	match str(move.op):
		"dress":
			return _undo_dress(move, inventory, stash, report, exact)
		"move":
			# A rig's or backpack's item moved into the new one: back into the old one.
			var item: ItemInstance = move.item
			var into: InventoryGrid = move.to
			var home: InventoryGrid = move.grid
			if not into.items.has(item):
				return true
			if exact and not home.can_place(item, move.cell, move.rotated):
				return false
			var cell := item.cell
			var turned := item.rotated
			into.remove(item)
			if home.place(item, move.cell, move.rotated):
				_reorder(home, item, int(move.get("index", -1)))
			elif not (home.add(item) or stash.add(item)):
				into.place(item, cell, turned)
				report.append("Your %s stayed where it was." % item.title())
		"fit":
			var gun: ItemInstance = move.gun
			var part: ItemInstance = move.part
			if WeaponMods.mod_at(gun, move.path) != part:
				return true
			if exact and not _fits_back(move, part):
				return false
			WeaponMods.uninstall(gun, move.path)
			if not _put_back(move, part, inventory, stash):
				WeaponMods.install(gun, move.path, part)
				report.append("No room to put your %s back: it stays on the %s." % [part.title(), gun.title()])
		"load":
			if exact:
				for taken: Dictionary in move.taken:
					var probe := _piece(taken.id, int(taken.count), taken.status, taken.charges)
					if probe and not _fits_back(taken, probe):
						return false
			_undo_load(move, inventory, stash, report)
		"pack":
			var taken: Dictionary = move.take
			if exact:
				var probe := _piece(taken.id, int(taken.count), taken.status, taken.charges)
				if probe and not _fits_back(taken, probe):
					return false
			_undo_pack(move, inventory, stash, report)
	return true


## Slots auto-equip filled: the new items come off, the old ones come out of the stash and go back on,
## then the new ones go back to their spots. With `exact`, only if each new item's spot is free (or held
## by an old item about to go back on) and each old item is still in the stash: false (nothing done) if
## not. Without, a new item with its spot taken goes anywhere in its grid, else the stash, else the
## pockets, rig or backpack; if one has no room at all, the whole move stays as auto-equip left it (the
## new items on, the old ones in the stash), as body armor and an armored rig can't both go back on. A
## slot whose item was changed since is left as it is.
static func _undo_dress(move: Dictionary, inventory: Inventory, stash: InventoryGrid, report: Array[String], exact: bool) -> bool:
	var live: Array[Dictionary] = []
	var leaving: Array[ItemInstance] = []
	var notes: Array[String] = []
	for entry: Dictionary in move.entries:
		var item: ItemInstance = entry.new
		var old: ItemInstance = entry.old
		if item and inventory.equipment.get(entry.slot) != item:
			notes.append("Your %s was moved since: left as it is." % item.title())
			continue
		if old and stash.find_holder(old) == null:
			if exact:
				return false
			notes.append("Your %s wasn't in the stash any more." % old.title())
		elif old:
			leaving.append(old)
		live.append(entry)
	if exact:
		for entry in live:
			if entry.new and not _spot_free(entry.grid, entry.new, entry.cell, entry.rotated, leaving):
				return false
	report.append_array(notes)
	for entry in live:
		if entry.new:
			inventory.unequip(entry.slot)
	var worn_again: Array[Dictionary] = []
	for i in range(live.size() - 1, -1, -1):
		var old: ItemInstance = live[i].old
		if old in leaving:
			var holder := stash.find_holder(old)
			var spot := {"entry": live[i], "grid": holder, "cell": old.cell, "rotated": old.rotated}
			holder.remove(old)
			if _wear_again(inventory, live[i]):
				worn_again.append(spot)
			else:
				_back_in(holder, old, spot.cell, spot.rotated, inventory, stash)
				report.append("Your %s stayed in the stash." % old.title())
	var put: Array[ItemInstance] = []
	var homeless: ItemInstance = null
	for i in range(live.size() - 1, -1, -1):
		var item: ItemInstance = live[i].new
		if item == null:
			continue
		if not _put_back(live[i], item, inventory, stash):
			homeless = item
			break
		put.append(item)
	if homeless == null:
		return true
	# No room for it anywhere: every slot of this move as auto-equip left it (old pieces off first, as body
	# armor and an armored rig exclude each other).
	for item in put:
		var holder := stash.find_holder(item)
		if holder == null:
			holder = inventory.holder_of(item)
		if holder:
			holder.remove(item)
	for spot in worn_again:
		var old: ItemInstance = inventory.unequip(spot.entry.slot)
		_back_in(spot.grid, old, spot.cell, spot.rotated, inventory, stash)
	var slots: Array[String] = []
	for entry in live:
		slots.append(GearCompare.slot_name(entry.slot).to_lower())
		if entry.new and not inventory.equip(entry.slot, entry.new):
			_back_in(entry.grid, entry.new, entry.cell, entry.rotated, inventory, stash)
	report.append("No room to put your %s back: your %s stay%s as auto-equip left them." % [homeless.title(), " and ".join(slots),
		"" if slots.size() > 1 else "s"])
	return true


## Puts `item` (just taken out of `grid`) back at `cell`, else anywhere in `grid`, the stash or the
## pockets, rig or backpack. False if nothing had room.
static func _back_in(grid: InventoryGrid, item: ItemInstance, cell: Vector2i, turned: bool, inventory: Inventory, stash: InventoryGrid) -> bool:
	if grid and (grid.place(item, cell, turned) or grid.add(item)):
		return true
	return stash.add(item) or inventory.add(item)


## Puts a dress entry's old item back on its slot as it was (its cell and turn, which a worn item keeps
## from where it last lay, are saved with it). False if the slot doesn't take it.
static func _wear_again(inventory: Inventory, entry: Dictionary) -> bool:
	var old: ItemInstance = entry.old
	var cell := old.cell
	var turned := old.rotated
	old.cell = entry.old_cell
	old.rotated = entry.old_rotated
	if inventory.equip(entry.slot, old):
		return true
	old.cell = cell
	old.rotated = turned
	return false


## True if `item` could go at `cell` (`turned` or not) in `grid`, counting the items in `leaving` as gone.
static func _spot_free(grid: InventoryGrid, item: ItemInstance, cell: Vector2i, turned: bool, leaving: Array[ItemInstance]) -> bool:
	var footprint := item.footprint_if(turned)
	if not grid.accepts(item) or not grid.in_bounds(cell, footprint):
		return false
	var area := Rect2i(cell, footprint)
	for other in grid.items:
		if other != item and not other in leaving and Rect2i(other.cell, other.footprint()).intersects(area):
			return false
	return true


## Rounds or a med auto-equip moved (from the stash into the pockets, rig or backpack, or worse spare rounds
## you carried back to the stash): back where they came from, only what this move put there. What has no
## room anywhere goes back where auto-equip put it.
static func _undo_pack(move: Dictionary, inventory: Inventory, stash: InventoryGrid, report: Array[String]) -> void:
	var taken: Dictionary = move.take
	var got: Array = []  # [record, piece]
	var total := 0
	for i in range(move.added.size() - 1, -1, -1):
		var piece := _take_back(move.added[i])
		if piece:
			got.append([move.added[i], piece])
			total += piece.count
	if got.is_empty():
		return
	var piece: ItemInstance = got[0][1]
	for pair: Array in got:
		if pair[1] == taken.piece:
			piece = pair[1]
	piece.count = total
	if _put_back(taken, piece, inventory, stash) or piece.count <= 0:
		return
	var left := piece.count
	for pair: Array in got:
		if piece.count <= 0 or _give_back(pair[0], piece, inventory, stash):
			break
	report.append("%d × %s stayed where auto-equip put %s." % [left, piece.data.display_name, "it" if left == 1 else "them"])


## A gun loaded by auto-equip: unless its rounds changed since, the rounds that went back to the stash come
## out again (only what this move put there), the rounds it took go back where they came from (onto their
## stack, else anywhere), and the magazine is as it was. If some of the rounds it took have no room
## anywhere, nothing changes (the gun keeps what auto-equip loaded, and what came out of it stays out),
## so the gun never holds more than its magazine.
static func _undo_load(move: Dictionary, inventory: Inventory, stash: InventoryGrid, report: Array[String]) -> void:
	var gun: ItemInstance = move.gun
	if _snapshot(gun) != move.after:
		report.append("The rounds in your %s changed since: left as they are." % gun.title())
		return
	var back: Array = []  # [record, piece]
	var missing := {}
	for record: Dictionary in move.returned:
		var piece := _take_back(record)
		var got := piece.count if piece else 0
		if piece:
			back.append([record, piece])
		if got < int(record.count):
			var key := _key(record.id, record.status)
			missing[key] = int(missing.get(key, 0)) + int(record.count) - got
	var put: Array[Dictionary] = []
	for i in range(move.taken.size() - 1, -1, -1):
		var taken: Dictionary = move.taken[i]
		var piece := _piece(taken.id, int(taken.count), taken.status, taken.charges)
		if piece == null:
			continue
		var result := _put_back_tracked(taken, piece, inventory, stash)
		put.append_array(result.records)
		if int(result.left) > 0:
			# No room for them anywhere: everything as auto-equip left it.
			for j in range(put.size() - 1, -1, -1):
				_take_back(put[j])
			for pair: Array in back:
				_give_back(pair[0], pair[1], inventory, stash)
			report.append("No room to put %d × %s back: your %s keeps the rounds auto-equip loaded." % [int(result.left), piece.data.display_name, gun.title()])
			return
	_restore(gun, move.before, missing)
	gun.loaded_ammo = move.ammo_before
