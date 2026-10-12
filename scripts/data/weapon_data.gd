class_name WeaponData
extends Resource
## How one gun handles (DESIGN.md §12.1, §13.4). One .tres per gun in data/weapons/, which the gun's
## ItemData points to. Every gun runs the same Weapon script (scripts/combat/weapon.gd), so a new gun
## only needs a new file. Damage and penetration come from the ammo, never from the gun (DESIGN.md §6.3).
## The values here are the gun with its default parts; mods change them (WeaponStats makes a modded
## copy for the gun in hand).

## Ammo with the same `caliber` stat fits, e.g. "5.45x39".
@export var caliber := ""

@export_group("Firing")
## Rounds per minute.
@export_range(30, 1200, 10, "suffix:rpm") var fire_rate := 600
## Keeps firing while the trigger is held. Otherwise one shot per click.
@export var automatic := true
@export_range(1, 100) var magazine_size := 30
## Seconds to reload with rounds still in the magazine.
@export_range(0.2, 10.0, 0.05, "suffix:s") var reload_time := 2.2
## Seconds to reload an empty magazine: slower, because a round has to be chambered too.
@export_range(0.2, 10.0, 0.05, "suffix:s") var empty_reload_time := 2.8

@export_group("Accuracy")
## Spread of a single shot fired standing still, after recoil has settled.
@export_range(0.0, 10.0, 0.05, "suffix:°") var base_spread := 0.5
## Extra spread while moving at sprint speed; slower movement adds proportionally less.
@export_range(0.0, 15.0, 0.1, "suffix:°") var move_spread := 3.0

@export_group("Recoil")
## Spread added by every shot.
@export_range(0.0, 5.0, 0.05, "suffix:°") var recoil_per_shot := 0.5
## The most spread recoil can add.
@export_range(0.0, 20.0, 0.1, "suffix:°") var max_recoil := 5.0
## How fast recoil spread wears off once you stop firing.
@export_range(0.0, 60.0, 0.5, "suffix:°/s") var recoil_recovery := 10.0
## Pause after each shot before recoil starts wearing off, so full-auto keeps building it.
@export_range(0.0, 1.0, 0.01, "suffix:s") var recovery_delay := 0.15
## Camera shake per shot when the player fires (0-1, scaled by Settings).
@export_range(0.0, 1.0, 0.01) var camera_kick := 0.12


@export_group("Modding")
## Which mods fit: a mod's "fits" list names platforms, e.g. "ak".
@export var platform := ""
## Handling with the default parts, 0-100. Mods add or take away; higher aims faster and moves steadier.
@export_range(0, 100) var ergonomics := 50
## m/s with the default barrel. Faster rounds reach farther and keep more energy through wood.
@export_range(50, 1500, 5, "suffix:m/s") var muzzle_velocity := 880
## Mod slots: [{"id", "name", "kinds": [mod kinds that fit], "empty": {modifiers while it's empty},
## "required": true if the gun can't fire without it}].
## Mod kinds: muzzle, barrel, handguard, foregrip, stock, pistol_grip, receiver, sight, tactical,
## magazine. A magazine mod sets the magazine size; with a magazine slot left empty the gun can't fire.
@export var slots: Array[Dictionary] = []
## The parts a new gun comes with, slot path ("handguard" or "handguard/foregrip") -> mod item id.
@export var default_mods: Dictionary = {}

@export_group("Durability")
## Durability lost per shot (out of 100), before mods.
@export_range(0.0, 1.0, 0.005) var durability_per_shot := 0.03
## Below this durability the gun starts to jam; the chance grows the lower it gets.
@export_range(0.0, 100.0, 1.0) var malfunction_threshold := 85.0
## Chance per shot of a jam at 0 durability (before mods), 0-1.
@export_range(0.0, 1.0, 0.005) var max_malfunction_chance := 0.06
## Seconds to clear a jam (R).
@export_range(0.1, 10.0, 0.05, "suffix:s") var clear_time := 1.6

@export_group("Set by mods")
## These stay at their defaults in the .tres files: WeaponStats.build() sets them on the copy it makes
## for a modded gun.
## The name of a part the gun can't fire without that's missing (a barrel, a magazine), or "".
@export var missing_part := ""
## The sight on the gun (VisionConfig.Optic), -1 if the stats didn't come from mods.
@export var optic := -1
## Multipliers against the gun with its default parts: noise of each shot, time to raise a sight,
## muzzle velocity, chance of a jam per shot and durability lost per shot.
@export var noise_multiplier := 1.0
@export var aim_time_multiplier := 1.0
@export var velocity_multiplier := 1.0
@export var malfunction_multiplier := 1.0
@export var wear_multiplier := 1.0


## Seconds between shots.
func shot_interval() -> float:
	return 60.0 / float(fire_rate)


## Chance per shot of a jam at `durability` (0-100; below 0 means the gun doesn't wear, e.g. AI guns).
func malfunction_chance(durability: float) -> float:
	if durability < 0.0 or malfunction_threshold <= 0.0:
		return 0.0
	var wear := clampf((malfunction_threshold - durability) / malfunction_threshold, 0.0, 1.0)
	return clampf(max_malfunction_chance * wear * wear * malfunction_multiplier, 0.0, 1.0)


## Durability lost per shot, after mods.
func wear_per_shot() -> float:
	return durability_per_shot * wear_multiplier
