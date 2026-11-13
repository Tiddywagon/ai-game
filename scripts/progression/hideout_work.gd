class_name HideoutWork
extends RefCounted
## What the hideout is doing over real time (DESIGN.md §9), kept in GameState.hideout_state and saved:
## items handed over toward a station's next level, builds, crafts, the generator's fuel and switch,
## what the Water Collector and the Bitcoin Farm have made, the farm's graphics cards, the Gym's next
## session and the cosmetics bought. Everything runs on unix time (now(), which tests override), so it
## keeps going while the game is closed: update() catches up from the saved clock.
##
## GameState.hideout_state: {"clock" (unix time it was last brought up to date; never runs backwards),
## "handed": {station id: {item id: count}}, "builds": {station id: {"level", "ends" (unix time)}},
## "crafts": {station id: [{"id", "output": {"item", "count"}, "left" (seconds of full-speed work),
## "total"}]} (the queue: the first runs), "ready": {station id: [{"id", "output"}]} (done, waiting to be
## collected), "power_on" (the generator's switch), "fuel": [{"item" (id), "left" (seconds of power
## at efficiency 1)}] (the first burns), "production": {station id: {"progress" (0-1 toward the next
## item), "waiting"}}, "cards": [{"id", "fir"}] (the farm's graphics cards), "gym_ready" (unix time the
## next Gym session can start), "cosmetics": [cosmetic ids]}.
##
## Power: the generator is built, switched on and has fuel. Fuel burns only then, one second of a can's
## "left" every fuel_efficiency() seconds. Without power a station that needs it works at its
## unpowered_rate (crafts and the Water Collector at half speed, the Bitcoin Farm not at all) and gives
## no bonuses (Hideout.scav_cooldown_multiplier() and the insurance multipliers).

## Tests set this to a unix time; -1 means the real clock.
static var now_override := -1.0


static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


## A new profile's hideout state: nothing handed over, building or crafting, the generator off with no
## fuel, the clock at now.
static func blank() -> Dictionary:
	return {"clock": floorf(now()), "handed": {}, "builds": {}, "crafts": {}, "ready": {}, "power_on": true, "fuel": [],
		"production": {}, "cards": [], "gym_ready": 0.0, "cosmetics": []}


## GameState.hideout_state as saved: times in whole seconds, what's left of a craft or a fuel can and
## production progress to a thousandth (JSON keeps that exactly).
static func to_save() -> Dictionary:
	var result: Dictionary = GameState.hideout_state.duplicate(true)
	result.clock = floorf(float(result.get("clock", 0.0)))
	for station: String in result.get("builds", {}):
		result.builds[station].ends = snappedf(float(result.builds[station].ends), 1.0)
	for station: String in result.get("crafts", {}):
		for entry: Dictionary in result.crafts[station]:
			entry.left = snappedf(float(entry.left), 0.001)
			entry.total = snappedf(float(entry.total), 0.001)
	for entry: Dictionary in result.get("fuel", []):
		entry.left = snappedf(float(entry.left), 0.001)
	for station: String in result.get("production", {}):
		result.production[station].progress = snappedf(float(result.production[station].progress), 0.000001)
	result.gym_ready = snappedf(float(result.get("gym_ready", 0.0)), 1.0)
	return result


