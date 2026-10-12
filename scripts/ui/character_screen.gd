extends MenuScreen
## CHARACTER screen (DESIGN.md §16.2): gear, stats, skills and the stash side by side.

const DIM := Color(1, 1, 1, 0.35)


func _ready() -> void:
	%BackButton.pressed.connect(close)
	_fill_gear()
	_fill_stats()
	_fill_skills()
	%StashTitle.text = "STASH  ·  %d × %d" % [%StashGrid.columns, %StashGrid.rows]
	%BackButton.grab_focus.call_deferred()


func _fill_gear() -> void:
	var grid: GridContainer = %GearGrid
	var weight := 0.0
	for slot in GameState.SLOTS:
		var item := _item(GameState.equipment.get(slot[0], ""))
		weight += item.weight_kg if item else 0.0
		_row(grid, slot[1], item.display_name if item else "—", Palette.rarity_color(item.rarity) if item else DIM)
	var ammo := _item(GameState.weapon_ammo)
	_row(grid, "Loaded ammo", ammo.display_name if ammo else "—", Palette.rarity_color(ammo.rarity) if ammo else DIM)
	for i in GameState.POCKET_COUNT:
		var pocket: Dictionary = GameState.pockets[i] if i < GameState.pockets.size() else {}
		var item := _item(pocket.get("id", ""))
		var count := int(pocket.get("count", 1))
		weight += item.weight_kg * count if item else 0.0
		var text := "—" if item == null else (item.display_name + (" ×%d" % count if count > 1 else ""))
		_row(grid, "Pocket %d" % (i + 1), text, Palette.rarity_color(item.rarity) if item else DIM)
	%GearWeight.text = "Carried weight: %s" % Settings.format_weight(weight)


func _fill_stats() -> void:
	var grid: GridContainer = %StatsGrid
	_row(grid, "Faction", GameState.Faction.find_key(GameState.faction), MenuEntryButton.ACCENT)
	_row(grid, "Level", str(GameState.level), Color.WHITE)
	_row(grid, "Experience", UiFormat.thousands(GameState.xp), Color.WHITE)
	var health: HealthConfig = load("res://data/config/health.tres")
	_row(grid, "Health", "%d HP over 7 body parts" % health.max_total(), Color.WHITE)
	_row(grid, "Roubles", UiFormat.money(GameState.roubles), Color.WHITE)
	_row(grid, "Dollars", UiFormat.money(GameState.dollars, "USD"), Color.WHITE)
	_row(grid, "Items in stash", str(GameState.stash.size()), Color.WHITE)


func _fill_skills() -> void:
	var grid: GridContainer = %SkillsGrid
	for skill in GameState.SKILLS:
		var data: Dictionary = GameState.skills[skill[0]]
		var name := Label.new()
		name.text = skill[1]
		name.custom_minimum_size.x = 170
		var level := Label.new()
		level.theme_type_variation = &"DimLabel"
		level.text = "Lv %d" % data.level
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.value = data.progress * 100.0
		for control: Control in [name, level, bar]:
			grid.add_child(control)


func _row(grid: GridContainer, name: String, value: String, color: Color) -> void:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = name
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_color_override("font_color", color if color == DIM else color.lerp(Color.WHITE, 0.25))
	grid.add_child(label)
	grid.add_child(value_label)


func _item(item_id: String) -> ItemData:
	return ItemDB.get_item(item_id) if item_id != "" else null
