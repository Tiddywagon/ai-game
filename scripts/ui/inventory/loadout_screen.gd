class_name LoadoutScreen
extends InventoryScreen
## LOADOUT (DESIGN.md §16.6): your character and the stash side by side, out of raid. Opened from the
## main menu (LOADOUT), from CHARACTER (LOADOUT or Tab) and from the raid setup's loadout check (EDIT
## LOADOUT, so you can change your gear before every raid). It is the inventory screen out of raid and
## extends it: drag and drop, quick move (Ctrl-click, X), examine, modding, upgrades, containers' windows,
## the stash's filter bar (search, category, rarity, FIR only, sort), the controller cursor and touch
## gestures all work as there, and dropping an item on a filled slot swaps the two.
##
## Left: every equipment slot (helmet, headset, face cover, body armor, rig, backpack, secure container,
## primary, secondary, pistol, melee) and under them the total stats (LoadoutStats: armor per body part,
## weight, carry limit and storage, the gun in hand's ergonomics and recoil, hearing), kept up to date as
## you change things. Then the pockets and the grids of the worn rig, backpack and secure container; the
## presets (LoadoutPresets: up to five named loadouts to save, overwrite, rename, delete and LOAD, which
## dresses you from the stash and says what was missing); and the stash on the right. Hovering a stash
## item you could wear (or landing the controller cursor on it, or dragging it) shows a comparison with
## what you wear in its slot (GearCompare), beside the stash: green ▲ better, red ▼ worse. The space under
## the presets (%AutoEquip) is kept for automatic equipping. Closing saves.

## The slots: columns of rows of [slot, size in cells].
const SLOT_LAYOUT := [
	[[["helmet", Vector2i(2, 2)]], [["headset", Vector2i(2, 1)]], [["face_cover", Vector2i(2, 1)]], [["armor", Vector2i(2, 2)]]],
	[[["rig", Vector2i(2, 2)]], [["backpack", Vector2i(2, 2)]], [["secure", Vector2i(2, 2)]]],
	[[["primary", Vector2i(5, 2)]], [["secondary", Vector2i(5, 2)]], [["pistol", Vector2i(3, 2)], ["melee", Vector2i(2, 2)]]],
]
## Pixels per cell of the pockets' and worn containers' grids here (smaller than the stash's).
const CONTAINER_CELL := 40.0
const STAT_FONT_SIZE := 15
const COMPARE_FONT_SIZE := 15
const COMPARE_WIDTH := 560.0
const DIM_COLOR := Color(1, 1, 1, 0.35)
const LOADOUT_HINTS := [
	"Drag to move or onto a filled slot to swap  ·  Hover a stash item: compare  ·  R: turn  ·  Right-click: examine  ·  Ctrl-click: quick move  ·  Double-click: open",
	"D-pad or left stick: move the cursor (on a stash item: compare)  ·  The buttons below pick up, turn, quick-move and examine",
	"Drag to move or onto a filled slot to swap  ·  Long-press: examine  ·  Double-tap: open  ·  Pinch the stash: zoom",
]

## The preset picked in the list (-1 for none).
var selected_preset := -1
## The stash item compared now (null: the panel is hidden).
var compared: ItemInstance

var _compare_panel: PanelContainer
var _compare_dirty := false
## The presets list's toggles share it (one picked at a time).
var _preset_group := ButtonGroup.new()
## close() ran (it saves); freed without it (the screen under it closing), the screen saves as it goes.
var _closed := false
## What the mouse, cursor or drag was on last frame: the comparison follows it when it changes.
var _hover_target: ItemInstance
## Where the mouse last was (from its events, in this viewport).
var _mouse_at := Vector2(-1, -1)


