class_name LootContainer
extends Resource
## A type of container to search in a raid (DESIGN.md §6.2): a crate, toolbox, jacket, weapon box,
## medical bag, safe, filing cabinet or duffle bag, and the food spots: fridge, kitchen cabinet, store
## shelf and gas station counter; and the medical and lab spots where stims turn up: medicine cabinet and lab
## cabinet. Says what it rolls (its own LootTable), how big its
## grid is, how long searching it takes, and how the placeholder looks. One .tres per type in
## data/loot_tables/containers/; LootBox puts one in a map.

## Saved as numbers in the .tres files: only add new looks at the end.
enum Look { BOX, CRATE, TOOLBOX, JACKET, MEDICAL_BAG, SAFE, FILING_CABINET, FRIDGE, SHELF, KITCHEN_CABINET, COUNTER, MEDICINE_CABINET, LAB_CABINET }

@export var id := ""
@export var display_name := ""
## What it holds and how many items: this type's own table.
@export var loot_table: LootTable
## Its grid, columns × rows.
@export var grid_size := Vector2i(4, 3)
## Search time multiplier: a safe's lock and a cabinet's drawers take longer than a jacket's pockets.
@export_range(0.1, 5.0, 0.05) var search_time := 1.0

@export_group("Placeholder look")
@export var look := Look.BOX
@export var box_size := Vector3(0.9, 0.5, 0.6)
@export var color := Color(0.35, 0.3, 0.22)
## Solid containers block movement and bullets (and the AI walks around them).
@export var solid := false
## What a bullet hitting a solid one does (CoverBox.CoverMaterial: wood can be shot through).
@export_enum("Wood", "Concrete", "Metal") var cover_material := 2
