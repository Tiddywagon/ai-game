class_name HealthConfig
extends Resource
## Tuning for body-part health and status effects (DESIGN.md §13.5). The values live in
## data/config/health.tres: edit it in Godot's Inspector or in any text editor.

@export_group("Body part HP")
@export_range(1.0, 500.0, 1.0) var head_hp: float
@export_range(1.0, 500.0, 1.0) var thorax_hp: float
@export_range(1.0, 500.0, 1.0) var stomach_hp: float
## Each arm.
@export_range(1.0, 500.0, 1.0) var arm_hp: float
## Each leg.
@export_range(1.0, 500.0, 1.0) var leg_hp: float

@export_group("Blacked parts")
## Damage to a blacked part (and damage beyond a part's HP) is multiplied by this, then shared
## evenly by every part that still has HP, head and thorax included.
@export_range(0.0, 3.0, 0.05) var stomach_spread: float
@export_range(0.0, 3.0, 0.05) var arm_spread: float
@export_range(0.0, 3.0, 0.05) var leg_spread: float

@export_group("Hit zones")
## Where on the hitbox a bullet lands decides the part, as a share of the hitbox height from the feet.
@export_range(0.0, 1.0, 0.01) var head_from: float
@export_range(0.0, 1.0, 0.01) var thorax_from: float
## Below this is legs.
@export_range(0.0, 1.0, 0.01) var stomach_from: float
## In the head band, rounds further than this to the side of the centre line pass over the shoulder
## (the capsule hitbox is much wider than a head).
@export_range(0.0, 0.5, 0.01, "suffix:m") var head_half_width: float
## In the torso band, hits further than this to the side of the body's centre line hit an arm.
@export_range(0.0, 0.5, 0.01, "suffix:m") var arm_offset: float

@export_group("Status effects")
## Chances per hit at reference_damage; scaled by damage / reference_damage (up to 1.5×).
@export_range(1.0, 200.0, 1.0) var reference_damage: float
@export_range(0.0, 1.0, 0.01) var light_bleed_chance: float
@export_range(0.0, 1.0, 0.01) var heavy_bleed_chance: float
## Arms and legs only.
@export_range(0.0, 1.0, 0.01) var fracture_chance: float
## HP lost per second from the bleeding part.
@export_range(0.0, 10.0, 0.05, "suffix:HP/s") var light_bleed_rate: float
@export_range(0.0, 10.0, 0.05, "suffix:HP/s") var heavy_bleed_rate: float
## Movement speed with a fractured or blacked leg (no sprinting or rolling either).
@export_range(0.1, 1.0, 0.05) var injured_leg_speed: float
## Weapon sway per fractured or blacked arm, and while in pain.
@export_range(0.0, 15.0, 0.1, "suffix:°") var arm_sway: float
@export_range(0.0, 15.0, 0.1, "suffix:°") var pain_sway: float


## Max HP of `part` (a BodyHealth.Part).
func max_hp(part: int) -> float:
	return [head_hp, thorax_hp, stomach_hp, arm_hp, arm_hp, leg_hp, leg_hp][part]


func max_total() -> float:
	return head_hp + thorax_hp + stomach_hp + 2.0 * arm_hp + 2.0 * leg_hp