## The state from save data, cleaned: anything missing or malformed starts blank (a save from before
## version 17 has none of it: the clock starts at now, so nothing happened while it was closed), whole
## numbers back from JSON's floats, entries for stations, recipes, items and cosmetics that are gone
## dropped.
static func from_save(saved: Variant) -> Dictionary:
	var result := blank()
	if not saved is Dictionary:
		return result
	result.clock = float(saved.get("clock", result.clock))
	result.power_on = bool(saved.get("power_on", true))
	result.gym_ready = float(saved.get("gym_ready", 0.0))
	var handed: Variant = saved.get("handed")
	if handed is Dictionary:
		for station: String in handed:
			if Hideout.find(station).is_empty() or not handed[station] is Dictionary:
				continue
			var counts := {}
			for item: String in handed[station]:
				if ItemDB.has_item(item) and int(handed[station][item]) > 0:
					counts[item] = int(handed[station][item])
			if not counts.is_empty():
				result.handed[station] = counts
	var builds: Variant = saved.get("builds")
	if builds is Dictionary:
		for station: String in builds:
			var entry: Variant = builds[station]
			if not Hideout.find(station).is_empty() and entry is Dictionary:
				result.builds[station] = {"level": int(entry.get("level", 0)), "ends": float(entry.get("ends", 0.0))}
	for key: String in ["crafts", "ready"]:
		var lists: Variant = saved.get(key)
		if not lists is Dictionary:
			continue
		for station: String in lists:
			if Hideout.find(station).is_empty() or not lists[station] is Array:
				continue
			var kept := []
			for entry: Variant in lists[station]:
				if entry is Dictionary and entry.get("output") is Dictionary and ItemDB.has_item(str(entry.output.get("item", ""))):
					var clean := {"id": str(entry.get("id", "")), "output": {"item": str(entry.output.item), "count": maxi(int(entry.output.get("count", 1)), 1)}}
					if key == "crafts":
						clean.total = maxf(float(entry.get("total", 0.0)), 0.0)
						clean.left = clampf(float(entry.get("left", clean.total)), 0.0, clean.total)
					kept.append(clean)
			if not kept.is_empty():
				result[key][station] = kept
	for entry: Variant in saved.get("fuel", []) if saved.get("fuel") is Array else []:
		if entry is Dictionary and ItemDB.has_item(str(entry.get("item", ""))) and float(entry.get("left", 0.0)) > 0.0:
			result.fuel.append({"item": str(entry.item), "left": float(entry.left)})
	var production: Variant = saved.get("production")
	if production is Dictionary:
		for station: String in production:
			var entry: Variant = production[station]
			if not Hideout.find(station).is_empty() and entry is Dictionary:
				result.production[station] = {"progress": clampf(float(entry.get("progress", 0.0)), 0.0, 1.0), "waiting": maxi(int(entry.get("waiting", 0)), 0)}
	for entry: Variant in saved.get("cards", []) if saved.get("cards") is Array else []:
		if entry is Dictionary and ItemDB.has_item(str(entry.get("id", ""))):
			result.cards.append({"id": str(entry.id), "fir": bool(entry.get("fir", false))})
	for id: Variant in saved.get("cosmetics", []) if saved.get("cosmetics") is Array else []:
		if not Hideout.find_cosmetic(str(id)).is_empty() and not str(id) in result.cosmetics:
			result.cosmetics.append(str(id))
	return result


# --- The clock ----------------------------------------------------------------------------------

## Brings the hideout up to `at` (now if -1): builds finish when their time comes, fuel burns, crafts
## run (the first in each station's queue; the next starts the moment it's done), the Water Collector
## and the Bitcoin Farm make what they make, all at the speed power allows at each moment. Between the
## saved clock and now the game may have been closed: the same happens, in steps that end where a build
## finishes or the fuel runs out. The clock never runs backwards.
static func update(at := -1.0) -> void:
	var state := GameState.hideout_state
	if state.is_empty():
		return
	var end := floorf(now() if at < 0.0 else at)
	var time := float(state.clock)
	_finish_builds(time)
	while time < end:
		var step_end := end
		for station: String in state.builds:
			if float(state.builds[station].ends) > time:
				step_end = minf(step_end, float(state.builds[station].ends))
		var powered := _powered()
		if powered:
			step_end = minf(step_end, time + _fuel_power_seconds())
		step_end = maxf(step_end, time + 0.001)
		_advance(step_end - time, powered)
		time = step_end
		_finish_builds(time)
	state.clock = maxf(float(state.clock), end)


static func _finish_builds(time: float) -> void:
	var builds: Dictionary = GameState.hideout_state.builds
	for station: String in builds.keys():
		if float(builds[station].ends) <= time:
			Hideout.finish_build(Hideout.find(station))


## `seconds` of work, with or without power.
static func _advance(seconds: float, powered: bool) -> void:
	var state := GameState.hideout_state
	if powered:
		_burn(seconds / fuel_efficiency())
	for id: String in state.crafts.keys():
		var station := Hideout.find(id)
		var budget := seconds * (1.0 if powered else Hideout.unpowered_rate(station))
		var queue: Array = state.crafts[id]
		while not queue.is_empty() and budget > 0.0:
			var head: Dictionary = queue[0]
			var spent := minf(budget, float(head.left))
			head.left = float(head.left) - spent
			budget -= spent
			if float(head.left) <= 0.0001:
				queue.pop_front()
				if not state.ready.has(id):
					state.ready[id] = []
				state.ready[id].append({"id": head.id, "output": head.output})
		if queue.is_empty():
			state.crafts.erase(id)
	for id: String in [Hideout.WATER_COLLECTOR, Hideout.BITCOIN_FARM]:
		var station := Hideout.find(id)
		var made: Dictionary = Hideout.built_value(id, "produces", {})
		if station.is_empty() or made.is_empty():
			continue
		var rate := production_speed(id) * (1.0 if powered else Hideout.unpowered_rate(station))
		var entry: Dictionary = production(id)
		if rate <= 0.0 or int(entry.waiting) >= int(made.cap):
			continue
		var progress := float(entry.progress) + seconds * rate / (float(made.minutes) * 60.0)
		while progress >= 1.0 and int(entry.waiting) < int(made.cap):
			progress -= 1.0
			entry.waiting = int(entry.waiting) + 1
		entry.progress = progress if int(entry.waiting) < int(made.cap) else 0.0
		state.production[id] = entry