func _ready() -> void:
	if inventory == null:
		inventory = GameState.inventory
	if stash == null:
		stash = GameState.stash
	grid_cell = CONTAINER_CELL
	super()
	inventory.changed.connect(_on_loadout_changed)
	_build_compare_panel()
	%SaveNewButton.pressed.connect(save_new_preset)
	%LoadButton.pressed.connect(load_preset)
	%OverwriteButton.pressed.connect(overwrite_preset)
	%RenameButton.pressed.connect(rename_preset)
	%DeleteButton.pressed.connect(delete_preset)
	%PresetName.text_submitted.connect(func(_text: String) -> void: (%PresetName as LineEdit).release_focus())
	for control: Control in [%PresetName, %SaveNewButton, %LoadButton, %OverwriteButton, %RenameButton, %DeleteButton]:
		control.add_to_group(GridCursor.CURSOR_GROUP)
	refresh_stats()
	refresh_presets()


func _update_hint(device: int) -> void:
	%Hint.text = LOADOUT_HINTS[device] if device >= 0 and device < LOADOUT_HINTS.size() else LOADOUT_HINTS[0]
	%CloseButton.text = "CLOSE  (%s)" % Settings.key_label("toggle_inventory")


## Closing saves (what you moved, swapped or loaded).
func close() -> void:
	_closed = true
	SaveManager.save_game()
	super()


## Freed without close() (the screen it's over closed, the game quit): it still saves.
func _exit_tree() -> void:
	super()
	if not _closed and GameState.faction != GameState.Faction.NONE:
		_closed = true
		SaveManager.save_game()


## The cursor stays off the grids while the preset name box has the keys.
func cursor_allowed() -> bool:
	return super() and not (%PresetName as LineEdit).has_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_at = (event as InputEventMouse).position
	var box: LineEdit = %PresetName
	if box.has_focus():
		# Typing a name: the keys are the box's (no hotkeys, no R, Tab doesn't close); Esc / B leaves it,
		# a click anywhere else lets go of it.
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			box.release_focus()
			get_viewport().set_input_as_handled()
			return
		var click := event as InputEventMouseButton
		if click and click.pressed and not box.get_global_rect().has_point(click.position):
			box.release_focus()
		else:
			return
	super(event)


func _process(delta: float) -> void:
	super(delta)
	var target := _compare_target()
	if target != _hover_target:
		_hover_target = target
		compare_item(target)
	elif _compare_dirty:
		compare_item(compared)
	_place_compare()


func _on_loadout_changed() -> void:
	refresh_stats()
	_compare_dirty = true


# --- Slots ----------------------------------------------------------------------------------------

func _build_equipment() -> void:
	for column in SLOT_LAYOUT:
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		%Equipment.add_child(rows)
		for line in column:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			rows.add_child(row)
			for entry in line:
				var slot: String = entry[0]
				var box := VBoxContainer.new()
				box.add_theme_constant_override("separation", 2)
				row.add_child(box)
				var label := Label.new()
				label.theme_type_variation = &"DimLabel"
				label.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
				label.text = _slot_name(slot)
				box.add_child(label)
				var view := EquipmentSlotView.new()
				view.name = "Slot_" + slot
				view.setup(inventory, slot, _slot_name(slot), entry[1])
				view.examine_requested.connect(_examine_item)
				view.open_requested.connect(_open_window)
				view.quick_move_requested.connect(quick_move)
				box.add_child(view)


# --- Total stats ----------------------------------------------------------------------------------

## Rebuilds the total stats from what you wear now (LoadoutStats.rows()).
func refresh_stats() -> void:
	var grid: GridContainer = %Stats
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for row in LoadoutStats.rows(inventory, _config, GameState.skills):
		var name := Label.new()
		name.name = "StatName_" + str(row.key)
		name.theme_type_variation = &"DimLabel"
		name.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
		name.text = row.name
		grid.add_child(name)
		var value := Label.new()
		value.name = "Stat_" + str(row.key)
		value.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
		value.text = row.text
		value.clip_text = true
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.custom_minimum_size.x = 380
		value.tooltip_text = row.text
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		match str(row.tone):
			"dim":
				value.add_theme_color_override("font_color", DIM_COLOR)
			"heavy":
				value.add_theme_color_override("font_color", HEAVY_COLOR)
			"over":
				value.add_theme_color_override("font_color", OVERWEIGHT_COLOR)
		grid.add_child(value)


