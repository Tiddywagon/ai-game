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
## collected), "power_on", "fuel": [{"item": ItemInstance.to_dict(), "left" (seconds of power at
## efficiency 1)}], "production": {station id: {"progress" (0-1 toward the next item), "waiting"}},
## "cards": [ItemInstance.to_dict()], "gym_ready" (unix time the next Gym session can start),
## "cosmetics": [cosmetic ids]}.

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
		if entry is Dictionary and entry.get("item") is Dictionary and ItemDB.has_item(str(entry.item.get("id", ""))):
			result.fuel.append({"item": entry.item.duplicate(true), "left": maxf(float(entry.get("left", 0.0)), 0.0)})
	var production: Variant = saved.get("production")
	if production is Dictionary:
		for station: String in production:
			var entry: Variant = production[station]
			if not Hideout.find(station).is_empty() and entry is Dictionary:
				result.production[station] = {"progress": clampf(float(entry.get("progress", 0.0)), 0.0, 1.0), "waiting": maxi(int(entry.get("waiting", 0)), 0)}
	for entry: Variant in saved.get("cards", []) if saved.get("cards") is Array else []:
		if entry is Dictionary and ItemDB.has_item(str(entry.get("id", ""))):
			result.cards.append(entry.duplicate(true))
	for id: Variant in saved.get("cosmetics", []) if saved.get("cosmetics") is Array else []:
		if not Hideout.find_cosmetic(str(id)).is_empty() and not str(id) in result.cosmetics:
			result.cosmetics.append(str(id))
	return result
