@tool
class_name VisionOccluder
extends StaticBody3D
## Something that blocks sight but not bullets or movement, like a hedge or tall grass, or a door
## (DESIGN.md §13.6). It only sits on the "vision" physics layer. Set its size in the Inspector; the
## collision (and, if `show_mesh` is on, a placeholder mesh) is built from it. Its origin is its centre.
## Only rotate it around Y. If it moves (a door opening), call VisionSystem.mark_dirty().

@export var size := Vector3(4.0, 1.8, 0.8):
	set(value):
		size = value
		_rebuild()
@export var color := Color(0.25, 0.42, 0.2):
	set(value):
		color = value
		_rebuild()
@export var show_mesh := true:
	set(value):
		show_mesh = value
		_rebuild()

var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		collision_layer = VisionSystem.VISION_MASK  # Blocks sight only.
		collision_mask = 0
		VisionSystem.register_occluder(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		VisionSystem.unregister_occluder(self)


func vision_corners() -> PackedVector2Array:
	return BoxFootprint.corners(global_transform, size)


func vision_height_span() -> Vector2:
	return Vector2(global_position.y - size.y / 2.0, global_position.y + size.y / 2.0)


func vision_depth(normal: Vector3) -> float:
	return BoxFootprint.depth(global_basis, size, normal)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_shape = CollisionShape3D.new()
		add_child(_mesh, false, INTERNAL_MODE_FRONT)
		add_child(_shape, false, INTERNAL_MODE_FRONT)
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	box_mesh.material = material
	_mesh.mesh = box_mesh
	_mesh.visible = show_mesh
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	_shape.shape = box_shape
