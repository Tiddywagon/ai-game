extends Node
## Autoload "GameState": the current player profile, equipment, skills and stash contents, plus
## the raid being set up. Data only, no gameplay rules. SaveManager writes it to disk and reads it back.

enum Faction { NONE, BEAR, USEC }

## Trader ids (DESIGN.md §10). Each trader gets a loyalty entry.
const TRADERS: Array[String] = ["prapor", "therapist", "skier", "peacekeeper", "mechanic", "ragman", "jaeger"]
## Starting reputation bonus by faction (DESIGN.md §3).
const FACTION_TRADER: Dictionary[Faction, String] = {Faction.BEAR: "prapor", Faction.USEC: "peacekeeper"}
const FACTION_REP_BONUS := 0.05
## Starting money for a new character (DESIGN.md §14).
const START_ROUBLES := 500_000
const START_DOLLARS := 0
## Equipment slots (DESIGN.md §7), in display order, with their names. Pockets are separate.
const SLOTS := [
	["primary", "Primary weapon"], ["secondary", "Secondary weapon"], ["holster", "Holster"], ["melee", "Melee"],
	["helmet", "Helmet"], ["earpiece", "Earpiece"], ["face", "Face cover"], ["armor", "Body armor"],
	["rig", "Tactical rig"], ["backpack", "Backpack"], ["secure", "Secure container"],
]
const POCKET_COUNT := 4
## Player skills (DESIGN.md §12.3), with their names.
const SKILLS := [
	["strength", "Strength"], ["endurance", "Endurance"], ["vitality", "Vitality"],
	["metabolism", "Metabolism"], ["search", "Search"], ["assault_rifles", "Assault rifles"],
]
## What a new character starts with (DESIGN.md §16.4).
const STARTER_EQUIPMENT := {"primary": "ak_74n"}
const STARTER_AMMO := "ammo_545_ps"
const STARTER_POCKETS := [{"id": "ammo_545_ps", "count": 60}, {"id": "bandage", "count": 1}]
const STARTER_STASH := [
	{"id": "ak_74n", "x": 0, "y": 0}, {"id": "ammo_545_ps", "x": 5, "y": 0, "count": 60},
	{"id": "ammo_545_ps", "x": 6, "y": 0, "count": 60}, {"id": "bandage", "x": 7, "y": 0},
	{"id": "bandage", "x": 8, "y": 0}, {"id": "bandage", "x": 9, "y": 0}, {"id": "bolts", "x": 5, "y": 1},
	{"id": "bolts", "x": 6, "y": 1},
]

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
## Slot id -> item id, "" when empty.
var equipment: Dictionary = {}
## Ammo loaded in the primary weapon.
var weapon_ammo := ""
## Up to POCKET_COUNT entries: {"id": item id, "count": stack size}.
var pockets: Array[Dictionary] = []
## Skill id -> {"level": int, "progress": 0-1 toward the next level}.
var skills: Dictionary = {}
## The raid being set up or played: {"map": map id, "side": "pmc" or "scav", "loadout": {...}}.
## Not saved.
var raid: Dictionary = {}


func _ready() -> void:
	_reset(Faction.NONE)


## A fresh level-1 character of the given faction, with the starter kit equipped and in the stash.
func new_profile(new_faction: Faction) -> void:
	_reset(new_faction)
	_give_starter_kit()


## True once the player has picked a faction (or loaded a save).
func has_profile() -> bool:
	return faction != Faction.NONE


## What a PMC takes into a raid: the current equipment and pockets.
func pmc_loadout() -> Dictionary:
	return {"equipment": equipment.duplicate(), "weapon_ammo": weapon_ammo, "pockets": pockets.duplicate(true)}


## A random Scav kit (DESIGN.md §16.3): nothing from the stash is at risk.
func scav_loadout() -> Dictionary:
	var pocket_pool := [{"id": "ammo_545_ps", "count": 30}, {"id": "bandage", "count": 1}, {"id": "bolts", "count": 1}]
	pocket_pool.shuffle()
	return {
		"equipment": {"primary": "ak_74n"},
		"weapon_ammo": "ammo_545_ps",
		"pockets": [{"id": "ammo_545_ps", "count": randi_range(20, 60)}] + pocket_pool.slice(0, randi_range(0, 2)),
	}


func _reset(new_faction: Faction) -> void:
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
	equipment = {}
	for slot in SLOTS:
		equipment[slot[0]] = ""
	weapon_ammo = ""
	pockets = []
	skills = {}
	for skill in SKILLS:
		skills[skill[0]] = {"level": 0, "progress": 0.0}


func _give_starter_kit() -> void:
	equipment.merge(STARTER_EQUIPMENT, true)
	weapon_ammo = STARTER_AMMO
	for pocket: Dictionary in STARTER_POCKETS:
		pockets.append(pocket.duplicate())
	for item: Dictionary in STARTER_STASH:
		stash.append({"id": item.id, "x": item.x, "y": item.y, "rotated": false, "count": item.get("count", 1), "fir": false})


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
			"equipment": equipment.duplicate(),
			"weapon_ammo": weapon_ammo,
			"pockets": pockets.duplicate(true),
			"skills": skills.duplicate(true),
		},
		"stash": stash.duplicate(true),
	}


## Restores the profile and stash from to_dict() data. Missing fields keep new-profile defaults.
## JSON turns every number into a float, so whole numbers are converted back with int().
func from_dict(data: Dictionary) -> void:
	var profile: Dictionary = data.get("profile", {})
	_reset(Faction.get(profile.get("faction", "NONE"), Faction.NONE))
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

	if profile.has("equipment"):
		var saved_equipment: Dictionary = profile.equipment
		for slot: String in equipment:
			equipment[slot] = str(saved_equipment.get(slot, ""))
		weapon_ammo = str(profile.get("weapon_ammo", ""))
		for pocket: Dictionary in profile.get("pockets", []):
			pockets.append({"id": str(pocket.get("id", "")), "count": int(pocket.get("count", 1))})
	elif has_profile():
		# Saves from before equipment existed (version 1): start with the starter kit equipped.
		equipment.merge(STARTER_EQUIPMENT, true)
		weapon_ammo = STARTER_AMMO
		for pocket: Dictionary in STARTER_POCKETS:
			pockets.append(pocket.duplicate())
	var saved_skills: Dictionary = profile.get("skills", {})
	for skill: String in saved_skills:
		if skills.has(skill):
			var entry: Dictionary = saved_skills[skill]
			skills[skill] = {"level": int(entry.get("level", 0)), "progress": float(entry.get("progress", 0.0))}

	for entry: Dictionary in data.get("stash", []):
		stash.append({
			"id": str(entry.get("id", "")),
			"x": int(entry.get("x", 0)),
			"y": int(entry.get("y", 0)),
			"rotated": bool(entry.get("rotated", false)),
			"count": int(entry.get("count", 1)),
			"fir": bool(entry.get("fir", false)),
		})
