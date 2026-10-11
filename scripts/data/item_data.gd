class_name ItemData
extends Resource
## Definition of one item type (DESIGN.md §6, §15). One .tres file per item in data/items/.
## Per-copy state (rolled bonuses, durability, Found-in-Raid) lives on the item instance, not here.

## Item categories (DESIGN.md §6.1). Saved as numbers in .tres files: only add new values at the end.
enum Category { WEAPON, AMMO, ATTACHMENT, ARMOR, RIG, BACKPACK, HELMET, MEDS, FOOD_DRINK, VALUABLE, BARTER, KEY, CONTAINER }
## Rarity scale (DESIGN.md §6.2). Same rule: only add new values at the end.
enum Rarity { COMMON, UNCOMMON, RARE, ULTRA_RARE, EPIC, LEGENDARY }

## Unique id used by code and save files, e.g. "ak_74n". Match the file name and never rename it.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.BARTER
@export var rarity: Rarity = Rarity.COMMON
## Cells taken in the grid inventory, width × height (DESIGN.md §7).
@export var size: Vector2i = Vector2i.ONE
@export var weight_kg: float = 0.1
## Base trader value in roubles (DESIGN.md §14).
@export var base_value: int = 0
## How many fit in one stack; 1 means the item doesn't stack (DESIGN.md §7).
@export_range(1, 9999) var max_stack: int = 1
## Category-specific stats, e.g. {"caliber": "5.45x39", "fire_rate": 650} for a weapon.
@export var stats: Dictionary = {}
