class_name Lever
extends Node3D
## A lever in a map (DESIGN.md §5.2): F pulls it, once, for the rest of the raid. Doors with its
## `lever_id` (Door.lever_id) open when it's pulled: a bunker's shutter, a hatch. It clanks loudly
## enough for nearby AI to hear. A handle on a wall plate, down until pulled.

const NOISE_RADIUS := 25.0

@export var lever_id := ""
@export var lever_name := "Lever"

var pulled := false

var _handle: MeshInstance3D


func _ready() -> void:
	add_to_group("levers")
	add_to_group("interactables")
	_box(Vector3(0, 1.1, 0), Vector3(0.45, 0.7, 0.12), Color(0.32, 0.34, 0.36))
	_box(Vector3(0, 1.48, -0.07), Vector3(0.4, 0.05, 0.02), Color(0.95, 0.8, 0.2))  # A hazard stripe.
	_handle = _box(Vector3(0, 0.95, -0.12), Vector3(0.06, 0.4, 0.06), Color(0.75, 0.15, 0.12))
	_handle.rotation_degrees.x = -35.0


## True once the lever `id` has been pulled this raid.
static func is_pulled(tree: SceneTree, id: String) -> bool:
	for node in tree.get_nodes_in_group("levers"):
		if node is Lever and node.lever_id == id and node.pulled:
			return true
	return false


func interact_text() -> String:
	return "Pull the %s" % lever_name.to_lower()


func can_interact(_player: Player) -> bool:
	return not pulled


func interact(player: Player) -> void:
	pull(player)


## Pulls it (doors with its id open). False if it already was.
func pull(by: Actor = null) -> bool:
	if pulled:
		return false
	pulled = true
	create_tween().tween_property(_handle, "rotation_degrees:x", 35.0, 0.3)
	NoiseSystem.emit_noise(global_position, NOISE_RADIUS, by, &"lever")
	if by is Player:
		by.action_blocked.emit("Something heavy grinds open")
	return true


func _box(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	mesh.material_override = material
	add_child(mesh)
	return mesh
