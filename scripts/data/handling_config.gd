class_name HandlingConfig
extends Resource
## Tuning for how guns handle (DESIGN.md §12.1, §13.4): how strong attachments are by rarity, what
## ergonomics, weight, wear and skills do, and how bloom grows. The values live in
## data/config/handling.tres; each gun's own numbers are its WeaponData in data/weapons/, each
## attachment kind's default effects are in data/config/attachment_profiles.json, and each part's own
## in its item file.

@export_group("Attachment strength")
## How strong an attachment's bonuses are, by rarity (Common, Uncommon, Rare, Ultra Rare, Epic,
## Legendary), in percent: a profile value of 1 improves that stat by this much (Common about 4%,
## Legendary about 23%). Downsides are fixed and don't grow with rarity.
@export var rarity_bonus_percent: Array[float] = [4.0, 8.0, 12.0, 16.0, 20.0, 23.0]
## Ergonomics is in points: a profile value of 1 adds this many points per percent of strength
## (a Rare part with ergonomics 1: 12 × 0.25 = 3 points).
@export_range(0.0, 2.0, 0.01) var ergonomics_points_per_percent := 0.25
## The part-specific modifiers (noise, muzzle velocity, aim speed, jam chance, wear): bonuses × this
## by rarity.
@export var special_rarity_scale: Array[float] = [1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
## Default effects of each attachment kind (the profile table).
@export_file("*.json") var profiles_path := "res://data/config/attachment_profiles.json"

@export_group("Ergonomics and weight")
## Each point of ergonomics below the gun's default makes moving spread, sway and aim time 1% worse
## (each point above, 1% better).
@export_range(0.0, 0.05, 0.001) var handling_per_ergonomics_point := 0.01
## Degrees of sway added per kg the build weighs over the gun with its default parts (lighter builds
## sway less).
@export_range(0.0, 2.0, 0.01, "suffix:°/kg") var sway_per_extra_kg := 0.35
## Bloom recovers this much slower per kg over the default build (0.15: 15% slower per kg).
@export_range(0.0, 1.0, 0.01) var bloom_recovery_loss_per_kg := 0.15
## Sway while the sight is up, as a share of hip sway.
@export_range(0.0, 1.0, 0.05) var aimed_sway_multiplier := 0.6

@export_group("Bloom")
## How fast bloom from moving, sprinting, rolling and hip-firing grows (degrees per second). It
## shrinks at the gun's bloom recovery.
@export_range(1.0, 200.0, 1.0, "suffix:°/s") var stance_bloom_rise := 25.0
## Below this durability a worn gun adds spread, growing to `wear_spread_max` at 0.
@export_range(0.0, 100.0, 1.0) var wear_spread_threshold := 70.0
@export_range(0.0, 5.0, 0.05, "suffix:°") var wear_spread_max := 1.5

@export_group("Recoil")
## How much the climb of each shot varies, ± this share of the gun's vertical recoil.
@export_range(0.0, 1.0, 0.01) var vertical_jitter := 0.15
## Shots in the modding screen's recoil pattern preview (or a magazine, if smaller).
@export_range(5, 100) var pattern_shots := 30

@export_group("Skills")
## Recoil (vertical and horizontal) drops this much per level of the gun's weapon skill (assault
## rifles, pistols) and per level of Strength, up to `max_skill_recoil_reduction` together.
@export_range(0.0, 0.05, 0.0005) var weapon_skill_recoil_per_level := 0.005
@export_range(0.0, 0.05, 0.0005) var strength_recoil_per_level := 0.0025
@export_range(0.0, 0.5, 0.01) var max_skill_recoil_reduction := 0.15

@export_group("Limits")
## How far parts can push each kind of stat, as multipliers on the gun's own value.
@export var recoil_multiplier_range := Vector2(0.3, 2.5)
@export var spread_multiplier_range := Vector2(0.3, 3.0)
@export var recovery_multiplier_range := Vector2(0.3, 3.0)

@export_group("Repair")
## Max durability lost per point a repair restores.
@export_range(0.0, 1.0, 0.01) var repair_wear := 0.15
## Price per point restored, as a share of the gun's base value.
@export_range(0.0, 0.05, 0.0005) var repair_price_share := 0.004
