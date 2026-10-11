class_name WeaponData
extends Resource
## How one gun handles (DESIGN.md §13.4). One .tres per gun in data/weapons/, which the gun's ItemData
## points to. Every gun runs the same Weapon script (scripts/combat/weapon.gd), so a new gun only needs
## a new file. Damage and penetration come from the ammo, never from the gun (DESIGN.md §6.3).

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


## Seconds between shots.
func shot_interval() -> float:
	return 60.0 / float(fire_rate)
