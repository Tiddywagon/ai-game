class_name FirMark
extends Control
## The found-in-raid checkmark on its own, for lists: next to a requirement's item name when only
## found-in-raid items count, and on the examine panel. Hover: "Found in raid".

## Faded: looted this raid, found in raid once you extract.
var pending := false:
	set(value):
		pending = value
		tooltip_text = "Found in raid once you extract with it" if value else "Found in raid"
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(18, 18)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Found in raid"


func _draw() -> void:
	var side := minf(size.x, size.y)
	ItemDraw.draw_fir_mark(self, Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)), pending)
