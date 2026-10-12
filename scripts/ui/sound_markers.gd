extends Control
## Direction markers at the screen edge for sounds the player hears but can't see (DESIGN.md §13.6):
## each points from the player toward the sound and fades out after a moment. Shape and colour say what
## it was: a double red chevron for gunshots, a white ring for a flashbang, a single amber chevron for a
## roll, a small pale chevron for footsteps. One marker per source, refreshed by each new sound.

const STYLES := {
	&"gunshot": {"color": Color(0.95, 0.35, 0.25), "size": 1.3, "double": true},
	&"flashbang": {"color": Color(1.0, 1.0, 1.0), "size": 1.3, "ring": true},
	&"roll": {"color": Color(0.95, 0.7, 0.3), "size": 1.0},
	&"footstep": {"color": Color(0.85, 0.85, 0.75), "size": 0.75},
	&"other": {"color": Color(0.85, 0.85, 0.75), "size": 0.9},
}
## Distance of the markers from the screen edge, in pixels.
const EDGE_INSET := 70.0

var player: Player

var _markers := {}
var _next_key := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func add_marker(position: Vector3, kind: StringName, source_id: int) -> void:
	var key: Variant = source_id
	if source_id == 0:
		_next_key += 1
		key = "sound%d" % _next_key
	var duration := VisionSystem.config.sound_marker_time * (1.5 if kind == &"gunshot" or kind == &"flashbang" else 1.0)
	_markers[key] = {"position": position, "kind": kind if STYLES.has(kind) else &"other", "time": duration, "duration": duration}


func marker_count() -> int:
	return _markers.size()


func _process(delta: float) -> void:
	for key in _markers.keys():
		_markers[key].time -= delta
		if _markers[key].time <= 0.0:
			_markers.erase(key)
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or player == null or not is_instance_valid(player):
		return
	var from := camera.unproject_position(player.global_position)
	var center := size / 2.0
	var radii := size / 2.0 - Vector2.ONE * EDGE_INSET
	for marker in _markers.values():
		var direction := camera.unproject_position(marker.position) - from
		if direction.length() < 1.0:
			continue
		direction = direction.normalized()
		# Where that direction meets an ellipse just inside the screen edge.
		var reach := 1.0 / sqrt(pow(direction.x / radii.x, 2.0) + pow(direction.y / radii.y, 2.0))
		var point := center + direction * reach
		var style: Dictionary = STYLES[marker.kind]
		var color: Color = style.color
		color.a = clampf(marker.time / marker.duration * 1.5, 0.0, 1.0)
		var scale_by: float = style.size
		if style.get("ring", false):
			draw_arc(point, 13.0 * scale_by, 0.0, TAU, 32, Color(0, 0, 0, color.a * 0.6), 5.0)
			draw_arc(point, 13.0 * scale_by, 0.0, TAU, 32, color, 2.5)
		_draw_chevron(point, direction, scale_by, color)
		if style.get("double", false):
			_draw_chevron(point - direction * 11.0 * scale_by, direction, scale_by, color)


func _draw_chevron(point: Vector2, direction: Vector2, scale_by: float, color: Color) -> void:
	var side := Vector2(-direction.y, direction.x)
	var tip := point + direction * 10.0 * scale_by
	var points := PackedVector2Array([point - direction * 4.0 * scale_by + side * 11.0 * scale_by, tip,
		point - direction * 4.0 * scale_by - side * 11.0 * scale_by])
	draw_polyline(points, Color(0, 0, 0, color.a * 0.6), 6.0 * scale_by)
	draw_polyline(points, color, 3.0 * scale_by)
