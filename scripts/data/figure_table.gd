class_name FigureTable
extends RefCounted
## Collectible figures as data (DESIGN.md §6.6): the figure items (data/items/figures/: category
## figure, 1×1, "stats": {"set": a set id, "model": the recipe of its placeholder 3D model, FigureModel})
## and data/config/figures.json: the shelf ({"station", "columns"}), the sets in collection order
## ([{"id", "name", "about", "found", "bonus": {"type", "value"}}]) and the sources (where figures drop:
## {"container", "scav_body", "pmc_body", "boss", "landmark", "flea"}). A boss's figure is bosses.json's
## "figure", an original point of interest's is pois.json's "figure". Checked once the items are loaded
## (problems(), run by ItemDB). What the profile does with figures (the shelf, bonuses, spares) is
## Figures.

const PATH := "res://data/config/figures.json"
## The tag every figure carries (with its set id as a second tag: figure loot tables roll by them).
const TAG := "figure"
const SET_KEYS := ["id", "name", "about", "found", "bonus"]
const SOURCES := ["container", "scav_body", "pmc_body", "boss", "landmark", "flea"]
## Fewest figures a set may have.
const MIN_SET_SIZE := 3
## A figure weighs this much (kg).
const WEIGHT := Vector2(0.1, 0.3)
## The bonus types (Figures.bonus()), each with the lowest and highest value a set may give and what it
## reads as ("%s" takes the value: a share as a percentage, a count as it is).
const BONUS_TYPES := {
	"search_speed": {"min": 0.01, "max": 0.5, "text": "+%s loot search speed", "share": true},
	"pmc_kill_xp": {"min": 0.01, "max": 1.0, "text": "+%s XP from PMC kills", "share": true},
	"trader_prices": {"min": 0.005, "max": 0.1, "text": "%s better trader prices", "share": true},
	"boss_chance": {"min": 0.01, "max": 1.0, "text": "+%s boss spawn chance", "share": true},
	"metabolism": {"min": 0.01, "max": 0.9, "text": "%s slower energy and hydration drain", "share": true},
	"drip_spin": {"min": 1.0, "max": 10.0, "text": "+%s free Drip slot spin a day", "share": false},
	"exploration_xp": {"min": 0.01, "max": 1.0, "text": "+%s exploration XP", "share": true},
}

## The file config() loads (tests point it at a broken copy).
static var path := PATH
static var _config := {}
static var _figures: Array[ItemData] = []
static var _tables := {}


## data/config/figures.json ({} with an error if it isn't valid).
static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_config = parsed
		else:
			push_error("FigureTable: %s isn't valid JSON" % path)
	return _config


## Forgets what was loaded (tests that point `path` somewhere else).
static func reload() -> void:
	_config = {}
	_figures = []
	_tables = {}


## True for a collectible figure.
static func is_figure(data: ItemData) -> bool:
	return data != null and data.category == ItemData.Category.FIGURE


## The set id of figure `data` ("" for anything else).
static func set_of(data: ItemData) -> String:
	return str(data.stats.get("set", "")) if is_figure(data) else ""


## Every set, in collection order.
static func sets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in config().get("sets", []):
		if entry is Dictionary:
			result.append(entry)
	return result


static func set_ids() -> Array[String]:
	var result: Array[String] = []
	for entry in sets():
		result.append(str(entry.get("id", "")))
	return result


static func find_set(id: String) -> Dictionary:
	for entry in sets():
		if str(entry.get("id", "")) == id:
			return entry
	return {}


## The name of set `id` (not set_name(): that is Resource.set_name() on the script itself).
static func set_title(id: String) -> String:
	return str(find_set(id).get("name", id))


