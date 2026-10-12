class_name ArmorRules
extends RefCounted
## What armor does to a round (DESIGN.md §6.4, §13.5). A helmet, body armor or armored rig stops rounds
## on the body parts it covers (its "zones"). Whether a round gets through depends on its penetration
## against the armor's class, scaled down as the armor wears; a round that gets through keeps most of
## its damage, one that doesn't may glance off (its ricochet chance × the armor's) or push blunt damage
## through. Every hit wears the armor (penetration × the round's armor damage × the armor's
## destructibility). Rounds that reach flesh may fragment: more damage and a bleed. Tuning is in
## data/config/combat.tres ("Rounds and armor"), each round's stats in data/items/ammo/, each armor's in
## data/items/armor/ and data/items/helmets/.

const CONFIG: CombatConfig = preload("res://data/config/combat.tres")
## Equipment slots that can stop rounds, outermost first.
const SLOTS: Array[String] = ["helmet", "armor", "rig"]


## What a round brings to a hit, for take_hit(): its armor-relevant stats, with `penetration` as it
## is now (wood takes some off).
static func shot(ammo: ItemData, penetration: float) -> Dictionary:
	var stats := ammo.stats
	return {"ammo": ammo, "penetration": penetration, "armor_damage": float(stats.get("armor_damage", 0.0)),
		"fragmentation": float(stats.get("fragmentation", 0.0)), "ricochet": float(stats.get("ricochet", 0.0)),
		"light_bleed": float(stats.get("light_bleed", -1.0)), "heavy_bleed": float(stats.get("heavy_bleed", -1.0))}


## The name armor "zones" use for body part `part` (a BodyHealth.Part): "head", "thorax", ...
static func zone_name(part: int) -> String:
	return BodyHealth.Part.keys()[part].to_lower()


## The piece of armor `gear` wears over `part` that isn't worn out, or null.
static func armor_for(gear: Inventory, part: int) -> ItemInstance:
	if gear == null or part < 0:
		return null
	var zone := zone_name(part)
	for slot in SLOTS:
		var piece: ItemInstance = gear.equipment.get(slot)
		if piece and piece.data.stats.has("class") and zone in piece.data.stats.get("zones", []) and piece.durability > 0.0:
			return piece
	return null


## How much penetration armor of `armor_class` stops at `durability_ratio` (0-1 of its max).
static func resistance(armor_class: int, durability_ratio := 1.0) -> float:
	if durability_ratio <= 0.0:
		return 0.0
	return armor_class * CONFIG.armor_resistance_per_class * lerpf(CONFIG.armor_min_effectiveness, 1.0, clampf(durability_ratio, 0.0, 1.0))


## Chance (0-1) that a round with `penetration` goes through armor of `armor_class` at `durability_ratio`.
static func penetration_chance(penetration: float, armor_class: int, durability_ratio := 1.0) -> float:
	var resist := resistance(armor_class, durability_ratio)
	if resist <= 0.0:
		return 1.0
	return clampf(0.5 + (penetration - resist) / (2.0 * CONFIG.penetration_window), 0.0, 1.0)


## A round's chance against fresh armor of `armor_class` (1-6), for the ammo charts.
static func effectiveness(ammo: ItemData, armor_class: int) -> float:
	return penetration_chance(float(ammo.stats.get("penetration", 0)), armor_class)


## A round (`shot`, from shot()) dealing `damage` hits body part `part` of someone wearing `gear`.
## Rolls penetration, ricochet and fragmentation, wears the armor piece and returns what happened:
## {"damage": what reaches the body (blunt if stopped, 0 if it glanced off), "armor": the piece hit or
## null, "penetrated" (true without armor too), "ricochet", "blunt", "fragmented", "light_bleed" and
## "heavy_bleed" (chances for this hit, -1 = the default), "armor_loss": durability taken off}.
static func resolve(damage: float, shot_info: Dictionary, gear: Inventory, part: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var result := {"damage": damage, "armor": null, "penetrated": true, "ricochet": false, "blunt": false,
		"fragmented": false, "light_bleed": float(shot_info.get("light_bleed", -1.0)),
		"heavy_bleed": float(shot_info.get("heavy_bleed", -1.0)), "armor_loss": 0.0}
	var piece := armor_for(gear, part)
	if piece:
		var stats := piece.data.stats
		var ratio := piece.durability / maxf(piece.max_durability, 1.0)
		var penetration := float(shot_info.get("penetration", 0.0))
		var resist := resistance(int(stats["class"]), ratio)
		var wear := penetration * float(shot_info.get("armor_damage", 0.0)) / 100.0 * float(stats.get("destructibility", 0.5))
		result.armor = piece
		if _roll(rng) < penetration_chance(penetration, int(stats["class"]), ratio):
			result.damage = damage * CONFIG.penetrated_damage_kept
		else:
			result.penetrated = false
			result.light_bleed = 0.0
			result.heavy_bleed = 0.0
			if _roll(rng) < float(shot_info.get("ricochet", 0.0)) * float(stats.get("ricochet", 0.0)):
				result.ricochet = true
				result.damage = 0.0
				wear *= CONFIG.ricochet_wear
			else:
				result.blunt = true
				var push := clampf(penetration / maxf(resist, 1.0), CONFIG.blunt_min_push, 1.0)
				result.damage = damage * float(stats.get("blunt", 0.3)) * push
		result.armor_loss = minf(wear, piece.durability)
		piece.durability = maxf(piece.durability - wear, 0.0)
	if result.penetrated and _roll(rng) < float(shot_info.get("fragmentation", 0.0)):
		result.fragmented = true
		result.damage *= 1.0 + CONFIG.fragmentation_damage_bonus
		result.light_bleed = 1.0
		if result.heavy_bleed >= 0.0:
			result.heavy_bleed = minf(result.heavy_bleed * CONFIG.fragmentation_heavy_bleed, 1.0)
	return result


static func _roll(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng else randf()
