extends MenuScreen
## Tabbed settings menu (DESIGN.md §17), built from Settings.SCHEMA. Edits stay pending until Apply,
## which applies them and saves user://settings.cfg. Reset to Defaults resets the open tab.
## Used from the main menu and the in-raid pause menu.

const LABEL_WIDTH := 380
const CONTROL_WIDTH := 440
const WARNING_COLOR := Color(0.95, 0.6, 0.3)

var _pending := {}
## tab -> key -> the control showing that option.
var _controls := {}
var _slider_labels := {}
## action -> {"button": Button, "conflict": Label, "reset": Button}
var _bind_rows := {}
var _capturing := ""

@onready var _tabs: TabContainer = %Tabs
@onready var _status: Label = %Status
@onready var _discard_dialog: ConfirmationDialog = %DiscardDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pending = Settings.values.duplicate(true)
	for i in Settings.TABS.size():
		_build_tab(Settings.TABS[i], Settings.TAB_TITLES[i])
	%ApplyButton.pressed.connect(_on_apply)
	%ResetButton.pressed.connect(_on_reset)
	%BackButton.pressed.connect(_on_back)
	_discard_dialog.confirmed.connect(close)
	_tabs.tab_changed.connect(func(_tab: int) -> void: _focus_first.call_deferred())
	_refresh()
	_focus_first.call_deferred()


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_finish_capture("")
	elif (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		_finish_capture(Settings.code_from_event(event))
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_tab_previous"):
		_tabs.current_tab = posmod(_tabs.current_tab - 1, _tabs.get_tab_count())
	elif event.is_action_pressed("ui_tab_next"):
		_tabs.current_tab = posmod(_tabs.current_tab + 1, _tabs.get_tab_count())
	else:
		super(event)
		return
	get_viewport().set_input_as_handled()


func _on_cancel() -> void:
	_on_back()


# --- Building -----------------------------------------------------------------------------

func _build_tab(tab: String, title: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 14)
	scroll.add_child(rows)
	_controls[tab] = {}
	for entry: Dictionary in Settings.SCHEMA[tab]:
		if entry.type == "keybinds":
			rows.add_child(_build_keybinds())
			continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 24)
		var label := Label.new()
		label.text = entry.label
		label.custom_minimum_size.x = LABEL_WIDTH
		line.add_child(label)
		var control := _make_control(tab, entry)
		line.add_child(control)
		row.add_child(line)
		if entry.has("note"):
			var note := Label.new()
			note.theme_type_variation = &"DimLabel"
			note.text = entry.note
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size.x = LABEL_WIDTH + 24 + CONTROL_WIDTH
			row.add_child(note)
		rows.add_child(row)


func _make_control(tab: String, entry: Dictionary) -> Control:
	var key: String = entry.key
	match entry.type:
		"toggle":
			var check := CheckButton.new()
			check.toggled.connect(func(on: bool) -> void: _set_value(tab, key, on))
			_controls[tab][key] = check
			return check
		"choice":
			var option := OptionButton.new()
			option.custom_minimum_size.x = CONTROL_WIDTH
			option.item_selected.connect(func(index: int) -> void: _set_value(tab, key, option.get_item_metadata(index)))
			_controls[tab][key] = option
			return option
		"slider":
			var box := HBoxContainer.new()
			box.add_theme_constant_override("separation", 16)
			var slider := HSlider.new()
			slider.custom_minimum_size = Vector2(CONTROL_WIDTH - 96, 28)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.min_value = entry.min
			slider.max_value = entry.max
			slider.step = entry.step
			var value_label := Label.new()
			value_label.custom_minimum_size.x = 80
			slider.value_changed.connect(func(value: float) -> void:
				value_label.text = _format(entry, value)
				_set_value(tab, key, value))
			box.add_child(slider)
			box.add_child(value_label)
			_controls[tab][key] = slider
			_slider_labels[slider] = value_label
			return box
	return Control.new()


func _build_keybinds() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Key bindings"
	title.theme_type_variation = &"AccentLabel"
	box.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "Select a binding, then press a key or mouse button (Esc cancels). Controller buttons are fixed for now."
	box.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for pair in Settings.REBINDABLE:
		var action: String = pair[0]
		var label := Label.new()
		label.text = pair[1]
		label.custom_minimum_size.x = LABEL_WIDTH - 24
		var button := Button.new()
		button.custom_minimum_size.x = 220
		button.pressed.connect(_start_capture.bind(action))
		var conflict := Label.new()
		conflict.add_theme_color_override("font_color", WARNING_COLOR)
		conflict.custom_minimum_size.x = 240
		var reset := Button.new()
		reset.text = "Reset"
		reset.tooltip_text = "Back to the default key"
		reset.pressed.connect(func() -> void:
			_pending.keybinds.erase(action)
			_refresh())
		for control: Control in [label, button, conflict, reset]:
			grid.add_child(control)
		_bind_rows[action] = {"button": button, "conflict": conflict, "reset": reset}
	box.add_child(grid)
	return box


