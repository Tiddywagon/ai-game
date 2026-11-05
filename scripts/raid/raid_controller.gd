class_name RaidController
extends Node
## Runs a raid on a map (DESIGN.md §2, §5): the start (a random spawn point for your side; the map's
## extracts from data/config/extracts.json, which random ones are open this raid and which quest ones
## you've unlocked), the raid clock, the map's power, raid experience (kills, loot, trick shots,
## extracting) and how the raid ends. Standing in an ExtractZone you can use for
## `RaidConfig.extract_seconds` extracts (SURVIVED, or a Run Through if it was quick and you earned
## little); walking out or getting hit starts the count again. A random extract turns from "Unknown" to
## open or closed once you've been close enough to see it. AI PMCs join the raid as squads of 1-3 of one
## faction (BEAR or USEC), each with a raid plan (RaidPlan): most at the start at PMC spawn points you
## didn't get (_spawn_ai_pmcs()), a few as late arrivals mid-raid out of your sight (pmc_schedule,
## DESIGN.md §4.4). AI Scavs and PMCs leave through the same extracts (Bot). Dying is KILLED; the clock running out or leaving from the pause menu is MIA. The
## ending is settled by RaidOutcome (found-in-raid status, what you keep, insurance) and shown by the
## level.

## The raid ended (the outcome is already settled and saved).
signal raid_ended(outcome: RaidOutcome)
## The power came on (extracts that need it open).
signal power_on
## The player walked into a point of interest (DESIGN.md §5.2) for the first time this raid;
## `first_time` if they'd never explored it before (it's now explored, with its experience).
signal poi_entered(poi: PointOfInterest, first_time: bool)

## A point moved onto the navmesh further than this (metres) means the navmesh isn't there yet
## (_on_navmesh()).
const NAVMESH_SNAP := 8.0

@export var player: Player
@export var config: RaidConfig = preload("res://data/config/raid.tres")
## The map this scene is (data/maps/), when it's played without ENTER RAID (GameState.raid "map").
@export var map_id := "test_yard"
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
## AI PMCs in this raid in all (the map's budget in data/config/pmc_ai.json; GameState.raid "pmcs"
## overrides it, for tests), and the squads still to come: [{"time": raid seconds (0 at the start),
## "size", "faction", "late"}], soonest first (plan_pmc_schedule()).
var ai_pmcs := 0
var pmc_schedule: Array[Dictionary] = []
## Late arrivals so far: their schedule entries with "spawned_at", "point" and "squad" (its number), or
## "gave_up" when there was nowhere out of your sight to spawn in time.
var late_arrivals: Array[Dictionary] = []
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

## The AI PMC schedule's rolls (seeded in a seeded raid), AI PMCs spawned so far (their names), and
## when a late arrival with nowhere to spawn tries again.
var _pmc_rng := RandomNumberGenerator.new()
var _pmc_count := 0
var _next_late_try := 0.0
var _pmcs_started := false

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
		plan_pmc_schedule()
		if not pmc_schedule.is_empty():
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
	if _pmcs_started and not pmc_schedule.is_empty() and elapsed >= float(pmc_schedule[0].time) and elapsed >= _next_late_try:
		_late_arrival()
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


## `point` moved onto the navmesh; as it is while the navmesh isn't there yet (just baked, or synced
## before its regions were: the "closest point" is then the world origin, far off).
func _on_navmesh(point: Vector3) -> Vector3:
	var level := get_parent() as Node3D
	if level == null or not level.is_inside_tree():
		return point
	var map := level.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return point
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	return closest if closest.distance_to(point) <= NAVMESH_SNAP else point


## Rolls this raid's AI PMCs (data/config/pmc_ai.json "schedule"; DESIGN.md §4.4): ai_pmcs in all,
## of which late_share (at least one, when there are two or more) arrive late as late_squads squads (more
## if it takes more to keep each to 3) at times in late_window of the raid (earlier ones likelier:
## late_falloff), and the rest come as squads of 1-3 at the start (Factions.roll_squad_size()); each
## squad's faction (BEAR or USEC; none if factions.json is broken) is rolled. Without a schedule
## (pmc_ai.json missing) all of them (PmcAi.FALLBACK_BUDGET) come at the start. Its own RNG, seeded in a
## seeded raid, so the raid's other rolls stay as they were. Returns pmc_schedule.
func plan_pmc_schedule() -> Array[Dictionary]:
	pmc_schedule.clear()
	if GameState.raid.has("seed"):
		_pmc_rng.seed = hash([int(GameState.raid.seed), "ai_pmcs"])
	else:
		_pmc_rng.randomize()
	var tuning := PmcAi.schedule()
	ai_pmcs = maxi(int(GameState.raid.get("pmcs", PmcAi.budget(map_key()))), 0)
	var factions := Factions.ids()
	var late := clampi(roundi(ai_pmcs * PmcAi.number(tuning, "late_share", 0.35)), 1, ai_pmcs - 1) if ai_pmcs >= 2 and not tuning.is_empty() else 0
	var left := ai_pmcs - late
	while left > 0:
		var size := mini(Factions.roll_squad_size(_pmc_rng), left)
		left -= size
		pmc_schedule.append({"time": 0.0, "size": size, "faction": _roll_faction(factions), "late": false})
	if late > 0:
		var counts := PmcAi.pair(tuning.get("late_squads"), [1, 2])
		var squads := clampi(maxi(_pmc_rng.randi_range(int(counts[0]), int(counts[1])), ceili(late / 3.0)), 1, late)
		var window := PmcAi.pair(tuning.get("late_window"), [0.15, 0.6])
		var falloff := PmcAi.number(tuning, "late_falloff", 2.0)
		for i in squads:
			var size := late / squads + (1 if i < late % squads else 0)
			var at := raid_seconds() * lerpf(float(window[0]), float(window[1]), pow(_pmc_rng.randf(), falloff))
			pmc_schedule.append({"time": at, "size": size, "faction": _roll_faction(factions), "late": true})
	pmc_schedule.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	return pmc_schedule


