class_name CoverRoute
extends RefCounted
## Travel routes that keep to walls and cover (DESIGN.md §4.4): an AI PMC walking to a point of interest
## or its extract doesn't cut across open ground when going along the walls isn't much longer. The plain
## navmesh path is sampled every sample_spacing metres; each sample is pulled to the nearest cover point
## (CoverSystem: 0.45 m off a wall, a crate, a car) within hug_radius of it, preferring one near the last
## (so the route keeps to one side), and the route runs through those anchors on the navmesh. If that
## comes out longer than max_detour × the plain path, the plain path it is (data/config/pmc_ai.json
## "route"). Built once per leg; cover_distance() measures how close a route keeps to cover.

## Grid cell size (metres) of the cover point lookup.
const CELL := 4.0

## The lookup: cell -> cover points in it, for the point list it was built from.
static var _cells := {}
static var _cells_for: Array[CoverPoint] = []
static var _cells_size := -1
static var _cells_first: CoverPoint


## The plain navmesh path from `from` to `to` on `map` (empty if there's none yet).
static func plain(map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, from, to, true)


## A route from `from` to `to` keeping to the cover in `points`: {"points": the waypoints,
## "cover": 1 for each waypoint that is a cover spot, "plain": the plain path's length, "length"}.
## Empty points if there's no path.
static func build(map: RID, from: Vector3, to: Vector3, points: Array[CoverPoint], tuning: Dictionary) -> Dictionary:
	var path := plain(map, from, to)
	var result := {"points": path, "cover": PackedByteArray(), "plain": length(path), "length": length(path)}
	result.cover.resize(path.size())
	if path.size() < 2:
		return result
	var spacing := maxf(float(tuning.get("sample_spacing", 2.5)), 0.5)
	var reach := float(tuning.get("hug_radius", 3.0))
	var max_detour := float(tuning.get("max_detour", 1.35))
	var samples := resample(path, spacing)
	var anchors: Array[Vector3] = [from]
	var is_cover: Array[bool] = [false]
	for i in range(1, samples.size()):
		var sample := samples[i]
		if sample.distance_to(to) < spacing:
			break
		var spot: Variant = _nearest_cover(points, sample, reach, anchors[-1], map)
		var at: Vector3 = spot if spot != null else sample
		if at.distance_to(anchors[-1]) < 1.0:
			continue
		anchors.append(at)
		is_cover.append(spot != null)
	anchors.append(to)
	is_cover.append(false)
	var route := PackedVector3Array([from])
	var flags := PackedByteArray([0])
	for i in range(1, anchors.size()):
		var leg := NavigationServer3D.map_get_path(map, route[-1], anchors[i], true)
		if leg.size() < 2:
			continue
		for j in range(1, leg.size()):
			route.append(leg[j])
			flags.append(1 if j == leg.size() - 1 and is_cover[i] else 0)
	var total := length(route)
	if route.size() < 2 or route[-1].distance_to(path[-1]) > 1.0 or total > result.plain * max_detour:
		return result  # Too long a way round, or it doesn't get there: the plain path.
	return {"points": route, "cover": flags, "plain": result.plain, "length": total}


## Points every `spacing` metres along `path`, from its start (not including its end).
static func resample(path: PackedVector3Array, spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if path.is_empty():
		return out
	out.append(path[0])
	var carry := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var segment := a.distance_to(b)
		var at := spacing - carry
		while at < segment:
			out.append(a.lerp(b, at / segment))
			at += spacing
		carry = segment - (at - spacing)
	return out


## The path's length in metres.
static func length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## How far from cover `path` keeps on average (metres): the distance from points every 0.5 m along it
## to the nearest cover point in `points` (capped at 10 m). What hugging walls and cover improves.
static func cover_distance(path: PackedVector3Array, points: Array[CoverPoint]) -> float:
	var samples := resample(path, 0.5)
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in samples:
		var nearest := 10.0
		for point in _near(points, sample, 10.0):
			nearest = minf(nearest, Vector2(point.position.x - sample.x, point.position.z - sample.z).length())
		total += nearest
	return total / samples.size()


## The cover point within `reach` of `sample` (and on its floor, on the navmesh) nearest to it, with a
## small pull toward `previous` so a route keeps to one side of a corridor. Null if none.
static func _nearest_cover(points: Array[CoverPoint], sample: Vector3, reach: float, previous: Vector3, map: RID) -> Variant:
	var best: Variant = null
	var best_score := INF
	for point in _near(points, sample, reach):
		var flat := Vector2(point.position.x - sample.x, point.position.z - sample.z).length()
		if flat > reach or absf(point.position.y - sample.y) > 1.0:
			continue
		var score := flat + 0.3 * point.position.distance_to(previous)
		if score >= best_score:
			continue
		var on_navmesh := NavigationServer3D.map_get_closest_point(map, point.position)
		if Vector2(on_navmesh.x - point.position.x, on_navmesh.z - point.position.z).length() > CoverSystem.NAVMESH_TOLERANCE:
			continue
		best = on_navmesh
		best_score = score
	return best


## Cover points within `radius` of `at` (and a few more), through a grid built once per point list.
static func _near(points: Array[CoverPoint], at: Vector3, radius: float) -> Array[CoverPoint]:
	if not is_same(_cells_for, points) or _cells_size != points.size() or (not points.is_empty() and not is_same(_cells_first, points[0])):
		_cells.clear()
		for point in points:
			var key := Vector2i(floori(point.position.x / CELL), floori(point.position.z / CELL))
			if not _cells.has(key):
				_cells[key] = []
			_cells[key].append(point)
		_cells_for = points
		_cells_size = points.size()
		_cells_first = points[0] if not points.is_empty() else null
	var result: Array[CoverPoint] = []
	var low := Vector2i(floori((at.x - radius) / CELL), floori((at.z - radius) / CELL))
	var high := Vector2i(floori((at.x + radius) / CELL), floori((at.z + radius) / CELL))
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			for point: CoverPoint in _cells.get(Vector2i(x, z), []):
				result.append(point)
	return result
