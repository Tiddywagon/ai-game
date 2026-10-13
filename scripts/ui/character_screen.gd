extends MenuScreen
## CHARACTER screen (DESIGN.md §16.2): gear, stats, skills and the stash side by side. INVENTORY (or Tab)
## opens the grid inventory with the stash beside it, to move gear between them; closing it saves.

const DIM := Color(1, 1, 1, 0.35)
const INVENTORY_SCENE := preload("res://ui/inventory_screen.tscn")

var _inventory_screen: InventoryScreen


func _ready() -> void:
	%BackButton.pressed.connect(close)
	%InventoryButton.pressed.connect(open_inventory)
	%FirFilter.toggled.connect(func(on: bool) -> void: %StashGrid.fir_only = on)
	_refresh()
	%StashTitle.text = "STASH  ·  %d × %d" % [GameState.stash.size.x, GameState.stash.size.y]
	%InventoryButton.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and _inventory_screen == null:
		open_inventory()
		get_viewport().set_input_as_handled()
		return
	super(event)


## Opens the grid inventory over this screen, with the stash.
func open_inventory() -> void:
	if _inventory_screen:
		return
	_inventory_screen = INVENTORY_SCENE.instantiate()
	_inventory_screen.inventory = GameState.inventory
	_inventory_screen.stash = GameState.stash
	_inventory_screen.closed.connect(_on_inventory_closed)
	add_child(_inventory_screen)


func _on_inventory_closed() -> void:
	_inventory_screen = null
	SaveManager.save_game()
	_refresh()
	%InventoryButton.grab_focus()


func _refresh() -> void:
	for grid: GridContainer in [%GearGrid, %StatsGrid, %SkillsGrid]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_fill_gear()
	_fill_stats()
	_fill_skills()
	%StashGrid.queue_redraw()


func _fill_gear() -> void:
	var grid: GridContainer = %GearGrid
	var inventory := GameState.inventory
	for slot in Inventory.SLOTS:
		var item: ItemInstance = inventory.equipment[slot[0]]
		var text := "—"
		if item:
			text = item.data.display_name
			if item.contents and not item.contents.items.is_empty():
				text += "  (%d inside)" % item.contents.items.size()
			elif item.loaded_ammo != "" and ItemDB.get_item(item.loaded_ammo):
				text += "  ·  " + ItemDB.get_item(item.loaded_ammo).display_name
		_row(grid, slot[1], text, Palette.rarity_color(item.data.rarity) if item else DIM)
	var pockets: Array = inventory.pockets.items.map(func(item: ItemInstance) -> String:
		return item.data.display_name + (" ×%d" % item.count if item.count > 1 else ""))
	_row(grid, "Pockets", ", ".join(pockets) if not pockets.is_empty() else "—", Color.WHITE if not pockets.is_empty() else DIM)
	%GearWeight.text = "Carried weight: %s  ·  value %s" % [Settings.format_weight(inventory.total_weight()), UiFormat.money(inventory.total_value())]


func _fill_stats() -> void:
	var grid: GridContainer = %StatsGrid
	_row(grid, "Faction", GameState.Faction.find_key(GameState.faction), MenuEntryButton.ACCENT)
	_row(grid, "Level", str(GameState.level), Color.WHITE)
	_row(grid, "Experience", UiFormat.thousands(GameState.xp), Color.WHITE)
	var health: HealthConfig = load("res://data/config/health.tres")
	_row(grid, "Health", "%d HP over 7 body parts" % health.max_total(), Color.WHITE)
	Consumables.recover_profile()
	var tuning := Consumables.CONFIG
	var low := GameState.energy <= tuning.low_threshold or GameState.hydration <= tuning.low_threshold
	_row(grid, "Energy / water", "%d / %d  ·  %d / %d  (+%d an hour in the hideout)" % [ceili(GameState.energy), roundi(tuning.max_energy),
		ceili(GameState.hydration), roundi(tuning.max_hydration), roundi(Consumables.hideout_recovery_rate() * 60.0)],
		Color(0.95, 0.7, 0.3) if low else Color.WHITE)
	_row(grid, "Metabolism", "level %d: energy and water drain %d%% slower" % [Skills.level(Consumables.METABOLISM),
		roundi((1.0 - Consumables.skill_multiplier()) * 100.0)], Color.WHITE)
	_row(grid, "Roubles", UiFormat.money(GameState.roubles), Color.WHITE)
	_row(grid, "Dollars", UiFormat.money(GameState.dollars, "USD"), Color.WHITE)
	_row(grid, "Drip", UiFormat.thousands(GameState.drip), Player.TRICK_COLOR)
	var tricks: Dictionary = GameState.trick_shots
	_row(grid, "Trick Shots", "%s kill%s  ·  %s hit%s (360)" % [UiFormat.thousands(tricks.kills), "" if tricks.kills == 1 else "s",
		UiFormat.thousands(tricks.hits), "" if tricks.hits == 1 else "s"], Player.TRICK_COLOR if tricks.kills > 0 else Color.WHITE)
	_row(grid, "Items in stash", str(GameState.stash.items.size()), Color.WHITE)


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
