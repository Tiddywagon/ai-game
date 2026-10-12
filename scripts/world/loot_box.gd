class_name LootBox
extends Node3D
## A container to search in a raid (DESIGN.md §6.2, §7): a crate, toolbox, jacket, weapon box, medical
## bag, safe, filing cabinet or duffle bag, set by its LootContainer type. At the start of the raid it's
## filled from the type's own LootTable (with the map's multipliers) and everything inside is hidden.
## F nearby opens it beside your inventory and searches it: items turn up one by one (LootSearch).
## Whatever you take out is loot (found in raid if you extract with it). Big types are solid: they block
## movement and bullets and the AI walks around them. Placeholder shapes in the type's colour for now.

@export var container: LootContainer
## Rolls the same contents every time when not 0 (for tests).
@export var loot_seed := 0

var grid: InventoryGrid
var search: LootSearch


func _ready() -> void:
	add_to_group("interactables")
	_build_look()
	grid = InventoryGrid.new(container.grid_size if container else Vector2i(4, 3), &"loot")
	search = LootSearch.new(func() -> Array[InventoryGrid]: return [grid], container.search_time if container else 1.0)
	roll()


func title() -> String:
	return container.display_name if container else "Container"


## Fills the grid from the type's loot table (what doesn't fit is skipped) and hides it all.
func roll() -> void:
	if container == null or container.loot_table == null:
		return
	var rng := RandomNumberGenerator.new()
	if loot_seed != 0:
		rng.seed = loot_seed
	else:
		rng.randomize()
	for item in container.loot_table.roll_items(rng, MapInfo.find(GameState.raid.get("map", ""))):
		grid.add(item)
	search.hide_all()


func interact_text() -> String:
	return ("Open %s" if search.is_done() else "Search %s") % title()


func can_interact(_player: Player) -> bool:
	return true


func interact(player: Player) -> void:
	player.open_loot(title().to_upper(), grid, self)


func _build_look() -> void:
	var size := container.box_size if container else Vector3(0.9, 0.5, 0.6)
	var color := container.color if container else Color(0.35, 0.3, 0.22)
	_box(Vector3(0, size.y / 2.0, 0), size, color)
	var dark := color.darkened(0.45)
	var front := -size.z / 2.0 - 0.01
	match container.look if container else LootContainer.Look.BOX:
		LootContainer.Look.CRATE:
			for x in [-0.33, 0.0, 0.33]:  # Planks on the lid.
				_box(Vector3(x * size.x, size.y + 0.005, 0), Vector3(0.04, 0.01, size.z), dark)
		LootContainer.Look.TOOLBOX:
			_box(Vector3(0, size.y + 0.04, 0), Vector3(size.x * 0.5, 0.03, 0.04), dark)  # Handle.
		LootContainer.Look.JACKET:
			_box(Vector3(0, size.y + 0.02, -size.z * 0.38), Vector3(size.x * 0.5, 0.04, size.z * 0.2), dark)  # Collar.
		LootContainer.Look.MEDICAL_BAG:
			var red := Color(0.8, 0.12, 0.1)
			_box(Vector3(0, size.y + 0.005, 0), Vector3(size.x * 0.4, 0.01, size.z * 0.13), red)
			_box(Vector3(0, size.y + 0.005, 0), Vector3(size.x * 0.13, 0.01, size.z * 0.4), red)
		LootContainer.Look.SAFE:
			_box(Vector3(0.12, size.y * 0.6, front), Vector3(0.12, 0.12, 0.03), Color(0.7, 0.68, 0.6))  # Dial.
			_box(Vector3(-0.15, size.y * 0.5, front), Vector3(0.04, 0.22, 0.04), dark)  # Handle.
		LootContainer.Look.FILING_CABINET:
			for i in 3:  # Drawers, each with a handle.
				var y := size.y * (0.2 + 0.31 * i)
				_box(Vector3(0, y + size.y * 0.15, front), Vector3(size.x * 0.92, 0.015, 0.01), dark)
				_box(Vector3(0, y + size.y * 0.06, front - 0.01), Vector3(size.x * 0.3, 0.03, 0.02), Color(0.75, 0.75, 0.72))
	if container and container.solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1  # World: blocks movement and bullets, baked into the navmesh.
		body.collision_mask = 0
		body.set_meta("cover_material", container.cover_material)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position.y = size.y / 2.0
		body.add_child(shape)
		add_child(body)


func _box(at: Vector3, box_size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	add_child(mesh)