# --- Power and fuel -----------------------------------------------------------------------------

## True while the hideout has power now: the generator built and switched on, with fuel left (worked out
## from the saved clock, so it's right even before update()).
static func has_power() -> bool:
	if not _powered():
		return false
	var since := maxf(now() - float(GameState.hideout_state.get("clock", now())), 0.0)
	return _fuel_power_seconds() > since


## Power at the clock: built, on and fuelled.
static func _powered() -> bool:
	var state := GameState.hideout_state
	return Hideout.level(Hideout.find(Hideout.GENERATOR)) >= 1 and bool(state.get("power_on", true)) and not state.get("fuel", []).is_empty()


static func fuel_slots() -> int:
	return int(Hideout.built_value(Hideout.GENERATOR, "fuel_slots", 0))


## How much longer fuel lasts at the generator's level (1: as long as its minutes say).
static func fuel_efficiency() -> float:
	return maxf(float(Hideout.built_value(Hideout.GENERATOR, "fuel_efficiency", 1.0)), 0.01)


## {item id: minutes of power one gives} (the Generator's "fuel").
static func fuel_items() -> Dictionary:
	return Hideout.find(Hideout.GENERATOR).get("fuel", {})


## Seconds of power the fuel in the generator gives at its efficiency (as of the clock).
static func _fuel_power_seconds() -> float:
	var total := 0.0
	for entry: Dictionary in GameState.hideout_state.get("fuel", []):
		total += float(entry.left)
	return total * fuel_efficiency()


## Seconds of power left now.
static func fuel_seconds_left() -> float:
	var since := maxf(now() - float(GameState.hideout_state.get("clock", now())), 0.0) if _powered() else 0.0
	return maxf(_fuel_power_seconds() - since, 0.0)


## The fuel gauge: power left over what full slots of the first fuel item would give (0-1).
static func fuel_fraction() -> float:
	var full := 0.0
	for id: String in fuel_items():
		full = float(fuel_items()[id]) * 60.0 * fuel_slots() * fuel_efficiency()
		break
	return clampf(fuel_seconds_left() / full, 0.0, 1.0) if full > 0.0 else 0.0


static func _burn(fuel_seconds: float) -> void:
	var fuel: Array = GameState.hideout_state.fuel
	while not fuel.is_empty() and fuel_seconds > 0.0:
		var spent := minf(fuel_seconds, float(fuel[0].left))
		fuel[0].left = float(fuel[0].left) - spent
		fuel_seconds -= spent
		if float(fuel[0].left) <= 0.0001:
			fuel.pop_front()


## Why no fuel can go in now ("" if it can): no generator, every slot taken, no fuel item.
static func add_fuel_block_reason() -> String:
	if Hideout.level(Hideout.find(Hideout.GENERATOR)) == 0:
		return "Build the Generator first"
	update()
	if GameState.hideout_state.fuel.size() >= fuel_slots():
		return "Every fuel slot is full"
	if _fuel_item() == "":
		return "You have no fuel"
	return ""


## Puts one fuel item (a fuel can) in a free slot: it's used up as it burns. "" on success.
static func add_fuel() -> String:
	var reason := add_fuel_block_reason()
	if reason != "":
		return reason
	var id := _fuel_item()
	if ItemSearch.take(id, 1, false) != 1:
		return "You have no fuel"
	GameState.hideout_state.fuel.append({"item": id, "left": float(fuel_items()[id]) * 60.0})
	return ""


## The first fuel item you have ("" if none).
static func _fuel_item() -> String:
	for id: String in fuel_items():
		if ItemSearch.count(id, false) > 0:
			return id
	return ""


## The generator's switch: off, no fuel burns and nothing has power.
static func set_power(on: bool) -> void:
	update()
	GameState.hideout_state.power_on = on


static func power_on() -> bool:
	return bool(GameState.hideout_state.get("power_on", true))


