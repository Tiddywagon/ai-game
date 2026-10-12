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
## - Raid experience is added to the profile either way, then the game is saved.

enum Status { SURVIVED, RUN_THROUGH, KILLED, MIA }

const TITLES := ["SURVIVED", "RUN THROUGH", "KILLED IN ACTION", "MISSING IN ACTION"]

var status := Status.SURVIVED
var side := "pmc"
var seconds := 0.0
var xp := 0
var kills := 0
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


## Total base value of the items that became found in raid.
func found_value() -> int:
	var total := 0
	for item in found:
		total += item.data.base_value * item.count
	return total


## Settles the raid (see the class notes) with `inventory`, what the player has at the end. With
## `to_profile` false (the test level run on its own) only the found-in-raid marks change.
static func settle(end: Status, raid_side: String, inventory: Inventory, raid_seconds: float, raid_xp: int,
		raid_kills: int, to_profile: bool) -> RaidOutcome:
	var outcome := RaidOutcome.new()
	outcome.status = end
	outcome.side = raid_side
	outcome.seconds = raid_seconds
	outcome.xp = raid_xp
	outcome.kills = raid_kills
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
