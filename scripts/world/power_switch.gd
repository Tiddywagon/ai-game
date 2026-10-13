class_name PowerSwitch
extends Node3D
## A power switch in a map (DESIGN.md §5): F throws it, and RaidConfig.power_delay seconds later the
## power comes on for the rest of the raid, opening the extracts that need it (ExtractZone.needs_power).
## A lamp on the box shows the state: red off, amber starting, green on.

const OFF_COLOR := Color(0.9, 0.2, 0.15)
const STARTING_COLOR := Color(0.95, 0.7, 0.2)
const ON_COLOR := Color(0.35, 1.0, 0.45)

@export var switch_name := "Power switch"

var _lamp: StandardMaterial3D
var _lever: MeshInstance3D


func _ready() -> void:
	add_to_group("interactables")
	_box(Vector3(0, 1.0, 0), Vector3(0.6, 0.8, 0.25), Color(0.35, 0.37, 0.33))
	_box(Vector3(0, 1.0, -0.14), Vector3(0.5, 0.06, 0.02), Color(0.95, 0.8, 0.2))  # A hazard stripe.
	_lever = _box(Vector3(0.18, 0.95, -0.17), Vector3(0.05, 0.3, 0.05), Color(0.15, 0.15, 0.15))
	var lamp := _box(Vector3(-0.15, 1.3, -0.14), Vector3(0.1, 0.1, 0.04), OFF_COLOR)
	_lamp = lamp.material_override
	_lamp.emission_enabled = true
	_update_look()


func _process(_delta: float) -> void:
	_update_look()


func interact_text() -> String:
	return "Throw the %s" % switch_name.to_lower()


func can_interact(_player: Player) -> bool:
	var raid := _raid()
	return raid != null and raid.power_state() == "off"


func interact(player: Player) -> void:
	var raid := _raid()
	if raid and raid.switch_power_on():
		player.action_blocked.emit("Power coming on in %d s" % roundi(raid.config.power_delay))


func _update_look() -> void:
	var raid := _raid()
	var state := raid.power_state() if raid else "off"
	var color: Color = {"off": OFF_COLOR, "starting": STARTING_COLOR, "on": ON_COLOR}[state]
	if _lamp.albedo_color != color:
		_lamp.albedo_color = color
		_lamp.emission = color
		_lever.position.y = 0.95 if state == "off" else 1.1


func _raid() -> RaidController:
	return get_tree().get_first_node_in_group("raid_controller") as RaidController if is_inside_tree() else null


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