# --- Crafts -------------------------------------------------------------------------------------

## `station`'s craft queue (the first runs): [{"id", "output", "left", "total"}].
static func queue(station: Dictionary) -> Array:
	return GameState.hideout_state.get("crafts", {}).get(station.id, [])


## Crafts done and waiting to be collected at `station`: [{"id", "output"}].
static func ready(station: Dictionary) -> Array:
	return GameState.hideout_state.get("ready", {}).get(station.id, [])


## How fast `station` works now (1, its unpowered rate without power).
static func rate(station: Dictionary) -> float:
	return 1.0 if has_power() else Hideout.unpowered_rate(station)


## Real seconds `recipe` takes at full speed.
static func craft_seconds(recipe: Dictionary) -> float:
	return float(recipe.get("minutes", 1.0)) * 60.0


## Real seconds until queue entry `index` of `station` is done at the speed it works now (those before
## it first), -1 if it never will (no power for a station that stops without it).
static func seconds_until_done(station: Dictionary, index: int) -> float:
	var speed := rate(station)
	if speed <= 0.0:
		return -1.0
	var work := 0.0
	var since := maxf(now() - float(GameState.hideout_state.clock), 0.0)
	for i in mini(index + 1, queue(station).size()):
		work += float(queue(station)[i].left)
	return maxf(work / speed - since, 0.0)


## Why `recipe` can't be queued at `station` now, or "" if it can.
static func craft_block_reason(station: Dictionary, recipe: Dictionary) -> String:
	if recipe not in Hideout.crafts(station):
		return "Upgrade the station first"
	update()
	if queue(station).size() >= Hideout.craft_queue_size():
		return "The queue is full (%d)" % Hideout.craft_queue_size()
	if not ItemSearch.can_afford(Requirement.list(recipe.inputs)):
		return "Missing items"
	return ""


## Queues `recipe` at `station`: the inputs are taken now; it runs once those before it are done and
## waits to be collected (collect()). "" on success.
static func craft(station: Dictionary, recipe: Dictionary) -> String:
	var reason := craft_block_reason(station, recipe)
	if reason != "":
		return reason
	ItemSearch.pay(Requirement.list(recipe.inputs))
	var state := GameState.hideout_state
	if not state.crafts.has(station.id):
		state.crafts[station.id] = []
	var seconds := craft_seconds(recipe)
	state.crafts[station.id].append({"id": str(recipe.id), "output": {"item": str(recipe.output.item), "count": int(recipe.output.get("count", 1))},
		"left": seconds, "total": seconds})
	return ""


## Collects `station`'s finished crafts into the stash (found in raid), in order, as long as each fits.
## "" when all of them went in, else "No room in the stash" (what didn't fit waits).
static func collect(station: Dictionary) -> String:
	update()
	var waiting := ready(station)
	if waiting.is_empty():
		return "Nothing to collect"
	while not waiting.is_empty():
		var output: Dictionary = waiting[0].output
		if not _put_in_stash(str(output.item), int(output.count)):
			return "No room in the stash"
		waiting.pop_front()
	GameState.hideout_state.ready.erase(station.id)
	return ""


## Puts `count` of `id` (found in raid, made in the hideout) in the stash, in stacks no bigger than its
## max stack, if all of it fits; false (and nothing added) if it doesn't.
static func _put_in_stash(id: String, count: int) -> bool:
	var data := ItemDB.get_item(id)
	if data == null:
		return true  # An item that's gone from the game: nothing to give.
	var stacks: Array[int] = []
	var left := count
	while left > 0:
		stacks.append(mini(left, data.max_stack))
		left -= stacks[-1]
	var copy := InventoryGrid.new(GameState.stash.size, &"stash")
	copy.load_array(GameState.stash.to_array())
	for amount in stacks:
		if not copy.add(FoundInRaid.make(id, amount, FoundInRaid.Source.CRAFT)):
			return false
	for amount in stacks:
		GameState.stash.add(FoundInRaid.make(id, amount, FoundInRaid.Source.CRAFT))
	return true


# --- Production: the Water Collector and the Bitcoin Farm --------------------------------------

## {"progress" (0-1 toward the next item), "waiting"} for a producing station.
static func production(station_id: String) -> Dictionary:
	var entry: Dictionary = GameState.hideout_state.get("production", {}).get(station_id, {})
	return {"progress": float(entry.get("progress", 0.0)), "waiting": int(entry.get("waiting", 0))}


