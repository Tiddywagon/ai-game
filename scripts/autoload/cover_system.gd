extends Node
## Autoload "CoverSystem": every CoverBox and the cover points around them (DESIGN.md §13.3).
## The player and AI use the same points and can't take a spot someone else holds.
## Call the queries from _physics_process: they use physics queries.

## Distance from a cover's side to the centre of someone in cover (body radius 0.35 + 0.1).
const STAND_OFF := 0.45
## Cover spots stay at least this far from the ends of a side.
const EDGE_MARGIN := 0.3
## Distance between the cover points generated along each side.
const POINT_SPACING := 1.2
## Leaning out of tall cover puts the body centre this far past its end.
const PEEK_CLEARANCE := 0.5
## Two actors can't use cover spots closer together than this.
const PERSONAL_SPACE := 0.9
## A cover spot counts as reachable if the navmesh comes within this distance of it.
const NAVMESH_TOLERANCE := 0.6
## AI won't pick cover closer than this to the threat.
const MIN_THREAT_DISTANCE := 5.0
const BODY_RADIUS := 0.35
const STAND_HEIGHT := 1.8
## Gun height of someone standing, used to check that low cover can be shot over.
const GUN_HEIGHT := 1.3

var config: CombatConfig = preload("res://data/config/combat.tres")

var _boxes: Array[CoverBox] = []
var _points: Array[CoverPoint] = []
var _dirty := true
var _claims: Dictionary = {}  # Actor -> CoverPoint


func register(box: CoverBox) -> void:
	_boxes.append(box)
	_dirty = true


func unregister(box: CoverBox) -> void:
	_boxes.erase(box)
	_dirty = true


## Rebuilds the points on the next query, e.g. after the level's navigation mesh is baked.
func mark_dirty() -> void:
	_dirty = true


## All usable cover points, generated along every side of every CoverBox.
func get_points() -> Array[CoverPoint]:
	if _dirty:
		_rebuild()
	return _points


## Marks `point` as taken by `actor` (one spot per actor). Passing null releases it.
func claim(actor: Actor, point: CoverPoint) -> void:
	if point == null:
		_claims.erase(actor)
	else:
		_claims[actor] = point


func release(actor: Actor) -> void:
	_claims.erase(actor)


## True if no one else is in or heading to a spot this close.
func is_available(point: CoverPoint, actor: Actor) -> bool:
	for other in _claims.keys():
		if not is_instance_valid(other):
			_claims.erase(other)
		elif other != actor and _claims[other].position.distance_to(point.position) < PERSONAL_SPACE:
			return false
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other != actor and not other.is_dead and other.global_position.distance_to(point.position) < PERSONAL_SPACE:
			return false
	return true


## True if the cover is between the point and the threat, and actually hides someone ducked there.
func protects(point: CoverPoint, threat: Vector3) -> bool:
	if (threat - point.position).dot(point.normal) > -1.0:
		return false  # The threat isn't on the far side of the cover.
	var hidden_height := config.duck_height * 0.8 if point.is_low else 1.5
	return _blocked(threat + Vector3.UP * 1.5, point.position + Vector3.UP * hidden_height)


## Nearest cover spot within `max_distance` of the actor's body. With `toward` set, only cover
## the actor is moving into counts (used for snapping into cover at the end of a roll).
func find_snap_point(actor: Actor, max_distance: float, toward := Vector3.ZERO) -> CoverPoint:
	var position := actor.global_position
	var best: CoverPoint = null
	var best_gap := INF
	for box in _boxes:
		if not box.provides_cover or position.y < box.bottom_height() - 0.5 or position.y > box.bottom_height() + box.size.y:
			continue
		for face in 4:
			var f := box.get_face(face)
			var offset: Vector3 = position - f.center
			var gap: float = offset.dot(f.normal) - BODY_RADIUS
			if gap < -0.1 or gap > max_distance or gap >= best_gap:
				continue
			if absf(offset.dot(f.tangent)) > f.half_length + 0.2:
				continue
			if not toward.is_zero_approx() and (-f.normal).dot(toward.normalized()) < 0.5:
				continue
			var point := point_on_face(box, face, position)
			if point and is_available(point, actor):
				best = point
				best_gap = gap
	return best


