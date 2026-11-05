extends MenuScreen
## CHARACTER screen (DESIGN.md §16.2): stats (level with the XP toward the next one, health, energy and
## water, money, Drip, Trick Shots, items in the stash) and skills side by side. Your gear and the stash
## are on the LOADOUT screen (LoadoutScreen, §16.6): LOADOUT (or Tab) opens it over this one (hiding
## this one's content meanwhile, so the focus stays on LOADOUT), and closing it saves and brings the
## stats up to date. "Items in stash" follows the stash (a sort, a
## delivery).

const DIM := Color(1, 1, 1, 0.35)
const LOADOUT_SCENE := preload("res://ui/loadout_screen.tscn")

var _loadout_screen: LoadoutScreen
## The "Items in stash" value in the stats.
var _stash_count: Label


func _ready() -> void:
	%BackButton.pressed.connect(close)
	%LoadoutButton.pressed.connect(open_loadout)
	_refresh()
	GameState.stash.changed.connect(_on_stash_changed)  # A sort, an insurance return.
	%LoadoutButton.grab_focus.call_deferred()


func _exit_tree() -> void:
	if GameState.stash.changed.is_connected(_on_stash_changed):
		GameState.stash.changed.disconnect(_on_stash_changed)


## The stash changed: the stats' item count follows (SORT merges stacks).
func _on_stash_changed() -> void:
	if is_instance_valid(_stash_count):
		_stash_count.text = str(GameState.stash.items.size())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and _loadout_screen == null:
		open_loadout()
		get_viewport().set_input_as_handled()
		return
	super(event)


## Opens the LOADOUT screen over this one. This screen's content hides meanwhile, so the keyboard and
## controller focus can't reach its buttons under LOADOUT.
func open_loadout() -> void:
	if _loadout_screen:
		return
	get_viewport().gui_release_focus()
	$Margin.hide()
	_loadout_screen = LOADOUT_SCENE.instantiate()
	_loadout_screen.closed.connect(_on_loadout_closed)
	add_child(_loadout_screen)


## LOADOUT saved as it closed: the stats follow what you wear now.
func _on_loadout_closed() -> void:
	_loadout_screen = null
	$Margin.show()
	_refresh()
	%LoadoutButton.grab_focus()


func _refresh() -> void:
	for grid: GridContainer in [%StatsGrid, %SkillsGrid]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_fill_stats()
	_fill_skills()


func _fill_stats() -> void:
	var grid: GridContainer = %StatsGrid
	_row(grid, "Faction", GameState.Faction.find_key(GameState.faction), MenuEntryButton.ACCENT)
	_row(grid, "Level", "%d of %d" % [GameState.level, Progression.max_level()], Color.WHITE)
	var bar := ProgressBar.new()  # Toward the next level, beside the level.
	bar.name = "XpBar"
	bar.custom_minimum_size = Vector2(220, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.value = Progression.level_progress(GameState.xp, GameState.level) * 100.0
	var level_line := HBoxContainer.new()
	level_line.add_theme_constant_override("separation", 18)
	grid.get_child(grid.get_child_count() - 1).reparent(level_line)
	level_line.add_child(bar)
	grid.add_child(level_line)
	_row(grid, "Experience", Progression.xp_text(GameState.xp, GameState.level) + ("  (to level %d)" % (GameState.level + 1)
		if GameState.level < Progression.max_level() else ""), Color.WHITE)
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
	_stash_count = _row(grid, "Items in stash", str(GameState.stash.items.size()), Color.WHITE)
	_stash_count.name = "StashCount"


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


## Adds a name and its value to `grid`; returns the value's label.
func _row(grid: GridContainer, name: String, value: String, color: Color) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = name
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_color_override("font_color", color if color == DIM else color.lerp(Color.WHITE, 0.25))
	grid.add_child(label)
	grid.add_child(value_label)
	return value_label
