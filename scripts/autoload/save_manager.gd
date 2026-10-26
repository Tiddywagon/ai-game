extends Node
## Autoload "SaveManager": saves and loads GameState (profile + stash) as JSON (DESIGN.md §15).
## The main menu loads the save at start-up and saves when a new profile is created.
## The file lives in Godot's user folder, e.g. on Windows:
## %APPDATA%\Godot\app_userdata\AI Game\savegame.json

const SAVE_PATH := "user://savegame.json"
## Increase when the save format changes, and convert old saves in load_game().
## Version 2 added equipment, pockets and skills; version 1 saves get the starter kit equipped.
## Version 3 stores the inventory as item instances in grids (with container contents and loaded
## rounds); version 2 equipment and pockets are converted, and get the Alpha secure container.
## Version 4 keeps each gun's rounds with their Found-in-Raid status (version 3 rounds load as not
## found in raid), and adds quests and hideout station levels.
## Version 5 adds weapon mods and durability (older guns load with their default parts, as new).
## Version 6 adds Drip and trick-shot stats (older profiles start at 0).
## Version 7 adds insurance: insured items and returns waiting for room in the stash (older saves have
## neither).
## Version 8 adds explored points of interest, the insurer you pick and timed insurance returns
## ({"item", "due", "insurer"}; version 7 returns waiting for room arrive at once).
## Version 9 renames the traders (DESIGN.md §10) and adds the reputation barters earned with each
## ("barter_reputation", 0 for older saves). Older saves get the new ids everywhere a trader id is
## saved (TRADER_IDS_V8): loyalty (Jaeger's merges into Bulat's: the higher level and reputation, the
## money spent added up; Mole starts fresh), the insurer you pick, insurance returns on their way and
## the insurer on every item (nested contents and parts too). Version 9 also raised every quest's
## reputation and moved USEC's starting bonus from The Broker to Tinker, so older saves get their
## reputation counted again (_recount_reputation()). The level is worked out again from the experience
## whatever the version (GameState.from_dict()).
## Version 10 adds trader stock (DESIGN.md §10, TraderStock): per trader the next restock time, the
## restock number, how many of each limited offer was bought since the last restock (by offer id; the
## fence's worn gear too) and how many of each Wanted item was sold. The Wanted lists and the fence's
## stock are rolled again from the trader and the restock number, so they aren't saved. Older saves
## start with full stock and a restock one period from loading.
const SAVE_VERSION := 10
## Trader ids before version 9 -> the trader who took over (upgrade()).
const TRADER_IDS_V8 := {"prapor": "bulat", "therapist": "vera", "skier": "zoya", "peacekeeper": "broker",
	"mechanic": "tinker", "ragman": "stitch", "jaeger": "bulat"}
## The trader each faction's starting reputation went to before version 9 (old ids).
const FACTION_TRADER_V8 := {"BEAR": "prapor", "USEC": "peacekeeper"}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Writes GameState to disk. Returns true on success.
func save_game() -> bool:
	var data := GameState.to_dict()
	data["version"] = SAVE_VERSION
	# Write a temporary file first, so a crash while saving can't corrupt the existing save.
	var temp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: can't write %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(temp_path, SAVE_PATH)
	if err != OK:
		push_error("SaveManager: can't replace %s (%s)" % [SAVE_PATH, error_string(err)])
		return false
	return true


## Loads the save into GameState. Returns false if there is no usable save;
## GameState is left unchanged in that case.
func load_game() -> bool:
	if not has_save():
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		push_error("SaveManager: %s is not valid save data" % SAVE_PATH)
		return false
	if int(data.get("version", 0)) > SAVE_VERSION:
		push_error("SaveManager: the save was made by a newer version of the game")
		return false
	GameState.from_dict(data)
	return true


## Deletes the save file, e.g. when starting a new character.
func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


