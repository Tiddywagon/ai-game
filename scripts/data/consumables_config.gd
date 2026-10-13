class_name ConsumablesConfig
extends Resource
## Tuning for energy, hydration and using items (DESIGN.md §13.7). The values live in
## data/config/consumables.tres: edit it in Godot's Inspector or in any text editor. What each med,
## stim, food and drink does is in its own item data (data/items/meds/, data/items/food/); hot maps
## set their own drain multipliers (MapInfo).

@export_group("Energy and hydration")
@export_range(10.0, 500.0, 1.0) var max_energy: float
@export_range(10.0, 500.0, 1.0) var max_hydration: float
## Lost per minute in a raid while walking (the other activities multiply it).
@export_range(0.0, 20.0, 0.05, "suffix:/min") var energy_drain: float
@export_range(0.0, 20.0, 0.05, "suffix:/min") var hydration_drain: float

@export_group("Drain multipliers")
## Standing (or crouching) still, moving crouched, sprinting, rolling. Walking is 1.
@export_range(0.0, 2.0, 0.05) var still_drain: float
@export_range(0.0, 2.0, 0.05) var crouch_drain: float
@export_range(1.0, 5.0, 0.05) var sprint_drain: float
@export_range(1.0, 10.0, 0.05) var roll_drain: float
## Carrying enough to slow down, and overweight (DESIGN.md §7).
@export_range(1.0, 3.0, 0.05) var encumbered_drain: float
@export_range(1.0, 3.0, 0.05) var overweight_drain: float
## Bleeding, a fracture or a blacked part.
@export_range(1.0, 3.0, 0.05) var injured_drain: float
## Each Metabolism skill level drains this share less (DESIGN.md §12.3), up to max_skill_reduction.
@export_range(0.0, 0.05, 0.001) var drain_reduction_per_level: float
@export_range(0.0, 0.9, 0.05) var max_skill_reduction: float

@export_group("Low and empty")
## At or below this you're hungry or thirsty: the HUD warns you and stamina recovers slower.
@export_range(0.0, 100.0, 1.0) var low_threshold: float
## Stamina recovery × this for each of the two that's low.
@export_range(0.1, 1.0, 0.05) var low_stamina_regen: float
## At 0 energy (Exhaustion) or 0 hydration (Dehydration): HP lost per second from every body part
## that still has HP, extra weapon sway, and the vision cone × this (and the screen blurs).
@export_range(0.0, 1.0, 0.005, "suffix:HP/s") var exhaustion_damage: float
@export_range(0.0, 1.0, 0.005, "suffix:HP/s") var dehydration_damage: float
@export_range(0.0, 10.0, 0.1, "suffix:°") var exhaustion_sway: float
@export_range(0.0, 10.0, 0.1, "suffix:°") var dehydration_sway: float
@export_range(0.3, 1.0, 0.05) var depleted_vision: float

@export_group("Between raids")
## Out of raid, both refill by this much per real minute in the hideout, × (1 + level × the bonus)
## for the Nutrition Unit and the Rest Space.
@export_range(0.0, 20.0, 0.05, "suffix:/min") var hideout_recovery: float
@export_range(0.0, 2.0, 0.05) var nutrition_unit_bonus: float
@export_range(0.0, 2.0, 0.05) var rest_space_bonus: float
## A PMC who dies comes back with at least this much of each.
@export_range(0.0, 100.0, 1.0) var after_death_minimum: float
## Metabolism skill points per point of energy or hydration a food or drink gives (or takes).
@export_range(0.0, 5.0, 0.05) var metabolism_points_per_unit: float

@export_group("Using items")
## Walking speed while using an item (an item's "move" stat overrides it, e.g. surgery).
@export_range(0.0, 1.0, 0.05) var use_move_multiplier: float
## Taking a hit that does damage interrupts what you're using.
@export var hits_interrupt := true
## Quick treatment (use_item, E) looks for meds here: pockets, rig and secure container. The backpack
## needs the inventory open.
@export var quick_use_backpack := false
## Quick treatment eats or drinks when energy or hydration is at or below this share of its max and
## nothing needs treating.
@export_range(0.0, 1.0, 0.05) var quick_eat_below: float