## Best cover for an AI actor against a threat: protected, reachable, free, and preferably one it
## can shoot from. `avoid` skips spots near the cover the actor is leaving.
func find_cover(actor: Actor, threat: Vector3, max_distance: float, avoid: CoverPoint = null) -> CoverPoint:
	var map := actor.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return null  # The navmesh baked at raid start hasn't synced yet.
	var best: CoverPoint = null
	var best_score := INF
	for point in get_points():
		var distance := point.position.distance_to(actor.global_position)
		if distance > max_distance or point.position.distance_to(threat) < MIN_THREAT_DISTANCE:
			continue
		if avoid and point.position.distance_to(avoid.position) < 2.5:
			continue
		var score := distance + (0.0 if point.can_peek else 8.0)
		if score >= best_score or not is_available(point, actor) or not protects(point, threat):
			continue
		# Only spots the bot can walk to. The navmesh stops a body's radius short of walls,
		# so allow some gap; the bot walks the last bit directly.
		var on_navmesh := NavigationServer3D.map_get_closest_point(map, point.position)
		if Vector2(on_navmesh.x - point.position.x, on_navmesh.z - point.position.z).length() > NAVMESH_TOLERANCE:
			continue
		best = point
		best_score = score
	return best


## A cover point on `face` of `box`, at the spot along it nearest to `near`.
## Returns null if there's no room to stand there.
func point_on_face(box: CoverBox, face: int, near: Vector3) -> CoverPoint:
	var f := box.get_face(face)
	var half_length: float = f.half_length
	var reach := maxf(half_length - EDGE_MARGIN, 0.0)
	var along := clampf((near - f.center).dot(f.tangent), -reach, reach)
	var point := CoverPoint.new()
	point.box = box
	point.face = face
	point.normal = f.normal
	point.tangent = f.tangent
	point.position = f.center + f.tangent * along + f.normal * STAND_OFF
	point.is_low = box.size.y <= config.low_cover_max_height
	point.material = box.cover_material
	if not _is_free(point.position, config.duck_height if point.is_low else STAND_HEIGHT) or not _has_ground(point.position):
		return null
	if point.is_low:
		# Peeking means standing up and shooting over; something taller right behind (a car roof) stops that.
		var gun := point.position + Vector3.UP * GUN_HEIGHT
		point.can_peek = not _blocked(gun, gun - point.normal * (f.depth + 1.0))
	else:
		# Lean out past the nearest end of the cover, if it's close enough and there's room.
		for side: float in ([1.0, -1.0] if along >= 0.0 else [-1.0, 1.0]):
			var to_end := half_length - along * side
			if to_end > config.peek_edge_reach:
				continue
			var offset := point.tangent * side * (to_end + PEEK_CLEARANCE)
			var lean := point.position + offset
			if _is_free(lean, STAND_HEIGHT) and not _blocked(point.position + Vector3.UP, lean + Vector3.UP):
				point.can_peek = true
				point.peek_offset = offset
				break
	return point


func _rebuild() -> void:
	_points.clear()
	for box in _boxes:
		if not box.provides_cover:
			continue
		for face in 4:
			var f := box.get_face(face)
			var reach := maxf(f.half_length - EDGE_MARGIN, 0.0)
			var count := floori(reach * 2.0 / POINT_SPACING) + 1
			for i in count:
				var along := 0.0 if count == 1 else lerpf(-reach, reach, float(i) / (count - 1))
				var point := point_on_face(box, face, f.center + f.tangent * along)
				if point:
					_points.append(point)
	_dirty = false


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state


## True if a body of `height` fits standing at `feet` without touching the world.
func _is_free(feet: Vector3, height: float) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = height - 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = Actor.WORLD_MASK
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height / 2.0 + 0.05))
	return _space().intersect_shape(query, 1).is_empty()


func _has_ground(feet: Vector3) -> bool:
	return _blocked(feet + Vector3.UP * 0.3, feet + Vector3.DOWN * 0.3)


func _blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.WORLD_MASK)
	return not _space().intersect_ray(query).is_empty()
