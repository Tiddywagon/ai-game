extends Node
## Autoload "ItemDB": every item definition in the game, loaded once at startup (DESIGN.md §6, §15).
## Reads everything under data/items/, including subfolders:
## - .tres files: one ItemData resource each (made in the Inspector).
## - .json files: one item object, or a list of them (keys in ItemData.from_dict()).
## Adding an item never needs code: drop a file in. Ids must be unique across both kinds.
## Usage: ItemDB.get_item("bandage").display_name

const ITEMS_DIR := "res://data/items"

var _items: Dictionary[String, ItemData] = {}
## Items by rarity, for loot rolls.
var _by_rarity: Array[Array] = []


func _ready() -> void:
	_load_dir(ITEMS_DIR)
	for rarity in ItemData.Rarity.size():
		_by_rarity.append([])
	for item: ItemData in _items.values():
		_by_rarity[item.rarity].append(item)
	print("ItemDB: loaded %d items" % _items.size())


## Returns the definition for `id`, or null (with a warning) if no item has that id.
func get_item(id: String) -> ItemData:
	if not _items.has(id):
		push_warning("ItemDB: unknown item id '%s'" % id)
		return null
	return _items[id]


func has_item(id: String) -> bool:
	return _items.has(id)


func all_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	result.assign(_items.values())
	return result


## Items of `rarity` that loot can drop (loot_weight above 0), limited to `categories` unless it's empty.
func lootable(rarity: int, categories: Array = []) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item: ItemData in _by_rarity[rarity]:
		if item.loot_weight > 0.0 and (categories.is_empty() or item.category in categories):
			result.append(item)
	return result


func _load_dir(path: String) -> void:
	for sub_dir in DirAccess.get_directories_at(path):
		_load_dir(path.path_join(sub_dir))
	for file_name in DirAccess.get_files_at(path):
		# In exported builds, resources are listed as "name.tres.remap".
		file_name = file_name.trim_suffix(".remap")
		var file_path := path.path_join(file_name)
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var item := load(file_path) as ItemData
			if item == null:
				push_error("ItemDB: %s is not an ItemData resource" % file_path)
			else:
				_add(item, file_path)
		elif file_name.ends_with(".json"):
			_load_json(file_path)


func _load_json(file_path: String) -> void:
	var text := FileAccess.get_file_as_string(file_path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ItemDB: %s line %d: %s" % [file_path, json.get_error_line(), json.get_error_message()])
		return
	var entries: Array = json.data if json.data is Array else [json.data]
	for entry in entries:
		if not entry is Dictionary:
			push_error("ItemDB: %s: every item must be a JSON object" % file_path)
			continue
		var item := ItemData.from_dict(entry, file_path)
		if item:
			_add(item, file_path)


func _add(item: ItemData, file_path: String) -> void:
	if item.id.is_empty():
		push_error("ItemDB: %s has an item with no id" % file_path)
	elif _items.has(item.id):
		push_error("ItemDB: duplicate id '%s' in %s" % [item.id, file_path])
	else:
		_items[item.id] = item
