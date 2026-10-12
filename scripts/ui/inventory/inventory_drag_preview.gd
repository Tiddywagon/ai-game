class_name InventoryDragPreview
extends Control
## The item following the mouse while dragging, centred on it, turned when R turns it and showing how
## many are moving in a split. See-through, so the green / red cells underneath show.

var drag: InventoryDrag


## A preview for set_drag_preview(): a holder at the mouse with the item centred on it.
static func create(source: InventoryDrag) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := InventoryDragPreview.new()
	preview.drag = source
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(preview)
	source.updated.connect(preview._layout)
	preview._layout()
	return holder


func _layout() -> void:
	size = Vector2(drag.footprint()) * InventoryGridView.CELL
	position = -size / 2.0
	queue_redraw()


func _draw() -> void:
	ItemDraw.draw(self, drag.item, Rect2(Vector2.ZERO, size).grow(-2.0), drag.rotated, 0.6, drag.amount)
