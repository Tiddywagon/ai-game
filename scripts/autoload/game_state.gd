extends Node
## Autoload "GameState": the current player profile, inventory (equipment, pockets and what's in
## them), skills and stash, plus the raid being set up. Data only, no gameplay rules. SaveManager writes
## it to disk and reads it back.

enum Faction { NONE, BEAR, USEC }

## Trader ids (DESIGN.md §10). Each trader gets a loyalty entry.
const TRADERS: Array[String] = ["prapor", "therapist", "skier", "peacekeeper", "mechanic", "ragman", "jaeger"]
## Starting reputation bonus by faction (DESIGN.md §3).
const FACTION_TRADER: Dictionary[Faction, String] = {Faction.BEAR: "prapor", Faction.USEC: "peacekeeper"}
const FACTION_REP_BONUS := 0.05
## Starting money for a new character (DESIGN.md §14).
const START_ROUBLES := 500_000
const START_DOLLARS := 0
## Player skills (DESIGN.md §12.3), with their names.
const SKILLS := [
	["strength", "Strength"], ["endurance", "Endurance"], ["vitality", "Vitality"],
	["metabolism", "Metabolism"], ["search", "Search"], ["assault_rifles", "Assault rifles"],
]
## What a new character has in the stash (DESIGN.md §16.4). The worn kit is Inventory.starter().
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
## The stash grid (DESIGN.md §8).
var stash: InventoryGrid
## Equipment, pockets and everything in them.
var inventory := Inventory.new()
## Skill id -> {"level": int, "progress": 0-1 toward the next level}.
var skills: Dictionary = {}
## Quest id -> {"state": "active" or "completed", "progress": [handed over so far, per objective]}.
## Quests not in here haven't been accepted (DESIGN.md §11, QuestLog).
var quests: Dictionary = {}
## Hideout station id -> level built (DESIGN.md §9, Hideout). Missing: not built.
var hideout: Dictionary = {}
## The raid being set up or played: {"map": map id, "side": "pmc" or "scav", "loadout": Inventory}.
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


## What a PMC takes into a raid: a copy of the inventory. (Raid results aren't written back yet.)
func pmc_loadout() -> Inventory:
	return inventory.duplicate_deep()


## A random Scav kit (DESIGN.md §16.3): nothing from the stash is at risk.
func scav_loadout() -> Inventory:
	return Inventory.scav()


func _reset(new_faction: Faction) -> void:
	faction = new_faction
	level = 1
	xp = 0
	roubles = START_ROUBLES
	dollars = START_DOLLARS
	var config: InventoryConfig = load("res://data/config/inventory.tres")
	stash = InventoryGrid.new(config.stash_size, &"stash")
	trader_loyalty = {}
	for trader in TRADERS:
		trader_loyalty[trader] = {"level": 1, "reputation": 0.0, "spent": 0}
	if FACTION_TRADER.has(faction):
		trader_loyalty[FACTION_TRADER[faction]]["reputation"] += FACTION_REP_BONUS
	inventory = Inventory.new()
	quests = {}
	hideout = {}
	skills = {}
	for skill in SKILLS:
		skills[skill[0]] = {"level": 0, "progress": 0.0}


func _give_starter_kit() -> void:
	inventory = Inventory.starter()
	stash.load_array(STARTER_STASH)


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
			"inventory": inventory.to_dict(),
			"skills": skills.duplicate(true),
			"quests": quests.duplicate(true),
			"hideout": hideout.duplicate(),
		},
		"stash": stash.to_array(),
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

	if profile.has("inventory"):
		inventory = Inventory.from_dict(profile.inventory)
	elif profile.has("equipment"):
		# Version 2: slot -> item id, plus the loaded ammo and a list of pocket stacks.
		inventory = Inventory.from_v2(profile.equipment, str(profile.get("weapon_ammo", "")), profile.get("pockets", []))
		inventory.equip("secure", ItemInstance.create("secure_alpha"))
	elif has_profile():
		# Version 1, from before equipment existed: start with the starter kit worn.
		inventory = Inventory.starter()
	var saved_quests: Dictionary = profile.get("quests", {})
	for quest: String in saved_quests:
		var entry: Dictionary = saved_quests[quest]
		quests[quest] = {"state": str(entry.get("state", "active")),
			"progress": entry.get("progress", []).map(func(n: Variant) -> int: return int(n))}
	var saved_hideout: Dictionary = profile.get("hideout", {})
	for station: String in saved_hideout:
		hideout[station] = int(saved_hideout[station])
	var saved_skills: Dictionary = profile.get("skills", {})
	for skill: String in saved_skills:
		if skills.has(skill):
			var entry: Dictionary = saved_skills[skill]
			skills[skill] = {"level": int(entry.get("level", 0)), "progress": float(entry.get("progress", 0.0))}

	stash.load_array(data.get("stash", []))
