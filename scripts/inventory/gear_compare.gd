class_name GearCompare
extends RefCounted
## Compares a piece of gear with what's worn in the slot it would go in (DESIGN.md §16.6), for the
## LOADOUT screen's hover comparison: rows of [stat, now, with it, change], each judged better or worse
## where that makes sense (green ▲ better, red ▼ worse; rows it can't judge stay plain).
##
## Which slot: guns that aren't pistols are compared with your primary weapon (your secondary when the
## primary slot is empty), pistols with the pistol slot, everything else with its own slot. Against an
## empty slot, protection, room and hearing count as gained and weight as added; handling isn't judged.
## Body armor while you wear an armored rig (or an armored rig over body armor) can't go on: its armor
## rows compare with the piece in the way, which is what protects you there now.
## Rows by kind: armor, armored rigs and ballistic masks (class, what it covers, durability, weight),
## helmets (also the face: a fitted face shield, and hearing), face covers, headsets (hearing), rigs and
## backpacks (room in cells, grid, weight; armor rows too when armored), guns (WeaponStats rows:
## ergonomics, recoil, accuracy, fire rate, durability, jam chance, and the caliber) and melee (damage).

## Gun rows compared, by WeaponStats.rows() key.
const GUN_ROWS: Array[String] = ["ergonomics", "vertical_recoil", "horizontal_recoil", "base_spread", "fire_rate", "durability",
	"malfunction"]
const NONE := "—"


## The slot `item` would be compared with (see the class notes), or "" if it isn't worn gear.
static func slot_for(item: ItemInstance, gear: Inventory) -> String:
	var data := item.data
	match data.category:
		ItemData.Category.WEAPON:
			if str(data.stats.get("class", "")) == Inventory.PISTOL_CLASS:
				return "pistol"
			return "secondary" if gear.equipment.get("primary") == null and gear.equipment.get("secondary") != null else "primary"
		ItemData.Category.MELEE:
			return "melee"
		ItemData.Category.HELMET:
			return "helmet"
		ItemData.Category.FACE_COVER:
			return "face_cover"
		ItemData.Category.ARMOR:
			return "armor"
		ItemData.Category.RIG:
			return "rig"
		ItemData.Category.BACKPACK:
			return "backpack"
		ItemData.Category.ATTACHMENT:
			return "headset" if WeaponMods.kind_of(data) == "headset" else ""
	return ""


## `item` against what `gear` wears in its slot: {"slot", "slot_name", "item", "current" (or null),
## "against" (the piece in the way its armor rows compare with, or null), "rows": [{"key", "name",
## "now", "new", "change" (1 better, -1 worse, 0 plain), "delta"}], "note" (why it can't go on now, or
## "")}; {} if it isn't worn gear.
static func compare(item: ItemInstance, gear: Inventory) -> Dictionary:
	var slot := slot_for(item, gear)
	if slot == "":
		return {}
	var current: ItemInstance = gear.equipment.get(slot)
	var blocker := _blocker(slot, item, gear)
	var guard: ItemInstance = blocker if blocker else current  # What the armor rows compare with.
	var rows: Array[Dictionary] = []
	match item.data.category:
		ItemData.Category.WEAPON:
			rows = _gun_rows(item, current)
		ItemData.Category.MELEE:
			rows.append(_row("damage", "Damage", _stat(current, "damage"), _stat(item, "damage"), 1, true, "%d"))
			rows.append(_weight_row(current, item))
		ItemData.Category.ATTACHMENT:
			rows.append(_row("hearing", "Hearing", _hearing(current), _hearing(item), 1, true, "%+d%%", 100.0))
			rows.append(_weight_row(current, item))
		ItemData.Category.RIG, ItemData.Category.BACKPACK:
			rows.append(_row("capacity", "Room", _cells(current), _cells(item), 1, true, "%d cells"))
			rows.append(_text_row("grid", "Grid", _grid_text(current), _grid_text(item)))
			if item.is_armor() or (guard and guard.is_armor()):
				rows.append_array(_armor_rows(guard, item))
			rows.append(_weight_row(current, item))
		_:
			rows.append_array(_armor_rows(guard, item))
			if item.data.category == ItemData.Category.HELMET:
				rows.append(_row("face", "Face", _face_class(current), _face_class(item), 1, true, "class %d"))
			if item.data.category in [ItemData.Category.HELMET, ItemData.Category.FACE_COVER]:
				rows.append(_row("hearing", "Hearing", _hearing(current), _hearing(item), 1, true, "%+d%%", 100.0))
			rows.append(_weight_row(current, item))
	var note := ""
	if blocker and slot == "rig":
		note = "Take off your body armor first: an armored rig doesn't go over it. Armor compared with your %s" % blocker.title()
	elif blocker:
		note = "Take off your armored rig first: body armor doesn't go under it. Armor compared with your %s" % blocker.title()
	elif not gear.accepts(slot, item):
		note = "Doesn't go in this slot"
	return {"slot": slot, "slot_name": slot_name(slot), "item": item, "current": current, "against": blocker, "rows": rows,
		"note": note}


