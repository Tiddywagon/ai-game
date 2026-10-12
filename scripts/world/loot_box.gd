class_name LootBox
extends Node3D
## A container to search in a raid (DESIGN.md §2, §6.2): a duffle bag, weapon box, medical case,
## jacket or safe. Filled at the start of the raid by the default LootTable for its LootContainer
## type and the map's multipliers. F nearby opens it beside your inventory; whatever you take out is
## loot (found in raid if you extract with it). A placeholder box for now: you can walk through it.

@export var container: LootContainer
## Its grid, columns × rows.
@export var grid_size := Vector2i(4, 3)
## Placeholder size and colour.
@export var box_size := Vector3(0.9, 0.5, 0.6)
@export var color := Color(0.35, 0.3, 0.22)
## Rolls the same contents every time when not 0 (for tests).
@export var loot_seed := 0

var grid: InventoryGrid


func _ready() -> void:
	add_to_group("interactables")
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh.mesh = box
	mesh.position.y = box_size.y / 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)
	grid = InventoryGrid.new(grid_size, &"loot")
	roll()


func title() -> String:
	return container.display_name if container else "Container"


## Fills the grid from the loot table (what doesn't fit is skipped).
func roll() -> void:
	if container == null:
		return
	var rng := RandomNumberGenerator.new()
	if loot_seed != 0:
		rng.seed = loot_seed
	else:
		rng.randomize()
	var table: LootTable = load("res://data/loot_tables/default.tres")
	var map := MapInfo.find(GameState.raid.get("map", ""))
	for entry in table.roll_container(rng, container, map):
		var item := ItemInstance.create(entry.id, entry.count)
		if item and item.data.weapon:
			item = Inventory.loaded_gun(entry.id, _ammo_for(item.data.weapon.caliber))
		if item:
			grid.add(item)


func interact_text() -> String:
	return "Search %s" % title()


func can_interact(_player: Player) -> bool:
	return true


func interact(player: Player) -> void:
	player.open_loot(title().to_upper(), grid, self)


static func _ammo_for(caliber: String) -> String:
	for item in ItemDB.all_items():
		if item.category == ItemData.Category.AMMO and item.stats.get("caliber", "") == caliber:
			return item.id
	return ""
