class_name ConsumablesConfig
extends Resource
## Tuning for energy, hydration and using items (DESIGN.md §13.7). The values live in
## data/config/consumables.tres: edit it in Godot's Inspector or in any text editor. What each med,
## stim, food and drink does is in its own item data (data/items/meds/, data/items/food/).

@export_group("Energy and hydration")
@export_range(10.0, 500.0, 1.0) var max_energy: float
@export_range(10.0, 500.0, 1.0) var max_hydration: float
## Lost per minute in a raid.
@export_range(0.0, 20.0, 0.05, "suffix:/min") var energy_drain: float
@export_range(0.0, 20.0, 0.05, "suffix:/min") var hydration_drain: float
## Drain is multiplied by this while sprinting.
@export_range(1.0, 5.0, 0.05) var sprint_drain_multiplier: float
## Each Metabolism skill level drains this share less (DESIGN.md §12.3).
@export_range(0.0, 0.05, 0.001) var drain_reduction_per_level: float
## At or below this (either one), you're hungry or thirsty.
@export_range(0.0, 100.0, 1.0) var low_threshold: float
## Hungry: stamina recovers this much as fast.
@export_range(0.1, 1.0, 0.05) var hungry_stamina_regen: float
## Thirsty: extra weapon sway.
@export_range(0.0, 10.0, 0.1, "suffix:°") var thirsty_sway: float
## At 0 energy (starving) or 0 hydration (dehydrated): HP lost per second from the stomach (once it's
## blacked, the damage spreads like any other).
@export_range(0.0, 5.0, 0.01, "suffix:HP/s") var starving_damage: float
@export_range(0.0, 5.0, 0.01, "suffix:HP/s") var dehydrated_damage: float
## Out of raid, both come back by this much per real minute.
@export_range(0.0, 20.0, 0.1, "suffix:/min") var recovery_per_minute: float
## A PMC who dies comes back with at least this much of each.
@export_range(0.0, 100.0, 1.0) var after_death_minimum: float

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
