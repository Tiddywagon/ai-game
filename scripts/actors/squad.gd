class_name Squad
extends RefCounted
## AI that move and fight together (DESIGN.md §4.3, §4.4): a boss and its guards (BossSpawn), or an AI
## PMC squad of 1-3 of one faction (RaidController). Squad mates are never hostile to each other
## (Actor.is_hostile()); they share what they see and join each other's fights, and out of a fight the
## followers keep to their spots near the leader (formation_spot(): a ring around it for a boss's guards,
## a wedge behind it for a PMC squad, facing the way the leader last moved) and go where it goes: a
## noise one of them heard (investigate()), the extract the leader picks at the time it picks
## (plan_extract(), pick_extract(): one they can all use if there is one). Whoever attacks one of them
## has the squad to deal with (Bot.provoke()). The first member leads; when the leader dies, leaves the
## raid or is removed from the scene the next living member takes over (leader_changed) and carries on
## with the leader's patrol and plans.
## Nothing here is about bosses: what a member is worth, whether it loots, rushes raid events or ever
## leaves the raid is its role's (Bot.role: boss, guard, or none).

## The leader died or left the raid and `leader` took over (null: nobody's left).
signal leader_changed(leader: Bot)
## A member was killed.
signal member_died(member: Bot)

enum Formation { RING, WEDGE }

## The leader counts as moving (and turns the formation) above this speed, m/s.
const HEADING_SPEED := 0.5

## Members in order of who leads next.
var members: Array[Bot] = []
var leader: Bot
## The PMC faction the squad belongs to (&"" for a boss's).
var faction: StringName = &""
var formation := Formation.WEDGE
## Metres from the leader to a follower's spot; degrees between the followers' spots in a wedge.
var spacing := 2.5
var wedge_degrees := 40.0
## A follower walks back to its spot once it's farther than this from it, and sprints when it's more
## than catch_up metres behind.
var tolerance := 2.0
var catch_up := 5.0
## Raid seconds when the squad heads for an extract (-1: never), once planned, and the extract its
## leader picked.
var extract_at := -1.0
var extract_planned := false
var extract_zone: ExtractZone
## Which way the formation faces (a yaw, like Node3D.rotation.y): the way the leader last moved, held
## while it stands looking around, so the followers don't circle it.
var heading := 0.0

## Game seconds when a member last called out each voice event (claim_call()).
var _calls := {}


## A squad of `bots` (the first leads), keeping together as factions.json "squads" says.
func _init(bots: Array[Bot] = [], squad_faction: StringName = &"") -> void:
	faction = squad_faction
	var tuning := Factions.squad_config()
	spacing = float(tuning.get("spacing", spacing))
	wedge_degrees = float(tuning.get("wedge_degrees", wedge_degrees))
	tolerance = float(tuning.get("tolerance", tolerance))
	catch_up = float(tuning.get("catch_up", catch_up))
	for bot in bots:
		add(bot)


func add(bot: Bot) -> void:
	if bot == null or bot in members:
		return
	members.append(bot)
	bot.squad = self
	if leader == null:
		leader = bot
		heading = bot.rotation.y
	bot.died.connect(_on_member_died.bind(bot))
	bot.tree_exiting.connect(_on_member_removed.bind(bot))


func size() -> int:
	return members.size()


func is_empty() -> bool:
	return members.is_empty()


func has(actor: Actor) -> bool:
	return actor is Bot and members.has(actor as Bot)


## Members still alive and in the raid.
func alive() -> Array[Bot]:
	var living: Array[Bot] = []
	for bot: Variant in members:
		if is_instance_valid(bot) and not (bot as Bot).is_dead:
			living.append(bot)
	return living


## The living members besides the leader, in order.
func followers() -> Array[Bot]:
	return alive().filter(func(bot: Bot) -> bool: return bot != leader)


## The living members besides `bot`.
func mates_of(bot: Bot) -> Array[Bot]:
	return alive().filter(func(mate: Bot) -> bool: return mate != bot)


