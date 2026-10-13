@tool
class_name Stairs
extends StaticBody3D
## A flight of stairs (DESIGN.md §5): walkable up to a catwalk, mezzanine or landing, by the player
## and (baked into the navigation mesh) the AI. It doesn't block sight. `size`: width (X), rise (Y)
## and run (Z); the bottom step is at local -Z / 2 on the floor, the top at +Z / 2, `rise` up. The
## node's origin is the middle of the flight's footprint at floor level. Collision is a smooth ramp;
## the steps are just the look.

@export var size := Vector3(1.6, 3.0, 5.0):
	set(value):
		size = value
		_build()
@export var color := Color(0.5, 0.52, 0.55):
	set(value):
		color = value
		_build()

const STEP_HEIGHT := 0.2


func _ready() -> void:
	_build()
	if not Engine.is_editor_hint():
		add_to_group("stairs")
		collision_layer = 1
		collision_mask = 0


func _build() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			child.free()
	var half_w := size.x / 2.0
	var half_r := size.z / 2.0
	var ramp := ConvexPolygonShape3D.new()
	ramp.points = PackedVector3Array([
		Vector3(-half_w, 0, -half_r), Vector3(half_w, 0, -half_r),
		Vector3(-half_w, 0, half_r), Vector3(half_w, 0, half_r),
		Vector3(-half_w, size.y, half_r), Vector3(half_w, size.y, half_r)])
	var shape := CollisionShape3D.new()
	shape.shape = ramp
	_add(shape)
	var steps := maxi(1, roundi(size.y / STEP_HEIGHT))
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	for i in steps:
		var step := MeshInstance3D.new()
		var box := BoxMesh.new()
		var top := size.y * (i + 1) / steps
		var depth := size.z / steps
		box.size = Vector3(size.x, top, depth)
		step.mesh = box
		step.position = Vector3(0, top / 2.0, -half_r + depth * (i + 0.5))
		step.material_override = material
		_add(step)


## Footprint corners on the ground (x, z), for the map.
func footprint() -> PackedVector2Array:
	return BoxFootprint.corners(global_transform, size)


func _add(node: Node) -> void:
	node.set_meta("generated", true)
	add_child(node)
