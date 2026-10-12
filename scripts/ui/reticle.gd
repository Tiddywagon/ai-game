extends Control
## In-raid aiming reticle (DESIGN.md §13.4, §17): drawn where the next shot goes before spread, i.e.
## the cursor moved by recoil and sway (a faint dot stays on the cursor itself while they move it), in
## the style and colour chosen in Settings > Interface. The "bloom" style is a circle the size of the
## real cone the next shot can land in, growing and shrinking live with bloom (shooting, moving,
## sprinting, rolling, hip-firing) and wear. A ring fills up while reloading or clearing a jam. Hit
## markers show here too. With a bolt-action rifle or DMR, a gold arc shows how far a 360 spin has
## got (DESIGN.md §13.4); a trick-shot hit gets a gold marker with a diamond.

const HIT_MARKER_TIME := 0.25
const KILL_COLOR := Color(1.0, 0.3, 0.25)
const RELOAD_RING_RADIUS := 22.0
## The gold ring that fills as a 360 spin goes round.
const SPIN_RING_RADIUS := 30.0
## Largest the bloom circle grows to, in pixels, and the smallest it shrinks to.
const MAX_BLOOM := 220.0
const MIN_BLOOM := 5.0
## The cursor dot shows once recoil or sway move the reticle this far from it, in pixels.
const CURSOR_DOT_DISTANCE := 4.0

var player: Player

var _hit_time := 0.0
var _hit_kill := false
var _hit_trick := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_hit_time = maxf(_hit_time - delta, 0.0)
	queue_redraw()


func show_hit_marker(killed: bool, trick := false) -> void:
	_hit_time = HIT_MARKER_TIME * (2.0 if trick else 1.0)
	_hit_kill = killed
	_hit_trick = trick


func _draw() -> void:
	if player == null or player.is_dead:
		return
	var center := player.reticle_position()
	var color := Settings.reticle_color()
	var shadow := Color(0, 0, 0, 0.6)
	if center.distance_to(player.cursor_position) > CURSOR_DOT_DISTANCE:
		draw_circle(player.cursor_position, 2.5, Color(shadow, 0.35))
		draw_circle(player.cursor_position, 1.5, Color(color, 0.45))
	match Settings.get_value("interface", "reticle_style"):
		"dot":
			draw_circle(center, 4.0, shadow)
			draw_circle(center, 2.5, color)
		"circle":
			draw_arc(center, 13.0, 0.0, TAU, 40, shadow, 4.0)
			draw_arc(center, 13.0, 0.0, TAU, 40, color, 2.0)
			draw_circle(center, 1.5, color)
		"cross":
			_draw_cross(center, 5.0, color, shadow)
		_:
			_draw_bloom(center, clampf(_spread_radius(), MIN_BLOOM, MAX_BLOOM), color, shadow)
	var spin := player.spin_progress()
	if spin > 0.1 or player.trick_window_left > 0.0:
		var start := -PI / 2.0
		var sweep := TAU if player.trick_window_left > 0.0 else TAU * spin
		draw_arc(center, SPIN_RING_RADIUS, start, start + sweep, 64, shadow, 5.0, true)
		draw_arc(center, SPIN_RING_RADIUS, start, start + sweep, 64, Player.TRICK_COLOR, 3.0, true)
	if player.weapon.is_reloading or player.weapon.is_clearing:
		var start := -PI / 2.0
		var end := start + TAU * player.weapon.reload_progress()
		draw_arc(center, RELOAD_RING_RADIUS, start, end, 40, shadow, 4.0)
		draw_arc(center, RELOAD_RING_RADIUS, start, end, 40, color, 2.0)
	if _hit_time > 0.0 and _hit_trick:
		_draw_trick_marker(center)
	elif _hit_time > 0.0:
		var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
		var t := _hit_time / HIT_MARKER_TIME
		var marker := KILL_COLOR if _hit_kill else Color.WHITE
		marker.a = 0.8 if reduced else t
		var size := 10.0 if reduced else 10.0 + 6.0 * t
		for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + corner * 5.0, center + corner * size, marker, 2.5)


## A trick-shot hit: a gold X with a diamond around it (red-gold for a kill), held twice as long.
func _draw_trick_marker(center: Vector2) -> void:
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	var t := _hit_time / (HIT_MARKER_TIME * 2.0)
	var color := Player.TRICK_COLOR.lerp(KILL_COLOR, 0.35) if _hit_kill else Player.TRICK_COLOR
	color.a = 0.9 if reduced else clampf(t * 1.5, 0.0, 1.0)
	var size := 14.0 if reduced else 14.0 + 10.0 * t
	for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_line(center + corner * 6.0, center + corner * size, Color(0, 0, 0, color.a * 0.6), 5.0)
		draw_line(center + corner * 6.0, center + corner * size, color, 3.0)
	var diamond := PackedVector2Array([center + Vector2(0, -size - 8), center + Vector2(size + 8, 0), center + Vector2(0, size + 8),
		center + Vector2(-size - 8, 0), center + Vector2(0, -size - 8)])
	draw_polyline(diamond, color, 2.0, true)


## Radius in pixels of the cone the next shot can land in, measured at the aim point.
func _spread_radius() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not player.has_aim:
		return 0.0
	var origin := player.global_position + Vector3.UP * player.gun_height()
	var to_aim := player.aim_point - origin
	var side := to_aim.cross(Vector3.UP).normalized()
	if to_aim.length() < 0.5 or side.is_zero_approx():
		return 0.0
	var edge := player.aim_point + side * to_aim.length() * tan(deg_to_rad(player.current_spread()))
	return camera.unproject_position(edge).distance_to(camera.unproject_position(player.aim_point))


## The bloom circle: the spread cone at the aim point, with four short ticks outside it and a dot in
## the middle.
func _draw_bloom(center: Vector2, radius: float, color: Color, shadow: Color) -> void:
	draw_arc(center, radius, 0.0, TAU, 64, shadow, 3.5, true)
	draw_arc(center, radius, 0.0, TAU, 64, color, 1.5, true)
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + direction * (radius + 3.0), center + direction * (radius + 9.0), shadow, 4.0)
		draw_line(center + direction * (radius + 3.0), center + direction * (radius + 9.0), color, 2.0)
	draw_circle(center, 2.5, shadow)
	draw_circle(center, 1.5, color)


func _draw_cross(center: Vector2, gap: float, color: Color, shadow: Color) -> void:
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + direction * gap, center + direction * (gap + 9.0), shadow, 4.0)
		draw_line(center + direction * gap, center + direction * (gap + 9.0), color, 2.0)
	draw_circle(center, 1.5, color)
