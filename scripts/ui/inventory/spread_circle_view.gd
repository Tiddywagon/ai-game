class_name SpreadCircleView
extends VBoxContainer
## The modding screen's spread circles (DESIGN.md §12.1, §13.4): the cone a shot lands in, drawn the
## way the bloom reticle shows it, for the gun as it is (grey while previewing) and with the change
## being previewed (amber): aimed (base spread, plus wear), hip-firing (plus hip-fire spread) and at
## full bloom (plus max bloom). Under it, the numbers before and after.

const BEFORE_COLOR := Color(0.75, 0.75, 0.72, 0.55)
const AFTER_COLOR := Color(0.95, 0.75, 0.3)
const CANVAS_SIZE := Vector2(300, 150)

var _canvas: CircleCanvas
var _numbers: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.theme_type_variation = &"AccentLabel"
	title.text = "SPREAD  ·  aimed, hip, full bloom"
	add_child(title)
	_canvas = CircleCanvas.new()
	_canvas.name = "CircleCanvas"
	_canvas.custom_minimum_size = CANVAS_SIZE
	add_child(_canvas)
	_numbers = GridContainer.new()
	_numbers.name = "Numbers"
	_numbers.columns = 3
	_numbers.add_theme_constant_override("h_separation", 12)
	_numbers.add_theme_constant_override("v_separation", 0)
	add_child(_numbers)


## Shows `before` (the gun now) and, if given, `after` (the change being previewed), for a gun at
## `durability` (wear adds spread).
func show_builds(before: WeaponData, after: WeaponData = null, durability := 100.0) -> void:
	var worn := WeaponStats.wear_spread(durability)
	_canvas.before = circles(before, worn)
	_canvas.after = circles(after, worn) if after else []
	_canvas.queue_redraw()
	for child in _numbers.get_children():
		_numbers.remove_child(child)
		child.queue_free()
	var has_after := after != null
	RecoilPatternView.add_number(_numbers, "Aimed", before.base_spread + worn, after.base_spread + worn if has_after else NAN, "%.2f°", -1)
	RecoilPatternView.add_number(_numbers, "Hip-fire", before.base_spread + worn + before.hip_spread,
		after.base_spread + worn + after.hip_spread if has_after else NAN, "%.2f°", -1)
	RecoilPatternView.add_number(_numbers, "Full bloom", before.base_spread + worn + before.max_bloom,
		after.base_spread + worn + after.max_bloom if has_after else NAN, "%.1f°", -1)
	RecoilPatternView.add_number(_numbers, "Settles in", WeaponStats.bloom_settle_time(before),
		WeaponStats.bloom_settle_time(after) if has_after else NAN, "%.2f s", -1)


## The three cone sizes of `gun` in degrees: aimed, hip-firing, full bloom.
static func circles(gun: WeaponData, worn: float) -> Array:
	var aimed := gun.base_spread + worn
	return [aimed, aimed + gun.hip_spread, aimed + gun.max_bloom]


## The drawing: each cone as a circle, scaled so the widest fits.
class CircleCanvas:
	extends Control

	var before := []
	var after := []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3))
		var widest := 0.5
		for value in before + after:
			widest = maxf(widest, value)
		var center := size / 2.0
		var scale := (minf(size.x, size.y) / 2.0 - 8.0) / widest
		_draw_set(before, center, scale, BEFORE_COLOR if not after.is_empty() else AFTER_COLOR)
		if not after.is_empty():
			_draw_set(after, center, scale, AFTER_COLOR)
		draw_circle(center, 2.0, Color(1, 1, 1, 0.6))

	func _draw_set(values: Array, center: Vector2, scale: float, color: Color) -> void:
		if values.size() < 3:
			return
		draw_arc(center, values[0] * scale, 0.0, TAU, 48, color, 2.0, true)  # Aimed: solid.
		_dashed(center, values[1] * scale, color)  # Hip-fire: dashed.
		draw_arc(center, values[2] * scale, 0.0, TAU, 64, Color(color, color.a * 0.6), 1.0, true)  # Full bloom: thin.

	func _dashed(center: Vector2, radius: float, color: Color) -> void:
		var dashes := 24
		for i in dashes:
			var start := TAU * i / dashes
			draw_arc(center, radius, start, start + TAU / dashes * 0.55, 6, color, 1.5, true)
