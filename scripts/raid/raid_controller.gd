class_name RaidController
extends Node
## Runs a raid on a map (DESIGN.md §2, §5): the start (a random spawn point for your side; the map's
## extracts from data/config/extracts.json, which random ones are open this raid and which quest ones
## you've unlocked), the raid clock, the map's power, raid experience (kills, loot, trick shots,
## extracting) and how the raid ends. Standing in an ExtractZone you can use for
## `RaidConfig.extract_seconds` extracts (SURVIVED, or a Run Through if it was quick and you earned
## little); walking out or getting hit starts the count again. A random extract turns from "Unknown" to
## open or closed once you've been close enough to see it. AI PMCs join the raid as squads of 1-3 of one
## faction (BEAR or USEC) at PMC spawn points you didn't get (_spawn_ai_pmcs()). AI Scavs and PMCs leave
## through the same extracts (Bot). Dying is KILLED; the clock running out or leaving from the pause menu is MIA. The
## ending is settled by RaidOutcome (found-in-raid status, what you keep, insurance) and shown by the
## level.

## The raid ended (the outcome is already settled and saved).
signal raid_ended(outcome: RaidOutcome)
## The power came on (extracts that need it open).
signal power_on
## The player walked into a point of interest (DESIGN.md §5.2) for the first time this raid;
## `first_time` if they'd never explored it before (it's now explored, with its experience).
signal poi_entered(poi: PointOfInterest, first_time: bool)

@export var player: Player
@export var config: RaidConfig = preload("res://data/config/raid.tres")
## The map this scene is (data/maps/), when it's played without ENTER RAID (GameState.raid "map").
@export var map_id := "test_yard"
## AI PMCs that join the raid (DESIGN.md §4.4, §5): this many in all, in squads of 1-3 (sizes rolled
## by Factions.squad_config(), each of one faction), one squad at each PMC spawn point the player didn't
## get.
@export_range(0, 8) var ai_pmcs := 0
@export var ai_pmc_profile: BotProfile = preload("res://data/bots/pmc.tres")
## Scav waves during the raid (RaidConfig), and the Scavs they bring.
@export var scav_waves := true
@export var scav_profile: BotProfile = preload("res://data/bots/scav.tres")
@export var poi_config: PoiConfig = preload("res://data/config/poi.tres")

var map: MapInfo
## Seconds since the raid started, and seconds left on the clock.
var elapsed := 0.0
var time_left := 0.0
## Raid experience so far, and where it came from: {"kills", "looting", "trick_shots", "exploration",
## "survived"}.
var xp := 0
var xp_parts := {"kills": 0, "looting": 0, "trick_shots": 0, "exploration": 0, "survived": 0}
## Who the player killed: [{"name", "side": "pmc" or "scav", "faction" (a PMC's: "bear" / "usec"),
## "role" (a boss's or guard's)}].
var kill_list: Array[Dictionary] = []
## Drip earned this raid (360 trick-shot kills), and the trick-shot kills: [{"side": "pmc" or "scav",
## "weapon_class"}] (for quests).
var drip := 0
var trick_kills: Array[Dictionary] = []
var outcome: RaidOutcome
## The extract zone the player is standing in, how long they've stood there able to use it, and the
## one they left through.
var extract_zone: ExtractZone
var extract_time := 0.0
var extracted_at := ""
## Where the raid started (null: the player's place in the scene).
var spawn_point: SpawnPoint
## AI that left through an extract: [{"name", "side": "pmc" or "scav", "faction", "extract"}].
var ai_extracts: Array[Dictionary] = []
## The AI PMC squads that joined the raid (Squad), in spawn order.
var ai_squads: Array[Squad] = []
## Rolls this raid: spawn point and random extracts. Seeded from GameState.raid "seed" if set.
var rng := RandomNumberGenerator.new()
## The point of interest the player is in (null: none), the ones they've been in this raid, and the
## ones explored for the first time this raid (ids).
var current_poi: PointOfInterest
var visited_pois: Array[String] = []
var discovered_pois: Array[String] = []
## Scav waves so far, and raid seconds until the next one.
var waves := 0
var next_wave := -1.0

