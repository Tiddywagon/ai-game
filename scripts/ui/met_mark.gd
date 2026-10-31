class_name MetMark
extends Control
## A green check or a red cross, for lists of required items (DESIGN.md §10): whether you have enough of
## one. The shape says it as well as the colour. Hover: what it means.

var met := false:
	set(value):
		met = value
		tooltip_text = "You have enough in your stash" if value else "Not enough in your stash"
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(22, 22)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Not enough in your stash"


func _draw() -> void:
	var side := minf(size.x, size.y)
	var box := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	var color := RequirementRow.MET_COLOR if met else RequirementRow.MISSING_COLOR
	draw_circle(box.get_center(), side / 2.0, Color(color, 0.18))
	draw_arc(box.get_center(), side / 2.0 - 1.0, 0.0, TAU, 24, Color(color, 0.9), 1.5, true)
	var width := maxf(side / 8.0, 2.0)
	if met:
		var points := PackedVector2Array([Vector2(0.27, 0.53), Vector2(0.44, 0.7), Vector2(0.75, 0.32)])
		for i in points.size():
			points[i] = box.position + points[i] * box.size
		draw_polyline(points, color, width, true)
	else:
		for line in [[Vector2(0.32, 0.32), Vector2(0.68, 0.68)], [Vector2(0.68, 0.32), Vector2(0.32, 0.68)]]:
			draw_line(box.position + line[0] * box.size, box.position + line[1] * box.size, color, width, true)