## The text of total stat `key` ("thorax", "weight", "ergonomics"...), for tests and tools.
func stat_text(key: String) -> String:
	var label := (%Stats as GridContainer).get_node_or_null("Stat_" + key) as Label
	return label.text if label else ""


# --- Comparison -----------------------------------------------------------------------------------

## What to compare now: the stash item being dragged (while it's over the stash: off it the panel gets
## out of the way of where it's going), else the one under the controller cursor or the mouse, if it's
## gear you could wear; null for none.
func _compare_target() -> ItemInstance:
	var item: ItemInstance = null
	if get_viewport().gui_is_dragging() and InventoryDrag.current:
		var point := cursor.at if cursor and cursor.active else _mouse_at
		if (%StashPanel as Control).get_global_rect().has_point(point):
			item = InventoryDrag.current.item
	elif cursor and cursor.active:
		item = cursor.item_under_cursor()
	else:
		var view := get_viewport().gui_get_hovered_control() as InventoryGridView
		if view and view.grid:
			item = view.item_at_position(view.get_global_transform().affine_inverse() * _mouse_at)
	if item == null or not stash.find_holder(item) or GearCompare.slot_for(item, inventory) == "":
		return null
	return item


func _build_compare_panel() -> void:
	_compare_panel = PanelContainer.new()
	_compare_panel.name = "ComparePanel"
	_compare_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compare_panel.custom_minimum_size.x = COMPARE_WIDTH
	_compare_panel.hide()
	%Overlay.add_child(_compare_panel)


## Shows the comparison of `item` (a stash item) with what you wear in its slot; null hides it.
func compare_item(item: ItemInstance) -> void:
	compared = item
	_compare_dirty = false
	for child in _compare_panel.get_children():
		_compare_panel.remove_child(child)
		child.queue_free()
	var result := GearCompare.compare(item, inventory) if item and stash.find_holder(item) else {}
	if result.is_empty():
		compared = null
		_compare_panel.hide()
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.06, 1.0)
	style.border_color = Palette.rarity_color(item.data.rarity)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	_compare_panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compare_panel.add_child(rows)
	var title := Label.new()
	title.name = "CompareTitle"
	title.theme_type_variation = &"AccentLabel"
	title.text = "COMPARE  ·  %s" % str(result.slot_name).to_upper()
	rows.add_child(title)
	var current: ItemInstance = result.current
	if current == null:
		current = result.against  # Body armor under your armored rig: what protects you there now.
	var line := Label.new()
	line.name = "CompareLine"
	line.text = "%s  vs  %s" % [item.title(), current.title() if current else "nothing worn"]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = COMPARE_WIDTH - 28.0
	rows.add_child(line)
	if str(result.note) != "":
		var note := Label.new()
		note.name = "CompareNote"
		note.text = result.note
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = COMPARE_WIDTH - 28.0
		note.add_theme_color_override("font_color", HEAVY_COLOR)
		rows.add_child(note)
	var grid := GridContainer.new()
	grid.name = "CompareRows"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Never in the way of a drop.
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	rows.add_child(grid)
	for text in ["", "Worn now", "This one", ""]:
		grid.add_child(_compare_label(text, "", DIM_COLOR))
	for row: Dictionary in result.rows:
		var change := int(row.change)
		var color := WeaponStatList.BETTER_COLOR if change > 0 else (WeaponStatList.WORSE_COLOR if change < 0 else Color.WHITE)
		grid.add_child(_compare_label(str(row.name), "Name_" + str(row.key), DIM_COLOR))
		grid.add_child(_compare_label(str(row.now), "Now_" + str(row.key), Color.WHITE))
		grid.add_child(_compare_label(str(row.new), "New_" + str(row.key), color))
		var delta := str(row.delta)
		if delta != "" and change != 0:
			delta = ("▲ " if change > 0 else "▼ ") + delta
		grid.add_child(_compare_label(delta, "Delta_" + str(row.key), color))
	_compare_panel.reset_size()
	_compare_panel.show()
	_place_compare()


