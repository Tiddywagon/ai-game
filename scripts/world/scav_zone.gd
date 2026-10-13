class_name ScavZone
extends Node3D
## Where AI Scavs spawn and roam (DESIGN.md §4, §5): at raid start `count` Scavs appear on random
## points of the zone (its Marker3D children) and patrol between them. A player Scav's spawn points sit
## in these zones too (SpawnPoint, side Scav). Shown on the map item as a Scav area. Place zones before
## the RaidController in the scene, so its spawn choice knows where the Scavs are.

const BOT_SCENE := preload("res://scenes/actors/bot.tscn")

@export var zone_name := "Scav zone"
@export_range(0, 12) var count := 2
@export var profile: BotProfile = preload("res://data/bots/scav.tres")
## Patrol stops per Scav (picked from the zone's points).
@export_range(1, 6) var patrol_length := 3

## The Scavs spawned this raid.
var spawned: Array[Bot] = []


func _enter_tree() -> void:
	add_to_group("scav_zones")


func _ready() -> void:
	var points := patrol_points()
	if points.is_empty() or count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	if GameState.raid.has("seed"):
		rng.seed = int(GameState.raid.seed) + hash(name)
	else:
		rng.randomize()
	var order := range(points.size())
	for i in count:
		var start: Vector3 = points[order[rng.randi_range(0, order.size() - 1)]]
		var route := PackedVector3Array([start])
		for stop in patrol_length - 1:
			route.append(points[rng.randi_range(0, points.size() - 1)])
		var bot: Bot = BOT_SCENE.instantiate()
		bot.name = "%s_Scav%d" % [name, i + 1]
		bot.profile = profile
		bot.patrol_points = route
		bot.position = start + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		add_child(bot)
		spawned.append(bot)


## Where Scavs spawn and walk to: the zone's Marker3D children, in world space.
func patrol_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	for child in get_children():
		if child is Marker3D:
			result.append(child.global_position)
	return result
