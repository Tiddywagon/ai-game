class_name HotkeyWheel
extends CanvasLayer
## The hotkey radial wheel (DESIGN.md §17.1): hotkeys 1-5 (what each holds and how many you carry),
## the flashlight, binoculars and your extracts, round a circle. Hold `hotkey_wheel` (View on a
## controller, G on a keyboard) and it opens; point with a stick (or the mouse) and let go to use that
## slice. A quick tap of View opens the map instead. On touch the Hotkeys button opens it: slide to a
## slice and lift, or tap the button and then tap a slice. Every slice presses its own InputMap action,
## so it works like the key would. The player can't aim or shoot while it's open.

## A slice was chosen.
signal used(slice: Dictionary)

## Holding the button this long (seconds) opens the wheel; a shorter press is a tap.
const HOLD_TIME := 0.25
const RADIUS := 200.0
const INNER_RADIUS := 64.0
## How far a stick must lean (0-1) to pick a slice.
const STICK_PICK := 0.4
const BACKDROP := Color(0.04, 0.045, 0.05, 0.82)
const SLICE_COLOR := Color(0.95, 0.75, 0.3)
const TEXT_COLOR := Color(0.92, 0.92, 0.88)
const DIM_TEXT := Color(0.6, 0.6, 0.58)

var player: Player
var is_open := false
## The slice pointed at (-1: none).
var selected := -1
## Who opened it: "pad", "key" or "touch".
var source := ""

var _centre := Vector2.ZERO
var _hold := -1.0
var _pointer := Vector2.ZERO
## Touch: opened by a tap, waiting for a tap on a slice.
var _sticky := false
var _was_ui_open := false
var _canvas: Control


func _ready() -> void:
	layer = 30
	_canvas = Control.new()
	_canvas.name = "Wheel"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_wheel)
	add_child(_canvas)
	visible = false


## The slices, clockwise from the top: {"action", "label", "detail"}.
func slices() -> Array:
	var list := []
	for i in GameState.HOTKEY_COUNT:
		var id := str(GameState.hotkeys[i])
		var label := "Empty"
		var detail := "Set it in the inventory"
		if id != "" and ItemDB.has_item(id):
			label = ItemDB.get_item(id).display_name
			var carried := player.inventory.count_of(id) if player and player.inventory else 0
			detail = "×%d" % carried if carried > 0 else "None on you"
		list.append({"action": "hotkey_%d" % (i + 1), "label": "%d  %s" % [i + 1, label], "detail": detail})
	list.append({"action": "flashlight", "label": "Flashlight", "detail": "On" if player and player.flashlight_on else "Off"})
	list.append({"action": "binoculars", "label": "Binoculars", "detail": "In hand" if player and player.using_binoculars else ""})
	list.append({"action": "show_extracts", "label": "Extracts", "detail": "Show your extracts"})
	return list


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hotkey_wheel"):
		if player == null or player.is_dead or (player.ui_open and not is_open):
			return
		_hold = 0.0
		source = "pad" if event is InputEventJoypadButton or event is InputEventJoypadMotion else "key"
		get_viewport().set_input_as_handled()
	elif event.is_action_released("hotkey_wheel") and _hold >= 0.0:
		_hold = -1.0
		if is_open:
			close(true)
		elif source == "pad":
			_send("map_view")  # A tap on View: the map.
		get_viewport().set_input_as_handled()
	elif is_open and source == "key" and event is InputEventMouseMotion:
		_pointer += event.relative
		point(_pointer)


func _input(event: InputEvent) -> void:
	if not (is_open and _sticky):
		return
	var touch := event as InputEventScreenTouch
	if touch and touch.pressed:
		var offset := touch.position - _centre
		if offset.length() <= RADIUS:
			point(offset)
			close(selected >= 0)
		else:
			close(false)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _hold >= 0.0 and not is_open:
		_hold += delta
		if _hold >= HOLD_TIME:
			open_at(_canvas.size / 2.0, source)
	if is_open and source == "pad":
		var lean := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if lean.length() < STICK_PICK:
			lean = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if lean.length() >= STICK_PICK:
			point(lean * RADIUS)
	if is_open:
		_canvas.queue_redraw()


## Opens the wheel centred on `centre` (screen pixels).
func open_at(centre: Vector2, opened_by: String) -> void:
	is_open = true
	source = opened_by
	_centre = centre
	_pointer = Vector2.ZERO
	_sticky = false
	selected = -1
	visible = true
	if player:
		_was_ui_open = player.ui_open
		player.ui_open = true
	_canvas.queue_redraw()


## Points at the slice in direction `offset` from the centre (nothing inside the inner circle).
func point(offset: Vector2) -> void:
	if offset.length() < INNER_RADIUS * 0.6:
		selected = -1
		return
	var count := slices().size()
	var step := TAU / count
	var angle := fposmod(offset.angle() + PI / 2.0 + step / 2.0, TAU)
	selected = int(angle / step) % count
	_canvas.queue_redraw()


## Touch: the finger came up. On a slice it's used; without one the wheel stays open for a tap.
func release_touch() -> void:
	if selected >= 0:
		close(true)
	else:
		_sticky = true


## Closes the wheel, using the slice pointed at if `use`.
func close(use: bool) -> void:
	if not is_open:
		return
	is_open = false
	_sticky = false
	visible = false
	if player:
		player.ui_open = _was_ui_open
	if use and selected >= 0:
		var slice: Dictionary = slices()[selected]
		_send(slice.action)
		used.emit(slice)


func _send(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _draw_wheel() -> void:
	if not is_open:
		return
	var list := slices()
	var step := TAU / list.size()
	var font := _canvas.get_theme_default_font()
	_canvas.draw_circle(_centre, RADIUS, BACKDROP)
	if selected >= 0:
		var start := -PI / 2.0 + step * selected - step / 2.0
		var wedge := PackedVector2Array()
		for i in 13:
			wedge.append(_centre + Vector2.from_angle(start + step * i / 12.0) * RADIUS)
		for i in range(12, -1, -1):
			wedge.append(_centre + Vector2.from_angle(start + step * i / 12.0) * INNER_RADIUS)
		_canvas.draw_colored_polygon(wedge, Color(SLICE_COLOR, 0.35))
	for i in list.size():
		var edge := -PI / 2.0 + step * i - step / 2.0
		_canvas.draw_line(_centre + Vector2.from_angle(edge) * INNER_RADIUS, _centre + Vector2.from_angle(edge) * RADIUS, Color(1, 1, 1, 0.12), 1.5)
		var at := _centre + Vector2.from_angle(-PI / 2.0 + step * i) * (RADIUS + INNER_RADIUS) * 0.5
		var label: String = list[i].label
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_canvas.draw_string(font, at + Vector2(-width / 2.0, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SLICE_COLOR if i == selected else TEXT_COLOR)
		var detail: String = list[i].detail
		var detail_width := font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_canvas.draw_string(font, at + Vector2(-detail_width / 2.0, 16), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM_TEXT)
	_canvas.draw_arc(_centre, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 2.0, true)
	_canvas.draw_arc(_centre, INNER_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
	var title: String = list[selected].label if selected >= 0 else "HOTKEYS"
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, INNER_RADIUS * 1.8, 14).x
	_canvas.draw_string(font, _centre + Vector2(-title_width / 2.0, 5), title, HORIZONTAL_ALIGNMENT_LEFT, INNER_RADIUS * 1.8, 14, TEXT_COLOR)
