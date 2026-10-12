extends Control
## Read-only view of the stash grid on the Character screen (DESIGN.md §8): every item at its cell with
## its rarity-coloured background and border, icon, short name, rarity letter and stack count. Hover an
## item for details. Moving items happens in the inventory (INVENTORY or Tab).

const CELL := InventoryGridView.CELL
const LINE_COLOR := Color(1, 1, 1, 0.07)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()


func _draw() -> void:
	var stash := GameState.stash
	custom_minimum_size = Vector2(stash.size) * CELL
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color(0, 0, 0, 0.35))
	for x in stash.size.x + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, stash.size.y * CELL), LINE_COLOR)
	for y in stash.size.y + 1:
		draw_line(Vector2(0, y * CELL), Vector2(stash.size.x * CELL, y * CELL), LINE_COLOR)
	for item in stash.items:
		ItemDraw.draw(self, item, _rect_of(item), item.rotated)


func _get_tooltip(at_position: Vector2) -> String:
	for item in GameState.stash.items:
		if _rect_of(item).has_point(at_position):
			var text := ItemDraw.tooltip(item).get_slice("\n", 0) + "\n" + ItemDraw.tooltip(item).get_slice("\n", 1)
			return text + ("\n" + item.data.description if item.data.description != "" else "")
	return ""


func _rect_of(item: ItemInstance) -> Rect2:
	return Rect2(Vector2(item.cell) * CELL, Vector2(item.footprint()) * CELL).grow(-2.0)
