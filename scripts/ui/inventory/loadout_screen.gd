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
## what you wear in its slot (GearCompare), beside the stash: green ▲ better, red ▼ worse. Under the
## presets, AUTO-EQUIP (%AutoEquip) puts on the best you own from the stash (LoadoutPlanner), within a
## budget per item and optionally leaving Legendary items alone (both kept in the profile:
## GameState.auto_equip), then shows a summary of every change with UNDO (reverses exactly what it did,
## LoadoutPlanner.undo()) and OK. Closing saves; so do AUTO-EQUIP and UNDO.
##
## Two tabs: LOADOUT (all of the above) and QUICK BUY (QuickBuyTab: whole loadouts bought from the
## traders in one go). Q / E or LB / RB switch them, through _unhandled_input(), and do nothing while a
## text box or the filter bar has the keys, an item is being dragged, or the examine panel, the modding
## screen, a container window or any dialog is open (tabs_allowed()).

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
const SUMMARY_WIDTH := 860.0
## The summary's list of changes scrolls past this share of the screen's height.
const SUMMARY_MAX_HEIGHT := 0.6
const DIM_COLOR := Color(1, 1, 1, 0.35)
## The energy and water line's width here (narrower than in a raid: the tabs need the room).
const TAB_STATUS_WIDTH := 340.0
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
## The plan the last AUTO-EQUIP made, while its summary is open (UNDO takes it back); {} once closed.
var auto_plan: Dictionary = {}
## The auto-equip summary (a modal panel over the screen: the mouse, the keys and the focus stay in it) and
## the shade behind it.
var _summary_shade: ColorRect
var _summary: PanelContainer
## The QUICK BUY tab, and the tab shown (0: LOADOUT, 1: QUICK BUY).
var quick_buy: QuickBuyTab
var tab := 0
var _tab_buttons: Array[Button] = []


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
	%AutoEquipButton.pressed.connect(auto_equip)
	%ProtectLegendary.toggled.connect(_on_protect_toggled)
	%BudgetField.text_changed.connect(_on_budget_typed)
	%BudgetField.text_submitted.connect(func(_text: String) -> void: (%BudgetField as LineEdit).release_focus())
	%BudgetField.focus_exited.connect(_apply_budget)
	%BudgetField.tooltip_text = "Auto-equip won't use anything worth more than this (a gun with its parts and the magazine it would get; rounds and meds one at a time). Empty: no limit"
	%ProtectLegendary.tooltip_text = "Auto-equip won't use Legendary items, rounds or meds. A gun or helmet with a Legendary part counts as Legendary. What you already wear stays on"
	%AutoEquipButton.tooltip_text = "Put on the best you own from the stash (armor, rig, helmet, face cover, headset, backpack, melee, guns), with magazines, rounds, spare rounds and meds. Shows what changed, with UNDO"
	for control: Control in [%PresetName, %SaveNewButton, %LoadButton, %OverwriteButton, %RenameButton, %DeleteButton,
			%BudgetField, %ProtectLegendary, %AutoEquipButton]:
		control.add_to_group(GridCursor.CURSOR_GROUP)
	_build_summary()
	_build_tabs()
	show_auto_options()
	refresh_stats()
	refresh_presets()


func _update_hint(device: int) -> void:
	if tab == 1:
		%Hint.text = "%s: switch tabs  ·  BUY shows every line before you pay" % ("LB / RB" if device == 1 else "Q / E")
	else:
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


## The cursor stays off the grids while the preset name or budget box has the keys, the auto-equip
## summary is open or the QUICK BUY tab is shown.
func cursor_allowed() -> bool:
	return super() and _typing_box() == null and not summary_open() and tab == 0


## The preset name box, the budget box or the quick-buy name box while it has the keys, else null.
func _typing_box() -> LineEdit:
	for box: LineEdit in [%PresetName, %BudgetField, quick_buy.name_box if quick_buy else null]:
		if box and box.has_focus():
			return box
	return null


# --- Tabs -----------------------------------------------------------------------------------------

