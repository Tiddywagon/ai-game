extends Node
## Autoload "ItemDB": every item definition in the game, loaded once at startup (DESIGN.md §6, §15).
## Reads all ItemData .tres files under data/items/, including subfolders.
## Usage: ItemDB.get_item("bandage").display_name

const ITEMS_DIR := "res://data/items"

var _items: Dictionary[String, ItemData] = {}


func _ready() -> void:
	_load_dir(ITEMS_DIR)
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


func _load_dir(path: String) -> void:
	for sub_dir in DirAccess.get_directories_at(path):
		_load_dir(path.path_join(sub_dir))
	for file_name in DirAccess.get_files_at(path):
		# In exported builds, resources are listed as "name.tres.remap".
		file_name = file_name.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var file_path := path.path_join(file_name)
		var item := load(file_path) as ItemData
		if item == null:
			push_error("ItemDB: %s is not an ItemData resource" % file_path)
		elif item.id.is_empty():
			push_error("ItemDB: %s has no id" % file_path)
		elif _items.has(item.id):
			push_error("ItemDB: duplicate id '%s' in %s" % [item.id, file_path])
		else:
			_items[item.id] = item
