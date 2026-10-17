class_name PromptIcon
extends Control
## An on-screen button prompt for `action` (DESIGN.md §17.1) that follows the device used last: a
## keycap ("F", "Tab") or a mouse with the button lit; a controller button in the controller's style
## (Xbox letters in their colours, PlayStation shapes, bumpers and triggers, the d-pad); or the touch
## button's icon. Redraws when the device changes.

const KEY_FILL := Color(0.16, 0.17, 0.18, 0.95)
const KEY_EDGE := Color(0.82, 0.82, 0.78)
const TEXT_COLOR := Color(0.95, 0.95, 0.92)
## Face button colours: Xbox by letter, PlayStation by shape (south, east, west, north).
const XBOX_COLORS := [Color(0.38, 0.75, 0.3), Color(0.85, 0.28, 0.25), Color(0.25, 0.5, 0.9), Color(0.95, 0.78, 0.2)]
const PS_COLORS := [Color(0.45, 0.62, 0.95), Color(0.92, 0.35, 0.38), Color(0.88, 0.5, 0.8), Color(0.35, 0.8, 0.6)]
const TOUCH_FILL := Color(0.1, 0.1, 0.1, 0.75)

## The InputMap action shown.
@export var action := "interact":
	set(value):
		action = value
		_refresh()
## Height in pixels (keycaps grow wider for long names).
@export var icon_size := 30.0:
	set(value):
		icon_size = value
		_refresh()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InputHub.device_changed.connect(func(_device: int) -> void: _refresh())
	Settings.applied.connect(_refresh)
	_refresh()


## The touch widget that does `action_name` ("" if none).
static func touch_widget_of(action_name: String) -> String:
	if action_name.begins_with("hotkey") or action_name in ["flashlight", "binoculars"]:
		return "hotkeys"
	for id: String in TouchLayout.WIDGETS:
		if TouchLayout.WIDGETS[id].get("action", "") == action_name:
			return id
	return "aim_stick" if action_name == "shoot" else ""


func _refresh() -> void:
	if not is_inside_tree():
		return
	var spec := InputHub.prompt(action)
	var width := icon_size
	if spec.device == InputHub.Device.KEYBOARD_MOUSE and not str(spec.text).ends_with("mouse"):
		width = maxf(icon_size, _font().get_string_size(spec.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x + icon_size * 0.5)
	elif spec.device == InputHub.Device.CONTROLLER and not _is_face(spec.code):
		width = icon_size * 1.5
	custom_minimum_size = Vector2(width, icon_size)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	var spec := InputHub.prompt(action)
	var rect := Rect2(Vector2.ZERO, size)
	match int(spec.device):
		InputHub.Device.CONTROLLER:
			_draw_pad(rect, str(spec.code), str(spec.family), str(spec.text))
		InputHub.Device.TOUCH:
			var at := rect.get_center()
			draw_circle(at, icon_size * 0.5, TOUCH_FILL)
			draw_arc(at, icon_size * 0.5 - 1.0, 0.0, TAU, 32, Color(TEXT_COLOR, 0.8), 1.5, true)
			TouchIcons.draw(self, touch_widget_of(action), at, icon_size * 0.62, TEXT_COLOR)
		_:
			if str(spec.text).ends_with("mouse"):
				_draw_mouse(rect, str(spec.text))
			else:
				_draw_key(rect, str(spec.text))


func _draw_key(rect: Rect2, text: String) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = KEY_FILL
	box.border_color = KEY_EDGE
	box.set_border_width_all(2)
	box.border_width_bottom = 4
	box.set_corner_radius_all(5)
	draw_style_box(box, rect)
	_centered_text(rect, text)


func _draw_mouse(rect: Rect2, text: String) -> void:
	var body := Rect2(rect.get_center() - Vector2(icon_size * 0.32, icon_size * 0.48), Vector2(icon_size * 0.64, icon_size * 0.96))
	var box := StyleBoxFlat.new()
	box.bg_color = KEY_FILL
	box.border_color = KEY_EDGE
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(icon_size * 0.3))
	draw_style_box(box, body)
	var half := Rect2(body.position, Vector2(body.size.x / 2.0, body.size.y * 0.42))
	if text.begins_with("Right"):
		half.position.x += body.size.x / 2.0
	elif text.begins_with("Middle"):
		half = Rect2(body.position + Vector2(body.size.x * 0.4, 0), Vector2(body.size.x * 0.2, body.size.y * 0.42))
	draw_rect(half.grow(-3.0), Color(0.95, 0.75, 0.3))
	draw_line(body.position + Vector2(body.size.x / 2.0, 2.0), body.position + Vector2(body.size.x / 2.0, body.size.y * 0.42), KEY_EDGE, 1.5)


