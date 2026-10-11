class_name MapInfo
extends Resource
## One raid map (DESIGN.md §5), shown on the map select screen. One .tres per map in data/maps/.

@export var id: String
@export var display_name: String
@export_multiline var description: String
## Order on the map select screen.
@export var order: int
@export var size: String
@export var raid_minutes: int
@export var players: String
@export var extracts: String
@export var boss: String
## The map's scene. Empty until the map is built; it then shows as "In development".
@export_file("*.tscn") var scene_path: String


func is_playable() -> bool:
	return scene_path != "" and ResourceLoader.exists(scene_path)


## Every map in data/maps/, in display order.
static func load_all() -> Array[MapInfo]:
	var maps: Array[MapInfo] = []
	for file_name in DirAccess.get_files_at("res://data/maps"):
		file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var map := load("res://data/maps".path_join(file_name)) as MapInfo
			if map:
				maps.append(map)
	maps.sort_custom(func(a: MapInfo, b: MapInfo) -> bool: return a.order < b.order)
	return maps


static func find(map_id: String) -> MapInfo:
	for map in load_all():
		if map.id == map_id:
			return map
	return null
