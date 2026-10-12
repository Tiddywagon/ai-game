class_name ModSlotView
extends Control
## One slot on a gun in the modding screen (DESIGN.md §12.1): the part in it (its icon in its rarity
## colours), or the slot's name when empty, outlined red if the gun can't fire without it. Drop a part
## that fits to put it on (green while it fits, red if it doesn't), replacing what's there; drag the
## part off (to the parts list) or double-click it to take it off. Click to list only the parts for
## this slot. Hovering a part that fits here previews the stats with it.

signal selected(path: String)
## A drag is over this slot with a part that fits (`mod`), or left (null).
signal preview_requested(path: String, mod: ItemInstance)
## A part was dropped here.
signal install_requested(path: String, drag: InventoryDrag)
signal remove_requested(path: String)

const SIZE := Vector2(132, 58)
const OK_COLOR := Color(0.35, 0.85, 0.4, 0.35)
const BAD_COLOR := Color(0.95, 0.3, 0.25, 0.35)
const REQUIRED_COLOR := Color(0.9, 0.35, 0.3, 0.8)
const SELECTED_COLOR := Color(0.95, 0.78, 0.35, 0.9)

var gun: ItemInstance
var path := ""
var slot: Dictionary
var inventory: Inventory
var is_selected := false:
	set(value):
		is_selected = value
		queue_redraw()

## 1 = the part being dragged fits, -1 = it doesn't, 0 = no drag over this slot.
var _hover := 0


func setup(target: ItemInstance, slot_path: String, owner: Inventory) -> void:
	gun = target
	path = slot_path
	slot = WeaponMods.slot_at(gun, path)
	inventory = owner
	custom_minimum_size = SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP


func mod() -> ItemInstance:
	return WeaponMods.mod_at(gun, path)


func _get_drag_data(_at: Vector2) -> Variant:
	if mod() == null:
		return null
	var drag := InventoryDrag.from_mod_slot(gun, path, inventory)
	set_drag_preview(InventoryDragPreview.create(drag))
	queue_redraw()
	return drag


## True if `drag` carries a part that can go in this slot (moving it from another slot of this gun
## counts too).
func accepts(drag: InventoryDrag) -> bool:
	if drag.splitting or drag.item == null or not WeaponMods.is_mod(drag.item.data):
		return false
	if drag.from_gun == gun:
		if drag.from_path == path or path.begins_with(drag.from_path + "/"):
			return false
		return WeaponMods.fits(WeaponMods.platform_of(gun), slot, drag.item.data)
	return WeaponMods.install_block_reason(gun, path, drag.item) == ""


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not data is InventoryDrag:
		return false
	var drag: InventoryDrag = data
	var fits := accepts(drag)
	var hover := 1 if fits else -1
	if hover != _hover:
		_hover = hover
		preview_requested.emit(path, drag.item if fits else null)
		queue_redraw()
	return fits


func _drop_data(_at: Vector2, data: Variant) -> void:
	_hover = 0
	install_requested.emit(path, data)
	queue_redraw()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT) and _hover != 0:
		_hover = 0
		preview_requested.emit(path, null)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.double_click and mod():
		remove_requested.emit(path)
	else:
		selected.emit(path)
	accept_event()


func _get_tooltip(_at: Vector2) -> String:
	var part := mod()
	var kinds: Array = slot.get("kinds", [])
	var takes := ", ".join(kinds.map(func(kind: String) -> String: return WeaponMods.KIND_NAMES.get(kind, kind)))
	if part == null:
		var text := "%s: empty (takes: %s)" % [slot.get("name", path), takes]
		if slot.get("required", false):
			text += "\nThe gun can't fire without one"
		var empty: Dictionary = slot.get("empty", {})
		for key: String in empty:
			text += "\nEmpty: %s %s" % [WeaponStats.MODIFIER_NAMES.get(key, key), WeaponStats.format_modifier(key, float(empty[key]))]
		return text
	var lines := ["%s  (%s)" % [part.data.display_name, Palette.RARITY_NAMES[part.data.rarity]]]
	for line in WeaponStats.modifier_lines(part.data):
		lines.append("%s %s" % [line[0], line[1]])
	lines.append("Drag off or double-click to take it off")
	return "\n".join(lines)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0, 0, 0, 0.4))
	var part := mod()
	if part:
		var lifted: bool = InventoryDrag.current != null and InventoryDrag.current.item == part and get_viewport().gui_is_dragging()
		var footprint := Vector2(part.data.size) * InventoryGridView.CELL
		var fit := minf(minf((size.x - 6.0) / footprint.x, (size.y - 6.0) / footprint.y), 1.0)
		var icon_rect := Rect2((size - footprint * fit) / 2.0, footprint * fit)
		ItemDraw.draw(self, part, icon_rect, false, 0.3 if lifted else 1.0)
	else:
		var required: bool = slot.get("required", false)
		draw_rect(rect.grow(-1.0), REQUIRED_COLOR if required else Color(1, 1, 1, 0.16), false, 1.0)
		var label := str(slot.get("name", path)).to_upper()
		draw_string(get_theme_default_font(), Vector2(0, size.y / 2.0 + 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11,
			Color(REQUIRED_COLOR, 0.9) if required else Color(1, 1, 1, 0.28))
	if is_selected:
		draw_rect(rect.grow(-1.5), SELECTED_COLOR, false, 2.0)
	if _hover != 0:
		var color := OK_COLOR if _hover > 0 else BAD_COLOR
		draw_rect(rect, color)
		draw_rect(rect.grow(-1.5), Color(color, 0.95), false, 3.0)
