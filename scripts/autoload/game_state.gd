extends Node
## Autoload "GameState": the current player profile, inventory (equipment, pockets and what's in
## them), skills and stash, plus the raid being set up. Data only, apart from add_xp(), the one place
## experience is added (it raises the level). SaveManager writes it to disk and reads it back.

## The player's level went up (add_xp()): several levels at once give one signal.
signal level_changed(old_level: int, new_level: int)

enum Faction { NONE, BEAR, USEC }

## Starting reputation bonus by faction (DESIGN.md §3): a trader id from TraderTable.
const FACTION_TRADER: Dictionary[Faction, String] = {Faction.BEAR: "bulat", Faction.USEC: "tinker"}
## The insurer a new profile uses (an id in data/config/insurers.json).
const DEFAULT_INSURER := "bulat"
const FACTION_REP_BONUS := 0.05
## Starting money for a new character (DESIGN.md §14).
const START_ROUBLES := 500_000
const START_DOLLARS := 0
## Player skills (DESIGN.md §12.3), with their names.
const SKILLS := [
	["strength", "Strength"], ["endurance", "Endurance"], ["vitality", "Vitality"],
	["metabolism", "Metabolism"], ["search", "Search"], ["assault_rifles", "Assault rifles"], ["pistols", "Pistols"],
	["bolt_action_rifles", "Bolt-action rifles"], ["marksman_rifles", "Marksman rifles"], ["smgs", "SMGs"],
	["shotguns", "Shotguns"], ["lmgs", "Machine guns"], ["stim_resistance", "Stim resistance"],
]
## What a new character's hotkeys 1-5 use (item ids; DESIGN.md §17.1).
const DEFAULT_HOTKEYS := ["bandage", "painkillers", "ai2_medkit", "frag_grenade", "flashbang_grenade"]
const HOTKEY_COUNT := 5
## A new character starts with full energy and hydration (DESIGN.md §13.7).
const START_ENERGY := 100.0
const START_HYDRATION := 100.0

var faction: Faction = Faction.NONE
var level: int = 1
var xp: int = 0
var roubles: int = START_ROUBLES
var dollars: int = START_DOLLARS
## Drip: style points, earned with 360 trick-shot kills and some quests (DESIGN.md §13.4).
var drip: int = 0
## 360 trick shots over the whole profile: rounds that hit, and kills.
var trick_shots := {"hits": 0, "kills": 0}
## Trader id (TraderTable) -> {"level": loyalty level 1-4, "reputation": float, "spent": money spent in
## roubles (dollars at Progression.dollar_rate()), "barter_reputation": the part of the reputation barters
## earned (capped)} (DESIGN.md §10).
var trader_loyalty: Dictionary = {}
## Trader id -> {"restock": unix time of the next restock, "number": restocks so far (1: the first
## stock), "bought": {offer id: how many bought since the last restock}, "wanted": {item id: how many of
## that Wanted item sold to them since}} (DESIGN.md §10, TraderStock).
var trader_stock: Dictionary = {}
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
## The PMC's energy and hydration (DESIGN.md §13.7): carried from raid to raid, recovering over real
## time out of raid (Consumables.recover_profile()), from `metabolism_time` (Unix seconds, 0: not yet).
var energy := START_ENERGY
var hydration := START_HYDRATION
var metabolism_time := 0.0
## Insured items on their way back (DESIGN.md §2, Insurance): {"item": ItemInstance.to_dict(), "due":
## unix time, "insurer"}, delivered to the stash once due and there's room (Insurance.deliver_due()).
var insurance_pending: Array = []
## The trader you insure with (an id in data/config/insurers.json).
var insurer := DEFAULT_INSURER
## Hotkeys 1-5: the item id each one uses (the first one you carry), "" for none.
var hotkeys: Array = DEFAULT_HOTKEYS.duplicate()
## Points of interest you've been in, by map (DESIGN.md §5.2): {map id: [POI ids]}.
var explored: Dictionary = {}
## The raid being set up or played: {"map": map id, "side": "pmc" or "scav", "loadout": Inventory}.
## Not saved.
var raid: Dictionary = {}
## The screen the main menu opens when it loads ("hideout" after a raid's summary; "" for none). Not
## saved.
var menu_return := ""


func _ready() -> void:
	_reset(Faction.NONE)


## A fresh level-1 character of the given faction, with the faction's starter kit equipped and its
## starter stash (DESIGN.md §16.4, data/config/factions.json).
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


