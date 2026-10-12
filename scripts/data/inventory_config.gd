class_name InventoryConfig
extends Resource
## Inventory tuning (DESIGN.md §7, §8): stash size and how carried weight slows you down. The values
## live in data/config/inventory.tres.

## Stash grid, columns × rows (DESIGN.md §8, level 1).
@export var stash_size := Vector2i(10, 30)

@export_group("Weight")
## From this weight you start slowing down and tiring faster.
@export_range(0.0, 200.0, 0.5, "suffix:kg") var encumbered_kg := 25.0
## From this weight you're overweight: no sprinting or rolling.
@export_range(0.0, 200.0, 0.5, "suffix:kg") var overweight_kg := 40.0
## At this weight you're as slow as you get.
@export_range(0.0, 300.0, 0.5, "suffix:kg") var max_weight_kg := 65.0
## Speed multiplier when you reach overweight_kg (it falls from 1 at encumbered_kg).
@export_range(0.1, 1.0, 0.05) var overweight_speed := 0.8
## Speed multiplier at max_weight_kg.
@export_range(0.1, 1.0, 0.05) var max_weight_speed := 0.55
## Sprint stamina cost multiplier at overweight_kg (it rises from 1 at encumbered_kg).
@export_range(1.0, 5.0, 0.05) var overweight_stamina_cost := 1.5


## Movement speed multiplier when carrying `kg`.
func speed_multiplier(kg: float) -> float:
	if kg <= encumbered_kg:
		return 1.0
	if kg <= overweight_kg:
		return lerpf(1.0, overweight_speed, (kg - encumbered_kg) / maxf(overweight_kg - encumbered_kg, 0.01))
	return lerpf(overweight_speed, max_weight_speed, clampf((kg - overweight_kg) / maxf(max_weight_kg - overweight_kg, 0.01), 0.0, 1.0))


## Sprint stamina cost multiplier when carrying `kg`.
func stamina_multiplier(kg: float) -> float:
	if kg <= encumbered_kg:
		return 1.0
	return lerpf(1.0, overweight_stamina_cost, clampf((kg - encumbered_kg) / maxf(overweight_kg - encumbered_kg, 0.01), 0.0, 1.0))
