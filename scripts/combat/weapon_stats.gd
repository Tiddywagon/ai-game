class_name WeaponStats
extends RefCounted
## What mods do to a gun (DESIGN.md §12.1). Each mod's "modifiers" change the gun's stats against its
## default build, and build() turns a gun with its mods into the WeaponData the Weapon node fires with.
## The default parts have no modifiers, so a stock gun handles exactly as its .tres file says.
##
## Modifiers (percent unless noted; the sign is the change, so recoil -8 is 8% less recoil):
## recoil, ergonomics (points, 0-100 in all), accuracy (spread; negative is tighter), velocity (muzzle
## velocity), aim_speed (positive raises a sight faster), noise (how far a shot is heard), malfunction
## (chance of a jam), durability_loss (wear per shot). Magazines set the capacity; the gun can't fire
## with a required slot empty. A sight sets the optic you aim through (the strongest one, if there are
## two). Empty slots can have modifiers of their own, e.g. an AK without a stock kicks much harder.
##
## Rarity: a mod's bonuses (the modifiers that make the gun better) grow with its rarity, by
## RARITY_SCALE. Its downsides stay as they are.

const RARITY_SCALE: Array[float] = [1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
const MODIFIERS: Array[String] = ["recoil", "ergonomics", "accuracy", "velocity", "aim_speed", "noise", "malfunction",
	"durability_loss"]
## +1 if a higher modifier makes the gun better, -1 if a lower one does.
const BETTER := {"recoil": -1, "ergonomics": 1, "accuracy": -1, "velocity": 1, "aim_speed": 1, "noise": -1,
	"malfunction": -1, "durability_loss": -1}
const MODIFIER_NAMES := {"recoil": "Recoil", "ergonomics": "Ergonomics", "accuracy": "Spread", "velocity": "Muzzle velocity",
	"aim_speed": "Aim speed", "noise": "Noise", "malfunction": "Malfunction chance", "durability_loss": "Wear"}
## Each point of ergonomics below the gun's default makes aiming and moving with it 1% worse (and each
## point above, 1% better).
const HANDLING_PER_POINT := 0.01
## Repairs: max durability lost per point restored, and the price per point as a share of the gun's
## base value.
const REPAIR_WEAR := 0.15
const REPAIR_PRICE_SHARE := 0.004
const COMBAT_CONFIG := preload("res://data/config/combat.tres")


## `mod_data`'s modifiers, with its bonuses scaled by its rarity.
static func modifiers_of(mod_data: ItemData) -> Dictionary:
	var scale := RARITY_SCALE[mod_data.rarity]
	var result := {}
	var raw: Dictionary = WeaponMods.info(mod_data).get("modifiers", {})
	for key: String in raw:
		var value := float(raw[key])
		if value * BETTER.get(key, 1) > 0.0:
			value *= scale
		result[key] = value
	return result


## Every modifier added up over `gun`'s mod tree, empty slots included.
static func totals(gun: ItemInstance) -> Dictionary:
	var sums := {}
	for key in MODIFIERS:
		sums[key] = 0.0
	for entry in WeaponMods.walk(gun):
		var modifiers: Dictionary = modifiers_of(entry.mod.data) if entry.mod else entry.slot.get("empty", {})
		for key: String in modifiers:
			if sums.has(key):
				sums[key] += float(modifiers[key])
	return sums


## The WeaponData `gun` fires with: a copy of its .tres changed by its mods.
static func build(gun: ItemInstance) -> WeaponData:
	var base := gun.data.weapon
	var result: WeaponData = base.duplicate()
	var sums := totals(gun)
	var recoil := clampf(1.0 + sums.recoil / 100.0, 0.3, 2.5)
	result.recoil_per_shot = base.recoil_per_shot * recoil
	result.max_recoil = base.max_recoil * recoil
	result.camera_kick = base.camera_kick * recoil
	var ergonomics := clampf(base.ergonomics + sums.ergonomics, 0.0, 100.0)
	result.ergonomics = roundi(ergonomics)
	var handling := 1.0 + (base.ergonomics - ergonomics) * HANDLING_PER_POINT
	result.move_spread = base.move_spread * handling
	result.base_spread = base.base_spread * clampf(1.0 + sums.accuracy / 100.0, 0.3, 3.0)
	result.velocity_multiplier = clampf(1.0 + sums.velocity / 100.0, 0.5, 1.5)
	result.muzzle_velocity = roundi(base.muzzle_velocity * result.velocity_multiplier)
	result.noise_multiplier = clampf(1.0 + sums.noise / 100.0, 0.15, 2.0)
	result.aim_time_multiplier = clampf(handling / maxf(1.0 + sums.aim_speed / 100.0, 0.1), 0.3, 3.0)
	result.malfunction_multiplier = clampf(1.0 + sums.malfunction / 100.0, 0.1, 4.0)
	result.wear_multiplier = clampf(1.0 + sums.durability_loss / 100.0, 0.2, 3.0)
	if not WeaponMods.slot_on(gun, "magazine").is_empty():
		var magazine := WeaponMods.mod_at(gun, "magazine")
		result.magazine_size = WeaponMods.capacity_of(magazine.data) if magazine else 0
	result.missing_part = WeaponMods.missing_part(gun)
	result.optic = 0
	for mod in WeaponMods.installed(gun):
		if WeaponMods.kind_of(mod.data) == "sight":
			result.optic = maxi(result.optic, int(mod.data.stats.get("optic", 0)))
	return result


## Stat rows for the modding screen and the examine panel: [{"key", "name", "value" (a number to
## compare), "text", "better": +1 if higher is better, -1 if lower is, 0 if neither, "bar": 0-1 or -1}].
static func rows(gun: ItemInstance) -> Array[Dictionary]:
	var data := build(gun)
	var base := gun.data.weapon
	var recoil := 100.0 * data.recoil_per_shot / base.recoil_per_shot if base.recoil_per_shot > 0.0 else 100.0
	var aim_time := VisionSystem.config.optic_transition_time * data.aim_time_multiplier
	var noise := COMBAT_CONFIG.gunshot_noise * data.noise_multiplier
	var jam := data.malfunction_chance(gun.durability) * 100.0
	var result: Array[Dictionary] = [
		_row("ergonomics", "Ergonomics", data.ergonomics, str(data.ergonomics), 1, data.ergonomics / 100.0),
		_row("recoil", "Recoil", recoil, "%d%%" % roundi(recoil), -1, clampf(recoil / 200.0, 0.0, 1.0)),
		_row("accuracy", "Spread", data.base_spread, "%.2f°" % data.base_spread, -1, clampf(data.base_spread / 2.0, 0.0, 1.0)),
		_row("velocity", "Muzzle velocity", data.muzzle_velocity, "%d m/s" % data.muzzle_velocity, 1, -1.0),
		_row("aim_time", "Aim time", aim_time, "%.2f s" % aim_time, -1, -1.0),
		_row("noise", "Shot heard at", noise, "%d m" % roundi(noise), -1, clampf(noise / 120.0, 0.0, 1.0)),
		_row("magazine", "Magazine", data.magazine_size, "%d rounds" % data.magazine_size if data.magazine_size > 0 else "None", 1, -1.0),
		_row("fire_rate", "Fire rate", data.fire_rate, "%d rpm  ·  %s" % [data.fire_rate, "auto" if data.automatic else "semi"], 0, -1.0),
		_row("weight", "Weight", gun.weight_without_rounds(), weight_text(gun.weight_without_rounds()), -1, -1.0),
		_row("durability", "Durability", gun.durability, "%.1f / %.1f" % [gun.durability, gun.max_durability], 1,
			gun.durability / 100.0),
		_row("malfunction", "Jam chance", jam, "%.2f%% per shot" % jam if jam > 0.0 else "None at this durability", -1, -1.0),
	]
	return result


static func _row(key: String, label: String, value: float, text: String, better: int, bar: float) -> Dictionary:
	return {"key": key, "name": label, "value": value, "text": text, "better": better, "bar": bar}


## One line per modifier of `mod_data` for tooltips and the examine panel: [["Recoil", "-8%", good?]].
static func modifier_lines(mod_data: ItemData) -> Array:
	var lines := []
	var modifiers := modifiers_of(mod_data)
	for key in MODIFIERS:
		if not modifiers.has(key) or is_zero_approx(modifiers[key]):
			continue
		var value: float = modifiers[key]
		lines.append([MODIFIER_NAMES[key], format_modifier(key, value), value * BETTER[key] > 0.0])
	return lines


## A modifier as shown: "+4" for ergonomics, "-8%" for the rest (with a real minus sign).
static func format_modifier(key: String, value: float) -> String:
	var text := ("%+d" % roundi(value)) if key == "ergonomics" else ("%+d%%" % roundi(value))
	return text.replace("-", "−")


## How a stat row (rows()) changed, e.g. "+6" or "−0.05°"; "" if it didn't.
static func format_delta(key: String, delta: float) -> String:
	var text := ""
	match key:
		"accuracy":
			text = "%+.2f°" % delta
		"aim_time":
			text = "%+.2f s" % delta
		"malfunction":
			text = "%+.2f%%" % delta
		"recoil":
			text = "%+d%%" % roundi(delta)
		"velocity":
			text = "%+d m/s" % roundi(delta)
		"noise":
			text = "%+d m" % roundi(delta)
		"weight":
			text = ("+" if delta > 0.0 else "-") + weight_text(absf(delta))
		_:
			text = "%+d" % roundi(delta)
	if text.replace("+", "").replace("-", "").to_float() == 0.0:
		return ""  # Rounds to nothing.
	return text.replace("-", "−")


## A weight to two decimals (parts are light), in the units chosen in Settings.
static func weight_text(kg: float) -> String:
	if Settings.get_value("gameplay", "units") == "imperial":
		return "%.2f lb" % (kg * 2.20462)
	return "%.2f kg" % kg


# --- Durability --------------------------------------------------------------------------------

## Roubles to repair `gun` back to its max durability.
static func repair_price(gun: ItemInstance) -> int:
	return ceili((gun.max_durability - gun.durability) * gun.data.base_value * REPAIR_PRICE_SHARE)


## Restores `gun` to its max durability, which drops by REPAIR_WEAR per point restored.
static func repair(gun: ItemInstance) -> void:
	var restored := gun.max_durability - gun.durability
	gun.max_durability = maxf(gun.max_durability - restored * REPAIR_WEAR, 1.0)
	gun.durability = gun.max_durability