## Save `data` brought up to SAVE_VERSION (a copy; GameState.from_dict() reads it). Version 8 and
## older: the version 9 trader ids and reputation (see the version notes). Version 9: nothing to change
## (no trader stock yet: GameState.from_dict() gives full stock and a restock from now). Data with no
## version is taken as current.
func upgrade(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", SAVE_VERSION))
	if version >= SAVE_VERSION:
		return data
	var result := data.duplicate(true)
	if version < 9:
		_upgrade_to_v9(result)
	result.version = SAVE_VERSION
	return result


## Version 8 and older to version 9 (in place): the new trader ids and reputation.
func _upgrade_to_v9(result: Dictionary) -> void:
	var profile: Dictionary = result.get("profile", {})
	var loyalty: Dictionary = profile.get("trader_loyalty", {})
	var renamed := {}
	for old_id: String in loyalty:
		var id: String = TRADER_IDS_V8.get(old_id, old_id)
		var entry: Dictionary = loyalty[old_id]
		if not renamed.has(id):
			renamed[id] = entry.duplicate()
			continue
		var kept: Dictionary = renamed[id]  # Two old traders became one (Jaeger into Bulat).
		kept.level = maxi(int(kept.get("level", 1)), int(entry.get("level", 1)))
		kept.reputation = maxf(float(kept.get("reputation", 0.0)), float(entry.get("reputation", 0.0)))
		kept.spent = int(kept.get("spent", 0)) + int(entry.get("spent", 0))
	_recount_reputation(renamed, str(profile.get("faction", "NONE")), profile.get("quests", {}))
	if profile.has("trader_loyalty") or not renamed.is_empty():
		profile.trader_loyalty = renamed
	if profile.has("insurer"):
		profile.insurer = TRADER_IDS_V8.get(str(profile.insurer), str(profile.insurer))
	_rename_insurers(profile.get("inventory", {}))
	_rename_insurers(profile.get("insurance_pending", []))
	_rename_insurers(result.get("stash", []))


## Before version 9 a trader's reputation came only from their quests and the faction bonus. Each
## trader in `loyalty` (version 9 ids) gets the faction bonus (GameState.FACTION_TRADER) plus today's
## reputation for every quest `quests` marks completed, or what the save had if that's more (less the
## old faction bonus where it moved to another trader: USEC's, from The Broker to Tinker).
func _recount_reputation(loyalty: Dictionary, faction: String, quests: Dictionary) -> void:
	var earned := {}
	var bonus_trader: String = GameState.FACTION_TRADER.get(GameState.Faction.get(faction, GameState.Faction.NONE), "")
	if bonus_trader != "":
		earned[bonus_trader] = GameState.FACTION_REP_BONUS
	for quest_id: String in quests:
		var quest := QuestLog.find(quest_id)
		if quest.is_empty() or str(quests[quest_id].get("state", "")) != "completed":
			continue
		var trader := str(quest.get("trader", ""))
		earned[trader] = float(earned.get(trader, 0.0)) + float(quest.get("rewards", {}).get("reputation", 0.0))
	var old_bonus_trader: String = TRADER_IDS_V8.get(FACTION_TRADER_V8.get(faction, ""), "")
	for id: String in earned:
		if not loyalty.has(id):
			loyalty[id] = {"level": 1, "reputation": 0.0, "spent": 0}
	for id: String in loyalty:
		var entry: Dictionary = loyalty[id]
		var saved := float(entry.get("reputation", 0.0))
		if id == old_bonus_trader and id != bonus_trader:
			saved = maxf(saved - GameState.FACTION_REP_BONUS, 0.0)
		entry.reputation = snappedf(maxf(saved, float(earned.get(id, 0.0))), Progression.REPUTATION_STEP)


## Renames every "insurer" in `value` (item dicts, lists of them, and whatever they hold) to its
## version 9 id.
func _rename_insurers(value: Variant) -> void:
	if value is Dictionary:
		if value.get("insurer") is String:
			value.insurer = TRADER_IDS_V8.get(value.insurer, value.insurer)
		for key: Variant in value:
			if value[key] is Dictionary or value[key] is Array:
				_rename_insurers(value[key])
	elif value is Array:
		for entry: Variant in value:
			_rename_insurers(entry)
