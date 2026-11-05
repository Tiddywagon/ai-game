class_name RaidPlan
extends RefCounted
## An AI PMC squad's raid plan (DESIGN.md §4.4), made when the squad spawns and seeded in a seeded raid:
## its personality (PmcAi: Rat, Looter, Chad or Quester), its gear tier, the 2-4 points of interest it
## means to visit in order, the extract it means to leave through (one every member can use:
## ExtractZone.usable_by()) and when it means to leave. The squad's leader works through it (Bot):
## TRAVEL to the next POI, LOOT it, on to the next, then EXTRACT; fights, noises, raid events, treating
## wounds and hiding interrupt it (`goal` says what it's doing now).
## The POIs and the extract go by path distance on the navmesh, so they're picked (choose()) when the
## leader first thinks with the navmesh ready: every POI it can reach (its requirement met, not hidden
## unless the personality knows hidden ones) is scored by what its tier is worth to the personality (a
## hidden stash it knows: its own value), its heat, how central or how quiet it is, against the path
## distance from where the squad is or the POI before; the best are taken one at a time, then visited in
## the shortest order. A Quester takes the map's quest targets. The extract is the usable one nearest the
## last POI. A POI it can't get to (stuck on the way) or that a Scav it hides from stands in front of is
## skipped (skip()).

enum Goal { TRAVEL, LOOT, EXTRACT, COMBAT, INVESTIGATE, HUNT, RUSH, HEAL, AVOID, COVER, REGROUP, FOLLOW, PATROL }
const GOAL_NAMES := ["travel", "loot", "extract", "combat", "investigate", "hunt", "rush", "heal", "avoid", "cover",
	"regroup", "follow", "patrol"]
## A POI's centre counts as reachable when the navmesh comes this close to it (flat metres) or it's inside.
const REACH_TOLERANCE := 3.0
## Within this of a hot POI (heat of a tier 3 one or more) a POI isn't quiet at all (Rat).
const QUIET_DISTANCE := 25.0
## choose() calls that may find no POI it can reach (the navmesh still coming up) before it settles for
## none.
const MAX_TRIES := 60

var personality: StringName = &""
var tier: StringName = &""
## The POIs to visit, in order; `index` is the next one (pois.size(): all visited).
var pois: Array[PointOfInterest] = []
var index := 0
var extract: ExtractZone
## Raid seconds when it leaves at the latest, and when the squad joined the raid.
var leave_at := -1.0
var spawned_at := 0.0
var goal := Goal.TRAVEL
## True once the POIs and extract are picked (choose()).
var chosen := false
## Why it headed out: "time", "low time", "bags full", "plan done" ("" until it does).
var reason := ""
## Path metres from where it started through its POIs to its extract.
var route_length := 0.0
## The squad's own rolls (seeded per squad in a seeded raid).
var rng := RandomNumberGenerator.new()
## Where the squad spawned: its POIs are picked from here (so a seeded raid picks the same ones however
## soon its leader gets to it). Vector3.INF: from wherever the leader is.
var start := Vector3.INF
## The POIs it has finished, and those it skipped (couldn't get to: Bot): ids.
var visited: Array[String] = []
var skipped: Array[String] = []

## Tries at picking while the navmesh doesn't reach any POI yet (just baked).
var _tries := 0


## A new plan seeded with `plan_seed`: a personality, a gear tier for a map of `difficulty`, and a
## leave time in the personality's leave window of a `raid_seconds` raid (a squad joining at `now`
## stays at least PmcAi.plan() min_stay).
static func roll(plan_seed: int, raid_seconds: float, now: float, difficulty: int) -> RaidPlan:
	var plan := RaidPlan.new()
	plan.rng.seed = plan_seed
	plan.personality = PmcAi.roll_personality(plan.rng)
	plan.tier = PmcAi.roll_tier(plan.rng, difficulty)
	plan.spawned_at = now
	var window := PmcAi.pair(plan.knobs().get("leave_window"), [0.45, 0.85])
	plan.leave_at = raid_seconds * plan.rng.randf_range(float(window[0]), float(window[1]))
	if now > 0.0:
		plan.leave_at = maxf(plan.leave_at, now + float(PmcAi.plan().get("min_stay", 120.0)))
	return plan