## The map's power: seconds until it comes on after the switch is thrown (-1: off), and on.
var _power_countdown := -1.0
var _power_on := false
var _confirm_timer := 0.0


func _ready() -> void:
	add_to_group("raid_controller")
	map = MapInfo.find(GameState.raid.get("map", map_id))
	time_left = raid_seconds()
	if GameState.raid.has("seed"):
		rng.seed = int(GameState.raid.seed)
	else:
		rng.randomize()
	for zone: ExtractZone in get_tree().get_nodes_in_group("extract_zones"):
		zone.configure_for_map(map.id if map else map_id)
		zone.roll(rng)
	if player:
		player.hurt.connect(_on_player_hurt)
		player.killed.connect(_on_kill)
		player.loot_claimed.connect(_on_loot_claimed)
		player.trick_shot_hit.connect(_on_trick_shot_hit)
		player.died.connect(end_raid.bind(RaidOutcome.Status.KILLED))
		if is_real_raid() and GameState.raid.get("spawn", "") != "scene":
			_place_player()
		if ai_pmcs > 0:
			_spawn_ai_pmcs.call_deferred()
	if scav_waves:
		next_wave = rng.randf_range(config.scav_wave_interval.x, config.scav_wave_interval.y)


func _physics_process(delta: float) -> void:
	if _power_countdown >= 0.0:
		_power_countdown -= delta
		if _power_countdown <= 0.0:
			_power_countdown = -1.0
			_power_on = true
			power_on.emit()
			if player:
				player.action_blocked.emit("The power is on")
	if outcome or player == null or player.is_dead:
		return
	_confirm_timer -= delta
	if _confirm_timer <= 0.0:
		_confirm_timer = 0.25
		_confirm_extracts()
		_track_poi()
	elapsed += delta
	time_left = maxf(time_left - delta, 0.0)
	if next_wave >= 0.0 and elapsed >= next_wave:
		spawn_wave()
	if time_left <= 0.0:
		end_raid(RaidOutcome.Status.MIA)
		return
	if extract_zone and extract_zone.block_reason(player) == "":
		extract_time += delta
		if extract_time >= config.extract_seconds:
			extracted_at = extract_zone.extract_name
			extract_zone.use_up_item(player)
			end_raid(RaidOutcome.extract_status(elapsed, xp, config))
	else:
		extract_time = 0.0


func is_over() -> bool:
	return outcome != null


## The raid's full length in seconds (the map's raid time).
func raid_seconds() -> float:
	return (map.raid_minutes if map else 15) * 60.0


## The extracts the player has this raid: the ones for their side, without quest extracts they haven't
## unlocked, in the order they're placed.
func available_extracts() -> Array[ExtractZone]:
	var zones: Array[ExtractZone] = []
	for zone: ExtractZone in get_tree().get_nodes_in_group("extract_zones"):
		if zone.available and zone.allows_side(side()):
			zones.append(zone)
	return zones


## "pmc" or "scav".
func side() -> String:
	return str(GameState.raid.get("side", "pmc"))


## Seconds of standing still in an extract left, or -1 when not extracting (outside one, or in one you
## can't use yet: extract_block()).
func extract_remaining() -> float:
	if extract_zone == null or outcome or extract_zone.block_reason(player) != "":
		return -1.0
	return maxf(config.extract_seconds - extract_time, 0.0)


## 0 to 1 through the extract countdown (0 when not extracting).
func extract_progress() -> float:
	var left := extract_remaining()
	return 1.0 - left / config.extract_seconds if left >= 0.0 and config.extract_seconds > 0.0 else 0.0


## Why the extract the player stands in won't take them yet ("" when it will, or when they're not in
## one).
func extract_block() -> String:
	return extract_zone.block_reason(player) if extract_zone and not outcome else ""


## True when the raid was started from ENTER RAID, so its ending changes the profile.
func is_real_raid() -> bool:
	return GameState.raid.has("side")