## Every figure: by set in collection order, then in the order its data file lists them (figures of an
## unknown set last).
static func figures() -> Array[ItemData]:
	if _figures.is_empty():
		var order := set_ids()
		var by_set := {}
		for data in ItemDB.all_items():
			if is_figure(data):
				(by_set.get_or_add(order.find(set_of(data)) if set_of(data) in order else order.size(), []) as Array).append(data)
		for index in range(order.size() + 1):
			_figures.append_array(by_set.get(index, []))
	return _figures


## The figures of set `id`, in data order.
static func in_set(id: String) -> Array[ItemData]:
	return figures().filter(func(data: ItemData) -> bool: return set_of(data) == id)


## Set `entry`'s bonus as words: "+5% loot search speed", "3% better trader prices", "+1 free Drip slot
## spin a day".
static func bonus_text(entry: Dictionary) -> String:
	var bonus: Dictionary = entry.get("bonus", {}) if entry.get("bonus") is Dictionary else {}
	var rule: Dictionary = BONUS_TYPES.get(str(bonus.get("type", "")), {})
	if rule.is_empty():
		return ""
	var value := float(bonus.get("value", 0.0))
	return str(rule.text) % ("%d%%" % roundi(value * 100.0) if rule.share else str(roundi(value)))


## How many slots one board of the shelf holds.
static func columns() -> int:
	return maxi(int(config().get("shelf", {}).get("columns", 14)), 1)


## The hideout station that displays figures (Hideout).
static func station_id() -> String:
	return str(config().get("shelf", {}).get("station", "collectors_shelf"))


## The rule for source `name` (one of SOURCES; {} if the config has none).
static func source(name: String) -> Dictionary:
	var rule: Variant = config().get("sources", {}).get(name, {})
	return rule if rule is Dictionary else {}


## The loot table at `table_path` (null if it isn't one), loaded once.
static func table(table_path: String) -> LootTable:
	if not _tables.has(table_path):
		_tables[table_path] = load(table_path) as LootTable if table_path != "" and ResourceLoader.exists(table_path) else null
	return _tables[table_path]


## A random stream of its own for a figure roll beside the rolls of `rng`, so adding figures changes
## nothing else that `rng` rolls (seeded from its seed and `salt`: the same in a seeded raid).
static func stream(rng: RandomNumberGenerator, salt: Variant) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = hash([rng.seed, rng.state, "figure", salt])
	return result


## False in a Shooting Range practice raid (Hideout.practice_raid()): figures never drop there.
static func drops_in_raid() -> bool:
	return not bool(GameState.raid.get("practice", false))


## Puts the figure of each original point of interest in the level into one of that POI's containers,
## in the raids its roll comes up (the landmark source's chance; seeded by the raid and the POI in a
## seeded raid), hidden until the container is searched. Run once the level is ready (RaidLevel).
## Returns the figures placed.
static func place_landmarks(tree: SceneTree) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	if not drops_in_raid():
		return result
	for node in tree.get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		if poi == null or not poi.entry().has("figure"):
			continue
		var rng := RandomNumberGenerator.new()
		if GameState.raid.has("seed"):
			rng.seed = hash([int(GameState.raid.seed), "landmark", poi.map_id, poi.poi_id])
		else:
			rng.randomize()
		var figure := roll_landmark(poi.entry(), rng)
		if figure == null:
			continue
		var boxes: Array[LootBox] = []
		for each in tree.get_nodes_in_group("interactables"):
			var box := each as LootBox
			if box and not box.sealed and not box.ignore_poi and box.grid and PointOfInterest.at(tree, box.global_position) == poi:
				boxes.append(box)
		var first := rng.randi_range(0, maxi(boxes.size() - 1, 0))
		for index in boxes.size():
			if boxes[(first + index) % boxes.size()].grid.add(figure):
				figure.hidden = true
				result.append(figure)
				break
	return result


## The chance a searched container of LootContainer id `container_id` holds a figure.
static func container_chance(container_id: String) -> float:
	var rule := source("container")
	return clampf(float(rule.get("chances", {}).get(container_id, rule.get("chance", 0.0))), 0.0, 1.0)