## Where `bot` (a follower) keeps out of a fight: `spacing` metres from the leader, around it (RING) or
## fanned out behind it (WEDGE), turned the way the leader last moved (heading). Not through a wall
## (pulled in short of one) and on the navmesh. The leader's own spot is where it stands.
func formation_spot(bot: Bot) -> Vector3:
	if leader == null or bot == leader:
		return bot.global_position
	var ranks := followers()
	var index := maxi(ranks.find(bot), 0)
	var count := maxi(ranks.size(), 1)
	var moving := Vector2(leader.velocity.x, leader.velocity.z)
	if moving.length() > HEADING_SPEED:
		heading = atan2(-moving.x, -moving.y)
	var angle := heading
	if formation == Formation.RING:
		angle += TAU * float(index + 1) / float(count + 1)
	else:
		angle += deg_to_rad(wedge_degrees) * (float(index) - float(count - 1) / 2.0)
	# A yaw of 0 faces -Z, so (sin, cos) of it points behind.
	var spot := leader.global_position + Vector3(sin(angle), 0.0, cos(angle)) * spacing
	if not leader.is_inside_tree():
		return spot
	var world := leader.get_world_3d()
	var chest := Vector3.UP * 1.0
	var wall := world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(leader.global_position + chest, spot + chest, Actor.WORLD_MASK))
	if not wall.is_empty():
		var reach := maxf(leader.global_position.distance_to(wall.position - chest) - Actor.BODY_RADIUS * 1.5, 0.0)
		spot = leader.global_position + (spot - leader.global_position).normalized() * reach
	if NavigationServer3D.map_get_iteration_id(world.navigation_map) != 0:
		spot = NavigationServer3D.map_get_closest_point(world.navigation_map, spot)
	return spot


## Something one of them heard: every member that isn't fighting, fleeing or leaving goes to look
## (running if `urgent`), so the squad stays together.
func investigate(point: Vector3, urgent: bool) -> void:
	for bot in alive():
		if bot.ai_enabled and not bot.state in [Bot.State.COMBAT, Bot.State.FLEE, Bot.State.EXTRACT]:
			bot.investigate(point, urgent)


## When the squad heads for an extract: rolled once for the squad in `window` (shares of the raid),
## the same for every member. -1 for a squad that holds its ground (a boss's).
func plan_extract(raid: RaidController, window: Vector2, rng: RandomNumberGenerator) -> float:
	if not extract_planned:
		extract_planned = true
		extract_at = raid.raid_seconds() * rng.randf_range(window.x, window.y)
	return extract_at


## The extract the squad leaves through: the one the leader picked while it's still usable, else the
## one nearest the leader that every living member can use (a key, no backpack...), else the nearest the
## leader can use (null if none).
func pick_extract() -> ExtractZone:
	if leader == null or not is_instance_valid(leader):
		extract_zone = null
		return null
	if extract_zone and is_instance_valid(extract_zone) and extract_zone.usable_by(leader):
		return extract_zone
	extract_zone = leader._nearest_extract(alive())
	if extract_zone == null:
		extract_zone = leader._nearest_extract()
	return extract_zone


## Whether a member may call out `event` now: not if a squad mate called it within `seconds`, so the
## squad doesn't echo itself. Claims it if so.
func claim_call(event: StringName, seconds: float) -> bool:
	var now := float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second
	if _calls.has(event) and now < float(_calls[event]) + seconds:
		return false
	_calls[event] = now
	return true


## A member left the raid through an extract: the next one leads if it was the leader.
func member_left(bot: Bot) -> void:
	if bot == leader:
		_hand_over()


## A member was taken out of the scene (freed, despawned): it's no longer in the squad, and the next
## one leads if it was the leader.
func _on_member_removed(bot: Bot) -> void:
	members.erase(bot)
	if bot == leader:
		_hand_over()


func _on_member_died(bot: Bot) -> void:
	if bot == leader:
		_hand_over()
	member_died.emit(bot)
	for mate in alive():
		if mate.voice:
			mate.voice.say(&"mate_down")
			break


## The next living member leads, carrying on with the old leader's patrol.
func _hand_over() -> void:
	var old := leader
	var living := alive()
	leader = living[0] if not living.is_empty() else null
	if leader and old and is_instance_valid(old):
		if leader.wander_points.is_empty() and leader.patrol_points.is_empty():
			leader.wander_points = old.wander_points
			leader.patrol_points = old.patrol_points
	leader_changed.emit(leader)