## The personality's knobs (PmcAi.personality()).
func knobs() -> Dictionary:
	return PmcAi.personality(personality)


func personality_name() -> String:
	return PmcAi.personality_name(personality)


func tier_name() -> String:
	return PmcAi.tier_name(tier)


func goal_name() -> String:
	return GOAL_NAMES[goal]


## The next POI to visit (null once they're all visited, or a freed one is skipped).
func next_poi() -> PointOfInterest:
	while index < pois.size() and not is_instance_valid(pois[index]):
		index += 1
	return pois[index] if index < pois.size() else null


func pois_left() -> int:
	return maxi(pois.size() - index, 0)


## True once every POI has been visited (never for a plan that found none to visit).
func is_done() -> bool:
	return chosen and not pois.is_empty() and next_poi() == null


## The POI it was at is done: on to the next.
func advance() -> void:
	var poi := next_poi()
	if poi:
		visited.append(poi.poi_id)
		index += 1


## The POI it was heading for can't be got to: on to the next, without counting it as visited.
func skip() -> void:
	var poi := next_poi()
	if poi:
		skipped.append(poi.poi_id)
		index += 1


## Where it walks to for `poi`: its centre, on the navmesh.
static func poi_point(poi: PointOfInterest) -> Vector3:
	var map := poi.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return poi.global_position
	return NavigationServer3D.map_get_closest_point(map, poi.global_position)


## Picks the POIs and the extract for a squad of `members` led by `leader`, from where it spawned
## (`start`; else where the leader stands). Once: true when done. False, picking nothing, while the
## navmesh isn't ready (for a moment after it's baked it reaches nothing: it tries again, from the same
## rolls, for MAX_TRIES calls).
func choose(leader: Bot, members: Array[Bot]) -> bool:
	if chosen:
		return true
	var map := leader.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var raid := leader._raid_controller()
	var map_id := raid.map_key() if raid else ""
	var cache := {}
	var distance := func(a: Vector3, b: Vector3) -> float: return path_distance(map, a, b, cache)
	var from := start if start.is_finite() else leader.global_position
	var rolls := rng.state
	pois = pick_pois(candidates(leader.get_tree(), knobs(), leader, map_id), from, knobs(), rng, distance,
		PmcAi.quest_targets(map_id), raid.elapsed if raid else 0.0)
	if pois.is_empty() and _tries < MAX_TRIES:
		_tries += 1
		rng.state = rolls  # The same rolls next time.
		return false
	chosen = true
	var last := poi_point(pois[-1]) if not pois.is_empty() else from
	extract = pick_extract(leader.get_tree(), members, last, distance)
	route_length = 0.0
	var at := from
	for poi in pois:
		route_length += distance.call(at, poi_point(poi))
		at = poi_point(poi)
	if extract:
		route_length += distance.call(at, extract.global_position)
	return true


## The POIs in `tree` a squad led by `who` could plan for: not hidden (unless `knobs` know hidden ones,
## or it's one of the map's quest targets for a Quester), their requirement met.
static func candidates(tree: SceneTree, knobs: Dictionary, who: Actor, map_id: String) -> Array[PointOfInterest]:
	var result: Array[PointOfInterest] = []
	var poi_knobs := PmcAi.dict(knobs.get("pois"))
	var quest: Array = PmcAi.quest_targets(map_id) if poi_knobs.get("quest", false) else []
	for node in tree.get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		if poi == null or poi.entry().is_empty():
			continue
		if poi.is_hidden() and not poi_knobs.get("knows_hidden", false) and not poi.poi_id in quest:
			continue
		if not poi.requirement_met(who):
			continue
		result.append(poi)
	return result