## LOADOUT | QUICK BUY in the header, and the QUICK BUY tab under it (hidden until picked).
func _build_tabs() -> void:
	var title := $Margin/Layout/Header/Title as Label
	title.hide()  # The tabs name the screen.
	var header := title.get_parent() as HBoxContainer
	var strip := HBoxContainer.new()
	strip.name = "Tabs"
	strip.add_theme_constant_override("separation", 4)
	header.add_child(strip)
	header.move_child(strip, title.get_index() + 1)
	var group := ButtonGroup.new()
	for entry in [["TabLoadout", "LOADOUT"], ["TabQuickBuy", "QUICK BUY"]]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 48)
		button.add_theme_font_size_override("font_size", 20)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Q / E or LB / RB: switch tabs"
		button.pressed.connect(set_tab.bind(_tab_buttons.size()))
		strip.add_child(button)
		_tab_buttons.append(button)
	_tab_buttons[0].button_pressed = true
	# The tabs are wider than the title they replace: the energy and water line gives up the room.
	var status := header.get_node_or_null("BodyStatus") as Control
	if status:
		for control: Control in [status] + status.get_children():
			control.custom_minimum_size.x = TAB_STATUS_WIDTH
	quick_buy = QuickBuyTab.new()
	quick_buy.screen = self
	quick_buy.visible = false
	var columns := $Margin/Layout/Columns as Control
	columns.get_parent().add_child(quick_buy)
	columns.get_parent().move_child(quick_buy, columns.get_index() + 1)


## Shows tab `index` (0: LOADOUT, 1: QUICK BUY).
func set_tab(index: int) -> void:
	tab = clampi(index, 0, 1)
	_tab_buttons[tab].button_pressed = true
	($Margin/Layout/Columns as Control).visible = tab == 0
	quick_buy.visible = tab == 1
	if tab == 1:
		compare_item(null)
		quick_buy.refresh(true)
		quick_buy.focus_first.call_deferred()
	_update_hint(InputHub.device)


## True when Q / E (LB / RB) may switch tabs: no text box or filter bar has the keys, nothing is being
## dragged, and no examine panel, modding screen, container window, summary or dialog is open.
func tabs_allowed() -> bool:
	if _typing_box() != null or (%FilterBar as StashFilterBar).has_focus_inside() or get_viewport().gui_is_dragging():
		return false
	if _examine.visible or get_node_or_null("WeaponModScreen") or not _windows.is_empty() or summary_open() or quick_buy.dialog_open():
		return false
	var upgrade_panel := %Overlay.get_node_or_null("GearUpgradePanel") as GearUpgradePanel
	return not (upgrade_panel and upgrade_panel.visible)


func _unhandled_input(event: InputEvent) -> void:
	var step := -1 if event.is_action_pressed("ui_tab_previous") else (1 if event.is_action_pressed("ui_tab_next") else 0)
	if step == 0 or not tabs_allowed():
		return
	set_tab(posmod(tab + step, 2))
	get_viewport().set_input_as_handled()


## The layer dialogs go on (QuickBuyTab's confirm dialog).
func overlay() -> Control:
	return %Overlay


## After a quick buy: everything shown is drawn again.
func gear_changed() -> void:
	_on_gear_changed()
	refresh_stats()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_at = (event as InputEventMouse).position
	if summary_open():
		# The summary has the screen: Esc / B or Tab is OK; its buttons take the rest.
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("toggle_inventory"):
			close_summary()
			get_viewport().set_input_as_handled()
		return
	if quick_buy and quick_buy.dialog_open():
		# The quick-buy dialog has the screen: Esc / B or Tab cancels; its buttons take the rest.
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("toggle_inventory"):
			quick_buy.close_dialog()
			get_viewport().set_input_as_handled()
		return
	var box := _typing_box()
	if box:
		# Typing a name or a budget: the keys are the box's (no hotkeys, no R, Tab doesn't close); Esc / B
		# leaves it, a click anywhere else lets go of it.
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
	if summary_open():
		return null
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


# --- Auto-equip -----------------------------------------------------------------------------------

