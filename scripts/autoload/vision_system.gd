extends Node
## Autoload "VisionSystem": the vision rules the player and the AI share (DESIGN.md §13.6).
## - Occluders: every CoverBox and VisionOccluder registers here. They also sit on the "vision" physics
##   layer, so sight lines are rays against that layer at eye height: standing eyes pass over low
##   cover, crouched eyes don't.
## - Light: time of day (set by the level's RaidEnvironment) and DarkZones; darkness shortens vision.
## - Weather: fog and rain shorten vision.
## - view_for(actor) describes what an actor sees right now; can_see() tests one target against it;
##   visibility_polygon() traces the player's visible area for the fog-of-war mask.

## Time of day or weather changed.
signal conditions_changed

## Physics layer 4, named "vision" in Project Settings.
const VISION_MASK := 8
## Angle offset of the rays cast just past each occluder corner, so shadow edges are exact.
const CORNER_EPSILON := 0.0004
## Rays around the awareness circle.
const AWARENESS_RAYS := 36
## The lit strip drawn on top of a visible wall face is at most this deep.
const MAX_FACE_DEPTH := 2.5

var config: VisionConfig = preload("res://data/config/vision.tres")
var time_of_day := VisionConfig.TimeOfDay.DAY
var weather := VisionConfig.Weather.CLEAR

var _occluders: Array[Node3D] = []
var _dark_zones: Array[Node3D] = []
var _dirty := true
# Corner cache: flat positions and the height span of the occluder each belongs to.
var _corners := PackedVector2Array()
var _bottoms := PackedFloat32Array()
var _tops := PackedFloat32Array()
var _bounds := Rect2()
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_query.collision_mask = VISION_MASK
	_query.collide_with_areas = false


# --- Registry ---------------------------------------------------------------------------------

## Called by occluders as they enter the tree. An occluder implements vision_corners(),
## vision_height_span() and vision_depth(normal).
func register_occluder(occluder: Node3D) -> void:
	if occluder not in _occluders:
		_occluders.append(occluder)
		_dirty = true


func unregister_occluder(occluder: Node3D) -> void:
	_occluders.erase(occluder)
	_dirty = true


## Call after moving an occluder (an opened door).
func mark_dirty() -> void:
	_dirty = true


func register_dark_zone(zone: Node3D) -> void:
	if zone not in _dark_zones:
		_dark_zones.append(zone)


func unregister_dark_zone(zone: Node3D) -> void:
	_dark_zones.erase(zone)


func dark_zones() -> Array[Node3D]:
	return _dark_zones


## The flat area covered by occluders plus a margin, as a square: the vision masks are drawn over it.
func world_bounds() -> Rect2:
	_refresh()
	return _bounds


# --- Conditions -------------------------------------------------------------------------------

func set_conditions(new_time: VisionConfig.TimeOfDay, new_weather: VisionConfig.Weather) -> void:
	time_of_day = new_time
	weather = new_weather
	conditions_changed.emit()


## Light level at `position` (0 = pitch dark, 1 = daylight): the time of day, or a dark room's.
func light_at(position: Vector3) -> float:
	var light: float = config.time_light[time_of_day]
	for zone in _dark_zones:
		if zone.contains(position):
			light = minf(light, zone.light_level())
	return light


func weather_multiplier() -> float:
	return config.weather_range[weather]


static func time_name(time: VisionConfig.TimeOfDay) -> String:
	return ["Day", "Dusk", "Night"][time]


static func weather_name(kind: VisionConfig.Weather) -> String:
	return ["Clear", "Fog", "Rain"][kind]


# --- Seeing -----------------------------------------------------------------------------------

## What `actor` sees right now: its cones (status effects and optics applied by the actor, weather
## here), awareness circle and posture. Blind actors keep only the awareness circle.
func view_for(actor: Actor) -> VisionView:
	var view := VisionView.new()
	view.origin = actor.global_position
	view.facing = actor.vision_facing()
	view.low = actor.is_low_profile()
	view.awareness = actor.awareness_radius()
	view.space = actor.get_world_3d().direct_space_state
	if not actor.is_blind():
		var multiplier := weather_multiplier()
		for cone in actor.vision_cones():
			view.cones.append(Vector3(cone.x, cone.y * multiplier, cone.z))
	return view


## True if `view` sees `target`: close enough in that direction (for the light where the target is,
## or in the viewer's flashlight beam), with a clear sight line to its centre or either side. A target
## with its flashlight on is easier to spot. `ignore_cones`: any direction counts as in view.
func can_see(view: VisionView, target: Actor, ignore_cones := false) -> bool:
	var origin := Vector2(view.origin.x, view.origin.z)
	var centre := Vector2(target.global_position.x, target.global_position.z)
	var to := centre - origin
	var distance := to.length()
	var direction := to / distance if distance > 0.001 else view.facing
	var light := 1.0 if target.has_light_on() or view.lit_toward(direction) else light_at(target.global_position)
	var reach := view.range_toward(direction, light, config, ignore_cones)
	if target.has_light_on():
		reach *= config.flashlight_conspicuity
	if distance > reach + Actor.BODY_RADIUS:
		return false
	var low := view.low or target.is_low_profile()
	var side := Vector2(-direction.y, direction.x) * Actor.BODY_RADIUS * 0.8
	for point in [centre, centre + side, centre - side]:
		if line_clear(view.space, view.origin, Vector3(point.x, target.global_position.y, point.y), low):
			return true
	return false