## What keeps `item` out of `slot` and already protects you there: the body armor an armored rig can't
## go over, or the armored rig body armor can't go under (null if nothing does).
static func _blocker(slot: String, item: ItemInstance, gear: Inventory) -> ItemInstance:
	var rig: ItemInstance = gear.equipment.get("rig")
	var armor: ItemInstance = gear.equipment.get("armor")
	if slot == "armor" and rig and rig.is_armor():
		return rig
	if slot == "rig" and item.is_armor() and armor:
		return armor
	return null


static func slot_name(slot: String) -> String:
	for entry: Array in Inventory.SLOTS:
		if entry[0] == slot:
			return entry[1]
	return slot


# --- Rows -----------------------------------------------------------------------------------------

## A judged row: `now` / `new` are numbers (null for nothing there); `better` 1 when higher is better,
## -1 when lower is, 0 for plain; `vs_empty`: judge it against an empty slot (as 0). `format` shows a
## value (× `scale`).
static func _row(key: String, name: String, now: Variant, new: Variant, better: int, vs_empty: bool, format: String,
		scale := 1.0) -> Dictionary:
	var row := {"key": key, "name": name, "now": _show(now, format, scale), "new": _show(new, format, scale), "change": 0, "delta": ""}
	if now == null and not vs_empty:
		return row
	var before := float(now) if now != null else 0.0
	var after := float(new) if new != null else 0.0
	var diff := after - before
	if is_zero_approx(diff * scale) or roundf(absf(diff) * scale * 10.0) == 0.0:
		return row
	row.change = int(signf(diff)) * better
	row.delta = _signed(_show(absf(diff), format.replace("%+", "%"), scale), diff)
	return row


## A plain row of two texts.
static func _text_row(key: String, name: String, now: String, new: String) -> Dictionary:
	return {"key": key, "name": name, "now": now, "new": new, "change": 0, "delta": ""}


static func _show(value: Variant, format: String, scale: float) -> String:
	if value == null:
		return NONE
	if format.contains("%d") or format.contains("%+d"):
		return (format % roundi(float(value) * scale)).replace("-", "−")
	return (format % (float(value) * scale)).replace("-", "−")


## "+3 cells" / "−0.4 kg" for a change of `diff` shown as `text` (its size).
static func _signed(text: String, diff: float) -> String:
	return ("+" if diff > 0.0 else "−") + text.trim_prefix("+")


static func _weight_row(now: ItemInstance, new: ItemInstance) -> Dictionary:
	var before: Variant = _own_weight(now)
	var after: float = _own_weight(new)
	var row := _row("weight", "Weight", before, after, -1, true, "%.2f kg")
	row.now = Settings.format_weight(float(before)) if before != null else NONE
	row.new = Settings.format_weight(after)
	if row.delta != "":
		var diff := after - (float(before) if before != null else 0.0)
		row.delta = _signed(Settings.format_weight(absf(diff)), diff)
	return row


## A piece's own weight: with its fitted parts, not what's inside it or loaded.
static func _own_weight(item: ItemInstance) -> Variant:
	if item == null:
		return null
	var total := item.data.weight_kg * GearUpgrades.weight_multiplier(item)
	for part in WeaponMods.installed(item):
		total += part.data.weight_kg * WeaponStats.part_weight_multiplier(part.data)
	return total


