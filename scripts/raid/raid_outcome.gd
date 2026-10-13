class_name RaidOutcome
extends RefCounted
## How a raid ended and what that does to your gear (DESIGN.md §2). Settling a raid:
##
## - Found in raid: loot you picked up becomes FIR only if you SURVIVED (extracted, not a Run Through).
##   Killed, missing in action or a Run Through: nothing gains FIR. Brought-in items keep their status.
## - PMC: surviving (or a Run Through) keeps everything you carry. Killed or MIA: everything is lost
##   except the secure container and what's inside it, and insured items, which come back to the
##   stash (Insurance).
## - Scav: surviving moves everything the Scav carries into the stash (what doesn't fit is left
##   behind). Dying costs nothing.
## - Raid experience (none for a Run Through), Drip and 360 trick-shot stats are added to the profile
##   either way (and trick-shot kills count toward quests), then the game is saved.

enum Status { SURVIVED, RUN_THROUGH, KILLED, MIA }

const TITLES := ["SURVIVED", "RUN THROUGH", "KILLED IN ACTION", "MISSING IN ACTION"]

var status := Status.SURVIVED
var side := "pmc"
var seconds := 0.0
var xp := 0
## Where the experience came from: {"kills", "looting", "trick_shots", "survived"}.
var xp_parts := {}
var kills := 0
## Who you killed: [{"name", "side": "pmc" or "scav"}].
var kill_list: Array = []
## The extract you left through ("" if you didn't).
var extract_name := ""
## Loot: what you picked up this raid and still carried at the end, and its base value (kept if you
## got out, lost if not).
var loot_count := 0
var loot_value := 0
## 360 trick shots this raid: rounds that hit, kills, and the Drip they earned.
var trick_hits := 0
var trick_kills := 0
var drip := 0
## Items that became found in raid.
var found: Array[ItemInstance] = []
## Scav runs: items that went into the stash, and those that didn't fit.
var moved_to_stash: Array[ItemInstance] = []
var left_behind: Array[ItemInstance] = []
## PMC deaths: the base value of the gear you brought in and lost (not the loot), and the insured
## items that came back to the stash (or are waiting for room in it).
var lost_value := 0
var insurance_returned: Array[ItemInstance] = []
var insurance_waiting := 0


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


## Kills by side: "3 (2 Scavs, 1 PMC)", or "0".
func kills_text() -> String:
	if kills == 0:
		return "0"
	var scavs := kill_list.filter(func(kill: Dictionary) -> bool: return kill.get("side", "") == "scav").size()
	var pmcs := kill_list.filter(func(kill: Dictionary) -> bool: return kill.get("side", "") == "pmc").size()
	var parts: Array[String] = []
	if scavs > 0:
		parts.append("%d Scav%s" % [scavs, "s" if scavs > 1 else ""])
	if pmcs > 0:
		parts.append("%d PMC%s" % [pmcs, "s" if pmcs > 1 else ""])
	return "%d (%s)" % [kills, ", ".join(parts)] if not parts.is_empty() else str(kills)


## Total base value of the insured items that came back.
func insurance_value() -> int:
	var total := 0
	for item in insurance_returned:
		total += item.value()
	return total


## Settles the raid (see the class notes) with `inventory`, what the player has at the end. With
## `to_profile` false (the test level run on its own) only the found-in-raid marks change.
## `tricks`: {"hits", "kills": [{"side", "weapon_class"}], "drip"} from the RaidController.
## `details`: {"xp_parts", "kill_list", "extract"} from the RaidController, for the summary.
static func settle(end: Status, raid_side: String, inventory: Inventory, raid_seconds: float, raid_xp: int,
		raid_kills: int, to_profile: bool, tricks: Dictionary = {}, details: Dictionary = {}) -> RaidOutcome:
	var outcome := RaidOutcome.new()
	outcome.status = end
	outcome.side = raid_side
	outcome.seconds = raid_seconds
	outcome.xp = 0 if end == Status.RUN_THROUGH else raid_xp
	outcome.xp_parts = details.get("xp_parts", {})
	outcome.kills = raid_kills
	outcome.kill_list = details.get("kill_list", [])
	outcome.extract_name = str(details.get("extract", ""))
	var secured: Array[ItemInstance] = []
	if inventory.equipment.secure:
		secured = inventory.equipment.secure.all_items()
	var own_value := 0
	for item in inventory.all_items():
		if item.fir_pending and not item.brought_in:
			outcome.loot_count += 1
			outcome.loot_value += item.data.base_value * item.count
		elif not item in secured:
			own_value += item.data.base_value * item.count
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
		outcome.lost_value = own_value  # Your own gear; the loot is counted in loot_value.
		var secure: ItemInstance = inventory.unequip("secure")
		if secure:
			kept.equip("secure", secure)
		GameState.inventory = kept
		outcome.insurance_returned = Insurance.returns_for(inventory.all_items())
		var delivered := Insurance.deliver(outcome.insurance_returned)
		outcome.insurance_waiting = outcome.insurance_returned.size() - delivered
	GameState.xp += outcome.xp
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