func _roll_faction(factions: Array[StringName]) -> StringName:
	return factions[_pmc_rng.randi_range(0, factions.size() - 1)] if not factions.is_empty() else &""


## The squads due at the start (pmc_schedule's time 0 entries), at the PMC spawn points the player isn't
## at, farthest from the player first, one squad a point (spawn_pmc_squad()); any left over without a
## point come as soon as there's a spot out of the player's sight (_late_arrival()). Returns ai_squads.
func _spawn_ai_pmcs() -> Array[Squad]:
	_pmcs_started = true
	var free_points: Array = get_tree().get_nodes_in_group("spawn_points").filter(func(point: SpawnPoint) -> bool:
		return point != spawn_point and point.side != "Scav")
	free_points.sort_custom(func(a: SpawnPoint, b: SpawnPoint) -> bool:
		return a.global_position.distance_to(player.global_position) > b.global_position.distance_to(player.global_position))
	for entry: Dictionary in pmc_schedule.filter(func(each: Dictionary) -> bool: return float(each.time) <= 0.0):
		if free_points.is_empty():
			break
		var point: SpawnPoint = free_points.pop_front()
		spawn_pmc_squad(int(entry.size), entry.faction, point.global_position, point.global_rotation.y)
		pmc_schedule.erase(entry)
	return ai_squads


## An AI PMC squad of `size` of `faction` at `at`, facing `yaw`: standing close together (spawn_spots()),
## the first of them leading, named AIPMC1, AIPMC2... in spawn order, with a raid plan (RaidPlan.roll():
## its personality, gear tier for the map's difficulty, which their kits are dressed for, and leave time;
## seeded per squad in a seeded raid). Without pmc_ai.json they have no plan and roam the Scav zones and
## points of interest instead. Returns the squad.
func spawn_pmc_squad(size: int, faction: StringName, at: Vector3, yaw: float) -> Squad:
	var number := ai_squads.size() + 1
	var plan: RaidPlan = null
	if not PmcAi.personalities().is_empty():
		var plan_seed := hash([int(GameState.raid.seed), "plan", number]) if GameState.raid.has("seed") else randi()
		plan = RaidPlan.roll(plan_seed, raid_seconds(), elapsed, map.difficulty if map else 1)
	var spots := spawn_spots(at, size)
	var stops := _roam_points()
	var members: Array[Bot] = []
	for i in size:
		_pmc_count += 1
		var bot: Bot = ScavZone.BOT_SCENE.instantiate()
		bot.name = "AIPMC%d" % _pmc_count
		bot.profile = ai_pmc_profile
		bot.faction = faction
		bot.gear_tier = plan.tier if plan else &""
		bot.wander_points = stops
		bot.position = spots[i]
		bot.rotation.y = yaw
		get_parent().add_child(bot)
		members.append(bot)
	var squad := Squad.new(members, faction)
	squad.plan = plan
	squad.number = number
	if plan:
		plan.start = spots[0]
	ai_squads.append(squad)
	return squad


## The next squad due mid-raid (a late arrival): at late_spot(). With nowhere to spawn it tries again
## late_retry seconds later, and gives up late_give_up seconds after it was due. Returns the squad (null
## if none came).
func _late_arrival() -> Squad:
	var entry: Dictionary = pmc_schedule[0]
	var tuning := PmcAi.schedule()
	if elapsed > float(entry.time) + float(tuning.get("late_give_up", 90.0)):
		pmc_schedule.pop_front()
		late_arrivals.append(entry.merged({"gave_up": true}))
		return null
	var point := late_spot()
	if point == null:
		_next_late_try = elapsed + float(tuning.get("late_retry", 5.0))
		return null
	pmc_schedule.pop_front()
	var squad := spawn_pmc_squad(int(entry.size), entry.faction, point.global_position, point.global_rotation.y)
	late_arrivals.append(entry.merged({"spawned_at": elapsed, "point": str(point.name), "squad": squad.number}))
	return squad


## Where a late arrival can spawn now: a PMC spawn point (not the player's) at least
## RaidConfig.scav_wave_min_distance from the player and out of their line of sight, like a Scav wave
## (wave_spot()); a random one of them, or null if there's none.
func late_spot() -> SpawnPoint:
	var space := player.get_world_3d().direct_space_state if player else null
	var options: Array[SpawnPoint] = []
	for node in get_tree().get_nodes_in_group("spawn_points"):
		var point := node as SpawnPoint
		if point == null or point == spawn_point or point.side == "Scav":
			continue
		var at := point.global_position
		if player and (at.distance_to(player.global_position) < config.scav_wave_min_distance
				or VisionSystem.line_clear(space, player.global_position, at, false)):
			continue
		options.append(point)
	return options[_pmc_rng.randi_range(0, options.size() - 1)] if not options.is_empty() else null


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
