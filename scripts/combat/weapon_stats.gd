class_name WeaponStats
extends RefCounted
## How a gun handles with its parts (DESIGN.md §12.1, §13.4). build() turns a gun and its mods into
## the WeaponData the Weapon node fires with; the stock parts change nothing, so a stock gun handles
## exactly as its .tres says. All the tuning is in data files: each gun's base values in
## data/weapons/, the strength of parts by rarity and the effects of ergonomics, weight, wear and
## skills in data/config/handling.tres, each attachment kind's default effects in
## data/config/attachment_profiles.json, and each part's own in its item file.
##
## The ten handling stats (vertical recoil, horizontal recoil, recoil recovery, base spread, bloom per
## shot, max bloom, bloom recovery, hip-fire spread, ergonomics, weight) come from the part's kind
## profile, which the part's "handling" can override entry by entry. A positive profile value is a
## bonus that grows with rarity (that many times the rarity's strength: Common about 4%, Legendary
## about 23%); a negative value is a fixed downside. Weight changes the part's own weight. "Standard"
## parts (what a gun comes with) have no effects. The part's "modifiers" are its own fixed effects on
## muzzle velocity, aim speed, noise, jam chance and wear (bonuses × a rarity factor).
##
## Stat changes are percentages (ergonomics: points), signed as the change: vertical_recoil -4 is 4%
## less climb. Empty slots can change the gun too (their "empty" modifiers, the same way).

const CONFIG: HandlingConfig = preload("res://data/config/handling.tres")
const COMBAT_CONFIG: CombatConfig = preload("res://data/config/combat.tres")

## The handling stats an attachment kind's profile covers, in display order.
const HANDLING: Array[String] = ["vertical_recoil", "horizontal_recoil", "recoil_recovery", "base_spread", "bloom_per_shot",
	"max_bloom", "bloom_recovery", "hip_spread", "ergonomics", "weight"]
## A part's own fixed modifiers.
const SPECIAL: Array[String] = ["velocity", "aim_speed", "noise", "malfunction", "durability_loss", "pellet_spread"]
## +1 if a higher value makes the gun better, -1 if a lower one does.
const BETTER := {"vertical_recoil": -1, "horizontal_recoil": -1, "recoil_recovery": 1, "base_spread": -1,
	"bloom_per_shot": -1, "max_bloom": -1, "bloom_recovery": 1, "hip_spread": -1, "ergonomics": 1, "weight": -1,
	"velocity": 1, "aim_speed": 1, "noise": -1, "malfunction": -1, "durability_loss": -1, "pellet_spread": -1}
const MODIFIER_NAMES := {"vertical_recoil": "Vertical recoil", "horizontal_recoil": "Horizontal recoil",
	"recoil_recovery": "Recoil recovery", "base_spread": "Base spread", "bloom_per_shot": "Bloom per shot",
	"max_bloom": "Max bloom", "bloom_recovery": "Bloom recovery", "hip_spread": "Hip-fire spread",
	"ergonomics": "Ergonomics", "weight": "Weight", "velocity": "Muzzle velocity", "aim_speed": "Aim speed",
	"noise": "Noise", "malfunction": "Jam chance", "durability_loss": "Wear", "pellet_spread": "Pellet spread"}

static var _profiles := {}
static var _part_effects := {}
static var _default_weights := {}
static var _everyday_speeds := {}


# --- Parts ---------------------------------------------------------------------------------------

## The default effects of attachment kind `kind` (from attachment_profiles.json).
static func kind_profile(kind: String) -> Dictionary:
	if _profiles.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG.profiles_path))
		_profiles = parsed.get("kinds", {}) if parsed is Dictionary else {}
		if _profiles.is_empty():
			push_error("WeaponStats: %s has no attachment kinds" % CONFIG.profiles_path)
	return _profiles.get(kind, {})


## The profile part `mod_data` uses: its kind's, with its own "handling" entries in place. Empty for
## standard parts.
static func profile_of(mod_data: ItemData) -> Dictionary:
	var info := WeaponMods.info(mod_data)
	if info.is_empty() or info.get("standard", false):
		return {}
	var profile := kind_profile(str(info.get("kind", ""))).duplicate()
	profile.merge(info.get("handling", {}), true)
	return profile