## 2-4 of `candidates` (knobs "pois" count) to visit from `start`, in order: the reachable ones
## (`distance` below INF to their point) scored by score(), the best taken one at a time from the last
## one taken, a Quester's `quest_ids` first; then the shortest order (best_order()).
static func pick_pois(candidates: Array[PointOfInterest], start: Vector3, knobs: Dictionary, rng: RandomNumberGenerator,
		distance: Callable, quest_ids: Array, elapsed: float) -> Array[PointOfInterest]:
	var poi_knobs := PmcAi.dict(knobs.get("pois"))
	var reachable: Array[PointOfInterest] = []
	for poi in candidates:
		if is_finite(distance.call(start, poi_point(poi))):
			reachable.append(poi)
	var chosen: Array[PointOfInterest] = []
	if reachable.is_empty():
		return chosen
	var count := PmcAi.pair(poi_knobs.get("count"), [2, 4])
	var want := mini(rng.randi_range(int(count[0]), int(count[1])), reachable.size())
	if poi_knobs.get("quest", false):
		for id: Variant in quest_ids:
			for poi in reachable:
				if poi.poi_id == str(id) and not poi in chosen:
					chosen.append(poi)
		want = maxi(want, chosen.size())
	var context := _context(reachable, start, distance, elapsed)
	var from := start
	while chosen.size() < want:
		var best: PointOfInterest = null
		var best_score := -INF
		for poi in reachable:
			if poi in chosen:
				continue
			var value := score(poi, from, poi_knobs, context, distance, elapsed) + PmcAi.number(poi_knobs, "random") * rng.randf()
			if value > best_score:
				best = poi
				best_score = value
		if best == null:
			break
		chosen.append(best)
		from = poi_point(best)
	return best_order(start, chosen, distance)


## How much a squad with `poi_knobs` wants `poi` coming from `from`: tier (what its tier is worth, or
## for a hidden stash it knows what hidden ones are worth to it), heat, centre and quiet (0-1 each, by
## their weights), less the path distance (as a share of the farthest reachable POI, by the distance
## weight). `context` is _context()'s.
static func score(poi: PointOfInterest, from: Vector3, poi_knobs: Dictionary, context: Dictionary, distance: Callable, elapsed: float) -> float:
	var at := poi_point(poi)
	var values: Variant = poi_knobs.get("tier_values")
	if not (values is Array and values.size() == 3):
		values = [0.3, 0.6, 1.0]
	var worth := float(values[clampi(poi.tier(), 1, 3) - 1])
	if poi.is_hidden() and poi_knobs.get("knows_hidden", false):
		worth = PmcAi.number(poi_knobs, "hidden", worth)
	var value := PmcAi.number(poi_knobs, "tier") * worth
	value += PmcAi.number(poi_knobs, "heat") * poi.heat(elapsed) / maxf(float(context.max_heat), 0.001)
	var centre: Vector3 = context.centre
	value += PmcAi.number(poi_knobs, "centre") * (1.0 - Vector2(at.x - centre.x, at.z - centre.z).length() / maxf(float(context.max_centre), 1.0))
	value += PmcAi.number(poi_knobs, "quiet") * quietness(poi, context.hot)
	value -= PmcAi.number(poi_knobs, "distance") * minf(float(distance.call(from, at)), float(context.far) * 2.0) / maxf(float(context.far), 1.0)
	return value


## 0 at (or within reach of) a hot POI, 1 at least QUIET_DISTANCE from every hot one in `hot`.
static func quietness(poi: PointOfInterest, hot: Array) -> float:
	var nearest := QUIET_DISTANCE
	for other: PointOfInterest in hot:
		if other == poi:
			return 0.0
		nearest = minf(nearest, other.global_position.distance_to(poi.global_position))
	return clampf(nearest / QUIET_DISTANCE, 0.0, 1.0)