func _draw_pad(rect: Rect2, code: String, pad_family: String, text: String) -> void:
	var at := rect.get_center()
	var r := icon_size * 0.5
	var parts := code.split(":")
	var index := int(parts[1]) if parts.size() >= 2 and parts[0] == "joy" else -1
	if _is_face(code):
		var playstation := pad_family == "playstation"
		var color: Color = (PS_COLORS if playstation else XBOX_COLORS)[index]
		draw_circle(at, r, Color(0.08, 0.08, 0.09, 0.95) if playstation else color.darkened(0.15))
		draw_arc(at, r - 1.0, 0.0, TAU, 32, color if playstation else color.lightened(0.3), 2.0, true)
		if playstation:
			_draw_ps_shape(at, r * 0.5, index, color)
		else:
			_centered_text(rect, text)
		return
	if index >= 11 and index <= 14:  # The d-pad, the pressed arm lit.
		var arm := icon_size * 0.3
		var lit: Vector2 = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT][index - 11]
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var centre := at + dir * arm * 0.95
			draw_rect(Rect2(centre - Vector2(arm, arm) * 0.5, Vector2(arm, arm)), Color(0.95, 0.75, 0.3) if dir == lit else KEY_FILL)
		draw_rect(Rect2(at - Vector2(arm, arm) * 0.5, Vector2(arm, arm)), KEY_FILL)
		return
	if index == 7 or index == 8:  # A stick click.
		draw_circle(at, r, KEY_FILL)
		draw_arc(at, r - 1.0, 0.0, TAU, 32, KEY_EDGE, 2.0, true)
		_centered_text(rect, text)
		return
	var box := StyleBoxFlat.new()  # Bumpers, triggers, menu buttons.
	box.bg_color = KEY_FILL
	box.border_color = KEY_EDGE
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(icon_size * (0.45 if parts[0] == "axis" else 0.2)))
	draw_style_box(box, rect)
	_centered_text(rect, text)


func _draw_ps_shape(at: Vector2, r: float, index: int, color: Color) -> void:
	match index:
		0:  # Cross.
			draw_line(at + Vector2(-r, -r), at + Vector2(r, r), color, 2.5, true)
			draw_line(at + Vector2(-r, r), at + Vector2(r, -r), color, 2.5, true)
		1:  # Circle.
			draw_arc(at, r, 0.0, TAU, 24, color, 2.5, true)
		2:  # Square.
			draw_rect(Rect2(at - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), color, false, 2.5)
		3:  # Triangle.
			draw_polyline(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, r * 0.75), at + Vector2(-r, r * 0.75), at + Vector2(0, -r)]), color, 2.5, true)


static func _is_face(code: String) -> bool:
	var parts := code.split(":")
	return parts.size() >= 2 and parts[0] == "joy" and int(parts[1]) >= 0 and int(parts[1]) <= 3


func _centered_text(rect: Rect2, text: String) -> void:
	var font := _font()
	var font_size := _font_size()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := rect.get_center().y + font.get_ascent(font_size) * 0.38
	draw_string(font, Vector2(rect.get_center().x - width / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)


func _font() -> Font:
	return get_theme_default_font()


func _font_size() -> int:
	return int(icon_size * 0.5)
