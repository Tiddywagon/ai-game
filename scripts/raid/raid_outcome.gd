class_name RaidOutcome
extends RefCounted
## How a raid ended and what that does to your gear (DESIGN.md §2). Settling a raid:
##
## - Found in raid: loot you picked up becomes FIR only if you SURVIVED (extracted, not a Run Through).
##   Killed, missing in action or a Run Through: nothing gains FIR. Brought-in items keep their status.
## - PMC: surviving (or a Run Through) keeps everything you carry. Killed or MIA: everything is lost
##   except the secure container and what's inside it.
## - Scav: surviving moves everything the Scav carries into the stash (what doesn't fit is left
##   behind). Dying costs nothing.
## - Raid experience, Drip and 360 trick-shot stats are added to the profile either way (and trick-shot
##   kills count toward quests), then the game is saved.

enum Status { SURVIVED, RUN_THROUGH, KILLED, MIA }

const TITLES := ["SURVIVED", "RUN THROUGH", "KILLED IN ACTION", "MISSING IN ACTION"]

var status := Status.SURVIVED
var side := "pmc"
var seconds := 0.0
var xp := 0
var kills := 0
## 360 trick shots this raid: rounds that hit, kills, and the Drip they earned.
var trick_hits := 0
var trick_kills := 0
var drip := 0
## Items that became found in raid.
var found: Array[ItemInstance] = []
## Scav runs: items that went into the stash, and those that didn't fit.
var moved_to_stash: Array[ItemInstance] = []
var left_behind: Array[ItemInstance] = []
## PMC deaths: what was lost (base value).
var lost_value := 0


## The status for reaching an extract: a Run Through if it was quick and you earned little.
static func extract_status(raid_seconds: float, raid_xp: int, config: RaidConfig) -> Status:
	if raid_seconds < config.run_through_seconds and raid_xp < config.run_through_xp:
		return Status.RUN_THROUGH
	return Status.SURVIVED


func survived() -> bool:
	return status == Status.SURVIVED or status == Status.RUN_THROUGH


## A PMC's energy and hydration go back to the profile at the end of a raid (DESIGN.md §13.7); after
## dying, at least ConsumablesConfig.after_death_minimum of each. Out of raid they recover from now on.
static func keep_metabolism(health: BodyHealth, died: bool) -> void:
	var floor_value := Consumables.CONFIG.after_death_minimum if died else 0.0
	GameState.energy = maxf(health.energy, floor_value)
	GameState.hydration = maxf(health.hydration, floor_value)
	GameState.metabolism_time = Time.get_unix_time_from_system()


## Total base value of the items that became found in raid.
func found_value() -> int:
	var total := 0
	for item in found:
		total += item.data.base_value * item.count
	return total


## Settles the raid (see the class notes) with `inventory`, what the player has at the end. With
## `to_profile` false (the test level run on its own) only the found-in-raid marks change.
## `tricks`: {"hits", "kills": [{"side", "weapon_class"}], "drip"} from the RaidController.
static func settle(end: Status, raid_side: String, inventory: Inventory, raid_seconds: float, raid_xp: int,
		raid_kills: int, to_profile: bool, tricks: Dictionary = {}) -> RaidOutcome:
	var outcome := RaidOutcome.new()
	outcome.status = end
	outcome.side = raid_side
	outcome.seconds = raid_seconds
	outcome.xp = raid_xp
	outcome.kills = raid_kills
	var trick_kill_list: Array = tricks.get("kills", [])
	outcome.trick_hits = int(tricks.get("hits", 0))
	outcome.trick_kills = trick_kill_list.size()
	outcome.drip = int(tricks.get("drip", 0))
	outcome.found = FoundInRaid.resolve(inventory.all_items(), end == Status.SURVIVED)
	if not to_profile:
		return outcome
	if raid_side == "scav":
		if outcome.survived():
			outcome._move_to_stash(inventory)
	elif outcome.survived():
		GameState.inventory = inventory
	else:
		var kept := Inventory.new()
		var secure: ItemInstance = inventory.unequip("secure")
		outcome.lost_value = inventory.total_value()
		if secure:
			kept.equip("secure", secure)
		GameState.inventory = kept
	GameState.xp += raid_xp
	GameState.drip += outcome.drip
	GameState.trick_shots.hits += outcome.trick_hits
	GameState.trick_shots.kills += outcome.trick_kills
	QuestLog.record_trick_kills(trick_kill_list)
	SaveManager.save_game()
	return outcome


func _move_to_stash(inventory: Inventory) -> void:
	var carried: Array[ItemInstance] = []
	for slot: String in inventory.equipment:
		var item := inventory.unequip(slot)
		if item:
			carried.append(item)
	for item in inventory.pockets.items.duplicate():
		inventory.pockets.remove(item)
		carried.append(item)
	for item in carried:
		if GameState.stash.add(item):
			moved_to_stash.append(item)
		else:
			left_behind.append(item)