static func _stat(item: ItemInstance, key: String) -> Variant:
	if item == null or not item.data.stats.has(key):
		return null
	return float(item.data.stats[key])


static func _armor_rows(now: ItemInstance, new: ItemInstance) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append(_row("class", "Armor class", _armor_class(now), _armor_class(new), 1, true, "%d"))
	rows.append(_row("zones", "Covers", _zone_count(now), _zone_count(new), 1, true, "%d"))
	rows[-1].now = _zones_text(now)
	rows[-1].new = _zones_text(new)
	if rows[-1].delta != "":
		rows[-1].delta = rows[-1].delta + (" zone" if absi(_zone_count(new) - _zone_count(now)) == 1 else " zones")
	var durability := _row("durability", "Durability", _durability(now), _durability(new), 1, true, "%d")
	durability.now = "%d / %d" % [roundi(now.durability), roundi(now.max_durability)] if now and now.is_armor() else NONE
	durability.new = "%d / %d" % [roundi(new.durability), roundi(new.max_durability)] if new.is_armor() else NONE
	rows.append(durability)
	return rows


static func _armor_class(item: ItemInstance) -> Variant:
	if item == null or not item.is_armor():
		return null
	return float(item.data.stats.get("class", 0))


static func _durability(item: ItemInstance) -> Variant:
	if item == null or not item.is_armor():
		return null
	return item.durability


static func _zone_count(item: ItemInstance) -> int:
	return item.data.stats.get("zones", []).size() if item and item.is_armor() else 0


static func _zones_text(item: ItemInstance) -> String:
	if item == null or not item.is_armor():
		return NONE
	return ", ".join(item.data.stats.get("zones", []).map(func(zone: String) -> String: return zone.capitalize()))


## The class of a helmet's fitted face shield (null with none).
static func _face_class(item: ItemInstance) -> Variant:
	if item == null:
		return null
	for part in WeaponMods.installed(item):
		if part.is_armor() and "face" in part.data.stats.get("zones", []):
			return float(part.data.stats.get("class", 0))
	return null


## How a piece (with its parts) changes hearing (GearUpgrades.hearing()); null for nothing there.
static func _hearing(item: ItemInstance) -> Variant:
	if item == null:
		return null
	var total := 0.0
	for part: ItemInstance in WeaponMods.installed(item) + [item]:
		total += GearUpgrades.hearing(part)
	return total


## Cells in a rig's or backpack's grid (at its upgrade level).
static func _cells(item: ItemInstance) -> Variant:
	if item == null or item.contents == null:
		return null
	return float(item.contents.size.x * item.contents.size.y)


static func _grid_text(item: ItemInstance) -> String:
	return "%d × %d" % [item.contents.size.x, item.contents.size.y] if item and item.contents else NONE


## WeaponStats rows (GUN_ROWS) for `new` against `now`, judged like WeaponStatList; plus the caliber.
static func _gun_rows(new: ItemInstance, now: ItemInstance) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var skills: Dictionary = GameState.skills
	var after := {}
	for row in WeaponStats.rows(new, skills):
		after[row.key] = row
	var before := {}
	if now and now.is_gun():
		for row in WeaponStats.rows(now, skills):
			before[row.key] = row
	for key in GUN_ROWS:
		if not after.has(key):
			continue
		var b: Dictionary = before.get(key, {})
		var a: Dictionary = after[key]
		var row := {"key": key, "name": "Accuracy (spread)" if key == "base_spread" else str(a.name), "now": str(b.get("text", NONE)),
			"new": str(a.text), "change": 0, "delta": ""}
		if not b.is_empty():
			var text := WeaponStats.format_delta(key, float(a.value) - float(b.value))
			if text != "":
				row.delta = text
				row.change = int(signf(float(a.value) - float(b.value))) * int(a.better)
		rows.append(row)
	var caliber_now := str(now.data.weapon.caliber) if now and now.is_gun() else NONE
	rows.append(_text_row("caliber", "Caliber", caliber_now, str(new.data.weapon.caliber) if new.is_gun() else NONE))
	return rows
