extends Node2D
## Draws triangles into a vision mask viewport (used by PlayerVision). One triangle array per update.

var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


## `points` and `colors` hold 3 entries per triangle.
func set_triangles(points: PackedVector2Array, colors: PackedColorArray) -> void:
	_points = points
	_colors = colors
	if _indices.size() != points.size():
		_indices.resize(points.size())
		for i in points.size():
			_indices[i] = i
	queue_redraw()


func _draw() -> void:
	if _points.size() >= 3:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _points, _colors)