## Shows the auto-equip options kept in the profile (GameState.auto_equip): the budget ("" for no limit)
## and Protect Legendary.
func show_auto_options() -> void:
	var options := LoadoutPlanner.clean_options(GameState.auto_equip)
	(%BudgetField as LineEdit).text = UiFormat.thousands(options.budget) if options.budget > 0 else ""
	(%ProtectLegendary as CheckButton).set_pressed_no_signal(options.protect_legendary)


## Sets the budget (roubles per item, 0 for no limit), in the profile and the box.
func set_budget(roubles: int) -> void:
	GameState.auto_equip.budget = maxi(roubles, 0)
	show_auto_options()


## Only digits go in the budget box (thousands separators come back when it's left).
func _on_budget_typed(text: String) -> void:
	var digits := _digits(text)
	if digits == text:
		return
	var field: LineEdit = %BudgetField
	var caret := field.caret_column - (text.length() - digits.length())
	field.text = digits
	field.caret_column = clampi(caret, 0, digits.length())


## The budget box was left (or AUTO-EQUIP pressed): its number becomes the budget.
func _apply_budget() -> void:
	var digits := _digits((%BudgetField as LineEdit).text).left(12)
	set_budget(int(digits) if digits != "" else 0)


static func _digits(text: String) -> String:
	var result := ""
	for character in text:
		if character >= "0" and character <= "9":
			result += character
	return result


func _on_protect_toggled(on: bool) -> void:
	GameState.auto_equip.protect_legendary = on


## AUTO-EQUIP: puts on the best you own from the stash with the options set (LoadoutPlanner.apply()),
## saves, and shows the summary with UNDO and OK. Returns the plan. While a summary is open it does
## nothing (that plan stays the one UNDO takes back).
func auto_equip() -> Dictionary:
	if summary_open():
		return auto_plan
	if (%BudgetField as LineEdit).has_focus():
		(%BudgetField as LineEdit).release_focus()
	_apply_budget()
	auto_plan = LoadoutPlanner.apply(inventory, stash, GameState.auto_equip)
	SaveManager.save_game()
	_on_gear_changed()
	_auto_message(str(auto_plan.message), false)
	_show_summary(auto_plan)
	return auto_plan


## UNDO: reverses what the last AUTO-EQUIP did (LoadoutPlanner.undo(): only its own moves, so anything that
## reached the stash meanwhile stays), saves, closes the summary and says how it went.
func undo_auto_equip() -> Dictionary:
	if auto_plan.is_empty():
		return {}
	var result := LoadoutPlanner.undo(auto_plan, inventory, stash)
	auto_plan = {}
	SaveManager.save_game()
	_on_gear_changed()
	_hide_summary()
	_auto_message(str(result.message), not result.lines.is_empty())
	return result


## OK (or Esc / B, Tab): closes the summary and keeps what changed (no undo after that).
func close_summary() -> void:
	auto_plan = {}
	_hide_summary()


func summary_open() -> bool:
	return _summary_shade != null and _summary_shade.visible


func _auto_message(text: String, warning: bool) -> void:
	%AutoEquipMessage.text = text
	if warning:
		%AutoEquipMessage.add_theme_color_override("font_color", HEAVY_COLOR)
	else:
		%AutoEquipMessage.remove_theme_color_override("font_color")


func _build_summary() -> void:
	_summary_shade = ColorRect.new()
	_summary_shade.name = "AutoEquipShade"
	_summary_shade.color = Color(0, 0, 0, 0.6)
	_summary_shade.mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing under it moves while it's open.
	_summary_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary_shade.hide()
	%Overlay.add_child(_summary_shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_shade.add_child(center)
	_summary = PanelContainer.new()
	_summary.name = "AutoEquipSummary"
	_summary.custom_minimum_size.x = SUMMARY_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.06, 1.0)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	_summary.add_theme_stylebox_override("panel", style)
	center.add_child(_summary)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	_summary.add_child(rows)
	var title := Label.new()
	title.name = "SummaryTitle"
	title.theme_type_variation = &"AccentLabel"
	title.add_theme_font_size_override("font_size", 24)
	rows.add_child(title)
	var options := Label.new()
	options.name = "SummaryOptions"
	options.theme_type_variation = &"DimLabel"
	rows.add_child(options)
	rows.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.name = "SummaryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	var lines := VBoxContainer.new()
	lines.name = "SummaryLines"
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 6)
	scroll.add_child(lines)
	rows.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	var note := Label.new()
	note.name = "SummaryNote"
	note.theme_type_variation = &"DimLabel"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.text = "UNDO puts everything back as it was"
	buttons.add_child(note)
	for entry in [["SummaryUndo", "UNDO", undo_auto_equip], ["SummaryOk", "OK", close_summary]]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.custom_minimum_size = Vector2(170, 46)
		button.pressed.connect(entry[2])
		buttons.add_child(button)


