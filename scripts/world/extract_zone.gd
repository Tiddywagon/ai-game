@tool
class_name ExtractZone
extends Area3D
## An extract (DESIGN.md §2, §5): stand inside for RaidConfig.extract_seconds to leave the raid with
## what you carry. A green ring and flare pillar mark it. The RaidController counts down; walking out
## stops it.

@export var extract_name := "Extract"
@export_range(0.5, 10.0, 0.1, "suffix:m") var radius := 2.5:
	set(value):
		radius = value
		_build()

const COLOR := Color(0.35, 1.0, 0.45)


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("extract_zones")
	collision_layer = 0
	collision_mask = 2  # Actors.
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _build() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			child.free()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	_add(shape)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.12
	torus.outer_radius = radius
	torus.rings = 48
	ring.mesh = torus
	ring.position.y = 0.03
	ring.scale.y = 0.15
	ring.material_override = _glow(0.9)
	_add(ring)
	var pillar := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.15
	beam.bottom_radius = 0.15
	beam.height = 4.0
	pillar.mesh = beam
	pillar.position.y = 2.0
	pillar.material_override = _glow(0.45)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(pillar)


func _add(node: Node) -> void:
	node.set_meta("generated", true)
	add_child(node)


func _glow(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(COLOR, alpha)
	material.emission_enabled = true
	material.emission = COLOR
	return material


func _raid() -> RaidController:
	return get_tree().get_first_node_in_group("raid_controller") as RaidController


func _on_body_entered(body: Node3D) -> void:
	if body is Player and _raid():
		_raid().enter_extract(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player and _raid():
		_raid().leave_extract(self)
