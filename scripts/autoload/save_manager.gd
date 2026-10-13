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
const SAVE_VERSION := 7


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
