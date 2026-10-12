extends Control
## Loot rate check (DESIGN.md §6.2). Rolls ROLLS times for the base table, every container type, Labs,
## and a safe on Labs, then prints expected vs rolled rarity rates to the Output panel and shows them
## here, with a few sample items. Open scenes/debug/loot_roll_test.tscn and press F6, or run:
##   godot --path . res://scenes/debug/loot_roll_test.tscn -- --quit [--seed=123]
## A rate is marked "ok" when it's within 3 standard deviations of the expected one (normal noise).

const ROLLS := 10000
const SAMPLE_ITEMS := 12
const CONTAINERS_DIR := "res://data/loot_tables/containers"

var table: LootTable = preload("res://data/loot_tables/default.tres")

@onready var _results: VBoxContainer = %Results
@onready var _seed_label: Label = %SeedLabel


func _ready() -> void:
	%RollButton.pressed.connect(func() -> void: run(randi()))
	var seed_value := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
	run(seed_value)
	if "--quit" in OS.get_cmdline_user_args():
		get_tree().quit()


## Runs every scenario with `seed_value` and shows the results.
func run(seed_value: int) -> void:
	for child in _results.get_children():
		child.queue_free()
	_seed_label.text = "Seed %d  ·  %s rolls per row" % [seed_value, UiFormat.thousands(ROLLS)]
	print("\nLoot roll test: %d rolls per scenario, seed %d" % [ROLLS, seed_value])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var test_yard := MapInfo.find("test_yard")
	var labs := MapInfo.find("labs")
	_scenario(rng, "Base table (no container, no map modifier)", null, null)
	for container in _containers():
		_scenario(rng, "%s on Test Yard" % container.display_name, container, test_yard)
	_scenario(rng, "Loose loot on Labs (Epic and Legendary x2)", _container("loose_loot"), labs)
	_scenario(rng, "Safe on Labs", _container("safe"), labs)


func _scenario(rng: RandomNumberGenerator, title: String, container: LootContainer, map: MapInfo) -> void:
	var categories: Array = container.categories if container else []
	var expected := table.chances(container, map, categories)
	var counts := PackedInt32Array()
	counts.resize(LootTable.RARITY_COUNT)
	for i in ROLLS:
		var rarity := table.roll_rarity(rng, container, map, categories)
		if rarity >= 0:
			counts[rarity] += 1
	var samples: Array[ItemData] = []
	for i in SAMPLE_ITEMS:
		var item := table.roll_item(rng, container, map)
		if item:
			samples.append(item)
	_print_scenario(title, expected, counts, container)
	_show_scenario(title, expected, counts, samples)


func _print_scenario(title: String, expected: PackedFloat32Array, counts: PackedInt32Array, container: LootContainer) -> void:
	print("\n%s" % title)
	if container and not container.categories.is_empty():
		print("  holds: %s" % ", ".join(container.categories.map(func(c: int) -> String: return ItemData.CATEGORY_NAMES[c])))
	print("  %s %s %s %s %s" % ["Rarity".rpad(12), "Expected".lpad(9), "Rolled".lpad(8), "Rolled %".lpad(9), ""])
	for rarity in LootTable.RARITY_COUNT:
		var rolled := counts[rarity] * 100.0 / ROLLS
		print("  %s %s %s %s  %s" % [Palette.RARITY_NAMES[rarity].rpad(12), ("%.2f%%" % (expected[rarity] * 100.0)).lpad(9),
			str(counts[rarity]).lpad(8), ("%.2f%%" % rolled).lpad(9), _verdict(expected[rarity], counts[rarity])])


func _show_scenario(title: String, expected: PackedFloat32Array, counts: PackedInt32Array, samples: Array[ItemData]) -> void:
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"AccentLabel"
	_results.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 28)
	for text in ["Rarity", "Expected", "Rolled", "Rolled %", ""]:
		var label := Label.new()
		label.text = text
		label.theme_type_variation = &"DimLabel"
		grid.add_child(label)
	for rarity in LootTable.RARITY_COUNT:
		var name_label := Label.new()
		name_label.text = Palette.RARITY_NAMES[rarity]
		name_label.add_theme_color_override("font_color", Palette.rarity_color(rarity))
		grid.add_child(name_label)
		for text in ["%.2f%%" % (expected[rarity] * 100.0), str(counts[rarity]), "%.2f%%" % (counts[rarity] * 100.0 / ROLLS), _verdict(expected[rarity], counts[rarity])]:
			var label := Label.new()
			label.text = text
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(label)
	_results.add_child(grid)
	var icons := HFlowContainer.new()
	icons.add_theme_constant_override("h_separation", 6)
	for item in samples:
		var icon := TextureRect.new()
		icon.texture = item.get_icon()
		icon.custom_minimum_size = Vector2(item.size) * 36.0
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon.tooltip_text = "%s (%s, %s)" % [item.display_name, Palette.RARITY_NAMES[item.rarity], item.category_name()]
		icons.add_child(icon)
	_results.add_child(icons)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	_results.add_child(gap)


## "ok" if `count` of ROLLS is within 3 standard deviations of `chance`, else "CHECK".
static func _verdict(chance: float, count: int) -> String:
	var spread := 3.0 * sqrt(maxf(chance * (1.0 - chance), 0.0) / ROLLS)
	return "ok" if absf(count / float(ROLLS) - chance) <= spread + 0.0001 else "CHECK"


func _containers() -> Array[LootContainer]:
	var result: Array[LootContainer] = []
	for file_name in DirAccess.get_files_at(CONTAINERS_DIR):
		file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			result.append(load(CONTAINERS_DIR.path_join(file_name)))
	return result


func _container(container_id: String) -> LootContainer:
	return load(CONTAINERS_DIR.path_join(container_id + ".tres"))
