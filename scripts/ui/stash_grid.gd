class_name StashGrid
extends Control
## Read-only view of the stash grid on the Character screen and in the TRADERS screen's FIND panel
## (DESIGN.md §8, §10): every item at its cell with its rarity-coloured background and border, icon,
## short name, rarity letter, stack count and found-in-raid checkmark. Hover an item for details. With
## `fir_only`, items that aren't found in raid are dimmed. With `highlight` (FIND), the items a barter
## asks for are outlined and everything else is dimmed (part-used food, drink and meds too: barters take
## only whole ones); a container holding one lights up too. With `drag_scroll`, dragging (a finger, or the
## mouse) scrolls the ScrollContainer it sits in. Moving items happens in the inventory (INVENTORY or Tab).

const CELL := InventoryGridView.CELL
const LINE_COLOR := Color(1, 1, 1, 0.07)
## How faded a dimmed item is, and the outline around a highlighted one.
const DIM_ALPHA := 0.18
const HIGHLIGHT_COLOR := Color(1.0, 0.84, 0.3)

## Dims everything that isn't found in raid.
var fir_only := false:
	set(value):
		fir_only = value
		queue_redraw()
## Item id -> true if only found-in-raid ones count: outlines those and dims everything else (empty:
## no highlight).
var highlight := {}:
	set(value):
		highlight = value
		queue_redraw()
## Dragging scrolls the parent ScrollContainer (FIND). Touches arrive as the mouse, so it works by touch
## without a touch screen being detected.
var drag_scroll := false
var _dragging := false
## The part of a pixel dragged but not scrolled yet (fingers move in fractions of a pixel).
var _drag_rest := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if GameState.stash:
		custom_minimum_size = Vector2(GameState.stash.size) * CELL  # Before the first draw: a scroll container sizes to it.
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
		var lit := is_lit(item)
		ItemDraw.draw(self, item, _rect_of(item), item.rotated, DIM_ALPHA if is_dimmed(item) else 1.0)
		if lit:
			draw_rect(_rect_of(item).grow(1.0), Color(HIGHLIGHT_COLOR, 0.35), false, 6.0)
			draw_rect(_rect_of(item).grow(-1.0), HIGHLIGHT_COLOR, false, 2.5)


## True if `item` is drawn faded: not found in raid with `fir_only`, or not lit while `highlight` is on.
func is_dimmed(item: ItemInstance) -> bool:
	return (fir_only and not item.fir) or (not highlight.is_empty() and not is_lit(item))


## True if `item` is one `highlight` names (found in raid where that's asked for, and whole: a barter
## doesn't take part-used food, drink or meds), or a container holding one at any depth.
func is_lit(item: ItemInstance) -> bool:
	if highlight.is_empty():
		return false
	if highlight.has(item.data.id) and (item.fir or not highlight[item.data.id]) and not item.is_part_used():
		return true
	if item.contents:
		for inner in item.contents.items:
			if is_lit(inner):
				return true
	return false


## The stash items `highlight` lights up, top row first, then left to right.
func lit_items() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	result.assign(GameState.stash.items.filter(is_lit))
	result.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.cell.y < b.cell.y if a.cell.y != b.cell.y else a.cell.x < b.cell.x)
	return result


## Where `item` is drawn, in this view's coordinates.
func item_rect(item: ItemInstance) -> Rect2:
	return _rect_of(item)


func _gui_input(event: InputEvent) -> void:
	var scroll := get_parent() as ScrollContainer
	if not drag_scroll or scroll == null:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		_drag_rest = 0.0
		accept_event()
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		if not motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_dragging = false
			return
		_drag_rest -= motion.relative.y
		var pixels := int(_drag_rest)
		_drag_rest -= pixels
		scroll.scroll_vertical += pixels
		accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	for item in GameState.stash.items:
		var rect := _rect_of(item)
		if rect.has_point(at_position):
			if ItemDraw.has_fir_mark(item) and ItemDraw.fir_mark_rect(rect).grow(3.0).has_point(at_position):
				return FoundInRaid.status_text(item)
			var lines := ItemDraw.tooltip(item).split("\n")
			lines.remove_at(lines.size() - 1)  # No examining here.
			if is_lit(item) and not highlight.has(item.data.id):
				lines.append("Holds something this barter asks for")
			return "\n".join(lines) + ("\n" + item.data.description if item.data.description != "" else "")
	return ""


func _rect_of(item: ItemInstance) -> Rect2:
	return Rect2(Vector2(item.cell) * CELL, Vector2(item.footprint()) * CELL).grow(-2.0)