func enter_extract(zone: ExtractZone) -> void:
	extract_zone = zone
	extract_time = 0.0


func leave_extract(zone: ExtractZone) -> void:
	if extract_zone == zone:
		extract_zone = null


## An AI Scav or PMC left through `zone`: it's gone from the raid (with its gear).
func bot_extracted(bot: Bot, zone: ExtractZone) -> void:
	ai_extracts.append({"name": bot.display_name(), "side": "scav" if bot.side == Actor.Side.SCAV else "pmc",
		"faction": String(bot.faction), "extract": zone.extract_name})
	bot.leave_raid()


## A hit restarts the extract countdown.
func _on_player_hurt(_damage: float) -> void:
	if extract_zone and extract_time > 0.0 and not outcome:
		extract_time = 0.0
		player.action_blocked.emit("Hit: extraction restarted")


## Random extracts the player is close enough to see become known (open or closed).
func _confirm_extracts() -> void:
	var space := player.get_world_3d().direct_space_state
	for zone: ExtractZone in get_tree().get_nodes_in_group("extract_zones"):
		if zone.confirmed or not zone.available:
			continue
		var to := zone.global_position
		if Vector2(to.x - player.global_position.x, to.z - player.global_position.z).length() > config.extract_confirm_distance:
			continue
		if VisionSystem.line_clear(space, player.global_position, to, false):
			zone.confirm()


# --- Points of interest --------------------------------------------------------------------------

## The map's id (data/maps).
func map_key() -> String:
	return str(map.id) if map else map_id


## Notices the player walking into a point of interest: the first time this raid it's announced
## (poi_entered); the first time ever it's explored (saved with the profile in a real raid) and earns
## PoiConfig.xp_discover (more for a hidden one), plus xp_map_complete for the map's last one.
func _track_poi() -> void:
	var poi := PointOfInterest.at(get_tree(), player.global_position)
	if poi == current_poi:
		return
	current_poi = poi
	if poi == null or poi.poi_id in visited_pois:
		return
	visited_pois.append(poi.poi_id)
	var first := false
	if is_real_raid() and not poi.entry().is_empty() and poi.map_id == map_key():
		first = GameState.explore(map_key(), poi.poi_id)
	if first:
		discovered_pois.append(poi.poi_id)
		var gained := poi_config.xp_discover_hidden if poi.is_hidden() else poi_config.xp_discover
		if GameState.explored_count(map_key()) == PoiTable.for_map(map_key()).size():
			gained += poi_config.xp_map_complete
		xp += gained
		xp_parts.exploration += gained
	poi_entered.emit(poi, first)


# --- Power ---------------------------------------------------------------------------------------

## "off", "starting" (the switch is thrown) or "on".
func power_state() -> String:
	if _power_on:
		return "on"
	return "starting" if _power_countdown >= 0.0 else "off"


## Seconds until the power comes on (0 when it's on or off).
func power_left() -> float:
	return maxf(_power_countdown, 0.0)


## Throws the power switch: the power comes on after RaidConfig.power_delay. False if it already was.
func switch_power_on() -> bool:
	if power_state() != "off":
		return false
	_power_countdown = config.power_delay
	if is_zero_approx(config.power_delay):
		_power_countdown = 0.0001
	return true


# --- Start ---------------------------------------------------------------------------------------

## Puts the player on a random spawn point for their side, away from hostile AI if one is: a PMC keeps
## away from every bot (Scavs, and PMCs of either faction: all hostile to it), a Scav from PMCs only.
func _place_player() -> void:
	var threats: Array[Vector3] = []
	for bot in get_tree().get_nodes_in_group("bots"):
		if bot is Bot and not bot.is_dead and (bot.side == Actor.Side.PMC or side() == "pmc"):
			threats.append(bot.global_position)
	var wanted := str(GameState.raid.get("spawn", ""))
	if wanted != "":
		for node in get_tree().get_nodes_in_group("spawn_points"):
			if node.name == wanted:
				spawn_point = node
	if spawn_point == null:
		spawn_point = SpawnPoint.pick(get_tree(), side(), rng, threats, config.spawn_safe_distance)
	if spawn_point:
		player.global_position = spawn_point.global_position
		player.rotation.y = spawn_point.global_rotation.y


