extends Node
## Autoload "GameState": the current player profile and stash contents.
## Data only, no gameplay rules. SaveManager writes it to disk and reads it back.

enum Faction { NONE, BEAR, USEC }

## Trader ids (DESIGN.md §10). Each trader gets a loyalty entry.
const TRADERS: Array[String] = ["prapor", "therapist", "skier", "peacekeeper", "mechanic", "ragman", "jaeger"]
## Starting reputation bonus by faction (DESIGN.md §3).
const FACTION_TRADER: Dictionary[Faction, String] = {Faction.BEAR: "prapor", Faction.USEC: "peacekeeper"}
const FACTION_REP_BONUS := 0.05
## Starting money for a new character (DESIGN.md §14).
const START_ROUBLES := 500_000
const START_DOLLARS := 0

var faction: Faction = Faction.NONE
var level: int = 1
var xp: int = 0
var roubles: int = START_ROUBLES
var dollars: int = START_DOLLARS
## Trader id -> {"level": loyalty level 1-4, "reputation": float, "spent": roubles spent} (DESIGN.md §10).
var trader_loyalty: Dictionary = {}
## Items in the stash. Each entry:
## {"id": item id, "x": column, "y": row, "rotated": bool, "count": stack size, "fir": Found-in-Raid}.
## Grid placement rules come later with the inventory (DESIGN.md §7–8).
var stash: Array[Dictionary] = []


func _ready() -> void:
	new_profile(Faction.NONE)


## Resets everything to a fresh level-1 character of the given faction.
func new_profile(new_faction: Faction) -> void:
	faction = new_faction
	level = 1
	xp = 0
	roubles = START_ROUBLES
	dollars = START_DOLLARS
	stash = []
	trader_loyalty = {}
	for trader in TRADERS:
		trader_loyalty[trader] = {"level": 1, "reputation": 0.0, "spent": 0}
	if FACTION_TRADER.has(faction):
		trader_loyalty[FACTION_TRADER[faction]]["reputation"] += FACTION_REP_BONUS


## Converts the profile and stash to plain data for saving as JSON.
func to_dict() -> Dictionary:
	return {
		"profile": {
			"faction": Faction.find_key(faction),
			"level": level,
			"xp": xp,
			"roubles": roubles,
			"dollars": dollars,
			"trader_loyalty": trader_loyalty.duplicate(true),
		},
		"stash": stash.duplicate(true),
	}


## Restores the profile and stash from to_dict() data. Missing fields keep new-profile defaults.
## JSON turns every number into a float, so whole numbers are converted back with int().
func from_dict(data: Dictionary) -> void:
	var profile: Dictionary = data.get("profile", {})
	new_profile(Faction.get(profile.get("faction", "NONE"), Faction.NONE))
	level = int(profile.get("level", level))
	xp = int(profile.get("xp", xp))
	roubles = int(profile.get("roubles", roubles))
	dollars = int(profile.get("dollars", dollars))

	var saved_loyalty: Dictionary = profile.get("trader_loyalty", {})
	for trader in saved_loyalty:
		if not trader_loyalty.has(trader):
			continue  # A trader that no longer exists.
		var entry: Dictionary = saved_loyalty[trader]
		trader_loyalty[trader] = {
			"level": int(entry.get("level", 1)),
			"reputation": float(entry.get("reputation", 0.0)),
			"spent": int(entry.get("spent", 0)),
		}

	for entry: Dictionary in data.get("stash", []):
		stash.append({
			"id": str(entry.get("id", "")),
			"x": int(entry.get("x", 0)),
			"y": int(entry.get("y", 0)),
			"rotated": bool(entry.get("rotated", false)),
			"count": int(entry.get("count", 1)),
			"fir": bool(entry.get("fir", false)),
		})
