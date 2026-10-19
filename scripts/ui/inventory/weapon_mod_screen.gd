class_name WeaponModScreen
extends Control
## Weapon modding (DESIGN.md §12.1), out of raid: MODIFY on a gun's examine panel opens it over the
## inventory. Left: the gun's slot tree; a part can add slots of its own (a rail handguard adds a
## foregrip and a tactical slot), shown under it. Right: every part you own (stash, pockets, rig,
## backpack, and inside containers) that fits somewhere on this gun; click a slot to list only the
## parts for it. Drag a part onto a slot to fit it (what was there goes to the stash), drag a part off
## the gun onto the list or double-click it to take it off. In the middle the gun's recoil pattern,
## its spread circles and its stats, with a live preview while you hover a part or drag one over a
## slot: the new pattern and circles over the old, the new values, better in green, worse in red.
## Durability shows there too, with REPAIR (roubles; each repair lowers the max durability). Stats
## include the character's skills (GameState.skills).
## Esc or CLOSE goes back to the inventory.

signal closed

const INDENT := 26.0

var gun: ItemInstance
var inventory: Inventory
var stash: InventoryGrid

var _slots: VBoxContainer
var _parts: VBoxContainer
var _parts_title: Label
var _stats: WeaponStatList
var _pattern: RecoilPatternView
var _spread: SpreadCircleView
var _icon: TextureRect
var _title: Label
var _subtitle: Label
var _money: Label
var _repair: Button
var _message: Label
var _selected_path := ""
var _slot_views: Array[ModSlotView] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.045, 0.05, 0.055)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)
	_build_header(rows)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	_build_slot_column(columns)
	_build_stats_column(columns)
	_build_parts_column(columns)
	_message = Label.new()
	_message.theme_type_variation = &"DimLabel"
	_message.text = "Drag parts onto the slots. Drag a part off the gun (or double-click it) to take it off. Hover a part to preview its stats."
	rows.add_child(_message)
	refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_inventory") or event.is_action_pressed("pause"):
		if not get_viewport().gui_is_dragging():
			close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


## Rebuilds everything from the gun as it is now.
func refresh() -> void:
	_title.text = "MODDING  ·  %s" % gun.data.display_name.to_upper()
	_title.add_theme_color_override("font_color", Palette.rarity_color(gun.data.rarity).lightened(0.25))
	var missing := WeaponMods.missing_part(gun)
	_subtitle.text = "%s  ·  %d parts  ·  %s  ·  %s" % [Palette.RARITY_NAMES[gun.data.rarity], WeaponMods.installed(gun).size(),
		Settings.format_weight(gun.weight_without_rounds()), UiFormat.money(gun.value())]
	if missing != "":
		_subtitle.text += "  ·  CAN'T FIRE: NO %s" % missing.to_upper()
	_money.text = UiFormat.money(GameState.roubles)
	_icon.texture = gun.data.get_icon()
	_build_slots()
	_build_parts()
	_show_stats()
	_update_repair()


# --- Actions ------------------------------------------------------------------------------------

## Fits the part `drag` carries to the slot at `path`. What was in the slot goes to the stash (or, when
## the part came off another slot of this gun, into that slot if it fits there). Returns "" or why not.
func install(path: String, drag: InventoryDrag) -> String:
	var view := _slot_view(path)
	if view == null or not view.accepts(drag):
		return _say("That part doesn't fit there.")
	var part := drag.item
	var old_cell := part.cell
	var old_turned := part.rotated
	drag.take()
	var replaced := WeaponMods.install(gun, path, part)
	if replaced:
		var swapped := drag.from_gun == gun and WeaponMods.install_block_reason(gun, drag.from_path, replaced) == ""
		if swapped:
			WeaponMods.install(gun, drag.from_path, replaced)
		elif not _stow(replaced):
			# Nowhere to put what came off: undo.
			WeaponMods.install(gun, path, replaced)
			if drag.from_gun == gun:
				WeaponMods.install(gun, drag.from_path, part)
			else:
				drag.from_grid.place(part, old_cell, old_turned)
			return _say("No room in the stash for the %s." % replaced.data.display_name)
	_after_change()
	return _say("Fitted the %s (%s)." % [part.data.display_name, str(WeaponMods.slot_at(gun, path).get("name", path)).to_lower()], true)