## A wave of Scavs (RaidConfig scav waves): 2-3 together at a spawn spot out of the player's sight,
## roaming the points around it. Skipped (and tried again later) while too many Scavs are alive (a boss
## and its guards don't count) or there's nowhere to spawn. Returns the Scavs it spawned.
func spawn_wave() -> Array[Bot]:
	var spawned: Array[Bot] = []
	next_wave = elapsed + rng.randf_range(config.scav_wave_interval.x, config.scav_wave_interval.y)
	if elapsed > raid_seconds() * config.scav_wave_until:
		next_wave = -1.0
		return spawned
	var alive := scavs_alive()
	var size := mini(rng.randi_range(config.scav_wave_size.x, config.scav_wave_size.y), config.scav_max_alive - alive)
	var at: Variant = wave_spot()
	if size <= 0 or at == null:
		return spawned
	waves += 1
	var roam := _points_near(at, 30.0)
	for i in size:
		var bot: Bot = ScavZone.BOT_SCENE.instantiate()
		bot.name = "Wave%d_Scav%d" % [waves, i + 1]
		bot.profile = scav_profile
		bot.wave = waves
		bot.wander_points = roam
		var angle := TAU * i / size
		bot.position = at + Vector3(cos(angle), 0.0, sin(angle)) * 1.2
		get_parent().add_child(bot)
		spawned.append(bot)
	return spawned


## Ordinary Scavs alive (zone, wave and scene Scavs): what RaidConfig.scav_max_alive caps. A boss and
## its guards (side Scav too) aren't counted, so a boss raid still gets its waves.
func scavs_alive() -> int:
	return get_tree().get_nodes_in_group("bots").filter(func(bot: Bot) -> bool:
		return not bot.is_dead and bot.side == Actor.Side.SCAV and not bot.is_boss() and not bot.is_guard()).size()


## Where a Scav wave can spawn now: a Scav zone point (weight 1) or a point of interest (its heat:
## higher tiers and fresh raid events pull harder), at least scav_wave_min_distance from the player and
## out of their line of sight. Null if there's none.
func wave_spot() -> Variant:
	var spots: Array[Vector3] = []
	var weights := PackedFloat32Array()
	for zone in get_tree().get_nodes_in_group("scav_zones"):
		for point in zone.patrol_points():
			spots.append(point)
			weights.append(1.0)
	for node in get_tree().get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		if not poi.is_hidden() and poi.requirement_met():
			spots.append(_on_navmesh(poi.global_position))
			weights.append(poi.heat(elapsed))
	var space := player.get_world_3d().direct_space_state if player else null
	for i in spots.size():
		if player and (spots[i].distance_to(player.global_position) < config.scav_wave_min_distance
				or VisionSystem.line_clear(space, player.global_position, spots[i], false)):
			weights[i] = 0.0
	var index := LootTable._pick(rng, weights)
	return spots[index] if index >= 0 else null


## A hot point of interest for a roaming bot near `from` to head for: picked by heat
## (PointOfInterest.heat(): high tiers, fresh raid events), among the ones you can get into now and
## that aren't hidden. Null if there's none.
func hot_point(from: Vector3) -> Variant:
	var pois: Array[PointOfInterest] = []
	var weights := PackedFloat32Array()
	for node in get_tree().get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		if poi.is_hidden() or not poi.requirement_met() or poi.contains(from):
			continue
		pois.append(poi)
		weights.append(poi.heat(elapsed))
	var index := LootTable._pick(rng, weights)
	if index < 0:
		return null
	var spots := pois[index].event_spots()
	return _on_navmesh(spots[rng.randi_range(0, spots.size() - 1)])