## The figure a container of `container_id` holds this time, rolled with `rng` (null: none, mostly).
static func roll_container(container_id: String, rng: RandomNumberGenerator) -> ItemInstance:
	return _roll(container_chance(container_id), table(str(source("container").get("table", ""))), rng)


## The figure an AI body carries, rolled with `rng` (null: none, mostly): a Scav's from the scav_body
## table, a PMC's from its faction's table faction_share of the time, else the pmc_body table.
static func roll_body(pmc: bool, faction: StringName, rng: RandomNumberGenerator) -> ItemInstance:
	var rule := source("pmc_body" if pmc else "scav_body")
	var hit := _hit(float(rule.get("chance", 0.0)), rng)
	var own := _hit(float(rule.get("faction_share", 0.0)), rng)
	var table_path := str(rule.get("table", ""))
	if pmc and own and rule.get("faction_tables", {}).has(String(faction)):
		table_path = str(rule.faction_tables[String(faction)])
	return _roll(1.0, table(table_path), rng) if hit else null


## The boss's own figure (`entry`: its bosses.json row), rolled with `rng` against the boss source's
## chance (null: not this time).
static func roll_boss(entry: Dictionary, rng: RandomNumberGenerator) -> ItemInstance:
	var id := str(entry.get("figure", ""))
	if not ItemDB.has_item(id) or not _hit(float(source("boss").get("chance", 0.0)), rng):
		return null
	return ItemInstance.create(id)


## The figure of point of interest `entry` (its pois.json row), rolled with `rng` against the landmark
## source's chance (null: not this raid).
static func roll_landmark(entry: Dictionary, rng: RandomNumberGenerator) -> ItemInstance:
	var id := str(entry.get("figure", ""))
	if not ItemDB.has_item(id) or not _hit(float(source("landmark").get("chance", 0.0)), rng):
		return null
	return ItemInstance.create(id)


## The figure the flea market lists at a refresh, rolled with `rng` (null: none, mostly).
static func roll_flea(rng: RandomNumberGenerator) -> ItemInstance:
	var rule := source("flea")
	return _roll(float(rule.get("per_refresh", 0.0)), table(str(rule.get("table", ""))), rng)