## Puts item `id` on hotkey `index` (0-4; "" clears it), taking it off any other hotkey.
func set_hotkey(index: int, id: String) -> void:
	for i in hotkeys.size():
		if hotkeys[i] == id:
			hotkeys[i] = ""
	if index >= 0 and index < HOTKEY_COUNT:
		hotkeys[index] = id


## The hotkey (0-4) item `id` is on, or -1.
func hotkey_of(id: String) -> int:
	return hotkeys.find(id) if id != "" else -1


## Adds `amount` experience: raid settle (RaidOutcome) and quest turn-in (QuestLog) come through here.
## The level rises as experience crosses Progression's thresholds, several levels at once if need be,
## and never falls; a level-up emits level_changed and checks every trader's loyalty again
## (Trading.update_all_loyalty()). Returns how many levels were gained.
func add_xp(amount: int) -> int:
	if amount > 0:
		xp += amount
	var old_level := level
	level = maxi(level, Progression.level_for_xp(xp))
	if level == old_level:
		return 0
	level_changed.emit(old_level, level)
	Trading.update_all_loyalty()
	return level - old_level


## Marks POI `poi_id` on `map_id` explored. False if it already was.
func explore(map_id: String, poi_id: String) -> bool:
	var list: Array = explored.get(map_id, [])
	if poi_id in list:
		return false
	list.append(poi_id)
	explored[map_id] = list
	return true


## How many of `map_id`'s points of interest you've explored (that still exist).
func explored_count(map_id: String) -> int:
	var ids := PoiTable.for_map(map_id).map(func(entry: Dictionary) -> String: return str(entry.get("id", "")))
	return explored.get(map_id, []).filter(func(id: String) -> bool: return id in ids).size()


## Share (0-1) of `map_id`'s points of interest you've explored.
func exploration(map_id: String) -> float:
	var total := PoiTable.for_map(map_id).size()
	return float(explored_count(map_id)) / total if total > 0 else 0.0


func _reset(new_faction: Faction) -> void:
	faction = new_faction
	level = 1
	xp = 0
	roubles = START_ROUBLES
	dollars = START_DOLLARS
	drip = 0
	trick_shots = {"hits": 0, "kills": 0}
	energy = START_ENERGY
	hydration = START_HYDRATION
	metabolism_time = 0.0
	var config: InventoryConfig = load("res://data/config/inventory.tres")
	stash = InventoryGrid.new(config.stash_size, &"stash")
	trader_loyalty = {}
	for trader in TraderTable.ids():
		trader_loyalty[trader] = {"level": 1, "reputation": 0.0, "spent": 0, "barter_reputation": 0.0}
	if FACTION_TRADER.has(faction):
		trader_loyalty[FACTION_TRADER[faction]]["reputation"] += FACTION_REP_BONUS
	trader_stock = {}
	TraderStock.refresh_all()  # Full stock, restocks a period from now.
	inventory = Inventory.new()
	quests = {}
	hideout = {}
	insurance_pending = []
	insurer = DEFAULT_INSURER
	hotkeys = DEFAULT_HOTKEYS.duplicate()
	explored = {}
	skills = {}
	for skill in SKILLS:
		skills[skill[0]] = {"level": 0, "progress": 0.0}


func _give_starter_kit() -> void:
	inventory = Inventory.starter(Factions.of_profile(faction))
	stash.load_array(Factions.starter_stash(Factions.of_profile(faction)))


## Converts the profile and stash to plain data for saving as JSON.
func to_dict() -> Dictionary:
	return {
		"profile": {
			"faction": Faction.find_key(faction),
			"level": level,
			"xp": xp,
			"roubles": roubles,
			"dollars": dollars,
			"drip": drip,
			"trick_shots": trick_shots.duplicate(),
			"trader_loyalty": trader_loyalty.duplicate(true),
			"trader_stock": trader_stock.duplicate(true),
			"inventory": inventory.to_dict(),
			"skills": skills.duplicate(true),
			"quests": quests.duplicate(true),
			"hideout": hideout.duplicate(),
			"metabolism": {"energy": snappedf(energy, 0.01), "hydration": snappedf(hydration, 0.01), "time": metabolism_time},
			"insurance_pending": insurance_pending.duplicate(true),
			"insurer": insurer,
			"hotkeys": hotkeys.duplicate(),
			"explored": explored.duplicate(true),
		},
		"stash": stash.to_array(),
	}


## {key: whole number} from saved {key: number} data (JSON reads every number as a float).
static func _counts(saved: Variant) -> Dictionary:
	var result := {}
	if saved is Dictionary:
		for key: Variant in saved:
			result[str(key)] = int(saved[key])
	return result


