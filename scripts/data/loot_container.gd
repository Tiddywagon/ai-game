class_name LootContainer
extends Resource
## A kind of place loot spawns (DESIGN.md §6.2): loose on the ground, a jacket, a weapon box, a safe...
## Its multipliers scale the LootTable's rarity weights, so high-tier spots (safes) drop rarer loot;
## its categories limit what can be inside. One .tres per kind in data/loot_tables/containers/.

@export var id := ""
@export var display_name := ""
## Multiplies the weight of each rarity, indexed by ItemData.Rarity (Common ... Legendary).
## Missing entries count as 1.
@export var rarity_multipliers: PackedFloat32Array = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
## Item categories it can hold (ItemData.Category). Empty: anything.
@export var categories: Array[ItemData.Category] = []
## How many items it holds: a random number from x to y.
@export var item_count := Vector2i(1, 2)
