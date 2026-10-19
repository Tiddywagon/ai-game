class_name RecoilPatternView
extends VBoxContainer
## The modding screen's recoil pattern (DESIGN.md §12.1): where each shot of a full-auto spray goes
## relative to the aim (WeaponStats.recoil_pattern(): climb up, side kicks left and right, recovery
## between shots), for the gun as it is (grey while previewing) and with the change being previewed
## (amber), on the same side kicks so they compare fairly. Under it, the numbers before and after.

## Shots shown for a gun that isn't automatic (fired as fast as it cycles), at most a magazine.
const SEMI_AUTO_SHOTS := 8
const BEFORE_COLOR := Color(0.75, 0.75, 0.72, 0.55)
const AFTER_COLOR := Color(0.95, 0.75, 0.3)
const GRID_COLOR := Color(1, 1, 1, 0.07)
const CANVAS_SIZE := Vector2(300, 150)

var _canvas: PatternCanvas
var _numbers: GridContainer
var _title: Label


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_title = Label.new()
	_title.theme_type_variation = &"AccentLabel"
	add_child(_title)
	_canvas = PatternCanvas.new()
	_canvas.name = "PatternCanvas"
	_canvas.custom_minimum_size = CANVAS_SIZE
	add_child(_canvas)
	_numbers = GridContainer.new()
	_numbers.name = "Numbers"
	_numbers.columns = 3
	_numbers.add_theme_constant_override("h_separation", 12)
	_numbers.add_theme_constant_override("v_separation", 0)
	add_child(_numbers)


## Shows `before` (the gun now) and, if given, `after` (the change being previewed).
func show_builds(before: WeaponData, after: WeaponData = null) -> void:
	var shots := mini(WeaponStats.CONFIG.pattern_shots if before.automatic else SEMI_AUTO_SHOTS, maxi(before.magazine_size, 1))
	var how := " held" if before.automatic else ", fast as it fires"
	_title.text = "RECOIL PATTERN  ·  %s" % ("1 round" if shots == 1 else "%d rounds%s" % [shots, how])
	_canvas.before = WeaponStats.recoil_pattern(before, shots)
	_canvas.after = WeaponStats.recoil_pattern(after, shots) if after else PackedVector2Array()
	_canvas.queue_redraw()
	for child in _numbers.get_children():
		_numbers.remove_child(child)
		child.queue_free()
	add_number(_numbers, "Climb a shot", before.vertical_recoil, after.vertical_recoil if after else NAN, "%.2f°", -1)
	add_number(_numbers, "Side kick", before.horizontal_recoil, after.horizontal_recoil if after else NAN, "±%.2f°", -1)
	add_number(_numbers, "Recovery", before.recoil_recovery, after.recoil_recovery if after else NAN, "%.1f / s", 1)


## A row of `grid` (3 columns): the name, the value now, and with `after` (NAN for none) the new
## value in green if it's better, red if worse (`better`: +1 higher is better, -1 lower).
static func add_number(grid: GridContainer, label: String, before: float, after: float, format: String, better: int) -> void:
	var name_label := Label.new()
	name_label.theme_type_variation = &"DimLabel"
	name_label.text = label
	name_label.add_theme_font_size_override("font_size", 14)
	grid.add_child(name_label)
	var now := Label.new()
	now.text = format % before
	now.add_theme_font_size_override("font_size", 14)
	grid.add_child(now)
	var then := Label.new()
	then.add_theme_font_size_override("font_size", 14)
	if not is_nan(after) and format % after != format % before:
		var improved := (after - before) * better > 0.0
		then.text = "%s %s" % ["▲" if improved else "▼", format % after]
		then.add_theme_color_override("font_color", WeaponStatList.BETTER_COLOR if improved else WeaponStatList.WORSE_COLOR)
	grid.add_child(then)


## The drawing: one degree grid, the shots joined in order.
class PatternCanvas:
	extends Control

	var before := PackedVector2Array()
	var after := PackedVector2Array()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0, 0, 0, 0.3))
		var all := before + after
		if all.is_empty():
			return
		var reach := Vector2(0.5, 0.5)
		for point in all:
			reach = Vector2(maxf(reach.x, absf(point.x)), maxf(reach.y, point.y))
		var origin := Vector2(size.x / 2.0, size.y - 12.0)
		var scale := minf((size.x / 2.0 - 12.0) / reach.x, (size.y - 24.0) / reach.y)
		scale = minf(scale, 80.0)
		# A line every degree, with its value.
		var font := get_theme_default_font()
		var degree := 1
		while degree * scale < size.y - 12.0:
			var y := origin.y - degree * scale
			draw_line(Vector2(0, y), Vector2(size.x, y), GRID_COLOR)
			draw_string(font, Vector2(4, y - 2), "%d°" % degree, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.3))
			degree += 1
		draw_line(Vector2(origin.x, 0), Vector2(origin.x, size.y), GRID_COLOR)
		draw_circle(origin, 3.0, Color(1, 1, 1, 0.5))
		_draw_pattern(before, origin, scale, BEFORE_COLOR if not after.is_empty() else AFTER_COLOR)
		if not after.is_empty():
			_draw_pattern(after, origin, scale, AFTER_COLOR)

	func _draw_pattern(points: PackedVector2Array, origin: Vector2, scale: float, color: Color) -> void:
		var screen := PackedVector2Array()
		for point in points:
			screen.append(origin + Vector2(point.x, -point.y) * scale)
		if screen.size() > 1:
			draw_polyline(screen, Color(color, color.a * 0.6), 1.5, true)
		for i in screen.size():
			draw_circle(screen[i], 2.5 if i > 0 else 3.5, color)
