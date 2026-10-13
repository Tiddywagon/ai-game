class_name SpawnPoint
extends Marker3D
## Where a raid can start (DESIGN.md §2, §5). At raid start the RaidController puts the player on a
## random spawn point for their side, preferring ones at least RaidConfig.spawn_safe_distance from
## hostile AI. Facing: the marker's -Z.

@export_enum("Any", "PMC", "Scav") var side := "Any"


func _enter_tree() -> void:
	add_to_group("spawn_points")  # Before any _ready(), so the RaidController sees every one.


func allows(raid_side: String) -> bool:
	return side == "Any" or side.to_lower() == raid_side


## A random spawn point in `tree` for `raid_side` ("pmc" or "scav"), at least `safe_distance` from
## every position in `threats` if any is; else any for the side. Null if there are none.
static func pick(tree: SceneTree, raid_side: String, rng: RandomNumberGenerator, threats: Array[Vector3] = [],
		safe_distance := 0.0) -> SpawnPoint:
	var usable: Array[SpawnPoint] = []
	for node in tree.get_nodes_in_group("spawn_points"):
		if node is SpawnPoint and node.allows(raid_side):
			usable.append(node)
	if usable.is_empty():
		return null
	var safe := usable.filter(func(point: SpawnPoint) -> bool:
		return threats.all(func(at: Vector3) -> bool: return Vector2(at.x - point.global_position.x, at.z - point.global_position.z).length() >= safe_distance))
	var pool: Array = safe if not safe.is_empty() else usable
	return pool[rng.randi_range(0, pool.size() - 1)]
