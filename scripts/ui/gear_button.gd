extends Button
## Square button showing a gear icon drawn in code (Settings, DESIGN.md §16). The gear turns a
## little and lights up while hovered or focused.

const TEXT := Color(0.85, 0.84, 0.78)
const ACCENT := Color(0.88, 0.64, 0.23)
const TEETH := 8

var _angle := 0.0
var _color := TEXT


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	# Colour and rotation show hover and focus, so no box is drawn.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_set_hot.bind(true))
	focus_exited.connect(_set_hot.bind(false))


func _set_hot(hot: bool) -> void:
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_angle, _angle, deg_to_rad(30.0) if hot else 0.0, 0.25)
	tween.tween_method(_set_color, _color, ACCENT if hot else TEXT, 0.15)


func _set_angle(value: float) -> void:
	_angle = value
	queue_redraw()


func _set_color(value: Color) -> void:
	_color = value
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var outer := minf(size.x, size.y) * 0.4
	var inner := outer * 0.74
	var points := PackedVector2Array()
	for i in TEETH * 4:
		# Each tooth: two points on the outer radius, two on the inner one.
		var radius := outer if i % 4 < 2 else inner
		var angle := _angle + TAU * (float(i) - 0.5) / (TEETH * 4)
		points.append(center + Vector2.from_angle(angle) * radius)
	draw_colored_polygon(points, _color)
	draw_circle(center, inner * 0.45, Color(0.05, 0.055, 0.05))
