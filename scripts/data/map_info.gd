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
## (The extracts are in data/config/extracts.json: ExtractTable.)
@export var boss: String
## The map's scene. Empty until the map is built; it then shows as "In development".
@export_file("*.tscn") var scene_path: String
## Multiplies loot rarity weights on this map, indexed by ItemData.Rarity (DESIGN.md §6.2): Labs
## doubles Epic and Legendary. Missing entries count as 1.
@export var loot_multipliers: PackedFloat32Array = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
## Climate (DESIGN.md §13.7): hot maps dry you out faster. Energy and hydration drain × these.
@export_enum("Temperate", "Hot", "Cold") var climate := "Temperate"
@export_range(0.5, 3.0, 0.05) var energy_drain_multiplier := 1.0
@export_range(0.5, 3.0, 0.05) var hydration_drain_multiplier := 1.0


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