## How strong a bonus of 1 is at `rarity`, in percent.
static func rarity_strength(rarity: int) -> float:
	return CONFIG.rarity_bonus_percent[clampi(rarity, 0, CONFIG.rarity_bonus_percent.size() - 1)]


## What part `mod_data` does, as stat changes ({"vertical_recoil": -4.0, "ergonomics": 3.0, ...}):
## its profile with rarity applied, plus its own modifiers. Weight is the change to the part's own
## weight.
static func modifiers_of(mod_data: ItemData) -> Dictionary:
	if _part_effects.has(mod_data.id):
		return _part_effects[mod_data.id]
	var result := {}
	var strength := rarity_strength(mod_data.rarity)
	var profile := profile_of(mod_data)
	for stat: String in profile:
		var value := float(profile[stat])
		if is_zero_approx(value) or not BETTER.has(stat):
			continue
		# A bonus grows with rarity; a downside is the value itself.
		var amount := value * strength if value > 0.0 else -value
		if stat == "ergonomics" and value > 0.0:
			amount *= CONFIG.ergonomics_points_per_percent
		result[stat] = amount * BETTER[stat] * signf(value)
	var info := WeaponMods.info(mod_data)
	if not info.get("standard", false):
		var scale: float = CONFIG.special_rarity_scale[clampi(mod_data.rarity, 0, CONFIG.special_rarity_scale.size() - 1)]
		var special: Dictionary = info.get("modifiers", {})
		for key: String in special:
			var value := float(special[key])
			result[key] = value * scale if value * BETTER.get(key, 1) > 0.0 else value
	_part_effects[mod_data.id] = result
	return result


## How much part `mod_data` weighs compared with its item weight (rarer parts are lighter).
static func part_weight_multiplier(mod_data: ItemData) -> float:
	return maxf(1.0 + float(modifiers_of(mod_data).get("weight", 0.0)) / 100.0, 0.1)


## Every stat change added up over `gun`'s mod tree, empty slots included (not weight: that's in the
## parts' own weights).
static func totals(gun: ItemInstance) -> Dictionary:
	var sums := {}
	for key: String in BETTER:
		sums[key] = 0.0
	for entry in WeaponMods.walk(gun):
		var modifiers: Dictionary = modifiers_of(entry.mod.data) if entry.mod else entry.slot.get("empty", {})
		for key: String in modifiers:
			if sums.has(key) and key != "weight":
				sums[key] += float(modifiers[key])
	return sums


# --- The gun -------------------------------------------------------------------------------------

## The WeaponData `gun` fires with: a copy of its .tres changed by its parts, its weight and (with
## `skills`, GameState.skills) its holder's skills.
static func build(gun: ItemInstance, skills: Dictionary = {}) -> WeaponData:
	var base := gun.data.weapon
	var result: WeaponData = base.duplicate()
	var sums := totals(gun)
	var recoil_range := CONFIG.recoil_multiplier_range
	var spread_range := CONFIG.spread_multiplier_range
	var recovery_range := CONFIG.recovery_multiplier_range
	result.skill_recoil_reduction = skill_recoil_reduction(base, skills)
	var trained := 1.0 - result.skill_recoil_reduction
	result.vertical_recoil = base.vertical_recoil * _multiplier(sums.vertical_recoil, recoil_range) * trained
	result.horizontal_recoil = base.horizontal_recoil * _multiplier(sums.horizontal_recoil, recoil_range) * trained
	result.camera_kick = base.camera_kick * _multiplier(sums.vertical_recoil, recoil_range)
	result.recoil_recovery = base.recoil_recovery * _multiplier(sums.recoil_recovery, recovery_range)
	result.base_spread = base.base_spread * _multiplier(sums.base_spread, spread_range)
	result.bloom_per_shot = base.bloom_per_shot * _multiplier(sums.bloom_per_shot, spread_range)
	result.max_bloom = base.max_bloom * _multiplier(sums.max_bloom, spread_range)
	result.hip_spread = base.hip_spread * _multiplier(sums.hip_spread, spread_range)
	# Ergonomics: handling. Weight over the stock build: more sway, slower bloom recovery.
	var ergonomics := clampf(base.ergonomics + sums.ergonomics, 0.0, 100.0)
	result.ergonomics = roundi(ergonomics)
	var handling := 1.0 + (base.ergonomics - ergonomics) * CONFIG.handling_per_ergonomics_point
	result.weight = gun.weight_without_rounds()
	result.extra_weight = result.weight - default_weight(gun.data)
	result.bloom_recovery = base.bloom_recovery * _multiplier(sums.bloom_recovery, recovery_range) \
		/ maxf(1.0 + result.extra_weight * CONFIG.bloom_recovery_loss_per_kg, 0.5)
	result.move_spread = base.move_spread * handling
	result.sprint_spread = base.sprint_spread * handling
	result.roll_spread = base.roll_spread * handling
	result.sway = maxf(base.sway + result.extra_weight * CONFIG.sway_per_extra_kg, 0.0) * handling
	result.velocity_multiplier = clampf(1.0 + sums.velocity / 100.0, 0.5, 1.5)
	result.muzzle_velocity = roundi(base.muzzle_velocity * result.velocity_multiplier)
	result.noise_multiplier = clampf(1.0 + sums.noise / 100.0, 0.15, 2.0)
	result.aim_time_multiplier = clampf(handling / maxf(1.0 + sums.aim_speed / 100.0, 0.1), 0.3, 3.0)
	result.malfunction_multiplier = clampf(1.0 + sums.malfunction / 100.0, 0.1, 4.0)
	result.wear_multiplier = clampf(1.0 + sums.durability_loss / 100.0, 0.2, 3.0)
	result.pellet_spread_multiplier = clampf(1.0 + sums.pellet_spread / 100.0, 0.3, 2.0)
	if not WeaponMods.slot_on(gun, "magazine").is_empty():
		var magazine := WeaponMods.mod_at(gun, "magazine")
		result.magazine_size = WeaponMods.capacity_of(magazine.data) if magazine else 0
	result.missing_part = WeaponMods.missing_part(gun)
	result.optic = 0
	for mod in WeaponMods.installed(gun):
		if WeaponMods.kind_of(mod.data) == "sight":
			result.optic = maxi(result.optic, int(mod.data.stats.get("optic", 0)))
	return result


