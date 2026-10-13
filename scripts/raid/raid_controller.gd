class_name RaidController
extends Node
## Runs a raid on a map (DESIGN.md §2, §5): the start (a random spawn point for your side, which
## extracts are open this raid), the raid clock, the map's power, raid experience (kills, loot, trick
## shots, extracting) and how the raid ends. Standing in an ExtractZone you can use for
## `RaidConfig.extract_seconds` extracts (SURVIVED, or a Run Through if it was quick and you earned
## little); dying is KILLED; the clock running out or leaving from the pause menu is MIA. The ending
## is settled by RaidOutcome (found-in-raid status, what you keep, insurance) and shown by the level.

## The raid ended (the outcome is already settled and saved).
signal raid_ended(outcome: RaidOutcome)
## The power came on (extracts that need it open).
signal power_on

@export var player: Player
@export var config: RaidConfig = preload("res://data/config/raid.tres")

var map: MapInfo
## Seconds since the raid started, and seconds left on the clock.
var elapsed := 0.0
var time_left := 0.0
## Raid experience so far, and where it came from: {"kills", "looting", "trick_shots", "survived"}.
var xp := 0
var xp_parts := {"kills": 0, "looting": 0, "trick_shots": 0, "survived": 0}
## Who the player killed: [{"name", "side": "pmc" or "scav"}].
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
## Rolls this raid: spawn point and random extracts. Seeded from GameState.raid "seed" if set.
var rng := RandomNumberGenerator.new()

## The map's power: seconds until it comes on after the switch is thrown (-1: off), and on.
var _power_countdown := -1.0
var _power_on := false


func _ready() -> void:
	add_to_group("raid_controller")
	map = MapInfo.find(GameState.raid.get("map", "test_yard"))
	time_left = (map.raid_minutes if map else 15) * 60.0
	if GameState.raid.has("seed"):
		rng.seed = int(GameState.raid.seed)
	else:
		rng.randomize()
	for zone in get_tree().get_nodes_in_group("extract_zones"):
		zone.roll(rng)
	if player:
		player.killed.connect(_on_kill)
		player.loot_claimed.connect(_on_loot_claimed)
		player.trick_shot_hit.connect(_on_trick_shot_hit)
		player.died.connect(end_raid.bind(RaidOutcome.Status.KILLED))
		if is_real_raid() and GameState.raid.get("spawn", "") != "scene":
			_place_player()


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
	elapsed += delta
	time_left = maxf(time_left - delta, 0.0)
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


## "pmc" or "scav".
func side() -> String:
	return str(GameState.raid.get("side", "pmc"))


## Seconds of standing still in an extract left, or -1 when not extracting (outside one, or in one you
## can't use yet: extract_block()).
func extract_remaining() -> float:
	if extract_zone == null or outcome or extract_zone.block_reason(player) != "":
		return -1.0
	return maxf(config.extract_seconds - extract_time, 0.0)


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

## Puts the player on a random spawn point for their side, away from hostile AI if one is.
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
		{"xp_parts": xp_parts.duplicate(), "kill_list": kill_list.duplicate(), "extract": extracted_at})
	raid_ended.emit(outcome)
	return outcome


func _on_kill(target: Actor) -> void:
	var pmc := target.side == Actor.Side.PMC
	var gained := config.xp_pmc_kill if pmc else config.xp_scav_kill
	xp += gained
	xp_parts.kills += gained
	kill_list.append({"name": target.display_name(), "side": "pmc" if pmc else "scav"})


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
