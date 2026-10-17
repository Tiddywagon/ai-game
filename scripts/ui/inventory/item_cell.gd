class_name ItemCell
extends Control
## One item drawn on its own, as in the grid (rarity colours, count, found-in-raid checkmark), for lists
## outside the inventory: trader offers, quest and hideout requirements, crafts, the raid result.
## Sized to the item's footprint at `cell_size` per cell, or to `box` when set. Right-click (a long
## press on a touch screen) asks for it to be examined.

signal examine_requested(item: ItemInstance)

var item: ItemInstance:
	set(value):
		item = value
		_resize()
var cell_size := 40.0:
	set(value):
		cell_size = value
		_resize()
## A fixed size to fit the item into instead (keeps lists tidy).
var box := Vector2.ZERO:
	set(value):
		box = value
		_resize()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _resize() -> void:
	if item:
		custom_minimum_size = box if box != Vector2.ZERO else Vector2(item.data.size) * cell_size
	queue_redraw()


func _draw() -> void:
	if item:
		ItemDraw.draw(self, item, Rect2(Vector2.ZERO, size).grow(-1.0), false)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT and item:
		examine_requested.emit(item)
		accept_event()


func _get_tooltip(at: Vector2) -> String:
	if item == null:
		return ""
	var lines := ItemDraw.tooltip_at(item, Rect2(Vector2.ZERO, size).grow(-1.0), at).split("\n")
	if lines.size() > 2 and lines[lines.size() - 1].begins_with("Right-click") and examine_requested.get_connections().is_empty():
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines)