## 1 + `percent` / 100, kept inside `limits`.
static func _multiplier(percent: float, limits: Vector2) -> float:
	return clampf(1.0 + percent / 100.0, limits.x, limits.y)


## How fast `ammo` leaves `gun` (the stats it fires with, parts included), in m/s: the round's
## velocity (from a standard barrel) × the gun's barrel: its muzzle velocity over the velocity of its
## caliber's everyday round. Without a gun, the round's own velocity.
static func shot_speed(gun: WeaponData, ammo: ItemData) -> float:
	var round_speed := float(ammo.stats.get("velocity", 0.0)) if ammo else 0.0
	if gun == null:
		return round_speed if round_speed > 0.0 else 800.0
	if round_speed <= 0.0:
		return float(gun.muzzle_velocity)
	return gun.muzzle_velocity * round_speed / everyday_velocity(gun.caliber, round_speed)


## The velocity of `caliber`'s everyday round (ItemDB.ammo_of()), or `fallback`.
static func everyday_velocity(caliber: String, fallback := 800.0) -> float:
	if not _everyday_speeds.has(caliber):
		var rounds := ItemDB.ammo_of(caliber)
		_everyday_speeds[caliber] = float(rounds[0].stats.get("velocity", 0.0)) if not rounds.is_empty() else 0.0
	var speed: float = _everyday_speeds[caliber]
	return speed if speed > 0.0 else fallback


## What the gun `gun_data` weighs with its default parts (no rounds): the build weight effects are
## measured from it.
static func default_weight(gun_data: ItemData) -> float:
	if not _default_weights.has(gun_data.id):
		var stock := ItemInstance.create(gun_data.id)
		_default_weights[gun_data.id] = stock.weight_without_rounds() if stock else gun_data.weight_kg
	return _default_weights[gun_data.id]


## How much less recoil `skills` (GameState.skills) give with `gun`: its weapon skill and Strength.
static func skill_recoil_reduction(gun: WeaponData, skills: Dictionary) -> float:
	var weapon_level := int(skills.get(gun.skill, {}).get("level", 0)) if gun.skill != "" else 0
	var strength := int(skills.get("strength", {}).get("level", 0))
	return clampf(weapon_level * CONFIG.weapon_skill_recoil_per_level + strength * CONFIG.strength_recoil_per_level,
		0.0, CONFIG.max_skill_recoil_reduction)


# --- Recoil and spread (shared by the Weapon node and the previews) -------------------------------