## What score() compares against: the farthest reachable POI from `start`, the hottest, the middle of
## them and how far out the farthest from it is, and the hot ones (tier 3 heat or more: a tier 3 POI,
## or a fresh raid event; not a hidden stash, which draws nobody).
static func _context(reachable: Array[PointOfInterest], start: Vector3, distance: Callable, elapsed: float) -> Dictionary:
	var centre := Vector3.ZERO
	var far := 1.0
	var max_heat := 0.0
	var hot: Array = []
	var hot_heat: float = PoiTable.CONFIG.tier_heat[2] if PoiTable.CONFIG.tier_heat.size() >= 3 else 4.0
	for poi in reachable:
		centre += poi.global_position
		far = maxf(far, float(distance.call(start, poi_point(poi))))
		max_heat = maxf(max_heat, poi.heat(elapsed))
		if poi.heat(elapsed) >= hot_heat and not poi.is_hidden():
			hot.append(poi)
	centre /= maxf(reachable.size(), 1)
	var max_centre := 1.0
	for poi in reachable:
		max_centre = maxf(max_centre, Vector2(poi.global_position.x - centre.x, poi.global_position.z - centre.z).length())
	return {"centre": centre, "far": far, "max_heat": max_heat, "max_centre": max_centre, "hot": hot}


## `pois` in the order that makes the shortest walk from `start` through all of them (every order is
## tried: there are at most four).
static func best_order(start: Vector3, pois: Array[PointOfInterest], distance: Callable) -> Array[PointOfInterest]:
	var best: Array[PointOfInterest] = pois.duplicate()
	var best_length := INF
	for order in _permutations(pois.size()):
		var total := 0.0
		var at := start
		for i: int in order:
			total += float(distance.call(at, poi_point(pois[i])))
			at = poi_point(pois[i])
		if total < best_length - 0.01:
			best_length = total
			best = []
			for i: int in order:
				best.append(pois[i])
	return best


## Every order of 0..count-1.
static func _permutations(count: int) -> Array:
	if count <= 1:
		return [range(count)]
	var result := []
	for rest in _permutations(count - 1):
		for at in count:
			var order: Array = rest.duplicate()
			order.insert(at, count - 1)
			result.append(order)
	return result


## Path metres from `start` through `route` (POIs, in that order).
static func walk_length(start: Vector3, route: Array[PointOfInterest], distance: Callable) -> float:
	var total := 0.0
	var at := start
	for poi in route:
		total += float(distance.call(at, poi_point(poi)))
		at = poi_point(poi)
	return total


## The extract the squad (`members`) leaves through: every member can use it, nearest by path to
## `from` (its last POI); else the nearest the first member (the leader) can use; null if none.
static func pick_extract(tree: SceneTree, members: Array[Bot], from: Vector3, distance: Callable) -> ExtractZone:
	var best: ExtractZone = null
	var best_distance := INF
	var fallback: ExtractZone = null
	var fallback_distance := INF
	for zone: ExtractZone in tree.get_nodes_in_group("extract_zones"):
		if members.is_empty() or not zone.usable_by(members[0]):
			continue
		var length := float(distance.call(from, zone.global_position))
		if not is_finite(length):
			length = 1.0e6 + from.distance_to(zone.global_position)  # Reachable some other way, maybe.
		if length < fallback_distance:
			fallback = zone
			fallback_distance = length
		if length < best_distance and members.all(func(member: Bot) -> bool: return not is_instance_valid(member) or zone.usable_by(member)):
			best = zone
			best_distance = length
	return best if best else fallback


## Path metres on `map` from `a` to `b` (INF if the navmesh doesn't get within REACH_TOLERANCE of `b`),
## remembered in `cache`.
static func path_distance(map: RID, a: Vector3, b: Vector3, cache: Dictionary = {}) -> float:
	var key := [a.snapped(Vector3.ONE * 0.1), b.snapped(Vector3.ONE * 0.1)]
	if cache.has(key):
		return cache[key]
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	var length := INF
	if path.size() >= 2 and Vector2(path[-1].x - b.x, path[-1].z - b.z).length() <= REACH_TOLERANCE and absf(path[-1].y - b.y) < 1.5:
		length = CoverRoute.length(path)
	elif path.size() < 2 and a.distance_to(b) < 0.5:
		length = 0.0
	cache[key] = length
	return length
