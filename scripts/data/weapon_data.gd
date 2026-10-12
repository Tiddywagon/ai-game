class_name WeaponData
extends Resource
## How one gun handles (DESIGN.md §12.1, §13.4). One .tres per gun in data/weapons/, which the gun's
## ItemData points to. Every gun runs the same Weapon script (scripts/combat/weapon.gd), so a new gun
## only needs a new file. Damage and penetration come from the ammo, never from the gun (DESIGN.md §6.3).
## The values here are the gun with its default parts; mods change them (WeaponStats makes a modded
## copy for the gun in hand).

## Ammo with the same `caliber` stat fits, e.g. "5.45x39".
@export var caliber := ""
## The weapon skill that trains with it and lowers its recoil (GameState.SKILLS), e.g. "assault_rifles".
@export var skill := ""
## What kind of gun it is (CLASS_NAMES). Bolt-action rifles and DMRs can make 360 trick shots (see
## "Trick shot").
@export_enum("assault_rifle", "pistol", "bolt_action", "dmr", "smg", "shotgun", "lmg") var weapon_class := "assault_rifle"

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

@export_group("Recoil")
## Muzzle climb per shot, in degrees: the aim kicks out along the aim direction and rounds fly higher,
## so long bursts at range go over the target.
@export_range(0.0, 5.0, 0.01, "suffix:°") var vertical_recoil := 0.55
## The most side kick per shot, in degrees, left or right at random.
@export_range(0.0, 5.0, 0.01, "suffix:°") var horizontal_recoil := 0.35
## How fast the kick pulls back to where you aim once it starts recovering: the share of what's left
## that comes back per second (exponential; 7 brings it most of the way back in about 0.3 s).
@export_range(0.0, 40.0, 0.1, "suffix:/s") var recoil_recovery := 7.0
## Pause after each shot before the kick starts to recover, so full-auto keeps building it.
@export_range(0.0, 1.0, 0.01, "suffix:s") var recovery_delay := 0.06
## Camera shake per shot when the player fires (0-1, scaled by Settings), scaled with vertical recoil.
@export_range(0.0, 1.0, 0.01) var camera_kick := 0.12

@export_group("Spread and bloom")
## Spread of a single aimed shot standing still, once bloom has settled.
@export_range(0.0, 10.0, 0.05, "suffix:°") var base_spread := 0.5
## Bloom: spread added by every shot, up to `max_bloom`.
@export_range(0.0, 5.0, 0.01, "suffix:°") var bloom_per_shot := 0.35
@export_range(0.0, 20.0, 0.1, "suffix:°") var max_bloom := 4.5
## How fast bloom shrinks back when you stop shooting (and from moving, once you stop).
@export_range(0.1, 60.0, 0.1, "suffix:°/s") var bloom_recovery := 9.0
## Pause after each shot before bloom from shooting starts to shrink: longer than the time between
## shots, so a held trigger keeps building it.
@export_range(0.0, 2.0, 0.01, "suffix:s") var bloom_delay := 0.2
## Extra spread hip-firing, gone once the sight is up (aim time decides how fast).
@export_range(0.0, 10.0, 0.05, "suffix:°") var hip_spread := 1.8
## Extra spread while moving at sprint speed; slower movement adds proportionally less.
@export_range(0.0, 15.0, 0.1, "suffix:°") var move_spread := 3.0
## Extra on top of that while sprinting, and while rolling.
@export_range(0.0, 15.0, 0.1, "suffix:°") var sprint_spread := 2.0
@export_range(0.0, 20.0, 0.1, "suffix:°") var roll_spread := 6.0
## How far the aim drifts side to side with the default parts, in degrees. Heavier builds sway more.
@export_range(0.0, 5.0, 0.01, "suffix:°") var sway := 0.2

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

@export_group("Trick shot")
## 360 trick shots (DESIGN.md §13.4), bolt-action rifles and DMRs only: spin the aim a full turn one
## way within `trick_spin_time` seconds and a TRICK SHOT READY window opens for `trick_window`
## seconds. The first shot fired in it deals `trick_damage_bonus` more damage (0.5: +50%), applied to
## the round before armor.
@export_range(0.3, 5.0, 0.05, "suffix:s") var trick_spin_time := 1.5
@export_range(0.1, 5.0, 0.05, "suffix:s") var trick_window := 1.0
@export_range(0.0, 3.0, 0.05) var trick_damage_bonus := 0.5

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
## Multiplier on how wide a shotgun's pellets spread (chokes, barrels).
@export var pellet_spread_multiplier := 1.0
## The build's weight (kg, without rounds), and how much more than the gun with its default parts.
@export var weight := 0.0
@export var extra_weight := 0.0
## How much less recoil the holder's skills give (0.03: 3% less).
@export var skill_recoil_reduction := 0.0


## Gun classes that can make 360 trick shots.
const TRICK_SHOT_CLASSES: Array[String] = ["bolt_action", "dmr"]
## Each class's name, for the examine panel and the weapon tables.
const CLASS_NAMES := {"pistol": "Pistol", "smg": "Submachine gun", "shotgun": "Shotgun", "assault_rifle": "Assault rifle",
	"dmr": "Marksman rifle", "bolt_action": "Bolt-action rifle", "lmg": "Light machine gun"}


## True if this gun can make 360 trick shots (a bolt-action rifle or DMR with a damage bonus).
func allows_trick_shots() -> bool:
	return weapon_class in TRICK_SHOT_CLASSES and trick_damage_bonus > 0.0


## The name of this gun's class, e.g. "Submachine gun".
func class_title() -> String:
	return CLASS_NAMES.get(weapon_class, weapon_class.capitalize())


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
