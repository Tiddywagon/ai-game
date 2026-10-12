class_name ItemData
extends Resource
## Definition of one item type (DESIGN.md §6, §15). Items live in data/items/, either as one .tres
## file per item or as JSON files holding one item or a list of them (see from_dict() for the keys).
## Per-copy state (rolled bonuses, durability, Found-in-Raid) lives on the item instance, not here.

## Item categories (DESIGN.md §6.1). Saved as numbers in .tres files: only add new values at the end.
enum Category { WEAPON, AMMO, ATTACHMENT, ARMOR, RIG, BACKPACK, HELMET, MEDS, FOOD, VALUABLE, JUNK, KEY, CONTAINER, MELEE }
## Rarity scale (DESIGN.md §6.2). Same rule: only add new values at the end.
enum Rarity { COMMON, UNCOMMON, RARE, ULTRA_RARE, EPIC, LEGENDARY }

## Names used in JSON files, indexed by Category and Rarity.
const CATEGORY_NAMES: Array[String] = ["weapon", "ammo", "attachment", "armor", "rig", "backpack", "helmet",
	"meds", "food", "valuable", "junk", "key", "container", "melee"]
const RARITY_IDS: Array[String] = ["common", "uncommon", "rare", "ultra_rare", "epic", "legendary"]
## Keys a JSON item may have.
const JSON_KEYS: Array[String] = ["id", "name", "description", "category", "rarity", "size", "weight", "value",
	"max_stack", "stats", "weapon", "icon", "loot_weight"]

## Unique id used by code and save files, e.g. "ak_74n". Match the file name and never rename it.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.JUNK
@export var rarity: Rarity = Rarity.COMMON
## Cells taken in the grid inventory, width × height (DESIGN.md §7).
@export var size: Vector2i = Vector2i.ONE
@export var weight_kg: float = 0.1
## Base trader value in roubles (DESIGN.md §14).
@export var base_value: int = 0
## How many fit in one stack; 1 means the item doesn't stack (DESIGN.md §7).
@export_range(1, 9999) var max_stack: int = 1
## Category-specific stats, e.g. {"caliber": "5.45x39", "damage": 50, "penetration": 28} for ammo,
## {"grid": [4, 2]} for anything with its own grid (rigs, backpacks, containers; add "secure": true
## for secure containers), {"class": "pistol"} for guns that go in the pistol slot.
@export var stats: Dictionary = {}
## Weapons only: how the gun handles (fire rate, magazine, reload, recoil). See WeaponData.
@export var weapon: WeaponData
## Inventory art. Leave empty for a placeholder: a box in the rarity's colour with a category symbol.
@export var icon: Texture2D
## How often loot tables pick this item compared with others of the same rarity; 0 = never from loot.
@export_range(0.0, 100.0, 0.1) var loot_weight: float = 1.0


## The icon, or a generated placeholder coloured by rarity (follows the colorblind palette).
func get_icon() -> Texture2D:
	return icon if icon else ItemIcons.placeholder(self)


func category_name() -> String:
	return CATEGORY_NAMES[category]


## Builds an item from a JSON object. Keys: id, name, description, category (a CATEGORY_NAMES entry),
## rarity (a RARITY_IDS entry; "Ultra Rare" works too), size ([width, height]), weight (kg), value
## (roubles), max_stack, stats ({...}), weapon (path to a WeaponData .tres), icon (path to an image),
## loot_weight. Only id, name, category and rarity are required. Returns null (and reports why) if the
## data is invalid. `source` names the file in error messages.
static func from_dict(data: Dictionary, source: String) -> ItemData:
	for key in ["id", "name", "category", "rarity"]:
		if not data.has(key):
			push_error("ItemDB: %s: an item is missing \"%s\"" % [source, key])
			return null
	for key: String in data:
		if key not in JSON_KEYS:
			push_warning("ItemDB: %s: item \"%s\" has an unknown key \"%s\"" % [source, data.id, key])
	var item := ItemData.new()
	item.id = str(data.id)
	item.display_name = str(data.name)
	item.description = str(data.get("description", ""))
	var category_index := CATEGORY_NAMES.find(str(data.category).to_lower())
	var rarity_index := RARITY_IDS.find(str(data.rarity).to_lower().replace(" ", "_"))
	if category_index < 0:
		push_error("ItemDB: %s: \"%s\" has unknown category \"%s\" (use one of %s)" % [source, item.id, data.category, ", ".join(CATEGORY_NAMES)])
		return null
	if rarity_index < 0:
		push_error("ItemDB: %s: \"%s\" has unknown rarity \"%s\" (use one of %s)" % [source, item.id, data.rarity, ", ".join(RARITY_IDS)])
		return null
	item.category = category_index as Category
	item.rarity = rarity_index as Rarity
	var grid: Array = data.get("size", [1, 1])
	if grid.size() != 2 or int(grid[0]) < 1 or int(grid[1]) < 1:
		push_error("ItemDB: %s: \"%s\" size must be [width, height], both at least 1" % [source, item.id])
		return null
	item.size = Vector2i(int(grid[0]), int(grid[1]))
	item.weight_kg = float(data.get("weight", 0.1))
	item.base_value = int(data.get("value", 0))
	item.max_stack = maxi(int(data.get("max_stack", 1)), 1)
	item.stats = data.get("stats", {})
	item.loot_weight = maxf(float(data.get("loot_weight", 1.0)), 0.0)
	for key in ["weapon", "icon"]:
		if data.has(key):
			var resource := load(str(data[key]))
			if resource == null:
				push_error("ItemDB: %s: \"%s\" can't load %s \"%s\"" % [source, item.id, key, data[key]])
				return null
			item.set(key, resource)
	return item