## Shows `plan`'s summary: a title with how many changes, the options it ran with, and every line
## (changes plain, what stayed dim, what didn't work out amber).
func _show_summary(plan: Dictionary) -> void:
	var count := int(plan.changes)
	(_summary.find_child("SummaryTitle", true, false) as Label).text = "AUTO-EQUIP  ·  %s" % (
		("%d CHANGE%s" % [count, "" if count == 1 else "S"]) if count > 0 else "NOTHING TO CHANGE")
	var options: Dictionary = plan.options
	(_summary.find_child("SummaryOptions", true, false) as Label).text = "Budget: %s  ·  %s" % [
		("%s per item" % UiFormat.money(int(options.budget))) if int(options.budget) > 0 else "no limit",
		"Legendary items protected" if options.protect_legendary else "Legendary items allowed"]
	var lines := _summary.find_child("SummaryLines", true, false) as VBoxContainer
	for child in lines.get_children():
		lines.remove_child(child)
		child.queue_free()
	var index := 0
	for line: Dictionary in plan.lines:
		var label := Label.new()
		label.name = "SummaryLine_%d" % index
		label.text = str(line.text)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = SUMMARY_WIDTH - 72.0
		label.add_theme_font_size_override("font_size", 17)
		match str(line.tone):
			LoadoutPlanner.KEPT:
				label.add_theme_color_override("font_color", DIM_COLOR.lightened(0.2))
			LoadoutPlanner.WARNING:
				label.add_theme_color_override("font_color", HEAVY_COLOR)
		lines.add_child(label)
		index += 1
	(_summary.find_child("SummaryUndo", true, false) as Button).disabled = plan.moves.is_empty()
	_summary_shade.show()
	trap_focus(true, _summary_shade)
	_fit_summary.call_deferred()
	var ok := _summary.find_child("SummaryOk", true, false) as Button
	ok.grab_focus.call_deferred()


## The list of changes as tall as it needs, up to SUMMARY_MAX_HEIGHT of the screen (then it scrolls).
func _fit_summary() -> void:
	var scroll := _summary.find_child("SummaryScroll", true, false) as ScrollContainer
	var lines := _summary.find_child("SummaryLines", true, false) as Control
	scroll.custom_minimum_size.y = minf(lines.get_combined_minimum_size().y, size.y * SUMMARY_MAX_HEIGHT)
	_summary.reset_size()


func _hide_summary() -> void:
	_summary_shade.hide()
	trap_focus(false, _summary_shade)


## While a modal panel is open (`on`: the auto-equip summary, the quick-buy dialog; `keep` is its shade
## in %Overlay), nothing under it takes the keyboard or controller focus: the screen's own content and the
## rest of %Overlay are FOCUS_BEHAVIOR_DISABLED, so the arrows, Tab and the d-pad only move between its
## buttons. Off gives the focus back.
func trap_focus(on: bool, keep: Control) -> void:
	var behavior := Control.FOCUS_BEHAVIOR_DISABLED if on else Control.FOCUS_BEHAVIOR_INHERITED
	for child in get_children() + %Overlay.get_children():
		if child is Control and child != %Overlay and child != keep:
			(child as Control).focus_behavior_recursive = behavior


## The text of the summary's lines, in order (tests and tools).
func summary_lines() -> Array[String]:
	var result: Array[String] = []
	var lines := _summary.find_child("SummaryLines", true, false)
	for child in lines.get_children():
		if not child.is_queued_for_deletion():
			result.append((child as Label).text)
	return result
