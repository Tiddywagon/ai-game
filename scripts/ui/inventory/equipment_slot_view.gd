class_name EquipmentSlotView
extends Control
## One equipment slot on screen (DESIGN.md §7): the item in it, or the slot's name when empty. Drop an
## item that belongs there to equip it (the slot lights up green, or red if it doesn't fit there); drag
## it out to unequip. Dropping something on an equipped rig or backpack puts it inside. Right-click
## examines; double-click opens a rig, backpack or container.

signal examine_requested(item: ItemInstance)
signal open_requested(item: ItemInstance)

const OK_COLOR := Color(0.35, 0.85, 0.4, 0.35)
const BAD_COLOR := Color(0.95, 0.3, 0.25, 0.35)
const COMBINE_COLOR := Color(0.95, 0.75, 0.3, 0.45)

var inventory: Inventory
var slot := ""
var title := ""

## 1 = would equip, 2 = would go inside, -1 = can't, 0 = not dragging over.
var _hover := 0


func setup(owner: Inventory, slot_id: String, slot_name: String, cells: Vector2i) -> void:
	inventory = owner
	slot = slot_id
	title = slot_name
	custom_minimum_size = Vector2(cells) * InventoryGridView.CELL
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	inventory.changed.connect(queue_redraw)


func item() -> ItemInstance:
	return inventory.equipment.get(slot)


func _get_drag_data(_at: Vector2) -> Variant:
	if item() == null:
		return null
	var drag := InventoryDrag.new(item(), null, slot, inventory, false)
	set_drag_preview(InventoryDragPreview.create(drag))
	queue_redraw()
	return drag


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not data is InventoryDrag:
		return false
	var drag: InventoryDrag = data
	if drag.can_equip(slot):
		_hover = 1
	elif item() and drag.can_insert(item()):
		_hover = 2
	else:
		_hover = -1
	queue_redraw()
	return _hover > 0


func _drop_data(_at: Vector2, data: Variant) -> void:
	var drag: InventoryDrag = data
	if not drag.drop_on_slot(slot) and item():
		drag.insert(item())
	_hover = 0
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_hover = 0
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or item() == null:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		examine_requested.emit(item())
		accept_event()
	elif click.button_index == MOUSE_BUTTON_LEFT and click.double_click and item().contents:
		open_requested.emit(item())
		accept_event()


func _get_tooltip(_at: Vector2) -> String:
	return ItemDraw.tooltip(item()) if item() else "%s: empty" % title


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0, 0, 0, 0.35))
	draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)
	var equipped := item()
	if equipped:
		var lifted: bool = InventoryDrag.current != null and InventoryDrag.current.item == equipped and get_viewport().gui_is_dragging()
		ItemDraw.draw(self, equipped, rect.grow(-2.0), false, 0.3 if lifted else 1.0)
	else:
		draw_string(get_theme_default_font(), Vector2(0, size.y / 2.0 + 5.0), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(1, 1, 1, 0.25))
	if _hover != 0:
		var color: Color = {1: OK_COLOR, 2: COMBINE_COLOR, -1: BAD_COLOR}[_hover]
		draw_rect(rect, color)
		draw_rect(rect.grow(-1.5), Color(color, 0.95), false, 3.0)
