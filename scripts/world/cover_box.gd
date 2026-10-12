@tool
class_name CoverBox
extends StaticBody3D
## A box-shaped obstacle that counts as cover: walls, crates, car bodies, low barriers (DESIGN.md §13.3).
## Set its size and material in the Inspector; the mesh and collision are built from them.
## Its origin is its centre, like a CSG box. Only rotate it around Y.
## It also blocks sight (DESIGN.md §13.6): it joins the "vision" physics layer and VisionSystem.

## Decides what bullets can go through (DESIGN.md §13.4). Only add new values at the end.
enum CoverMaterial { WOOD, CONCRETE, METAL }

const COLORS := {
	CoverMaterial.WOOD: Color(0.62, 0.48, 0.3),
	CoverMaterial.CONCRETE: Color(0.8, 0.78, 0.72),
	CoverMaterial.METAL: Color(0.36, 0.42, 0.5),
}

@export var size := Vector3(2.0, 2.0, 0.4):
	set(value):
		size = value
		_rebuild()
@export var cover_material := CoverMaterial.CONCRETE:
	set(value):
		cover_material = value
		_rebuild()
## Turn off for parts that shouldn't create cover spots, like a car's roof.
@export var provides_cover := true

static var _materials: Dictionary = {}

var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		collision_layer |= VisionSystem.VISION_MASK
		CoverSystem.register(self)
		VisionSystem.register_occluder(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		CoverSystem.unregister(self)
		VisionSystem.unregister_occluder(self)


## Footprint corners on the ground (x, z), for vision shadows.
func vision_corners() -> PackedVector2Array:
	return BoxFootprint.corners(global_transform, size)


## Bottom and top height of the box.
func vision_height_span() -> Vector2:
	return Vector2(global_position.y - size.y / 2.0, global_position.y + size.y / 2.0)


## Thickness of the box behind the face whose outward normal is `normal`.
func vision_depth(normal: Vector3) -> float:
	return BoxFootprint.depth(global_basis, size, normal)


## One upright side of the box: 0 = +X, 1 = -X, 2 = +Z, 3 = -Z (local axes). Returns
## "center" (ground level, middle of the side), "normal" (outward), "tangent" (along the side),
## "half_length" (half the side's length) and "depth" (the box's thickness behind the side).
func get_face(index: int) -> Dictionary:
	var axis_x := global_basis.x.normalized()
	var axis_z := global_basis.z.normalized()
	var on_x := index < 2
	var normal := (axis_x if on_x else axis_z) * (1.0 if index % 2 == 0 else -1.0)
	var depth := size.x if on_x else size.z
	return {
		"center": global_position + Vector3.DOWN * size.y / 2.0 + normal * depth / 2.0,
		"normal": normal,
		"tangent": axis_z if on_x else axis_x,
		"half_length": (size.z if on_x else size.x) / 2.0,
		"depth": depth,
	}


func bottom_height() -> float:
	return global_position.y - size.y / 2.0


func _rebuild() -> void:
	if not is_inside_tree():
		return  # Built in _ready().
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_shape = CollisionShape3D.new()
		# Internal children aren't saved with the scene or shown in the Scene dock.
		add_child(_mesh, false, INTERNAL_MODE_FRONT)
		add_child(_shape, false, INTERNAL_MODE_FRONT)
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	_mesh.mesh = box_mesh
	_mesh.material_override = _material_for(cover_material)
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	_shape.shape = box_shape


static func _material_for(kind: CoverMaterial) -> StandardMaterial3D:
	if not _materials.has(kind):
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[kind]
		material.albedo_texture = load("res://assets/textures/prototype_grid.png")
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.metallic = 0.5 if kind == CoverMaterial.METAL else 0.0
		material.roughness = 0.45 if kind == CoverMaterial.METAL else 0.9
		_materials[kind] = material
	return _materials[kind]
