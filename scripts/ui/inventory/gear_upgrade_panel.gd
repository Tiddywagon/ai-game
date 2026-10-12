class_name GearUpgradePanel
extends PanelContainer
## The upgrade dialog for one piece of gear (DESIGN.md §12.2), opened with UPGRADE in the examine panel
## out of raid: its level, and a row per place that can upgrade it (the Workbench, Ragman) with what the
## next level changes, the cost and UPGRADE. Esc or CLOSE hides it.

signal closed
## An upgrade went through (the inventory redraws).
signal upgraded(item: ItemInstance)

var item: ItemInstance

var _rows: VBoxContainer


func _ready() -> void:
	name = "GearUpgradePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(900, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.065, 0.07, 0.98)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	style.set_content_margin_all(22)
	add_theme_stylebox_override("panel", style)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	add_child(_rows)
	hide()


func show_item(upgrade_item: ItemInstance) -> void:
	item = upgrade_item
	_build()
	show()
	_fit.call_deferred()


func close() -> void:
	hide()
	closed.emit()


func _build() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "UPGRADE  ·  %s" % item.title()
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Palette.rarity_color(item.data.rarity).lightened(0.2))
	_rows.add_child(title)
	var max_level := GearUpgrades.max_level(item.data)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Level +%d of +%d: %s gear goes up to +%d. Each level costs roubles and barter items; the Workbench charges less money, Ragman needs no hideout. How far each can go depends on the Workbench's level or your loyalty with Ragman." % [
		item.upgrade_level, max_level, Palette.RARITY_NAMES[item.data.rarity], max_level]
	_rows.add_child(note)
	_rows.add_child(HSeparator.new())
	for source in GearUpgrades.sources():
		var row := GearUpgradeRow.create(item, source, false)
		row.upgraded.connect(_on_upgraded)
		_rows.add_child(row)
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(140, 40)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	_rows.add_child(close_button)


func _on_upgraded(upgraded_item: ItemInstance) -> void:
	upgraded.emit(upgraded_item)
	_build()
	_fit.call_deferred()


func _fit() -> void:
	reset_size()
	position = ((get_parent_area_size() - size) / 2.0).round()