func _compare_label(text: String, node_name: String, color: Color) -> Label:
	var label := Label.new()
	if node_name != "":
		label.name = node_name
	label.text = text
	label.add_theme_font_size_override("font_size", COMPARE_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label


## Keeps the comparison beside the stash, level with the mouse (or the cursor), on screen and never
## over the presets (their list, buttons and message line): it stays below them, and when there's no
## room for it there, it goes left of the presets column instead.
func _place_compare() -> void:
	if not _compare_panel.visible:
		return
	var stash_rect := (%StashPanel as Control).get_global_rect()
	var at_y := _mouse_at.y
	if cursor and cursor.active and not cursor.target.is_empty():
		at_y = cursor.at.y
	var panel_size := _compare_panel.get_combined_minimum_size()
	var lowest := maxf(size.y - panel_size.y - 12.0, stash_rect.position.y)
	var below_presets := _presets_bottom() + 10.0
	var left := stash_rect.position.x - panel_size.x - 10.0
	var top := clampf(at_y - 40.0, maxf(stash_rect.position.y, below_presets), maxf(lowest, below_presets))
	if top > lowest:
		left = (%SidePanel as Control).get_global_rect().position.x - panel_size.x - 10.0
		top = clampf(at_y - 40.0, stash_rect.position.y, lowest)
	_compare_panel.position = Vector2(left, top)


## The lowest edge of what's in the presets column (the message line, or the automatic equipping
## space once it shows), in screen pixels.
func _presets_bottom() -> float:
	var bottom := 0.0
	for child in (%PresetMessage as Control).get_parent().get_children():
		if child is Control and (child as Control).visible:
			bottom = maxf(bottom, (child as Control).get_global_rect().end.y)
	return bottom


## The label of comparison row `key` in `column` ("Name", "Now", "New", "Delta"), or null.
func compare_label(column: String, key: String) -> Label:
	if not _compare_panel.visible:
		return null
	return _compare_panel.find_child("%s_%s" % [column, key], true, false) as Label


# --- Presets --------------------------------------------------------------------------------------

## Brings the presets list (one toggle button each: its name and what it holds) and the buttons up to
## date. The buttons are updated in place (only the difference is added or removed), so the one the
## controller cursor is on stays when you pick it.
func refresh_presets() -> void:
	var list: VBoxContainer = %PresetList
	var presets := LoadoutPresets.all()
	selected_preset = selected_preset if selected_preset < presets.size() else -1
	var buttons: Array[Button] = []
	for child in list.get_children():
		if child is Button and buttons.size() < presets.size():
			buttons.append(child)
		else:
			list.remove_child(child)
			child.queue_free()
	for i in presets.size():
		var preset: Dictionary = presets[i]
		var button: Button = buttons[i] if i < buttons.size() else _new_preset_button(i)
		button.text = "%s\n%s" % [str(preset.name), LoadoutPresets.summary(preset)]
		button.tooltip_text = button.text
		button.set_pressed_no_signal(i == selected_preset)
	if presets.is_empty():
		var note := Label.new()
		note.name = "NoPresets"
		note.theme_type_variation = &"DimLabel"
		note.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 276
		note.text = "No presets yet. Name what you wear and SAVE NEW; LOAD puts it back on from the stash."
		list.add_child(note)
	%PresetsTitle.text = "PRESETS  ·  %d / %d" % [presets.size(), LoadoutPresets.MAX]
	%SaveNewButton.disabled = presets.size() >= LoadoutPresets.MAX
	%SaveNewButton.tooltip_text = "%d presets already: overwrite or delete one" % LoadoutPresets.MAX if presets.size() >= LoadoutPresets.MAX \
		else "Save what you wear and carry as a new preset"
	for button: Button in [%LoadButton, %OverwriteButton, %RenameButton, %DeleteButton]:
		button.disabled = selected_preset < 0
	%LoadButton.tooltip_text = "Put the preset on from the stash (what you wear now goes to the stash first)"
	%OverwriteButton.tooltip_text = "Save what you wear now over the preset"
	%RenameButton.tooltip_text = "Rename the preset to what's in the name box"


## The toggle for preset `index`, added to the end of the list.
func _new_preset_button(index: int) -> Button:
	var button := Button.new()
	button.name = "Preset_%d" % index
	button.toggle_mode = true
	button.button_group = _preset_group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.clip_text = true
	button.custom_minimum_size = Vector2(276, 50)
	button.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	button.pressed.connect(select_preset.bind(index))
	button.add_to_group(GridCursor.CURSOR_GROUP)
	%PresetList.add_child(button)
	return button


## Picks preset `index` (its name goes in the name box, for RENAME).
func select_preset(index: int) -> void:
	selected_preset = index
	if index >= 0 and index < LoadoutPresets.all().size():
		%PresetName.text = str(LoadoutPresets.all()[index].name)
	refresh_presets()


## SAVE NEW: what you wear and carry, as a new preset named from the name box. Saves the game.
func save_new_preset() -> bool:
	var reason := LoadoutPresets.add(%PresetName.text, inventory)
	if reason != "":
		_preset_message(reason, true)
		return false
	selected_preset = LoadoutPresets.all().size() - 1
	_preset_message("Saved %s." % str(LoadoutPresets.all()[selected_preset].name), false)
	SaveManager.save_game()
	refresh_presets()
	return true


## LOAD: dresses you from the stash (LoadoutPresets.apply()), says what was missing, saves the game.
func load_preset() -> Dictionary:
	if selected_preset < 0:
		return {}
	var result := LoadoutPresets.apply(LoadoutPresets.all()[selected_preset], inventory, stash)
	_preset_message(str(result.message), not result.ok or not result.missing.is_empty() or not result.no_room.is_empty())
	if result.ok:
		SaveManager.save_game()
	_on_gear_changed()
	return result


func overwrite_preset() -> bool:
	if LoadoutPresets.overwrite(selected_preset, inventory) != "":
		return false
	_preset_message("Saved what you wear as %s." % str(LoadoutPresets.all()[selected_preset].name), false)
	SaveManager.save_game()
	refresh_presets()
	return true


func rename_preset() -> bool:
	var reason := LoadoutPresets.rename(selected_preset, %PresetName.text)
	if reason != "":
		_preset_message(reason, true)
		return false
	_preset_message("Renamed to %s." % str(LoadoutPresets.all()[selected_preset].name), false)
	SaveManager.save_game()
	refresh_presets()
	return true


func delete_preset() -> bool:
	if selected_preset < 0:
		return false
	var name := str(LoadoutPresets.all()[selected_preset].name)
	LoadoutPresets.remove(selected_preset)
	selected_preset = -1
	%PresetName.text = ""
	_preset_message("Deleted %s." % name, false)
	SaveManager.save_game()
	refresh_presets()
	return true


func _preset_message(text: String, warning: bool) -> void:
	%PresetMessage.text = text
	if warning:
		%PresetMessage.add_theme_color_override("font_color", HEAVY_COLOR)
	else:
		%PresetMessage.remove_theme_color_override("font_color")


## After a preset loaded: every grid redraws, the containers follow the rig and backpack now worn.
func _on_gear_changed() -> void:
	for grid in inventory.grids():
		grid.changed.emit()
	stash.changed.emit()
	inventory.changed.emit()
	_build_containers()
