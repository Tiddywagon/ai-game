class_name CombatConfig
extends Resource
## Tuning for the combat roll, cover and bullets (DESIGN.md §13). The values live in
## data/config/combat.tres: edit it in Godot's Inspector or in any text editor.

@export_group("Combat roll")
@export_range(0.5, 10.0, 0.1, "suffix:m") var roll_distance: float
@export_range(0.1, 2.0, 0.05, "suffix:s") var roll_duration: float
## You can't roll with less stamina than this.
@export_range(0.0, 100.0, 1.0) var roll_stamina_cost: float
## Time after a roll ends before the next one.
@export_range(0.0, 10.0, 0.05, "suffix:s") var roll_cooldown: float
## From the start of a roll, how long the hitbox stays reduced.
@export_range(0.0, 2.0, 0.05, "suffix:s") var roll_evade_time: float
## Hitbox size during that window. A standing hitbox is 1.8 m tall with a 0.35 m radius.
@export_range(0.5, 1.8, 0.05, "suffix:m") var roll_evade_height: float
@export_range(0.1, 0.35, 0.01, "suffix:m") var roll_evade_radius: float
## How far away AI can hear a roll.
@export_range(0.0, 100.0, 1.0, "suffix:m") var roll_noise: float

@export_group("Cover")
## Q looks for cover within this distance.
@export_range(0.0, 5.0, 0.1, "suffix:m") var cover_snap_distance: float
## A roll toward cover that ends this close to it snaps into cover.
@export_range(0.0, 5.0, 0.1, "suffix:m") var roll_snap_distance: float
## Cover up to this height is low cover (crouch behind it, peek over). Taller cover: lean, peek around.
@export_range(0.5, 2.0, 0.05, "suffix:m") var low_cover_max_height: float
## Body height while ducked behind low cover.
@export_range(0.7, 1.2, 0.05, "suffix:m") var duck_height: float
## At tall cover you can lean out if one of its ends is within this distance.
@export_range(0.0, 5.0, 0.1, "suffix:m") var peek_edge_reach: float
## Speed when sliding along cover.
@export_range(0.1, 5.0, 0.1, "suffix:m/s") var cover_move_speed: float

@export_group("Bullets")
## Ammo needs at least this penetration to go through wood. Concrete and metal stop every round.
@export_range(0.0, 100.0, 1.0) var wood_min_penetration: float
## Share of damage a round keeps after going through wood.
@export_range(0.0, 1.0, 0.05) var wood_damage_kept: float
## Penetration a round loses going through wood.
@export_range(0.0, 100.0, 1.0) var wood_penetration_loss: float
## How far away AI can hear an unsuppressed shot.
@export_range(0.0, 200.0, 1.0, "suffix:m") var gunshot_noise: float
