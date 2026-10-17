class_name TouchLayoutEditor
extends Control
## The touch layout editor (DESIGN.md §17.1), from Settings > Controls > EDIT LAYOUT: every on-screen
## stick and button over a stand-in raid view, placed as in a raid. Drag one (finger or mouse) to move
## it; the one picked last can be resized and faded with the SIZE and OPACITY sliders. LAYOUT 1-3 switch
## between the three saved layouts (edits to each are kept while the editor is open), SAVE stores the
## one shown and makes it the active layout, DEFAULTS puts the shown one back to the default places.
## BACK leaves; with unsaved edits it asks for a second press first. Context buttons (Interact, Extract,
## Cover) are shown here, though in a raid they only appear when they're needed.

signal saved(slot: int)
signal closed

const BACKDROP := Color(0.11, 0.12, 0.11)
const GRID_LINE := Color(1, 1, 1, 0.04)
const SELECTED := Color(0.95, 0.75, 0.3)

## The layout slot shown (1-3) and each slot's working copy (TouchLayout.resolve() form).
var slot := 1
var layouts := {}
## The widget picked last ("" for none).
var selected := ""
## Joystick size to draw the sticks at (the Settings menu passes its pending value).
var stick_size := 1.0

var _dragging := false
var _drag_offset := Vector2.ZERO
var _dirty := {}
var _back_armed := false
var _canvas: Control
var _slot_buttons: Array[Button] = []
var _name_label: Label
var _size_slider: HSlider
var _opacity_slider: HSlider
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in range(1, TouchLayout.SLOTS + 1):
		layouts[i] = Settings.touch_layout(i)
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_canvas_input)
	add_child(_canvas)
	_build_toolbar()
	get_viewport().size_changed.connect(_canvas.queue_redraw)
	InputHub.fit_to_safe_area.call_deferred(_canvas)
	show_slot(slot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()


func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "Toolbar"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 12.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.065, 0.07, 0.94)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)
	var title := Label.new()
	title.text = "TOUCH LAYOUT"
	title.theme_type_variation = &"AccentLabel"
	top.add_child(title)
	var group := ButtonGroup.new()
	for i in range(1, TouchLayout.SLOTS + 1):
		var button := Button.new()
		button.name = "Slot%d" % i
		button.text = "LAYOUT %d" % i
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(110, 40)
		button.pressed.connect(show_slot.bind(i))
		top.add_child(button)
		_slot_buttons.append(button)
	for entry in [["DefaultsButton", "DEFAULTS", reset_slot], ["SaveButton", "SAVE", save], ["BackButton", "BACK", back]]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.custom_minimum_size = Vector2(110, 40)
		button.pressed.connect(entry[2])
		top.add_child(button)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	rows.add_child(bottom)
	_name_label = Label.new()
	_name_label.custom_minimum_size.x = 170
	bottom.add_child(_name_label)
	_size_slider = _add_slider(bottom, "SIZE", TouchLayout.MIN_SCALE, TouchLayout.MAX_SCALE, "scale")
	_opacity_slider = _add_slider(bottom, "OPACITY", TouchLayout.MIN_OPACITY, 1.0, "opacity")
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"DimLabel"
	rows.add_child(_status)


func _add_slider(parent: Control, text: String, low: float, high: float, field: String) -> HSlider:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"DimLabel"
	parent.add_child(label)
	var slider := HSlider.new()
	slider.name = text.capitalize() + "Slider"
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(200, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void: set_field(field, value))
	parent.add_child(slider)
	return slider


## Shows layout `which` (1-3) for editing.
func show_slot(which: int) -> void:
	slot = clampi(which, 1, TouchLayout.SLOTS)
	_slot_buttons[slot - 1].set_pressed_no_signal(true)
	_back_armed = false
	_refresh()


## The working copy of the layout shown.
func layout() -> Dictionary:
	return layouts[slot]


## Picks widget `id` for the sliders ("" for none).
func select(id: String) -> void:
	selected = id
	_refresh()


## Sets "scale" or "opacity" of the picked widget.
func set_field(field: String, value: float) -> void:
	if selected == "":
		return
	var place: Dictionary = layout()[selected]
	if is_equal_approx(float(place[field]), value):
		return
	place[field] = value
	_mark_dirty()


## Moves widget `id` so its centre is at `centre` (pixels on the canvas), kept on screen.
func move_widget(id: String, centre: Vector2) -> void:
	var area := _area()
	var radius := TouchLayout.radius_of(id, float(layout()[id].scale), stick_size)
	var clamped := centre.clamp(Vector2.ONE * minf(radius, area.x / 2.0), area - Vector2.ONE * minf(radius, area.x / 2.0))
	layout()[id].x = clamped.x / area.x
	layout()[id].y = clamped.y / area.y
	_mark_dirty()