## How many times the station's base speed it produces at (with power): 1 for the Water Collector; the
## farm: 1 for one card, + its bonus for each card after the first, 0 without cards.
static func production_speed(station_id: String) -> float:
	if station_id != Hideout.BITCOIN_FARM:
		return 1.0
	var cards := card_count()
	return 0.0 if cards == 0 else 1.0 + (cards - 1) * float(Hideout.find(Hideout.BITCOIN_FARM).get("cards", {}).get("bonus", 0.0))


## Real seconds until the station's next item at the speed it works now (-1: never, as it is: full,
## no cards or no power for the farm).
static func seconds_to_next(station_id: String) -> float:
	update()
	var made: Dictionary = Hideout.built_value(station_id, "produces", {})
	var speed := production_speed(station_id) * rate(Hideout.find(station_id))
	if made.is_empty() or speed <= 0.0 or production(station_id).waiting >= int(made.cap):
		return -1.0
	return (1.0 - production(station_id).progress) * float(made.minutes) * 60.0 / speed


## Collects what the station made into the stash (found in raid), as many as fit. "" when all went in.
static func collect_production(station_id: String) -> String:
	update()
	var entry := production(station_id)
	var made: Dictionary = Hideout.built_value(station_id, "produces", {})
	if entry.waiting == 0 or made.is_empty():
		return "Nothing to collect"
	var reason := ""
	while entry.waiting > 0:
		if not _put_in_stash(str(made.item), 1):
			reason = "No room in the stash"
			break
		entry.waiting -= 1
	GameState.hideout_state.production[station_id] = entry
	return reason


# --- Graphics cards -----------------------------------------------------------------------------

static func card_slots() -> int:
	return int(Hideout.built_value(Hideout.BITCOIN_FARM, "card_slots", 0))


static func card_count() -> int:
	return GameState.hideout_state.get("cards", []).size()


static func card_item() -> String:
	return str(Hideout.find(Hideout.BITCOIN_FARM).get("cards", {}).get("item", "gpu"))


## Why a graphics card can't go in now ("" if it can).
static func install_card_block_reason() -> String:
	if Hideout.level(Hideout.find(Hideout.BITCOIN_FARM)) == 0:
		return "Build the Bitcoin Farm first"
	if card_count() >= card_slots():
		return "Every card slot is full"
	if ItemSearch.count(card_item(), false) == 0:
		return "You have no graphics card"
	return ""


## Puts one graphics card in the farm (from the stash or your character; one without the found-in-raid
## checkmark first). It stays the same card: remove_card() gives it back as it went in. "" on success.
static func install_card() -> String:
	var reason := install_card_block_reason()
	if reason != "":
		return reason
	update()  # The cards so far made what they made before this one speeds it up.
	var fir_before := ItemSearch.count(card_item(), true)
	ItemSearch.take(card_item(), 1, false)
	GameState.hideout_state.cards.append({"id": card_item(), "fir": ItemSearch.count(card_item(), true) < fir_before})
	return ""


## Takes the last graphics card out into the stash. "" on success.
static func remove_card() -> String:
	if card_count() == 0:
		return "No cards in the farm"
	update()
	var card: Dictionary = GameState.hideout_state.cards[-1]
	var piece := ItemInstance.create(str(card.id))
	piece.fir = bool(card.fir)
	if not GameState.stash.add(piece):
		return "No room in the stash"
	GameState.hideout_state.cards.pop_back()
	return ""


# --- The Gym ------------------------------------------------------------------------------------

## The skills a Gym session trains.
const GYM_SKILLS := ["strength", "endurance"]


## Why you can't train now ("" if you can): no Gym, or the last session was too recent.
static func train_block_reason() -> String:
	if Hideout.level(Hideout.find(Hideout.GYM)) == 0:
		return "Build the Gym first"
	var left := float(GameState.hideout_state.get("gym_ready", 0.0)) - now()
	if left > 0.0:
		return "Rested in %s" % UiFormat.countdown(left)
	return ""


## A Gym session: the level's points to `skill` (strength or endurance), and the next session one period
## from now. "" on success.
static func train(skill: String) -> String:
	if not skill in GYM_SKILLS:
		return "The Gym trains Strength or Endurance"
	var reason := train_block_reason()
	if reason != "":
		return reason
	var training: Dictionary = Hideout.built_value(Hideout.GYM, "training", {})
	Skills.add_points(skill, float(training.get("points", 0.0)))
	GameState.hideout_state.gym_ready = snappedf(now() + float(training.get("hours", 1.0)) * 3600.0, 1.0)
	return ""
