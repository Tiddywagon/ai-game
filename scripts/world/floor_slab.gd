@tool
class_name FloorSlab
extends StaticBody3D
## A raised floor you can walk on (DESIGN.md §5): a catwalk, a mezzanine or a landing at the top of
## Stairs. It doesn't block sight and isn't cover (put railings on it for that). Catwalks are see-
## through grating so the floor below stays visible from above. `size`: X and Z the footprint, Y the
## thickness; the node's origin is the middle of its top surface.

@export var size := Vector3(4.0, 0.2, 2.0):
	set(value):
		size = value
		_build()
@export var color := Color(0.45, 0.47, 0.5):
	set(value):
		color = value
		_build()
## See-through grating (a catwalk) rather than a solid floor.
@export var grating := true:
	set(value):
		grating = value
		_build()


func _ready() -> void:
	_build()
	if not Engine.is_editor_hint():
		add_to_group("floor_slabs")
		collision_layer = 1
		collision_mask = 0


func _build() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			child.free()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = -size.y / 2.0
	_add(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.position.y = -size.y / 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.45 if grating else 1.0)
	if grating:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.8
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if grating else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_add(mesh)


## Footprint corners on the ground (x, z), for the map.
func footprint() -> PackedVector2Array:
	return BoxFootprint.corners(global_transform, size)


func _add(node: Node) -> void:
	node.set_meta("generated", true)
	add_child(node)
