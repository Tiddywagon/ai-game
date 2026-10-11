class_name MenuEntryButton
extends Button
## Big text button for the main and pause menus (DESIGN.md §16). While hovered or focused it slides
## right and glows; hovering also takes keyboard focus, so mouse and controller never highlight two
## buttons at once. A `primary` button (ENTER RAID) is larger and highlighted all the time.

const ACCENT := Color(0.88, 0.64, 0.23)
const TEXT := Color(0.85, 0.84, 0.78)
const SLIDE := 18.0
const MARGIN := 20.0
const ANIMATION_TIME := 0.12

@export var primary := false
@export var font_size := 30

var _style := StyleBoxFlat.new()
var _tween: Tween


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	_style.content_margin_left = MARGIN
	_style.content_margin_right = MARGIN + SLIDE
	_style.content_margin_top = 6
	_style.content_margin_bottom = 6
	_style.border_width_left = 3
	_style.shadow_offset = Vector2.ZERO
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, _style)
	add_theme_font_override("font", get_theme_font("font", "HeadingLabel"))
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", ACCENT if primary else TEXT)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.WHITE)
	mouse_entered.connect(func() -> void:
		if not disabled:
			grab_focus())
	focus_entered.connect(_set_hot.bind(true))
	focus_exited.connect(_set_hot.bind(false))
	_set_hot(false, true)


func _set_hot(hot: bool, instant := false) -> void:
	var resting_alpha := 0.1 if primary else 0.0
	var bg := Color(ACCENT, 0.18 if hot else resting_alpha)
	var border := Color(ACCENT, 1.0 if hot else (0.85 if primary else 0.0))
	var glow := Color(ACCENT, 0.35 if hot else (0.12 if primary else 0.0))
	var margin := MARGIN + (SLIDE if hot else 0.0)
	if _tween:
		_tween.kill()
	if instant:
		_style.bg_color = bg
		_style.border_color = border
		_style.shadow_color = glow
		_style.shadow_size = 14 if hot or primary else 0
		_style.content_margin_left = margin
		return
	_style.shadow_size = 14
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_style, "bg_color", bg, ANIMATION_TIME)
	_tween.tween_property(_style, "border_color", border, ANIMATION_TIME)
	_tween.tween_property(_style, "shadow_color", glow, ANIMATION_TIME)
	_tween.tween_property(_style, "content_margin_left", margin, ANIMATION_TIME)