## Takes the part in slot `path` off (with whatever is on it) and puts it in the stash. "" or why not.
func remove(path: String) -> String:
	var part := WeaponMods.uninstall(gun, path)
	if part == null:
		return ""
	if not _stow(part):
		WeaponMods.install(gun, path, part)
		return _say("No room in the stash for the %s." % part.data.display_name)
	_after_change()
	return _say("Took off the %s: it's in the stash." % part.data.display_name, true)


## Repairs the gun to its max durability for roubles. "" or why not.
func repair() -> String:
	var price := WeaponStats.repair_price(gun)
	if price <= 0:
		return _say("Already at full durability.")
	if GameState.roubles < price:
		return _say("Not enough roubles to repair (%s)." % UiFormat.money(price))
	GameState.roubles -= price
	WeaponStats.repair(gun)
	_after_change()
	return _say("Repaired for %s. Max durability is now %.1f." % [UiFormat.money(price), gun.max_durability], true)


## Every loose part you own that fits somewhere on the gun (or in `path`, if given):
## [{"item", "grid", "place"}], in slot order, rarer first.
func parts(path := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var places: Array = []
	if stash:
		places.append([stash, "Stash"])
	for grid in inventory.grids():
		places.append([grid, _grid_name(grid)])
	while not places.is_empty():
		var entry: Array = places.pop_front()
		var grid: InventoryGrid = entry[0]
		for item in grid.items:
			if item.contents:
				places.append([item.contents, "%s (%s)" % [item.data.display_name, entry[1]]])
			if item == gun or not WeaponMods.is_mod(item.data):
				continue
			var fits := WeaponMods.install_block_reason(gun, path, item) == "" if path != "" \
				else not WeaponMods.compatible_paths(gun, item).is_empty()
			if fits:
				result.append({"item": item, "grid": grid, "place": entry[1]})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var kind_a := WeaponMods.KINDS.find(WeaponMods.kind_of(a.item.data))
		var kind_b := WeaponMods.KINDS.find(WeaponMods.kind_of(b.item.data))
		if kind_a != kind_b:
			return kind_a < kind_b
		if a.item.data.rarity != b.item.data.rarity:
			return a.item.data.rarity > b.item.data.rarity
		return a.item.data.display_name < b.item.data.display_name)
	return result


## Lists only the parts for slot `path` ("" or the same slot again: every part that fits).
func select_slot(path: String) -> void:
	_selected_path = "" if path == _selected_path else path
	for view in _slot_views:
		view.is_selected = view.path == _selected_path
	_build_parts()


# --- Preview ------------------------------------------------------------------------------------

## The stats with `part` fitted to `path` (a copy of it: nothing changes), or without what's in
## `path` when `part` is null. `from_path`: where on this gun the part comes from, if it's on it.
func preview(path: String, part: ItemInstance, from_path := "") -> void:
	if path == "":
		_show_stats()
		return
	var copy := gun.duplicate_deep()
	if part == null:
		WeaponMods.uninstall(copy, path)
	else:
		if from_path != "":
			WeaponMods.uninstall(copy, from_path)
		WeaponMods.install(copy, path, part.duplicate_deep())
	_show_stats(copy)


## The stats, recoil pattern and spread circles of the gun, and with `changed` (a copy with the
## change being previewed) the change too.
func _show_stats(changed: ItemInstance = null) -> void:
	var skills := GameState.skills
	var now := WeaponStats.build(gun, skills)
	var then := WeaponStats.build(changed, skills) if changed else null
	var preview_rows: Array[Dictionary] = []
	if changed:
		preview_rows = WeaponStats.rows(changed, skills)
	_stats.show_rows(WeaponStats.rows(gun, skills), preview_rows)
	_pattern.show_builds(now, then)
	_spread.show_builds(now, then, gun.durability)


func _on_slot_preview(path: String, part: ItemInstance) -> void:
	var drag := InventoryDrag.current
	if part == null:
		_show_stats()
	else:
		preview(path, part, drag.from_path if drag and drag.from_gun == gun else "")


func _on_part_hovered(row: ModPartRow) -> void:
	if get_viewport().gui_is_dragging():
		return
	var path := _selected_path if _selected_path != "" else WeaponMods.slot_for(gun, row.item)
	preview(path, row.item)


func _on_part_unhovered(_row: ModPartRow) -> void:
	if not get_viewport().gui_is_dragging():
		_show_stats()


# --- Parts list drops: taking a part off ---------------------------------------------------------

