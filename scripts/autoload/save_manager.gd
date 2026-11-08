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
## Version 11 adds the hideout's Stash station (DESIGN.md §8, §9): its level, saved with the other
## stations, sets the stash's size (no size is saved), so the stash is sized from it before its items
## load. Older saves get the Stash at level 1, the 10 × 30 they had; older builds refuse a version 11
## save, which could hold items past row 30.
## Version 12 makes the headset a character slot and adds the face cover slot and loadout presets
## (DESIGN.md §7, §12.2, §16.6). A headset fitted to a helmet in an older save (worn, in the stash or
## anywhere inside a container, at any depth) comes off the helmet (helmets have no headset slot any
## more): onto the headset slot if the helmet is worn and that slot is free, else into the stash as a
## loose item (upgrade() lists those under LOOSE_KEY; GameState.from_dict() places them, and one with
## no room waits in insurance_pending until there is, marked "from_save": Insurance announces it as an
## item from your old save, not an insurance return). An insured helmet's headset stays insured, with
## the helmet's insurer. A helmet on its way back from insurance (in either pending format) sends its
## headset back beside it, due at the same time. Older saves have no presets.
## Version 13 adds the LOADOUT screen's auto-equip options (DESIGN.md §16.6): "auto_equip": {"budget":
## roubles, 0 for no limit, "protect_legendary"}. Older saves get no limit and protect off (nothing to
## change in upgrade(): GameState.from_dict() fills them in).
const SAVE_VERSION := 13
## Where upgrade() lists items an old save had somewhere that no longer exists (version 12: headsets
## taken off helmets), for GameState.from_dict() to put in the stash. Never saved.
const LOOSE_KEY := "loose_items"
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
## (no trader stock yet: GameState.from_dict() gives full stock and a restock from now). Version 10 and
## older: the Stash station at level 1. Version 11 and older: headsets off helmets (LOOSE_KEY lists the
## ones for the stash). Version 12: nothing to change (no auto-equip options: the defaults). Data with no
## version is taken as current.
func upgrade(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", SAVE_VERSION))
	if version >= SAVE_VERSION:
		return data
	var result := data.duplicate(true)
	if version < 9:
		_upgrade_to_v9(result)
	if version < 11:
		_upgrade_to_v11(result)
	if version < 12:
		_upgrade_to_v12(result)
	result.version = SAVE_VERSION
	return result


## Version 11 and older to version 12 (in place): every headset fitted to a helmet comes off it. The
## worn helmet's goes on the headset slot when that's free; every other one (a helmet in the pockets, a
## rig, the backpack, the secure container or the stash, at any depth) is listed under LOOSE_KEY for the
## stash. A pending insurance return's headset becomes a return of its own, due with the helmet.
func _upgrade_to_v12(result: Dictionary) -> void:
	var loose: Array = []
	var profile: Variant = result.get("profile")
	if profile is Dictionary:
		var inventory: Variant = profile.get("inventory")
		if inventory is Dictionary and inventory.get("equipment") is Dictionary:
			var equipment: Dictionary = inventory.equipment
			var helmet: Variant = equipment.get("helmet")
			if helmet is Dictionary:
				var worn := _take_headset(helmet)
				if not worn.is_empty() and not equipment.get("headset") is Dictionary:
					worn.x = 0
					worn.y = 0
					worn.rotated = false
					equipment.headset = worn
				elif not worn.is_empty():
					loose.append(worn)
			for slot: Variant in equipment:
				if equipment[slot] is Dictionary:
					_take_headsets_inside(equipment[slot], loose)
		if inventory is Dictionary and inventory.get("pockets") is Array:
			for entry: Variant in inventory.pockets:
				_take_headsets_from(entry, loose)
		if profile.get("insurance_pending") is Array:
			var returns: Array = []
			for entry: Variant in profile.insurance_pending:
				returns.append(entry)
				if not entry is Dictionary:
					continue
				# Version 7 kept a bare item dictionary (due at once, Insurance.pending()).
				var item: Variant = entry.get("item") if entry.has("item") else entry
				if not item is Dictionary:
					continue
				var parts: Array = []
				_take_headsets_from(item, parts)
				for part: Dictionary in parts:
					returns.append({"item": part, "due": entry.get("due", 0.0) if entry.has("item") else 0.0,
						"insurer": entry.get("insurer", "") if entry.has("item") else ""})
			profile.insurance_pending = returns
	if result.get("stash") is Array:
		for entry: Variant in result.stash:
			_take_headsets_from(entry, loose)
	for part: Dictionary in loose:
		part.x = -1  # No saved spot: it goes wherever there's room.
		part.y = -1
		part.rotated = false
	result[LOOSE_KEY] = loose


## Takes the headset off the item dictionary `item` (its "mods" entry "headset") and returns it ({} if
## it has none). An insured helmet's insurance covered its headset, so the headset stays insured, with
## the same insurer.
func _take_headset(item: Dictionary) -> Dictionary:
	var mods: Variant = item.get("mods")
	if not mods is Dictionary or not mods.get("headset") is Dictionary:
		return {}
	var headset: Dictionary = mods.headset
	mods.erase("headset")
	if item.get("insured", false):
		headset.insured = true
		if str(item.get("insurer", "")) != "":
			headset.insurer = str(item.insurer)
	return headset


## `entry` (an item dictionary) and everything inside it: each headset taken off a helmet goes into `into`.
func _take_headsets_from(entry: Variant, into: Array) -> void:
	if not entry is Dictionary:
		return
	var headset := _take_headset(entry)
	if not headset.is_empty():
		into.append(headset)
	_take_headsets_inside(entry, into)


## Everything inside item dictionary `entry` (its contents, at any depth), as _take_headsets_from().
func _take_headsets_inside(entry: Dictionary, into: Array) -> void:
	if entry.get("contents") is Array:
		for inside: Variant in entry.contents:
			_take_headsets_from(inside, into)


## Version 10 and older to version 11 (in place): the Stash station, at level 1 (the stash they had).
func _upgrade_to_v11(result: Dictionary) -> void:
	var profile: Variant = result.get("profile")
	if not profile is Dictionary:
		return
	if not profile.get("hideout") is Dictionary:
		profile.hideout = {}
	profile.hideout[Hideout.STASH] = maxi(int(profile.hideout.get(Hideout.STASH, 0)), 1)


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
