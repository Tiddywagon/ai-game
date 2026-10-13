@tool
class_name LootZone
extends Node3D
## A high-value loot area (DESIGN.md §5, §6.2): containers and loose loot spots inside its box roll
## with its rarity multipliers on top of their table's and the map's (an office with a safe, a lab, an
## armory). Shown on the map item. `size`: the box (X, Z footprint; Y height), centred on the node.

@export var zone_name := "High-value loot"
@export var size := Vector3(6.0, 4.0, 6.0)
## Indexed by ItemData.Rarity, as LootTable.rarity_multipliers (missing entries are 1).
@export var rarity_multipliers: PackedFloat32Array = [1.0, 1.0, 1.3, 1.6, 2.0, 2.0]


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("loot_zones")


func contains(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	return absf(local.x) <= size.x / 2.0 and absf(local.z) <= size.z / 2.0 and local.y >= -0.5 and local.y <= size.y


## The rarity multipliers for loot at `point`: every zone it's in, multiplied (empty: none).
static func boost_at(tree: SceneTree, point: Vector3) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for zone in tree.get_nodes_in_group("loot_zones"):
		if zone is LootZone and zone.contains(point):
			if result.is_empty():
				result = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
			for rarity in 6:
				result[rarity] *= zone.rarity_multipliers[rarity] if rarity < zone.rarity_multipliers.size() else 1.0
	return result


## Footprint corners on the ground (x, z), for the map.
func footprint() -> PackedVector2Array:
	return BoxFootprint.corners(global_transform, size)