func _list_can_drop(data: Variant) -> bool:
	var drag := data as InventoryDrag
	if drag == null or drag.from_gun != gun:
		return false
	preview(drag.from_path, null)
	return true


func _list_dropped(data: Variant) -> void:
	var drag: InventoryDrag = data
	remove(drag.from_path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_node_ready():
		_show_stats()


# --- Building -----------------------------------------------------------------------------------

func _build_header(parent: Control) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	parent.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(150, 60)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_icon)
	header.move_child(_icon, 0)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	titles.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"DimLabel"
	titles.add_child(_subtitle)
	_money = Label.new()
	_money.theme_type_variation = &"AccentLabel"
	_money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_money)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(130, 40)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	header.add_child(close_button)
	parent.add_child(HSeparator.new())


func _build_slot_column(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 560
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	var heading := Label.new()
	heading.theme_type_variation = &"AccentLabel"
	heading.text = "SLOTS"
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_slots = VBoxContainer.new()
	_slots.name = "Slots"
	_slots.add_theme_constant_override("separation", 6)
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slots)


func _build_stats_column(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var previews := HBoxContainer.new()
	previews.add_theme_constant_override("separation", 16)
	column.add_child(previews)
	_pattern = RecoilPatternView.new()
	_pattern.name = "RecoilPattern"
	_pattern.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	previews.add_child(_pattern)
	_spread = SpreadCircleView.new()
	_spread.name = "SpreadCircles"
	_spread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	previews.add_child(_spread)
	var heading := Label.new()
	heading.theme_type_variation = &"AccentLabel"
	heading.text = "STATS"
	column.add_child(heading)
	_stats = WeaponStatList.new()
	_stats.name = "Stats"
	column.add_child(_stats)
	column.add_child(HSeparator.new())
	_repair = Button.new()
	_repair.name = "RepairButton"
	_repair.custom_minimum_size = Vector2(0, 40)
	_repair.pressed.connect(repair)
	column.add_child(_repair)


func _build_parts_column(parent: Control) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 540
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	_parts_title = Label.new()
	_parts_title.theme_type_variation = &"AccentLabel"
	column.add_child(_parts_title)
	var area := DropPanel.new()
	area.name = "PartsArea"
	area.can_drop = _list_can_drop
	area.dropped = _list_dropped
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(area)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	area.add_child(scroll)
	_parts = VBoxContainer.new()
	_parts.name = "Parts"
	_parts.add_theme_constant_override("separation", 4)
	_parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(_parts)


func _build_slots() -> void:
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	_slot_views.clear()
	if WeaponMods.slots_of(gun).is_empty():
		var none := Label.new()
		none.theme_type_variation = &"DimLabel"
		none.text = "No slots: nothing fits this gun."
		_slots.add_child(none)
	for entry in WeaponMods.walk(gun):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_slots.add_child(row)
		var indent := Label.new()
		indent.custom_minimum_size.x = INDENT * entry.depth
		indent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		indent.text = "└" if entry.depth > 0 else ""
		indent.theme_type_variation = &"DimLabel"
		row.add_child(indent)
		var name_label := Label.new()
		name_label.custom_minimum_size.x = 112
		name_label.theme_type_variation = &"DimLabel"
		name_label.text = str(entry.slot.get("name", entry.path))
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_label)
		var view := ModSlotView.new()
		view.name = "Slot_" + str(entry.path).replace("/", "_")
		view.setup(gun, entry.path, inventory)
		view.is_selected = entry.path == _selected_path
		view.selected.connect(select_slot)
		view.preview_requested.connect(_on_slot_preview)
		view.install_requested.connect(install)
		view.remove_requested.connect(remove)
		row.add_child(view)
		_slot_views.append(view)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var part: ItemInstance = entry.mod
		var title := Label.new()
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var effects := Label.new()
		effects.theme_type_variation = &"DimLabel"
		effects.add_theme_font_size_override("font_size", 12)
		effects.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if part:
			title.text = part.data.display_name
			title.add_theme_color_override("font_color", Palette.rarity_color(part.data.rarity).lightened(0.2))
			effects.text = ModPartRow.summary(part.data)
		else:
			title.text = "Empty"
			title.theme_type_variation = &"DimLabel"
			var empty: Dictionary = entry.slot.get("empty", {})
			var notes: Array[String] = []
			if entry.slot.get("required", false):
				notes.append("needed to fire")
			for key: String in empty:
				notes.append("%s %s" % [WeaponStats.MODIFIER_NAMES.get(key, key), WeaponStats.format_modifier(key, float(empty[key]))])
			effects.text = "  ·  ".join(notes)
		info.add_child(title)
		info.add_child(effects)