## The kick of one shot: x sideways (degrees, + right), y climb (degrees, + up).
static func kick(gun: WeaponData, rng: RandomNumberGenerator) -> Vector2:
	var jitter := CONFIG.vertical_jitter
	return Vector2(rng.randf_range(-1.0, 1.0) * gun.horizontal_recoil, gun.vertical_recoil * (1.0 + rng.randf_range(-jitter, jitter)))


## What's left of a kick `offset` after recovering for `seconds`.
static func recover(offset: Vector2, gun: WeaponData, seconds: float) -> Vector2:
	return offset * exp(-gun.recoil_recovery * maxf(seconds, 0.0))


## Where each shot of a full-auto spray goes, relative to the aim (degrees: x sideways, y climb): the
## recoil pattern. The first shot is (0, 0). Same seed, same side kicks, so two builds compare fairly.
static func recoil_pattern(gun: WeaponData, shots: int, seed := 74) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points := PackedVector2Array()
	var offset := Vector2.ZERO
	for i in shots:
		points.append(offset)
		offset = recover(offset + kick(gun, rng), gun, gun.shot_interval() - gun.recovery_delay)
	return points


## Extra spread from wear at `durability` (none for guns that don't wear).
static func wear_spread(durability: float) -> float:
	var threshold := CONFIG.wear_spread_threshold
	if durability < 0.0 or threshold <= 0.0:
		return 0.0
	return CONFIG.wear_spread_max * clampf((threshold - durability) / threshold, 0.0, 1.0)


## Seconds for full bloom to shrink back to the base spread.
static func bloom_settle_time(gun: WeaponData) -> float:
	return gun.bloom_delay + gun.max_bloom / maxf(gun.bloom_recovery, 0.01)


# --- Display -------------------------------------------------------------------------------------

## Stat rows for the modding screen and the examine panel: [{"key", "name", "value" (a number to
## compare), "text", "better": +1 if higher is better, -1 if lower is, 0 if neither, "bar": 0-1 or -1}].
static func rows(gun: ItemInstance, skills: Dictionary = {}) -> Array[Dictionary]:
	var data := build(gun, skills)
	var aim_time := VisionSystem.config.optic_transition_time * data.aim_time_multiplier
	var noise := COMBAT_CONFIG.gunshot_noise * data.noise_multiplier
	var jam := data.malfunction_chance(gun.durability) * 100.0
	var worn := wear_spread(gun.durability)
	var result: Array[Dictionary] = [
		_row("ergonomics", "Ergonomics", data.ergonomics, str(data.ergonomics), 1, data.ergonomics / 100.0),
		_row("vertical_recoil", "Vertical recoil", data.vertical_recoil, "%.2f° / shot" % data.vertical_recoil, -1, data.vertical_recoil / 1.5),
		_row("horizontal_recoil", "Horizontal recoil", data.horizontal_recoil, "±%.2f°" % data.horizontal_recoil, -1, data.horizontal_recoil / 1.0),
		_row("recoil_recovery", "Recoil recovery", data.recoil_recovery, "%.1f / s" % data.recoil_recovery, 1, data.recoil_recovery / 15.0),
		_row("base_spread", "Base spread", data.base_spread, "%.2f°" % data.base_spread, -1, data.base_spread / 2.0),
		_row("hip_spread", "Hip-fire spread", data.hip_spread, "+%.2f°" % data.hip_spread, -1, data.hip_spread / 4.0),
		_row("bloom_per_shot", "Bloom per shot", data.bloom_per_shot, "+%.2f°" % data.bloom_per_shot, -1, data.bloom_per_shot / 1.5),
		_row("max_bloom", "Max bloom", data.max_bloom, "+%.1f°" % data.max_bloom, -1, data.max_bloom / 10.0),
		_row("bloom_recovery", "Bloom recovery", data.bloom_recovery, "%.1f° / s" % data.bloom_recovery, 1, data.bloom_recovery / 20.0),
		_row("sway", "Sway", data.sway, "%.2f°" % data.sway, -1, data.sway / 1.0),
		_row("wear_spread", "Worn spread", worn, "+%.2f°" % worn if worn > 0.0 else "None", -1, -1.0),
		_row("velocity", "Muzzle velocity", data.muzzle_velocity, "%d m/s" % data.muzzle_velocity, 1, -1.0),
		_row("aim_time", "Aim time", aim_time, "%.2f s" % aim_time, -1, -1.0),
		_row("noise", "Shot heard at", noise, "%d m" % roundi(noise), -1, clampf(noise / 120.0, 0.0, 1.0)),
		_row("magazine", "Magazine", data.magazine_size, "%d rounds" % data.magazine_size if data.magazine_size > 0 else "None", 1, -1.0),
		_row("fire_rate", "Fire rate", data.fire_rate, "%d rpm  ·  %s" % [data.fire_rate, "auto" if data.automatic else "semi"], 0, -1.0),
		_row("weight", "Weight", data.weight, weight_text(data.weight), -1, -1.0),
		_row("durability", "Durability", gun.durability, "%.1f / %.1f" % [gun.durability, gun.max_durability], 1,
			gun.durability / 100.0),
		_row("malfunction", "Jam chance", jam, "%.2f%% per shot" % jam if jam > 0.0 else "None at this durability", -1, -1.0),
	]
	if data.weapon_class == "shotgun":
		var pellets := data.pellet_spread_multiplier * 100.0
		result.insert(result.size() - 3, _row("pellet_spread", "Pellet spread", pellets, "%d%% of the shell's" % roundi(pellets), -1, -1.0))
	for row in result:
		if row.bar >= 0.0:
			row.bar = clampf(row.bar, 0.0, 1.0)
	return result