## Scav zone points and point of interest centres within `radius` of `at` (at least `at` itself): where
## a wave roams.
func _points_near(at: Vector3, radius: float) -> PackedVector3Array:
	var points := PackedVector3Array([at])
	for point in _roam_points():
		if point.distance_to(at) <= radius and point.distance_to(at) > 1.0:
			points.append(point)
	return points


## Every point AI roams between: the Scav zones' points and the (not hidden) points of interest.
func _roam_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for zone in get_tree().get_nodes_in_group("scav_zones"):
		points.append_array(zone.patrol_points())
	for node in get_tree().get_nodes_in_group("pois"):
		if not node.is_hidden():
			points.append(_on_navmesh(node.global_position))
	return points


func _on_navmesh(point: Vector3) -> Vector3:
	var level := get_parent() as Node3D
	if level == null or not level.is_inside_tree():
		return point
	var map := level.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


## AI PMCs (ai_pmcs in all) as squads of 1-3 (Factions.roll_squad_size(), never more than are left
## to place), each squad of one faction (BEAR or USEC at random; none if factions.json is broken), at
## the PMC spawn points the player isn't at, farthest from the player first, one squad a point. Squad
## mates stand close together at their point (spawn_spots()), the first of them leading; they roam the
## Scav zones and points of interest (hot ones draw them: BotProfile.hot_poi_chance) together. Seeded
## raids roll the same squads. Returns the squads.
func _spawn_ai_pmcs() -> Array[Squad]:
	var free_points: Array = get_tree().get_nodes_in_group("spawn_points").filter(func(point: SpawnPoint) -> bool:
		return point != spawn_point and point.side != "Scav")
	free_points.sort_custom(func(a: SpawnPoint, b: SpawnPoint) -> bool:
		return a.global_position.distance_to(player.global_position) > b.global_position.distance_to(player.global_position))
	var stops := _roam_points()
	var factions := Factions.ids()
	var squad_rng := RandomNumberGenerator.new()  # Its own, so the raid's other rolls stay as they were.
	if GameState.raid.has("seed"):
		squad_rng.seed = hash([int(GameState.raid.seed), "ai_pmcs"])
	else:
		squad_rng.randomize()
	var left := ai_pmcs
	var count := 0
	for point: SpawnPoint in free_points:
		if left <= 0:
			break
		var size := mini(Factions.roll_squad_size(squad_rng), left)
		left -= size
		var faction: StringName = factions[squad_rng.randi_range(0, factions.size() - 1)] if not factions.is_empty() else &""
		var spots := spawn_spots(point.global_position, size)
		var members: Array[Bot] = []
		for i in size:
			count += 1
			var bot: Bot = ScavZone.BOT_SCENE.instantiate()
			bot.name = "AIPMC%d" % count
			bot.profile = ai_pmc_profile
			bot.faction = faction
			bot.wander_points = stops
			bot.position = spots[i]
			bot.rotation.y = point.global_rotation.y
			get_parent().add_child(bot)
			members.append(bot)
		ai_squads.append(Squad.new(members, faction))
	return ai_squads


## Where `count` squad mates stand at a spawn point `at`: the point itself, then spots around it
## `spawn_spacing` apart (and farther out if those are taken) that a body fits in, with nothing solid
## between them and the point, on the navmesh once it's ready.
func spawn_spots(at: Vector3, count: int) -> Array[Vector3]:
	var spacing := float(Factions.squad_config().get("spawn_spacing", 1.3))
	var spots: Array[Vector3] = [at]
	var space := (get_parent() as Node3D).get_world_3d().direct_space_state if get_parent() is Node3D else null
	var body := CapsuleShape3D.new()
	body.radius = Actor.BODY_RADIUS
	body.height = 1.6
	for ring: float in [1.0, 2.0, 3.0]:
		for step in 8:
			if spots.size() >= count:
				return spots
			var angle := TAU * step / 8.0 + ring * 0.4
			var spot := _on_navmesh(at + Vector3(cos(angle), 0.0, sin(angle)) * spacing * ring)
			spot.y = at.y
			if spots.any(func(other: Vector3) -> bool: return other.distance_to(spot) < spacing * 0.8):
				continue
			if space:
				var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.9, spot + Vector3.UP * 0.9, Actor.WORLD_MASK)
				if not space.intersect_ray(ray).is_empty():
					continue  # A wall between it and the point.
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = body
				query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 1.0)
				query.collision_mask = Actor.WORLD_MASK | Actor.ACTOR_MASK
				if not space.intersect_shape(query, 1).is_empty():
					continue  # Something solid (or someone) already there.
			spots.append(spot)
	while spots.size() < count:
		spots.append(at + Vector3(0.0, 0.0, spacing * spots.size()))  # Nowhere better: in a line.
	return spots


