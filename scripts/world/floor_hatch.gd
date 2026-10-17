class_name FloorHatch
extends Node3D
## Loose floorboards over a hidden stash (DESIGN.md §5.2): easy to miss, a few boards a shade darker
## than the floor. F pries them up and reveals the containers underneath (its concealed LootBox
## children, which can't be seen or searched until then). Once open it stays open.

const BOARD_COLOR := Color(0.3, 0.24, 0.17)
const HOLE_COLOR := Color(0.05, 0.05, 0.05)

@export var hatch_name := "Loose floorboards"
## The boards' footprint (X, Z).
@export var size := Vector2(1.2, 0.9)

var opened := false

var _boards: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("interactables")
	var hole := _plank(Vector3(0, 0.005, 0), Vector3(size.x, 0.01, size.y), HOLE_COLOR)
	hole.name = "Hole"
	var count := 4
	for i in count:
		var z := -size.y / 2.0 + size.y * (i + 0.5) / count
		_boards.append(_plank(Vector3(0, 0.025, z), Vector3(size.x, 0.03, size.y / count - 0.02), BOARD_COLOR.lightened(0.04 * (i % 2))))
	for child in get_children():
		if child is LootBox:
			child.concealed = true


func interact_text() -> String:
	return "Pry up the %s" % hatch_name.to_lower()


func can_interact(_player: Player) -> bool:
	return not opened


func interact(player: Player) -> void:
	open()
	player.action_blocked.emit("A stash under the floor")


## Lifts the boards and reveals what's under them.
func open() -> void:
	if opened:
		return
	opened = true
	for i in _boards.size():
		var board := _boards[i]
		var tween := create_tween()
		tween.tween_property(board, "position", board.position + Vector3(size.x * 0.8 + i * 0.05, 0.02 * i, 0), 0.25)
	for child in get_children():
		if child is LootBox:
			child.reveal()
	NoiseSystem.emit_noise(global_position, 6.0, get_tree().get_first_node_in_group("player"), &"hatch")


func _plank(at: Vector3, plank_size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = plank_size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
	add_child(mesh)
	return mesh
