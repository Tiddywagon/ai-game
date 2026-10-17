@tool
class_name PointOfInterest
extends Node3D
## A point of interest placed in a map (DESIGN.md §5.2): `poi_id` on `map_id` in
## data/config/pois.json (PoiTable: name, loot tier, focus tags, requirement, hidden), and its boundary:
## a box, `size` (X and Z footprint, Y height), centred on the node across and standing on it. The
## containers and loose loot spots inside it are its spawn points: at raid start each one rolls whether
## it's active this raid (PoiTable.spawn_chance(), seeded by the raid), and the active ones roll their
## items with the POI's tier multipliers and focus tags (LootBox, LootPickup); the rest stay empty.
## Where POIs overlap, the smallest one a point is in owns it. Marker3D children named EventSpot* are
## where raid events can happen in it (else its centre). It records what spawned where, for the debug
## overlay.

@export var map_id := "test_yard"
@export var poi_id := ""
@export var size := Vector3(8.0, 3.0, 8.0)

## Every spawn point rolled so far, by its node path: {"name", "at" (where), "kind": "container" or
## "loose", "active", "items" (names)}. (Loose spots that stay empty free themselves.)
var spots := {}
## Raid seconds until which a raid event here makes it hot (-1: none), and the event's name.
var event_until := -1.0
var event_name := ""

var _entry := {}
var _seed := 0


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("pois")


## The POI's row in data/config/pois.json ({} if it isn't there).
func entry() -> Dictionary:
	if _entry.is_empty():
		_entry = PoiTable.find(map_id, poi_id)
	return _entry


func poi_name() -> String:
	return str(entry().get("name", poi_id))


func tier() -> int:
	return int(entry().get("tier", 1))


func focus() -> Array:
	return entry().get("focus", [])


func is_hidden() -> bool:
	return entry().get("hidden", false)


## The rarity multipliers for loot rolled in here (PoiTable.loot_boost()).
func loot_boost() -> PackedFloat32Array:
	return PoiTable.loot_boost(entry())


func contains(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	return absf(local.x) <= size.x / 2.0 and absf(local.z) <= size.z / 2.0 and local.y >= -0.5 and local.y <= size.y


func volume() -> float:
	return size.x * size.y * size.z


## The POI `point` is in (the smallest one, where they overlap), or null.
static func at(tree: SceneTree, point: Vector3) -> PointOfInterest:
	var best: PointOfInterest = null
	for node in tree.get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		if poi and poi.contains(point) and (best == null or poi.volume() < best.volume()):
			best = poi
	return best


## Whether spawn point `spot` spawns anything this raid: a roll against the POI's spawn chance, the same
## for the whole raid (seeded by the raid's seed and the spot's path, so the order nothing rolls in
## doesn't matter).
func spot_active(spot: Node) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_raid_seed(), poi_id, str(spot.get_path())])
	return rng.randf() < PoiTable.spawn_chance(entry())


## Notes what spawn point `spot` spawned this raid (for the debug overlay).
func record(spot: Node, kind: String, active: bool, items: Array) -> void:
	var names := PackedStringArray()
	for item in items:
		names.append(item.data.display_name if item is ItemInstance else str(item))
	var at: Vector3 = spot.global_position if spot is Node3D and spot.is_inside_tree() else global_position
	spots[str(spot.get_path())] = {"name": str(spot.name), "at": at, "kind": kind, "active": active, "items": names}


## Spawn points active this raid, and all of them.
func active_count() -> int:
	return spots.values().filter(func(info: Dictionary) -> bool: return info.active).size()


## Where raid events can happen here: its EventSpot markers, or its centre.
func event_spots() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for child in get_children():
		if child is Marker3D and child.name.begins_with("EventSpot"):
			result.append(child.global_position)
	if result.is_empty():
		result.append(global_position)
	return result


## True once its requirement is met: its key's door unlocked (or the key on `who`), the power on, or
## its lever pulled. Always true without one.
func requirement_met(who: Actor = null) -> bool:
	var requires: Dictionary = entry().get("requires", {})
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	var key := str(requires.get("key", ""))
	if key != "":
		for door in get_tree().get_nodes_in_group("doors"):
			if door.key_id == key and not door.locked:
				return true
		var gear := who.worn_gear() if who else null
		return gear != null and gear.all_items().any(func(item: ItemInstance) -> bool: return item.data.id == key)
	if requires.get("power", false):
		return raid != null and raid.power_state() == "on"
	if str(requires.get("lever", "")) != "":
		return Lever.is_pulled(get_tree(), str(requires.lever))
	return true


## How strongly it draws Scav waves and roaming AI PMCs at `raid_seconds` into the raid: its tier's
## heat, plus more while a raid event here is fresh.
func heat(raid_seconds: float) -> float:
	var config := PoiTable.CONFIG
	var value: float = config.tier_heat[clampi(tier(), 1, 3) - 1]
	if event_until >= 0.0 and raid_seconds <= event_until:
		value += config.event_heat
	return value


## Footprint corners on the ground (x, z), for the map.
func footprint() -> PackedVector2Array:
	return BoxFootprint.corners(global_transform, size)


func _raid_seed() -> int:
	if GameState.raid.has("seed"):
		return int(GameState.raid.seed)
	if _seed == 0:
		_seed = randi() | 1
	return _seed
