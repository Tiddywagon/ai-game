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

@export_group("Rounds and armor")
## A round's velocity this fast (m/s) or faster reaches the full range (Ballistics.MAX_RANGE) and keeps
## full energy through wood; slower rounds reach proportionally less far (pistols, subsonic).
@export_range(100.0, 1500.0, 10.0, "suffix:m/s") var reference_velocity: float
## The shortest range, as a share of the full range, however slow the round.
@export_range(0.1, 1.0, 0.05) var min_range_factor: float
## Rounds do full damage up to this share of their range, then lose damage in a straight line...
@export_range(0.0, 1.0, 0.05) var falloff_start: float
## ...down to this share of it at the end of their range.
@export_range(0.0, 1.0, 0.05) var range_damage_kept: float
## Armor resistance per class: a class 4 vest resists penetration 40.
@export_range(1.0, 30.0, 0.5) var armor_resistance_per_class: float
## Penetration this far above the armor's resistance always goes through, this far below never;
## halfway, half the time.
@export_range(1.0, 50.0, 0.5) var penetration_window: float
## A worn-out armor piece resists this share of its class (scaled up to full at full durability).
## At 0 durability it stops nothing.
@export_range(0.0, 1.0, 0.05) var armor_min_effectiveness: float
## Share of a round's damage that reaches the body after it goes through armor.
@export_range(0.0, 1.0, 0.05) var penetrated_damage_kept: float
## Blunt damage of a stopped round = damage × the armor's blunt × (penetration / resistance), at least
## this share: a round far below the armor's class pushes little through.
@export_range(0.0, 1.0, 0.05) var blunt_min_push: float
## Armor wear from a round that glances off (ricochets), as a share of a normal hit's.
@export_range(0.0, 1.0, 0.05) var ricochet_wear: float
## A round that fragments in flesh deals this much more damage (0.4: +40%), always starts a light bleed
## and multiplies its heavy-bleed chance by `fragmentation_heavy_bleed`.
@export_range(0.0, 2.0, 0.05) var fragmentation_damage_bonus: float
@export_range(1.0, 5.0, 0.1) var fragmentation_heavy_bleed: float
## Tracer rounds: how long their bright tracer shows, and how close they pass to warn someone (normal
## rounds: Ballistics.NEAR_MISS_DISTANCE): tracers give the shooter away.
@export_range(0.0, 2.0, 0.01, "suffix:s") var tracer_time: float
@export_range(0.0, 20.0, 0.5, "suffix:m") var tracer_warn_distance: float
