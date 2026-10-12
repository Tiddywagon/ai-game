class_name ModPartRow
extends PanelContainer
## A weapon part you own, in the modding screen's parts list (DESIGN.md §12.1): its icon, name in its
## rarity colour with the rarity, what it does (its bonuses grow with rarity) and where it is. Drag it
## onto a slot to fit it; double-click fits it to the best slot. Hovering previews the gun's stats with
## it fitted.

signal hovered(row: ModPartRow)
signal unhovered(row: ModPartRow)
signal fit_requested(row: ModPartRow)

var item: ItemInstance
## The grid it's in, and a name for that place ("Stash", "Backpack").
var grid: InventoryGrid
var inventory: Inventory
var place := ""
## Forwarded drop handling, so a part dragged off the gun can be let go over the list anywhere.
var can_drop: Callable
var dropped: Callable

var _style: StyleBoxFlat


func setup(part: ItemInstance, source: InventoryGrid, owner: Inventory, where: String) -> void:
	item = part
	grid = source
	inventory = owner
	place = where


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 66)
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(1, 1, 1, 0.03)
	_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var icon := PartIcon.new()
	icon.item = item
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var title := Label.new()
	title.text = "%s  ·  %s" % [item.data.display_name, Palette.RARITY_SHORT[item.data.rarity]]
	title.add_theme_color_override("font_color", Palette.rarity_color(item.data.rarity).lightened(0.2))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var effects := Label.new()
	effects.theme_type_variation = &"DimLabel"
	effects.text = summary(item.data)
	effects.add_theme_font_size_override("font_size", 13)
	effects.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(effects)
	var where := Label.new()
	where.theme_type_variation = &"DimLabel"
	where.text = "%s  ·  %s" % [WeaponMods.KIND_NAMES.get(WeaponMods.kind_of(item.data), "Part"), place]
	where.add_theme_font_size_override("font_size", 12)
	where.modulate.a = 0.7
	text.add_child(where)
	mouse_entered.connect(func() -> void:
		_style.bg_color = Color(1, 1, 1, 0.08)
		hovered.emit(self))
	mouse_exited.connect(func() -> void:
		_style.bg_color = Color(1, 1, 1, 0.03)
		unhovered.emit(self))


## "Recoil −10% · Noise −70% · Ergonomics −8", "30 rounds" for magazines, or "Standard part".
static func summary(data: ItemData) -> String:
	var parts: Array[String] = []
	var capacity := WeaponMods.capacity_of(data)
	if capacity > 0:
		parts.append("%d rounds" % capacity)
	var optic := VisionSystem.config.optic(int(data.stats.get("optic", 0))) if data.stats.has("optic") else null
	if optic:
		parts.append(optic.display_name)
	for line in WeaponStats.modifier_lines(data):
		parts.append("%s %s" % [line[0], line[1]])
	var slots: Array = WeaponMods.info(data).get("slots", [])
	if not slots.is_empty():
		parts.append("adds %s" % ", ".join(slots.map(func(slot: Dictionary) -> String: return str(slot.name).to_lower())))
	return "  ·  ".join(parts) if not parts.is_empty() else "Standard part"


func _get_drag_data(_at: Vector2) -> Variant:
	var drag := InventoryDrag.new(item, grid, "", inventory, false)
	set_drag_preview(InventoryDragPreview.create(drag))
	return drag


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return can_drop.is_valid() and can_drop.call(data)


func _drop_data(_at: Vector2, data: Variant) -> void:
	if dropped.is_valid():
		dropped.call(data)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and click.double_click:
		fit_requested.emit(self)
		accept_event()


func _get_tooltip(_at: Vector2) -> String:
	var lines := ["%s  (%s)" % [item.data.display_name, Palette.RARITY_NAMES[item.data.rarity]]]
	if item.data.description != "":
		lines.append(item.data.description)
	for line in WeaponStats.modifier_lines(item.data):
		lines.append("%s %s" % [line[0], line[1]])
	if not WeaponStats.profile_of(item.data).is_empty():
		lines.append("%s: bonuses at %d%% strength" % [Palette.RARITY_NAMES[item.data.rarity], roundi(WeaponStats.rarity_strength(item.data.rarity))])
	lines.append("Drag onto a slot, or double-click to fit it")
	return "\n".join(lines)


## The part's icon, scaled to fit, with its rarity colours.
class PartIcon:
	extends Control

	var item: ItemInstance

	func _init() -> void:
		custom_minimum_size = Vector2(92, 52)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var footprint := Vector2(item.data.size) * InventoryGridView.CELL
		var fit := minf(minf(size.x / footprint.x, size.y / footprint.y), 1.0)
		ItemDraw.draw(self, item, Rect2((size - footprint * fit) / 2.0, footprint * fit), false)