static func _row(key: String, label: String, value: float, text: String, better: int, bar: float) -> Dictionary:
	return {"key": key, "name": label, "value": value, "text": text, "better": better, "bar": bar}


## One line per effect of part `mod_data` for tooltips and the examine panel: [["Vertical recoil",
## "−4.8%", good?]].
static func modifier_lines(mod_data: ItemData) -> Array:
	var lines := []
	var modifiers := modifiers_of(mod_data)
	for key: String in HANDLING + SPECIAL:
		if not modifiers.has(key) or absf(modifiers[key]) < 0.05:
			continue
		var value: float = modifiers[key]
		lines.append([MODIFIER_NAMES[key], format_modifier(key, value), value * BETTER[key] > 0.0])
	return lines


## A modifier as shown: "+3" for ergonomics, "−4.8%" or "−12%" for the rest (with a real minus sign).
static func format_modifier(key: String, value: float) -> String:
	var text := ""
	if key == "ergonomics":
		text = "%+.1f" % value if absf(value - roundf(value)) > 0.05 and absf(value) < 10.0 else "%+d" % roundi(value)
	elif absf(value - roundf(value)) > 0.05 and absf(value) < 10.0:
		text = "%+.1f%%" % value
	else:
		text = "%+d%%" % roundi(value)
	return text.replace("-", "−")


## How a stat row (rows()) changed, e.g. "+6" or "−0.05°"; "" if it rounds to nothing.
static func format_delta(key: String, delta: float) -> String:
	var text := ""
	match key:
		"vertical_recoil", "horizontal_recoil", "base_spread", "hip_spread", "bloom_per_shot", "sway", "wear_spread":
			text = "%+.2f°" % delta
		"max_bloom":
			text = "%+.1f°" % delta
		"bloom_recovery":
			text = "%+.1f°/s" % delta
		"recoil_recovery":
			text = "%+.1f/s" % delta
		"aim_time":
			text = "%+.2f s" % delta
		"malfunction":
			text = "%+.2f%%" % delta
		"pellet_spread":
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
		return ""
	return text.replace("-", "−")


## A weight to two decimals (parts are light), in the units chosen in Settings.
static func weight_text(kg: float) -> String:
	if Settings.get_value("gameplay", "units") == "imperial":
		return "%.2f lb" % (kg * 2.20462)
	return "%.2f kg" % kg


# --- Durability --------------------------------------------------------------------------------

## Roubles to repair `gun` back to its max durability.
static func repair_price(gun: ItemInstance) -> int:
	return ceili((gun.max_durability - gun.durability) * gun.data.base_value * CONFIG.repair_price_share)


## What `gun`'s max durability would drop to with a repair now.
static func max_after_repair(gun: ItemInstance) -> float:
	return maxf(gun.max_durability - (gun.max_durability - gun.durability) * CONFIG.repair_wear, 1.0)


## Restores `gun` to its max durability, which drops by the repair wear per point restored.
static func repair(gun: ItemInstance) -> void:
	gun.max_durability = max_after_repair(gun)
	gun.durability = gun.max_durability