## True if `view` sees a spot on the ground (an item lying there): within reach in that light and with
## a clear sight line.
func can_see_point(view: VisionView, point: Vector3) -> bool:
	var origin := Vector2(view.origin.x, view.origin.z)
	var to := Vector2(point.x, point.z) - origin
	var distance := to.length()
	var direction := to / distance if distance > 0.001 else view.facing
	var light := 1.0 if view.lit_toward(direction) else light_at(point)
	if distance > view.range_toward(direction, light, config):
		return false
	return line_clear(view.space, view.origin, point, view.low)


## True if nothing on the vision layer is between `from` and `to` (feet positions) at eye height:
## crouched eye height if `low` (either end crouched), so low cover counts, standing otherwise.
func line_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, low: bool) -> bool:
	var height := config.crouched_eye_height if low else config.standing_eye_height
	_query.from = from + Vector3.UP * height
	_query.to = to + Vector3.UP * height
	return space.intersect_ray(_query).is_empty()


## The area `view` sees, by 2D shadow casting: rays along each cone's arc, around the awareness
## circle, and just either side of every occluder corner in reach, so walls cast clean shadows.
## Returns {"origin": Vector2, "points": PackedVector2Array (sorted by angle, closing a fan around the
## origin), "lit": PackedByteArray (1 where a point is in the flashlight beam), "faces":
## PackedVector2Array (quads, 4 points each: the visible strips of occluder tops, so walls you look at
## aren't dark)}.
func visibility_polygon(view: VisionView) -> Dictionary:
	_refresh()
	var eye_y := view.origin.y + (config.crouched_eye_height if view.low else config.standing_eye_height)
	var origin := Vector2(view.origin.x, view.origin.z)
	var light := light_at(view.origin)
	var base := view.facing.angle()
	var angles := PackedFloat32Array()
	var step := deg_to_rad(config.arc_step_degrees)
	for cone in view.cones:
		var count := maxi(1, ceili(2.0 * cone.x / step))
		for i in count + 1:
			angles.append(base - cone.x + 2.0 * cone.x * i / count)
		for edge in [-cone.x, cone.x]:
			angles.append(base + edge - CORNER_EPSILON)
			angles.append(base + edge + CORNER_EPSILON)
	for i in AWARENESS_RAYS:
		angles.append(TAU * i / AWARENESS_RAYS)
	var reach := view.max_range()
	for i in _corners.size():
		if _bottoms[i] > eye_y or _tops[i] < eye_y:
			continue  # The sight line passes over (or under) this occluder.
		var to := _corners[i] - origin
		var distance_squared := to.length_squared()
		if distance_squared > reach * reach or distance_squared < 0.0025:
			continue
		var distance := sqrt(distance_squared)
		if view.range_toward(to / distance, light, config) < distance - 0.01:
			continue  # Outside the view in that direction.
		var angle := to.angle()
		angles.append(angle - CORNER_EPSILON)
		angles.append(angle)
		angles.append(angle + CORNER_EPSILON)
	for i in angles.size():
		angles[i] = fposmod(angles[i], TAU)
	angles.sort()

	var points := PackedVector2Array()
	var lit := PackedByteArray()
	var normals := PackedVector2Array()
	var colliders: Array[Object] = []
	var last := -1.0
	for angle in angles:
		if angle - last < 0.00001:
			continue
		last = angle
		var direction := Vector2.from_angle(angle)
		var end := origin + direction * view.range_toward(direction, light, config)
		_query.from = Vector3(origin.x, eye_y, origin.y)
		_query.to = Vector3(end.x, eye_y, end.y)
		var hit := view.space.intersect_ray(_query)
		if hit.is_empty():
			points.append(end)
			normals.append(Vector2.ZERO)
			colliders.append(null)
		else:
			points.append(Vector2(hit.position.x, hit.position.z))
			normals.append(Vector2(hit.normal.x, hit.normal.z).normalized())
			colliders.append(hit.collider)
		lit.append(1 if view.lit_toward(direction) else 0)

	# Where two neighbouring rays hit the same face, light the strip of occluder behind it.
	var faces := PackedVector2Array()
	for i in points.size():
		var j := (i + 1) % points.size()
		var collider := colliders[i]
		if collider == null or collider != colliders[j] or normals[i].dot(normals[j]) < 0.99:
			continue
		var normal := normals[i]
		var depth := 0.5
		if collider.has_method("vision_depth"):
			depth = collider.vision_depth(Vector3(normal.x, 0.0, normal.y))
		depth = minf(depth, MAX_FACE_DEPTH)
		faces.append_array([points[i], points[j], points[j] - normal * depth, points[i] - normal * depth])
	return {"origin": origin, "points": points, "lit": lit, "faces": faces}


func _refresh() -> void:
	if not _dirty:
		return
	_dirty = false
	_corners.clear()
	_bottoms.clear()
	_tops.clear()
	var area := Rect2()
	var first := true
	for occluder in _occluders:
		if not is_instance_valid(occluder) or not occluder.is_inside_tree():
			continue
		var span: Vector2 = occluder.vision_height_span()
		for corner: Vector2 in occluder.vision_corners():
			_corners.append(corner)
			_bottoms.append(span.x)
			_tops.append(span.y)
			if first:
				area = Rect2(corner, Vector2.ZERO)
				first = false
			else:
				area = area.expand(corner)
	# Square, with a margin, so mask pixels are square too.
	var side := maxf(area.size.x, area.size.y) + 20.0
	_bounds = Rect2(area.get_center() - Vector2.ONE * side / 2.0, Vector2.ONE * side)