## One roll of `rng` against `chance` (a chance of 1 always hits).
static func _hit(chance: float, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < chance or chance >= 1.0


static func _roll(chance: float, from: LootTable, rng: RandomNumberGenerator) -> ItemInstance:
	if not _hit(chance, rng) or from == null:
		return null
	var data := from.roll_item(rng)
	return ItemInstance.create(data.id) if data else null


# --- Checks -------------------------------------------------------------------------------------

## What's wrong with the figures and figures.json (empty if nothing): every figure is 1×1, doesn't
## stack, weighs 0.1-0.3 kg, is worth what its rarity's band says, carries the figure tag and its set's,
## belongs to a set that exists and has a model FigureModel can build; every set has an id and a name
## of its own, at least three figures and a known bonus with a value in range; every boss has a figure
## of the Bosses set and every original point of interest one of the Landmarks set, each figure of
## those sets used exactly once; every trader has a figure of the Traders set a barter of theirs gives;
## the sources are known, with chances from 0 to 1 and loot tables that exist and hold only figures; and
## the shelf's station exists, with display slots that grow every level and hold every figure at the top.
static func problems() -> Array[String]:
	var found: Array[String] = []
	if config().is_empty():
		return ["%s: no figure rules" % path]
	var ids := {}
	for entry: Variant in config().get("sets", []):
		if not entry is Dictionary:
			found.append("a set isn't an object")
			continue
		var id := str(entry.get("id", ""))
		var where := "set %s" % id
		for key: String in entry:
			if not key in SET_KEYS:
				found.append("%s: unknown key \"%s\"" % [where, key])
		if id == "" or ids.has(id) or str(entry.get("name", "")).strip_edges() == "":
			found.append("%s: a set needs an id and a name of its own" % where)
		ids[id] = true
		if in_set(id).size() < MIN_SET_SIZE:
			found.append("%s: has %d figures (at least %d)" % [where, in_set(id).size(), MIN_SET_SIZE])
		var bonus: Variant = entry.get("bonus")
		var rule: Dictionary = BONUS_TYPES.get(str(bonus.get("type", "")), {}) if bonus is Dictionary else {}
		if rule.is_empty():
			found.append("%s: its bonus needs a type of %s" % [where, ", ".join(BONUS_TYPES.keys())])
		elif not _number(bonus.get("value")) or float(bonus.value) < float(rule.min) or float(bonus.value) > float(rule.max) \
				or (not rule.share and float(bonus.value) != floorf(float(bonus.value))):
			found.append("%s: a %s bonus is %s to %s%s" % [where, bonus.type, rule.min, rule.max, "" if rule.share else ", a whole number"])
	if ids.is_empty():
		found.append("%s: no sets" % path)
	for data in figures():
		found.append_array(_figure_problems(data, ids))
	found.append_array(_owner_problems())
	found.append_array(_source_problems())
	found.append_array(_shelf_problems())
	return found


static func _figure_problems(data: ItemData, set_ids_known: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var where := "figure %s" % data.id
	if data.size != Vector2i.ONE or data.max_stack != 1:
		found.append("%s: a figure is 1×1 and doesn't stack" % where)
	if data.weight_kg < WEIGHT.x - 0.0001 or data.weight_kg > WEIGHT.y + 0.0001:
		found.append("%s: weighs %s kg (%s to %s)" % [where, data.weight_kg, WEIGHT.x, WEIGHT.y])
	var band := ItemGroups.value_band(data.rarity)
	if data.base_value < band.x or (band.y > 0 and data.base_value > band.y):
		found.append("%s: is worth %d, outside its rarity's band %d-%s" % [where, data.base_value, band.x, str(band.y) if band.y > 0 else ""])
	if data.description.strip_edges() == "":
		found.append("%s: no description" % where)
	if not set_ids_known.has(set_of(data)):
		found.append("%s: its set \"%s\" doesn't exist" % [where, set_of(data)])
	if not data.has_tag(TAG) or not data.has_tag(set_of(data)):
		found.append("%s: needs the tags \"%s\" and \"%s\"" % [where, TAG, set_of(data)])
	for problem in FigureModel.problems(data.stats.get("model")):
		found.append("%s: model: %s" % [where, problem])
	return found


## Bosses, original points of interest and traders each have their figure, used once.
static func _owner_problems() -> Array[String]:
	var found: Array[String] = []
	var used := {}
	for map_id: String in BossTable.maps():
		var id := str(BossTable.maps()[map_id].get("figure", ""))
		if not ItemDB.has_item(id) or set_of(ItemDB.get_item(id)) != "bosses" or used.has(id):
			found.append("boss of %s: its figure \"%s\" isn't a Bosses figure of its own" % [map_id, id])
		used[id] = true
	for pair: Array in PoiTable.originals():
		var id := str(pair[1].get("figure", ""))
		if not ItemDB.has_item(id) or set_of(ItemDB.get_item(id)) != "landmarks" or used.has(id):
			found.append("point of interest %s/%s: its figure \"%s\" isn't a Landmarks figure of its own" % [pair[0], pair[1].get("id", ""), id])
		used[id] = true
	for map_id: String in PoiTable.maps():
		for entry: Dictionary in PoiTable.for_map(map_id):
			if entry.has("figure") and not entry.get("original", false):
				found.append("point of interest %s/%s: only an original one has a figure" % [map_id, entry.get("id", "")])
	for owned_set: String in ["bosses", "landmarks"]:
		for data in in_set(owned_set):
			if not used.has(data.id):
				found.append("figure %s: no %s it belongs to" % [data.id, "boss" if owned_set == "bosses" else "original point of interest"])
	var bartered := {}
	for barter in BarterTable.all():
		for reward: Dictionary in BarterTable.rewards(barter):
			var data := ItemDB.get_item(str(reward.get("item", ""))) if ItemDB.has_item(str(reward.get("item", ""))) else null
			if set_of(data) == "traders":
				(bartered.get_or_add(str(barter.get("trader", "")), []) as Array).append(data.id)
	var traded := {}
	for trader_id in TraderTable.ids():
		var theirs: Array = bartered.get(trader_id, [])
		if theirs.size() != 1 or traded.has(theirs[0]):
			found.append("trader %s: needs one Traders figure of its own from a barter (has %s)" % [trader_id, theirs])
		elif not theirs.is_empty():
			traded[theirs[0]] = true
	for data in in_set("traders"):
		if not traded.has(data.id):
			found.append("figure %s: no trader barters it" % data.id)
	return found


static func _source_problems() -> Array[String]:
	var found: Array[String] = []
	var rules: Variant = config().get("sources")
	if not rules is Dictionary:
		return ["%s: no sources" % path]
	for name: String in rules:
		if not name in SOURCES:
			found.append("source %s: isn't one of %s" % [name, ", ".join(SOURCES)])
	for name: String in SOURCES:
		var rule: Variant = rules.get(name)
		if not rule is Dictionary:
			found.append("source %s: missing" % name)
			continue
		var chances := [rule.get("per_refresh") if name == "flea" else rule.get("chance")]
		chances.append_array(rule.get("chances", {}).values() if rule.get("chances", {}) is Dictionary else [null])
		if rule.has("faction_share"):
			chances.append(rule.faction_share)
		for chance: Variant in chances:
			if not _number(chance) or float(chance) < 0.0 or float(chance) > 1.0:
				found.append("source %s: a chance is a number from 0 to 1 (%s)" % [name, chance])
		var tables := [str(rule.get("table", ""))] if not name in ["boss", "landmark"] else []
		for faction: String in rule.get("faction_tables", {}):
			if not Factions.has(StringName(faction)):
				found.append("source %s: faction %s doesn't exist" % [name, faction])
			tables.append(str(rule.faction_tables[faction]))
		for table_path: String in tables:
			var loot := table(table_path)
			if loot == null:
				found.append("source %s: \"%s\" isn't a loot table" % [name, table_path])
				continue
			var holds := 0
			for rarity in LootTable.RARITY_COUNT:
				for data in loot.candidates(rarity):
					holds += 1
					if not is_figure(data):
						found.append("source %s: %s holds %s, which isn't a figure" % [name, table_path, data.id])
			if holds == 0:
				found.append("source %s: %s holds no figure" % [name, table_path])
		for container_id: String in rule.get("chances", {}) if rule.get("chances", {}) is Dictionary else {}:
			if not ResourceLoader.exists("res://data/loot_tables/containers/%s.tres" % container_id):
				found.append("source %s: no container type %s" % [name, container_id])
	return found


static func _shelf_problems() -> Array[String]:
	var found: Array[String] = []
	var station := Hideout.find(station_id())
	if station.is_empty():
		return ["shelf: no hideout station %s" % station_id()]
	if int(config().get("shelf", {}).get("columns", 0)) < 1:
		found.append("shelf: columns must be 1 or more")
	var last := 0
	for entry: Variant in station.get("levels", []):
		var slots := int(entry.get("display_slots", 0)) if entry is Dictionary else 0
		if slots <= last:
			found.append("shelf: level %s has %d display slots (each level needs more than the last, %d)" % [entry.get("level") if entry is Dictionary else "?", slots, last])
		last = slots
	if last < figures().size():
		found.append("shelf: the top level displays %d figures, but there are %d" % [last, figures().size()])
	return found


static func _number(value: Variant) -> bool:
	return value is float or value is int