# --- Ending --------------------------------------------------------------------------------------

## Ends the raid with `status` (once): a Run Through earns no experience and extracting earns the
## survival bonus; then settles found-in-raid status, gear and insurance, and emits raid_ended.
func end_raid(status: RaidOutcome.Status) -> RaidOutcome:
	if outcome:
		return outcome
	if status == RaidOutcome.Status.RUN_THROUGH:
		xp = 0
		for part in xp_parts:
			xp_parts[part] = 0
	elif status == RaidOutcome.Status.SURVIVED:
		xp_parts.survived = config.xp_survived
		xp += config.xp_survived
	if is_real_raid() and side() == "pmc":
		RaidOutcome.keep_metabolism(player.health, status == RaidOutcome.Status.KILLED or status == RaidOutcome.Status.MIA)
	outcome = RaidOutcome.settle(status, side(), player.inventory, elapsed, xp,
		player.kills, is_real_raid(), {"hits": player.trick_hits, "kills": trick_kills, "drip": drip},
		{"xp_parts": xp_parts.duplicate(), "kill_list": kill_list.duplicate(), "extract": extracted_at, "looters": looters(),
			"faction": String(player.faction)})
	raid_ended.emit(outcome)
	return outcome


## Hostile AI alive within Insurance's "taken" radius of the player: who could take insured gear off
## their body.
func looters() -> int:
	if player == null:
		return 0
	var radius := float(Insurance.config().get("taken", {}).get("radius", 40.0))
	return get_tree().get_nodes_in_group("bots").filter(func(bot: Bot) -> bool:
		return not bot.is_dead and bot.is_hostile(player) and bot.global_position.distance_to(player.global_position) <= radius).size()


## A kill by the player: experience by what it was (a PMC of either faction 300, a Scav 100, a boss
## 1,000, a guard 250: RaidConfig) and an entry in the kill list.
func _on_kill(target: Actor) -> void:
	var pmc := target.side == Actor.Side.PMC
	var gained := config.xp_pmc_kill if pmc else config.xp_scav_kill
	var role := ""
	if target is Bot and target.is_boss():
		role = "boss"
		gained = config.xp_boss_kill
	elif target is Bot and target.is_guard():
		role = "guard"
		gained = config.xp_guard_kill
	xp += gained
	xp_parts.kills += gained
	var entry := {"name": target.display_name(), "side": "pmc" if pmc else "scav"}
	if target.faction != &"":
		entry.faction = String(target.faction)
	if role != "":
		entry.role = role
	kill_list.append(entry)


## A 360 trick-shot kill: bonus experience on top of the kill's, and Drip.
func _on_trick_shot_hit(target: Actor, _damage: float, _at: Vector3, killed: bool) -> void:
	if not killed:
		return
	xp += config.xp_trick_kill
	xp_parts.trick_shots += config.xp_trick_kill
	drip += config.drip_trick_kill
	trick_kills.append({"side": "pmc" if target.side == Actor.Side.PMC else "scav",
		"weapon_class": player.weapon.data.weapon_class if player.weapon.data else ""})


func _on_loot_claimed(items: Array[ItemInstance]) -> void:
	if outcome:
		return  # Settling the raid moves things around; that isn't looting.
	var gained := config.xp_looted_item * items.size()
	xp += gained
	xp_parts.looting += gained
