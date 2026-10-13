@tool
class_name MapLabel
extends Marker3D
## A named place (DESIGN.md §5): shown on the map item (MapOverlay) and, with `painted`, painted on
## the ground in big letters so you know where you are ("MAIN HALL", "GATE 3"). `landmark` marks the
## things you navigate by (the smokestack, the crane) in bold on the map.

@export var text := "Place":
	set(value):
		text = value
		_build()
@export var painted := true:
	set(value):
		painted = value
		_build()
@export var landmark := false
@export_range(8, 200, 1) var paint_size := 64:
	set(value):
		paint_size = value
		_build()


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("map_labels")


func _ready() -> void:
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			child.free()
	if not painted:
		return
	var label := Label3D.new()
	label.set_meta("generated", true)
	label.text = text.to_upper()
	label.font_size = paint_size
	label.pixel_size = 0.01
	label.modulate = Color(0.95, 0.9, 0.7, 0.55)
	label.outline_size = 0
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.position.y = 0.02
	label.shaded = false
	label.double_sided = false
	label.no_depth_test = false
	add_child(label)
