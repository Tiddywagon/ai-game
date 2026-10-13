class_name BodySilhouette
extends Control
## Body silhouette for the HUD and the death screen (DESIGN.md §13.5): each body part is filled by its
## health (green, amber, red; black when blacked). Bleeds show as drops (two for a heavy bleed) and
## fractures as a crack, so colour is never the only cue. A part briefly lights up when it's hit.
## Seen from behind: the left arm is on the left. Hover a part for its HP (where the mouse is free).

const FULL := Color(0.55, 0.78, 0.42)
const HALF := Color(0.93, 0.7, 0.25)
const EMPTY := Color(0.85, 0.22, 0.18)
const BLACKED := Color(0.06, 0.06, 0.06)
const BLACKED_BORDER := Color(0.75, 0.15, 0.1)
const OUTLINE := Color(0, 0, 0, 0.7)
const BLEED := Color(0.55, 0.0, 0.02)
## Layout in a 64 × 136 design space, indexed by BodyHealth.Part. The head is drawn round.
const SIZE := Vector2(64, 136)
const RECTS: Array[Rect2] = [
	Rect2(23, 2, 18, 18), Rect2(20, 22, 24, 30), Rect2(20, 54, 24, 20),
	Rect2(8, 22, 10, 50), Rect2(46, 22, 10, 50), Rect2(20, 76, 11, 58), Rect2(33, 76, 11, 58),
]
const FLASH_TIME := 0.3

## The health to show. Set it and the silhouette follows changes on its own.
var health: BodyHealth:
	set(value):
		health = value
		_last_hp = health.hp.duplicate() if health else []
		queue_redraw()

var _last_hp: Array[float] = []
var _flash: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _style := StyleBoxFlat.new()


func _ready() -> void:
	_style.set_corner_radius_all(3)
	_style.set_border_width_all(1)


func _process(delta: float) -> void:
	if health == null:
		return
	for part in _flash.size():
		_flash[part] = maxf(_flash[part] - delta, 0.0)
		if health.hp[part] < _last_hp[part] - 0.5:
			_flash[part] = FLASH_TIME  # Hit (bleeding ticks are too small to count).
			_last_hp[part] = health.hp[part]
		elif health.hp[part] > _last_hp[part]:
			_last_hp[part] = health.hp[part]
	queue_redraw()


## Fill colour for a part at `fraction` of its HP.
static func health_color(fraction: float) -> Color:
	if fraction <= 0.0:
		return BLACKED
	if fraction < 0.5:
		return EMPTY.lerp(HALF, fraction / 0.5)
	return HALF.lerp(FULL, (fraction - 0.5) / 0.5)


func _draw() -> void:
	if health == null:
		return
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	for part in RECTS.size():
		var rect := _rect(part)
		var blacked := health.is_blacked(part)
		var fill := health_color(health.fraction(part))
		var border := BLACKED_BORDER if blacked else OUTLINE
		if _flash[part] > 0.0:
			border = Color.WHITE
			if not reduced:
				fill = fill.lerp(Color.WHITE, 0.6 * _flash[part] / FLASH_TIME)
		if part == BodyHealth.Part.HEAD:
			var radius := rect.size.x / 2.0
			draw_circle(rect.get_center(), radius + 1.0, border)
			draw_circle(rect.get_center(), radius, fill)
		else:
			_style.bg_color = fill
			_style.border_color = border
			draw_style_box(_style, rect)
		if health.fractures[part]:
			_draw_crack(rect)
		match health.bleeds[part]:
			BodyHealth.Bleed.LIGHT:
				_draw_drop(rect.get_center())
			BodyHealth.Bleed.HEAVY:
				var offset := Vector2(0, minf(rect.size.y * 0.22, 7.0 * _scale()))
				_draw_drop(rect.get_center() - offset)
				_draw_drop(rect.get_center() + offset)


func _get_tooltip(at_position: Vector2) -> String:
	if health == null:
		return ""
	for part in RECTS.size():
		if _rect(part).has_point(at_position):
			var text := "%s: %d / %d HP" % [BodyHealth.PART_NAMES[part], ceili(health.hp[part]), roundi(health.max_hp(part))]
			if health.is_blacked(part):
				text += " (blacked)"
			if health.bleeds[part] != BodyHealth.Bleed.NONE:
				text += "\n%s bleed" % ("Heavy" if health.bleeds[part] == BodyHealth.Bleed.HEAVY else "Light")
			if health.fractures[part]:
				text += "\nFracture"
			return text
	return ""


func _scale() -> float:
	return minf(size.x / SIZE.x, size.y / SIZE.y)


## A part's rectangle in this control, scaled to fit and centred.
func _rect(part: int) -> Rect2:
	var scale_by := _scale()
	var offset := (size - SIZE * scale_by) / 2.0
	var rect: Rect2 = RECTS[part]
	return Rect2(offset + rect.position * scale_by, rect.size * scale_by)


func _draw_drop(center: Vector2) -> void:
	var r := 3.2 * _scale()
	var points := PackedVector2Array([center + Vector2(0, -r * 2.2)])
	for i in 9:
		var angle := PI * (-0.15 + 1.3 * i / 8.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, BLEED)
	points.append(points[0])
	draw_polyline(points, Color(1, 1, 1, 0.85), 1.0)


func _draw_crack(rect: Rect2) -> void:
	var c := rect.get_center()
	var w := rect.size.x * 0.45
	var points := PackedVector2Array([c + Vector2(-w, -4), c + Vector2(-w * 0.3, 2), c + Vector2(w * 0.2, -3), c + Vector2(w, 3)])
	draw_polyline(points, Color(0, 0, 0, 0.8), 3.0)
	draw_polyline(points, Color.WHITE, 1.5)