func _build_parts() -> void:
	for child in _parts.get_children():
		_parts.remove_child(child)
		child.queue_free()
	var found := parts(_selected_path)
	if _selected_path != "":
		_parts_title.text = "PARTS FOR %s  ·  %d" % [str(WeaponMods.slot_at(gun, _selected_path).get("name", _selected_path)).to_upper(), found.size()]
	else:
		_parts_title.text = "PARTS THAT FIT  ·  %d" % found.size()
	for entry in found:
		var row := ModPartRow.new()
		row.setup(entry.item, entry.grid, inventory, entry.place)
		row.can_drop = _list_can_drop
		row.dropped = _list_dropped
		row.hovered.connect(_on_part_hovered)
		row.unhovered.connect(_on_part_unhovered)
		row.fit_requested.connect(_fit_row)
		_parts.add_child(row)
	if found.is_empty():
		var note := Label.new()
		note.theme_type_variation = &"DimLabel"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 500
		note.text = "No parts you own fit %s. Tinker sells them; weapon boxes and duffle bags hold them, and guns you find carry theirs." \
			% ("this slot" if _selected_path != "" else "this gun")
		if WeaponMods.slots_of(gun).is_empty():
			note.text = "This gun takes no parts."  # A junk gun (the sawn-off, the revolver).
		_parts.add_child(note)


func _update_repair() -> void:
	var price := WeaponStats.repair_price(gun)
	if price <= 0:
		_repair.text = "DURABILITY %.1f / %.1f  ·  NO REPAIR NEEDED" % [gun.durability, gun.max_durability]
		_repair.disabled = true
		_repair.tooltip_text = ""
		return
	_repair.text = "REPAIR  ·  %s" % UiFormat.money(price)
	_repair.disabled = GameState.roubles < price
	_repair.tooltip_text = "Back to %.1f durability. Max durability drops to %.1f (each repair wears the gun a little)." \
		% [gun.max_durability, WeaponStats.max_after_repair(gun)]


func _fit_row(row: ModPartRow) -> void:
	var path := _selected_path if _selected_path != "" and WeaponMods.install_block_reason(gun, _selected_path, row.item) == "" \
		else WeaponMods.slot_for(gun, row.item)
	if path != "":
		install(path, InventoryDrag.new(row.item, row.grid, "", inventory, false))


## After the gun changed: rounds that no longer fit the magazine go to the stash, and everything
## that shows the gun or the stash redraws.
func _after_change() -> void:
	for rounds in gun.trim_magazine(WeaponMods.capacity(gun)):
		if not _stow(rounds):
			gun.load_rounds(rounds)  # Nowhere to put them: they stay loaded.
	if _selected_path != "" and WeaponMods.slot_at(gun, _selected_path).is_empty():
		_selected_path = ""  # The part with that slot came off.
	if stash:
		stash.changed.emit()
	inventory.changed.emit()
	refresh()


## Puts `item` in the stash, else anywhere on the character. False if there's no room.
func _stow(item: ItemInstance) -> bool:
	return (stash != null and stash.add(item)) or inventory.add(item)


func _slot_view(path: String) -> ModSlotView:
	for view in _slot_views:
		if view.path == path:
			return view
	return null


func _say(text: String, ok := false) -> String:
	_message.text = text
	_message.add_theme_color_override("font_color", Color(0.85, 0.85, 0.78) if ok else Color(0.95, 0.62, 0.45))
	return "" if ok else text


func _grid_name(grid: InventoryGrid) -> String:
	match grid.kind:
		&"pockets":
			return "Pockets"
		&"rig":
			return "Rig"
		&"backpack":
			return "Backpack"
		&"secure":
			return "Secure container"
	return grid.owner_item().data.display_name if grid.owner_item() else "Stash"


## A panel that hands drops to the screen (the parts list: let go of a part dragged off the gun).
class DropPanel:
	extends PanelContainer

	var can_drop: Callable
	var dropped: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.25)
		style.border_color = Color(1, 1, 1, 0.08)
		style.set_border_width_all(1)
		style.set_content_margin_all(8)
		add_theme_stylebox_override("panel", style)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return can_drop.call(data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		dropped.call(data)
