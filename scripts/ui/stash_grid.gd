extends Control
## Read-only view of the stash grid on the Character screen (DESIGN.md §8): every item at its cell with
## its rarity-coloured background and border, icon, short name, rarity letter, stack count and
## found-in-raid checkmark. Hover an item for details. With `fir_only`, items that aren't found in raid
## are dimmed. Moving items happens in the inventory (INVENTORY or Tab).

const CELL := InventoryGridView.CELL
const LINE_COLOR := Color(1, 1, 1, 0.07)

## Dims everything that isn't found in raid.
var fir_only := false:
	set(value):
		fir_only = value
		queue_redraw()


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
		ItemDraw.draw(self, item, _rect_of(item), item.rotated, 0.18 if fir_only and not item.fir else 1.0)


func _get_tooltip(at_position: Vector2) -> String:
	for item in GameState.stash.items:
		var rect := _rect_of(item)
		if rect.has_point(at_position):
			if ItemDraw.has_fir_mark(item) and ItemDraw.fir_mark_rect(rect).grow(3.0).has_point(at_position):
				return FoundInRaid.status_text(item)
			var lines := ItemDraw.tooltip(item).split("\n")
			lines.remove_at(lines.size() - 1)  # No examining here.
			return "\n".join(lines) + ("\n" + item.data.description if item.data.description != "" else "")
	return ""


func _rect_of(item: ItemInstance) -> Rect2:
	return Rect2(Vector2(item.cell) * CELL, Vector2(item.footprint()) * CELL).grow(-2.0)