## Puts the shown layout back to the default places, sizes and opacity (until saved).
func reset_slot() -> void:
	layouts[slot] = TouchLayout.resolve({})
	_mark_dirty()


## Stores the shown layout and makes it the active one.
func save() -> void:
	Settings.save_touch_layout(slot, layout())
	_dirty.erase(slot)
	_back_armed = false
	_refresh()
	_status.text = "Layout %d saved and in use" % slot
	saved.emit(slot)


## Leaves the editor; with unsaved edits, only on the second press.
func back() -> void:
	if not _dirty.is_empty() and not _back_armed:
		_back_armed = true
		_status.text = "Unsaved changes to layout %s: press BACK again to leave without saving" % ", ".join(_dirty.keys().map(str))
		return
	closed.emit()
	queue_free()


func is_dirty() -> bool:
	return not _dirty.is_empty()


## Each widget's centre and radius on the canvas: {id: {"centre", "radius"}}.
func placed() -> Dictionary:
	var area := _area()
	var result := {}
	for id: String in TouchLayout.WIDGETS:
		var place: Dictionary = layout()[id]
		result[id] = {"centre": Vector2(place.x, place.y) * area, "radius": TouchLayout.radius_of(id, place.scale, stick_size)}
	return result


## The widget under `at` (canvas pixels): the nearest one it's inside, or "".
func widget_at(at: Vector2) -> String:
	var best := ""
	var best_distance := INF
	var all := placed()
	for id: String in all:
		var distance: float = at.distance_to(all[id].centre)
		if distance <= maxf(all[id].radius, 28.0) and distance < best_distance:
			best = id
			best_distance = distance
	return best


func _on_canvas_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			var id := widget_at(click.position)
			select(id)
			_dragging = id != ""
			if _dragging:
				_drag_offset = placed()[id].centre - click.position
		else:
			_dragging = false
		_canvas.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging and selected != "":
		move_widget(selected, motion.position + _drag_offset)
		_canvas.accept_event()


func _mark_dirty() -> void:
	_dirty[slot] = true
	_back_armed = false
	_refresh()


func _refresh() -> void:
	if _name_label == null:
		return
	var has := selected != ""
	_name_label.text = TouchLayout.WIDGETS[selected].label.to_upper() if has else "Pick a button"
	for slider in [_size_slider, _opacity_slider]:
		slider.editable = has
	if has:
		_size_slider.set_value_no_signal(layout()[selected].scale)
		_opacity_slider.set_value_no_signal(layout()[selected].opacity)
	var active := int(Settings.get_value("controls", "touch_layout"))
	_status.text = ("Unsaved changes" if _dirty.has(slot) else ("Layout %d (in use)" % slot if active == slot else "Layout %d" % slot)) \
		+ "  ·  Drag to move  ·  Pick one to resize or fade it"
	_canvas.queue_redraw()


func _area() -> Vector2:
	return _canvas.size if _canvas.size != Vector2.ZERO else get_viewport().get_visible_rect().size


func _draw_canvas() -> void:
	var area := _area()
	for x in range(0, int(area.x), 64):
		_canvas.draw_line(Vector2(x, 0), Vector2(x, area.y), GRID_LINE)
	for y in range(0, int(area.y), 64):
		_canvas.draw_line(Vector2(0, y), Vector2(area.x, y), GRID_LINE)
	_canvas.draw_line(Vector2(area.x * TouchControls.MOVE_ZONE, 0), Vector2(area.x * TouchControls.MOVE_ZONE, area.y), Color(1, 1, 1, 0.08), 2.0)
	var font := _canvas.get_theme_default_font()
	var all := placed()
	for id: String in all:
		var widget: Dictionary = TouchLayout.WIDGETS[id]
		var centre: Vector2 = all[id].centre
		var radius: float = all[id].radius
		var alpha := float(layout()[id].opacity)
		var tint := TouchControls.CONTEXT_COLOR if widget.kind == "context" else TouchControls.EDGE
		_canvas.draw_circle(centre, radius, Color(TouchControls.FILL, alpha * 0.6))
		_canvas.draw_arc(centre, radius - 1.5, 0.0, TAU, 48, Color(tint, alpha), 3.0, true)
		if widget.kind == "stick":
			_canvas.draw_circle(centre, radius * 0.38, Color(tint, alpha * 0.55))
		TouchIcons.draw(_canvas, id, centre, radius * (0.6 if widget.kind == "stick" else 1.0), Color(tint, minf(alpha + 0.25, 1.0)))
		var label: String = widget.label
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var at := centre + Vector2(-width / 2.0, radius + 17.0)
		_canvas.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
		_canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(tint, minf(alpha + 0.3, 1.0)))
		if id == selected:
			_canvas.draw_arc(centre, radius + 6.0, 0.0, TAU, 56, SELECTED, 3.0, true)