# --- Editing ------------------------------------------------------------------------------

func _set_value(tab: String, key: String, value: Variant) -> void:
	if _pending[tab][key] == value:
		return
	_pending[tab][key] = value
	if tab == "graphics":
		if key == "preset" and value != "custom":
			_pending.graphics.merge(Settings.PRESETS[value], true)
		elif Settings.PRESETS.has(_pending.graphics.preset) and Settings.PRESETS.high.has(key):
			_pending.graphics.preset = "custom"
	_refresh()


func _start_capture(action: String) -> void:
	_capturing = action
	var button: Button = _bind_rows[action].button
	button.text = "Press a key…"


func _finish_capture(code: String) -> void:
	var action := _capturing
	_capturing = ""
	if code != "":
		if code == Settings.default_binding(action):
			_pending.keybinds.erase(action)
		else:
			_pending.keybinds[action] = code
	_refresh()
	(_bind_rows[action].button as Button).grab_focus.call_deferred()


func _on_apply() -> void:
	Settings.apply(_pending)
	Settings.save_settings()
	_pending = Settings.values.duplicate(true)
	_refresh()
	_status.text = "Settings saved"


func _on_reset() -> void:
	var tab: String = Settings.TABS[_tabs.current_tab]
	_pending[tab] = Settings.defaults()[tab]
	if tab == "controls":
		_pending.keybinds = {}
	_refresh()


func _on_back() -> void:
	if _capturing != "":
		return
	if is_dirty():
		_discard_dialog.popup_centered()
		_discard_dialog.get_cancel_button().grab_focus.call_deferred()
	else:
		close()


## True when there are edits that haven't been applied.
func is_dirty() -> bool:
	return _pending != Settings.values


# --- Display ------------------------------------------------------------------------------

## Shows the pending values in every control without triggering their change signals.
func _refresh() -> void:
	for tab: String in _controls:
		for key: String in _controls[tab]:
			var control: Control = _controls[tab][key]
			var value: Variant = _pending[tab][key]
			if control is CheckButton:
				(control as CheckButton).set_pressed_no_signal(value)
			elif control is OptionButton:
				_fill_options(control, tab, key, value)
			elif control is HSlider:
				(control as HSlider).set_value_no_signal(value)
				(_slider_labels[control] as Label).text = _format(Settings.schema_entry(tab, key), value)
	_refresh_keybinds()
	_status.text = "Unsaved changes" if is_dirty() else ""


func _fill_options(option: OptionButton, tab: String, key: String, value: Variant) -> void:
	var choices := Settings.choices(tab, key)
	if not choices.any(func(choice: Array) -> bool: return choice[0] == value):
		choices = choices + [[value, str(value)]]
	option.clear()
	for choice: Array in choices:
		if key == "preset" and choice[0] == "custom" and value != "custom":
			continue  # "Custom" only appears once options were changed by hand.
		option.add_item(choice[1])
		option.set_item_metadata(option.item_count - 1, choice[0])
		if choice[0] == value:
			option.select(option.item_count - 1)


func _refresh_keybinds() -> void:
	var by_code := {}
	for pair in Settings.REBINDABLE:
		var code := Settings.binding_of(pair[0], _pending.keybinds)
		by_code[code] = by_code.get(code, []) + [pair[1]]
	for pair in Settings.REBINDABLE:
		var action: String = pair[0]
		var row: Dictionary = _bind_rows[action]
		var code := Settings.binding_of(action, _pending.keybinds)
		if action != _capturing:
			(row.button as Button).text = Settings.binding_label(code)
		var others: Array = by_code[code].filter(func(name: String) -> bool: return name != pair[1])
		(row.conflict as Label).text = "" if others.is_empty() else "Also: " + ", ".join(others)
		(row.reset as Button).disabled = not _pending.keybinds.has(action)


func _format(entry: Dictionary, value: float) -> String:
	if entry.get("format") == "percent":
		return "%d%%" % roundi(value * 100.0)
	return "%.2f" % value


func _focus_first() -> void:
	var page := _tabs.get_current_tab_control()
	for node in page.find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			control.grab_focus()
			return
