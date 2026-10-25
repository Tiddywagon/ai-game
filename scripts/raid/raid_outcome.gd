class_name RaidOutcome
extends RefCounted
## How a raid ended and what that does to your gear (DESIGN.md §2). Settling a raid:
##
## - Found in raid: loot you picked up becomes FIR only if you SURVIVED (extracted, not a Run Through).
##   Killed, missing in action or a Run Through: nothing gains FIR. Brought-in items keep their status.
## - PMC: surviving (or a Run Through) keeps everything you carry. Killed or MIA: everything is lost
##   except the secure container and what's inside it, and insured items, which come back to the
##   stash after the insurer's return time unless someone takes them first (Insurance.claim(): hostile
##   AI near your body; missing in action, nobody does).
## - Scav: surviving moves everything the Scav carries into the stash (what doesn't fit is left
##   behind). Dying costs nothing.
## - Raid experience (none for a Run Through), Drip and 360 trick-shot stats are added to the profile
##   either way (and trick-shot kills count toward quests), then the game is saved.

enum Status { SURVIVED, RUN_THROUGH, KILLED, MIA }

const TITLES := ["SURVIVED", "RUN THROUGH", "KILLED IN ACTION", "MISSING IN ACTION"]

var status := Status.SURVIVED
var side := "pmc"
## The player's faction in a PMC raid ("bear" / "usec"; "" as a Scav).
var faction := ""
var seconds := 0.0
var xp := 0
## Where the experience came from: {"kills", "looting", "trick_shots", "exploration", "survived"}.
var xp_parts := {}
var kills := 0
## Who you killed: [{"name", "side": "pmc" or "scav", "faction" (a PMC's), "role" (a boss's or guard's)}].
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
## PMC deaths: the base value of the gear you brought in and lost (not the loot), the insured items
## on their way back to the stash (Insurance: they arrive in insurance_seconds, real time) and the
## insured items someone took.
var lost_value := 0
var insurance_returned: Array[ItemInstance] = []
var insurance_taken: Array[ItemInstance] = []
var insurance_seconds := 0.0


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


## The side you played: "BEAR" or "USEC" for a PMC of that faction, "Scav", or "PMC" without a
## faction.
func side_text() -> String:
	if side == "scav":
		return "Scav"
	return Factions.display_name(StringName(faction)) if Factions.has(StringName(faction)) else "PMC"


## Kills by side: "4 (2 Scavs, 1 BEAR, 1 USEC)" (PMCs by faction), or "0".
func kills_text() -> String:
	if kills == 0:
		return "0"
	var scavs := kill_list.filter(func(kill: Dictionary) -> bool: return kill.get("side", "") == "scav" and not kill.has("role")).size()
	var guards := kill_list.filter(func(kill: Dictionary) -> bool: return kill.get("role", "") == "guard").size()
	var pmcs := {}
	for kill: Dictionary in kill_list:
		if kill.get("side", "") == "pmc":
			var faction_id := StringName(str(kill.get("faction", "")))
			var label := Factions.display_name(faction_id) if Factions.has(faction_id) else "PMC"
			pmcs[label] = pmcs.get(label, 0) + 1
	var parts: Array[String] = []
	for kill: Dictionary in kill_list:
		if kill.get("role", "") == "boss":
			parts.append(str(kill.name))  # A boss by name.
	if guards > 0:
		parts.append("%d guard%s" % [guards, "s" if guards > 1 else ""])
	if scavs > 0:
		parts.append("%d Scav%s" % [scavs, "s" if scavs > 1 else ""])
	for label: String in pmcs:
		parts.append("%d %s%s" % [pmcs[label], label, "s" if label == "PMC" and pmcs[label] > 1 else ""])
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
## `details`: {"xp_parts", "kill_list", "extract", "looters" (hostile AI alive near the body), "faction"
## (the player's)} from the RaidController, for the summary and insurance.
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
	outcome.faction = str(details.get("faction", "")) if raid_side != "scav" else ""
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
		var looters := int(details.get("looters", 0)) if end == Status.KILLED else -1
		var claim := Insurance.claim(inventory.all_items(), looters)
		outcome.insurance_returned = claim.returning
		outcome.insurance_taken = claim.taken
		outcome.insurance_seconds = maxf(Insurance.next_due(), 0.0)
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
