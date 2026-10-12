class_name RaidController
extends Node
## Runs a raid on a map (DESIGN.md §2, §5): the raid clock, raid experience (kills and loot), and how
## the raid ends. Standing in an ExtractZone for `RaidConfig.extract_seconds` extracts (SURVIVED, or a
## Run Through if it was quick and you earned little); dying is KILLED; the clock running out or leaving
## from the pause menu is MIA. The ending is settled by RaidOutcome (found-in-raid status, what you
## keep) and shown by the level.

## The raid ended (the outcome is already settled and saved).
signal raid_ended(outcome: RaidOutcome)

@export var player: Player
@export var config: RaidConfig = preload("res://data/config/raid.tres")

var map: MapInfo
## Seconds since the raid started, and seconds left on the clock.
var elapsed := 0.0
var time_left := 0.0
## Raid experience so far.
var xp := 0
var outcome: RaidOutcome
## The extract zone the player is standing in, and how long they've been in it.
var extract_zone: ExtractZone
var extract_time := 0.0


func _ready() -> void:
	add_to_group("raid_controller")
	map = MapInfo.find(GameState.raid.get("map", "test_yard"))
	time_left = (map.raid_minutes if map else 15) * 60.0
	if player:
		player.killed.connect(_on_kill)
		player.loot_claimed.connect(_on_loot_claimed)
		player.died.connect(end_raid.bind(RaidOutcome.Status.KILLED))


func _physics_process(delta: float) -> void:
	if outcome or player == null or player.is_dead:
		return
	elapsed += delta
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		end_raid(RaidOutcome.Status.MIA)
		return
	if extract_zone:
		extract_time += delta
		if extract_time >= config.extract_seconds:
			end_raid(RaidOutcome.extract_status(elapsed, xp, config))
	else:
		extract_time = 0.0


func is_over() -> bool:
	return outcome != null


## Seconds of standing still in an extract left, or -1 when not extracting.
func extract_remaining() -> float:
	return maxf(config.extract_seconds - extract_time, 0.0) if extract_zone and not outcome else -1.0


## True when the raid was started from ENTER RAID, so its ending changes the profile.
func is_real_raid() -> bool:
	return GameState.raid.has("side")


func enter_extract(zone: ExtractZone) -> void:
	extract_zone = zone
	extract_time = 0.0


func leave_extract(zone: ExtractZone) -> void:
	if extract_zone == zone:
		extract_zone = null


## Ends the raid with `status` (once): settles found-in-raid status and gear, then emits raid_ended.
func end_raid(status: RaidOutcome.Status) -> RaidOutcome:
	if outcome:
		return outcome
	outcome = RaidOutcome.settle(status, GameState.raid.get("side", "pmc"), player.inventory, elapsed, xp,
		player.kills, is_real_raid())
	raid_ended.emit(outcome)
	return outcome


func _on_kill(target: Actor) -> void:
	xp += config.xp_pmc_kill if target.side == Actor.Side.PMC else config.xp_scav_kill


func _on_loot_claimed(items: Array[ItemInstance]) -> void:
	xp += config.xp_looted_item * items.size()
