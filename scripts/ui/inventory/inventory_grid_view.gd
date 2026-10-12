class_name InventoryGridView
extends Control
## An InventoryGrid on screen (DESIGN.md §7): cells, and every item at its footprint with its icon and
## rarity colours. Drag items to move them (Shift-drag splits a stack); while dragging, the cells under
## the item light up green where it fits, amber when it would stack or go inside a container, red when
## it can't go there. Right-click examines an item; double-click opens a rig, backpack or container.

signal examine_requested(item: ItemInstance)
signal open_requested(item: ItemInstance)

const CELL := 52.0
const LINE_COLOR := Color(1, 1, 1, 0.07)
const FITS_COLOR := Color(0.35, 0.85, 0.4, 0.35)
const BLOCKED_COLOR := Color(0.95, 0.3, 0.25, 0.35)
const COMBINE_COLOR := Color(0.95, 0.75, 0.3, 0.45)

## The grid shown.
var grid: InventoryGrid:
	set(value):
		if grid and grid.changed.is_connected(queue_redraw):
			grid.changed.disconnect(queue_redraw)
		grid = value
		if grid:
			grid.changed.connect(queue_redraw)
			custom_minimum_size = Vector2(grid.size) * CELL
		queue_redraw()
## The character's inventory, so items can be dragged from here onto equipment slots.
var inventory: Inventory

var _hover := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func cell_at(at: Vector2) -> Vector2i:
	return Vector2i((at / CELL).floor())


func _get_drag_data(at: Vector2) -> Variant:
	var item := grid.item_at(cell_at(at))
	if item == null:
		return null
	var drag := InventoryDrag.new(item, grid, "", inventory, Input.is_key_pressed(KEY_SHIFT))
	set_drag_preview(InventoryDragPreview.create(drag))
	queue_redraw()
	return drag


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not data is InventoryDrag:
		return false
	var drag: InventoryDrag = data
	var top_left := drag.target_cell(at / CELL)
	var plan := drag.plan_grid(grid, cell_at(at), top_left)
	_hover = {"cell": top_left, "size": drag.footprint(), "plan": plan}
	queue_redraw()
	return not plan.is_empty()


func _drop_data(at: Vector2, data: Variant) -> void:
	var drag: InventoryDrag = data
	drag.drop_on_grid(grid, drag.plan_grid(grid, cell_at(at), drag.target_cell(at / CELL)))
	_hover = {}
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_hover = {}
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var item := grid.item_at(cell_at(click.position))
	if item == null:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		examine_requested.emit(item)
		accept_event()
	elif click.button_index == MOUSE_BUTTON_LEFT and click.double_click and item.contents:
		open_requested.emit(item)
		accept_event()


func _get_tooltip(at: Vector2) -> String:
	var item := grid.item_at(cell_at(at)) if grid else null
	return ItemDraw.tooltip(item) if item else ""


func _draw() -> void:
	if grid == null:
		return
	var area := Vector2(grid.size) * CELL
	draw_rect(Rect2(Vector2.ZERO, area), Color(0, 0, 0, 0.35))
	for x in grid.size.x + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, area.y), LINE_COLOR)
	for y in grid.size.y + 1:
		draw_line(Vector2(0, y * CELL), Vector2(area.x, y * CELL), LINE_COLOR)
	var lifted: ItemInstance = InventoryDrag.current.item if InventoryDrag.current and not InventoryDrag.current.splitting else null
	for item in grid.items:
		var rect := Rect2(Vector2(item.cell) * CELL, Vector2(item.footprint()) * CELL).grow(-2.0)
		ItemDraw.draw(self, item, rect, item.rotated, 0.3 if item == lifted and get_viewport().gui_is_dragging() else 1.0)
	if _hover.is_empty():
		return
	var plan: Dictionary = _hover.plan
	var rect := Rect2(Vector2(_hover.cell) * CELL, Vector2(_hover.size) * CELL).intersection(Rect2(Vector2.ZERO, area))
	var color := FITS_COLOR if not plan.is_empty() else BLOCKED_COLOR
	if plan.has("target"):
		var target: ItemInstance = plan.target
		rect = Rect2(Vector2(target.cell) * CELL, Vector2(target.footprint()) * CELL)
		color = COMBINE_COLOR
	draw_rect(rect, color)
	# A solid outline too: the see-through item being dragged covers the fill.
	draw_rect(rect.grow(-1.5), Color(color, 0.95), false, 3.0)
