extends Control
## In-raid aiming reticle (DESIGN.md §17): drawn at the player's reticle position in the style and
## colour chosen in Settings > Interface. The "bloom" style opens up while moving or firing.
## Hit markers show here too.

const HIT_MARKER_TIME := 0.25
const KILL_COLOR := Color(1.0, 0.3, 0.25)

var player: Player

var _hit_time := 0.0
var _hit_kill := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_hit_time = maxf(_hit_time - delta, 0.0)
	queue_redraw()


func show_hit_marker(killed: bool) -> void:
	_hit_time = HIT_MARKER_TIME
	_hit_kill = killed


func _draw() -> void:
	if player == null or player.is_dead:
		return
	var center := player.cursor_position
	var color := Settings.reticle_color()
	var shadow := Color(0, 0, 0, 0.6)
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
			_draw_cross(center, 5.0 + player.aim_spread() * 22.0, color, shadow)
	if _hit_time > 0.0:
		var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
		var t := _hit_time / HIT_MARKER_TIME
		var marker := KILL_COLOR if _hit_kill else Color.WHITE
		marker.a = 0.8 if reduced else t
		var size := 10.0 if reduced else 10.0 + 6.0 * t
		for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + corner * 5.0, center + corner * size, marker, 2.5)


func _draw_cross(center: Vector2, gap: float, color: Color, shadow: Color) -> void:
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + direction * gap, center + direction * (gap + 9.0), shadow, 4.0)
		draw_line(center + direction * gap, center + direction * (gap + 9.0), color, 2.0)
	draw_circle(center, 1.5, color)
