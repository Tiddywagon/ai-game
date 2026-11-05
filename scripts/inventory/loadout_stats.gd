class_name LoadoutStats
extends RefCounted
## The character's totals on the LOADOUT screen (DESIGN.md §16.6), worked out from what's worn: the
## armor over each body part (ArmorRules.armor_for(): class, durability and the piece; "—" where nothing
## covers it, "Worn out" where the piece that does stops nothing any more), the weight carried against
## the heavy and overweight thresholds (InventoryConfig), the ergonomics and recoil of the gun in hand
## (WeaponStats, with its parts and your skills), carry capacity (the weight left before overweight, and
## the free cells of the pockets, rig and backpack) and hearing (GearUpgrades.hearing_multiplier(): the
## headset, helmet and face cover).

## Body parts shown, as [key, name, BodyHealth.Part, frontal (the face)]. Both arms and both legs share
## their zones, so one row each.
const BODY_PARTS := [
	["head", "Head", BodyHealth.Part.HEAD, false], ["face", "Face", BodyHealth.Part.HEAD, true],
	["thorax", "Thorax", BodyHealth.Part.THORAX, false], ["stomach", "Stomach", BodyHealth.Part.STOMACH, false],
	["arms", "Arms", BodyHealth.Part.LEFT_ARM, false], ["legs", "Legs", BodyHealth.Part.LEFT_LEG, false],
]
const NONE := "—"


## Every row for `gear`: [{"key", "name", "text", "tone"}], `tone` being "" (plain), "dim" (nothing
## there), "heavy" or "over" (a warning, the second worse). `config`: the weight thresholds; `skills`:
## the skills that change a gun's handling (GameState.skills).
static func rows(gear: Inventory, config: InventoryConfig, skills: Dictionary = {}) -> Array[Dictionary]:
	var result := armor_rows(gear)
	result.append_array(carry_rows(gear, config))
	result.append_array(gun_rows(gear, skills))
	result.append(hearing_row(gear))
	return result


## The armor over each body part (BODY_PARTS): "Class 4  ·  49 / 49  ·  6B23-1 body armor", or "—".
static func armor_rows(gear: Inventory) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: Array in BODY_PARTS:
		var piece := ArmorRules.armor_for(gear, part[2], part[3])
		var row := {"key": part[0], "name": part[1], "text": NONE, "tone": "dim", "piece": piece}
		if piece:
			row.text = "Class %d  ·  %s  ·  %s" % [int(piece.data.stats.get("class", 0)), _durability(piece), piece.title()]
			row.tone = ""
		else:
			var worn := _worn_out(gear, ArmorRules.zone_name(part[2], part[3]))
			if worn:
				row.text = "Worn out  ·  %s  ·  %s" % [_durability(worn), worn.title()]
				row.tone = "over"
				row.piece = worn
		result.append(row)
	return result


## A worn-out piece `gear` wears over `zone` (it stops nothing), or null.
static func _worn_out(gear: Inventory, zone: String) -> ItemInstance:
	for piece in ArmorRules.worn_armor(gear):
		if zone in piece.data.stats.get("zones", []):
			return piece
	return null


static func _durability(piece: ItemInstance) -> String:
	return "%d / %d" % [roundi(piece.durability), roundi(piece.max_durability)]


## Weight (against the thresholds), the weight left before overweight and the room in the pockets, rig
## and backpack.
static func carry_rows(gear: Inventory, config: InventoryConfig) -> Array[Dictionary]:
	var weight := gear.total_weight()
	var tone := ""
	var state := "heavy from %s" % Settings.format_weight(config.encumbered_kg)
	if weight >= config.overweight_kg:
		tone = "over"
		state = "overweight (%d%% speed)" % roundi(config.speed_multiplier(weight) * 100.0)
	elif weight > config.encumbered_kg:
		tone = "heavy"
		state = "heavy (%d%% speed)" % roundi(config.speed_multiplier(weight) * 100.0)
	var room := storage(gear)
	return [
		{"key": "weight", "name": "Weight", "text": "%s / %s  ·  %s" % [Settings.format_weight(weight),
			Settings.format_weight(config.overweight_kg), state], "tone": tone},
		{"key": "capacity", "name": "Carry limit", "text": "%s before overweight" % Settings.format_weight(maxf(config.overweight_kg - weight, 0.0))
			if weight < config.overweight_kg else "over by %s" % Settings.format_weight(weight - config.overweight_kg), "tone": tone},
		{"key": "storage", "name": "Storage", "text": "%d of %d cells free  ·  pockets, rig, backpack" % [room.x, room.y],
			"tone": "heavy" if room.y > 0 and room.x == 0 else ""},
	]


## Free and total cells (x, y) of the pockets, rig and backpack (Inventory.ammo_grids(): not the secure
## container).
static func storage(gear: Inventory) -> Vector2i:
	var total := 0
	var used := 0
	for grid in gear.ammo_grids():
		total += grid.size.x * grid.size.y
		for item in grid.items:
			used += item.footprint().x * item.footprint().y
	return Vector2i(maxi(total - used, 0), total)


## Ergonomics and recoil of the gun in hand (Inventory.weapon_slot()), with its parts and `skills`.
static func gun_rows(gear: Inventory, skills: Dictionary = {}) -> Array[Dictionary]:
	var slot := gear.weapon_slot()
	var gun: ItemInstance = gear.equipment.get(slot) if slot != "" else null
	if gun == null or not gun.is_gun():
		return [{"key": "ergonomics", "name": "Ergonomics", "text": "%s  ·  no gun" % NONE, "tone": "dim"},
			{"key": "recoil", "name": "Recoil", "text": NONE, "tone": "dim"}]
	var data := WeaponStats.build(gun, skills)
	return [
		{"key": "ergonomics", "name": "Ergonomics", "text": "%d  ·  %s" % [data.ergonomics, gun.title()], "tone": ""},
		{"key": "recoil", "name": "Recoil", "text": "%.2f° climb, ±%.2f° side a shot" % [data.vertical_recoil, data.horizontal_recoil], "tone": ""},
	]


## How far you hear: "+20%  ·  ComTac headset" (the headset, else the helmet that muffles).
static func hearing_row(gear: Inventory) -> Dictionary:
	var change := GearUpgrades.hearing_multiplier(gear) - 1.0
	var text := ("%+d%%" % roundi(change * 100.0)).replace("-", "−") if not is_zero_approx(change) else "±0%"
	var headset: ItemInstance = gear.equipment.get("headset")
	if headset:
		text += "  ·  %s" % headset.title()
	elif gear.equipment.get("helmet"):
		text += "  ·  no headset"
	return {"key": "hearing", "name": "Hearing", "text": text, "tone": "" if change >= 0.0 else "heavy"}