## Restores the profile and stash from to_dict() data (older save versions are brought up to date
## first: SaveManager.upgrade()). Missing fields keep new-profile defaults. JSON turns every number into a
## float, so whole numbers are converted back with int(). The level is worked out again from the
## experience (never lower than the saved level), and loyalty levels are checked against it.
func from_dict(data: Dictionary) -> void:
	data = SaveManager.upgrade(data)
	var profile: Dictionary = data.get("profile", {})
	_reset(Faction.get(profile.get("faction", "NONE"), Faction.NONE))
	xp = int(profile.get("xp", xp))
	level = maxi(int(profile.get("level", level)), Progression.level_for_xp(xp))
	roubles = int(profile.get("roubles", roubles))
	dollars = int(profile.get("dollars", dollars))
	drip = int(profile.get("drip", 0))
	var saved_metabolism: Dictionary = profile.get("metabolism", {})
	energy = float(saved_metabolism.get("energy", START_ENERGY))
	hydration = float(saved_metabolism.get("hydration", START_HYDRATION))
	metabolism_time = float(saved_metabolism.get("time", 0.0))
	var saved_tricks: Dictionary = profile.get("trick_shots", {})
	trick_shots = {"hits": int(saved_tricks.get("hits", 0)), "kills": int(saved_tricks.get("kills", 0))}

	var saved_loyalty: Dictionary = profile.get("trader_loyalty", {})
	for trader in saved_loyalty:
		if not trader_loyalty.has(trader):
			continue  # A trader that no longer exists.
		var entry: Dictionary = saved_loyalty[trader]
		trader_loyalty[trader] = {
			"level": clampi(int(entry.get("level", 1)), 1, TraderTable.max_loyalty(trader)),
			"reputation": float(entry.get("reputation", 0.0)),
			"spent": int(entry.get("spent", 0)),
			"barter_reputation": float(entry.get("barter_reputation", 0.0)),
		}

	var saved_stock: Dictionary = profile.get("trader_stock", {})
	for trader: String in saved_stock:
		var entry: Dictionary = saved_stock[trader]
		if trader_stock.has(trader) and entry.has("restock"):  # Older saves have none: full stock from now.
			trader_stock[trader] = {"restock": float(entry.restock), "number": maxi(int(entry.get("number", 1)), 1),
				"bought": _counts(entry.get("bought", {})), "wanted": _counts(entry.get("wanted", {}))}
	TraderStock.refresh_all()  # Restocks that came due while the game was closed.

	if profile.has("inventory"):
		inventory = Inventory.from_dict(profile.inventory)
	elif profile.has("equipment"):
		# Version 2: slot -> item id, plus the loaded ammo and a list of pocket stacks.
		inventory = Inventory.from_v2(profile.equipment, str(profile.get("weapon_ammo", "")), profile.get("pockets", []))
		inventory.equip("secure", ItemInstance.create("secure_alpha"))
	elif has_profile():
		# Version 1, from before equipment existed: start with the faction's starter kit worn.
		inventory = Inventory.starter(Factions.of_profile(faction))
	var saved_quests: Dictionary = profile.get("quests", {})
	for quest: String in saved_quests:
		var entry: Dictionary = saved_quests[quest]
		quests[quest] = {"state": str(entry.get("state", "active")),
			"progress": entry.get("progress", []).map(func(n: Variant) -> int: return int(n))}
	insurance_pending = profile.get("insurance_pending", []).duplicate(true)
	insurer = str(profile.get("insurer", DEFAULT_INSURER))
	var saved_hotkeys: Array = profile.get("hotkeys", DEFAULT_HOTKEYS)
	for i in HOTKEY_COUNT:
		hotkeys[i] = str(saved_hotkeys[i]) if i < saved_hotkeys.size() else ""
	var saved_explored: Dictionary = profile.get("explored", {})
	for map_id: String in saved_explored:
		explored[map_id] = saved_explored[map_id].map(func(id: Variant) -> String: return str(id))
	var saved_hideout: Dictionary = profile.get("hideout", {})
	for station: String in saved_hideout:
		hideout[station] = int(saved_hideout[station])
	var saved_skills: Dictionary = profile.get("skills", {})
	for skill: String in saved_skills:
		if skills.has(skill):
			var entry: Dictionary = saved_skills[skill]
			skills[skill] = {"level": int(entry.get("level", 0)), "progress": float(entry.get("progress", 0.0))}

	stash.load_array(data.get("stash", []))
	Trading.update_all_loyalty()
