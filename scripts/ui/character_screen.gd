extends MenuScreen
## CHARACTER screen (DESIGN.md §16.2): stats (level with the XP toward the next one and what it takes,
## health, energy and water, money, Drip, Trick Shots, items in the stash) beside two tabs: SKILLS (every
## skill with its level, progress bar, points, current bonus and what trains it: Skills) and LIFETIME STATS
## (Stats.rows(): raids, survival rate, kills, shots, damage, loot, money, quests). Your gear and the stash
## are on the LOADOUT screen (LoadoutScreen, §16.6): LOADOUT (or Tab) opens it over this one (hiding
## this one's content meanwhile, so the focus stays on LOADOUT), and closing it saves and brings the
## stats up to date. "Items in stash" follows the stash (a sort, a
## delivery). The Scav karma row's cooldown counts down every second.

const DIM := Color(1, 1, 1, 0.35)
## Scav karma low enough that AI Scavs shoot you on sight.
const KARMA_LOW := Color(0.95, 0.45, 0.35)
const LOADOUT_SCENE := preload("res://ui/loadout_screen.tscn")
## The right-hand tabs.
enum { SKILLS, STATS }

var _loadout_screen: LoadoutScreen
## The "Items in stash" value in the stats.
var _stash_count: Label


func _ready() -> void:
	%BackButton.pressed.connect(close)
	%LoadoutButton.pressed.connect(open_loadout)
	%CollectionButton.pressed.connect(open_collection)
	var tabs := ButtonGroup.new()
	for tab: Button in [%SkillsTab, %StatsTab]:
		tab.button_group = tabs
	%SkillsTab.pressed.connect(show_tab.bind(SKILLS))
	%StatsTab.pressed.connect(show_tab.bind(STATS))
	_refresh()
	GameState.stash.changed.connect(_on_stash_changed)  # A sort, an insurance return.
	var timer := Timer.new()
	timer.name = "KarmaTimer"
	timer.wait_time = 1.0
	timer.timeout.connect(_update_karma)
	add_child(timer)
	timer.start()  # The Scav cooldown in the karma row counts down.
	%LoadoutButton.grab_focus.call_deferred()


func _exit_tree() -> void:
	if GameState.stash.changed.is_connected(_on_stash_changed):
		GameState.stash.changed.disconnect(_on_stash_changed)


## The stash changed: the stats' item count follows (SORT merges stacks).
func _on_stash_changed() -> void:
	if is_instance_valid(_stash_count):
		_stash_count.text = str(GameState.stash.items.size())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and _loadout_screen == null and not has_node("CollectionScreen"):
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


## Opens the figure collection (CollectionScreen's COLLECTION tab) over this screen, which hides meanwhile.
func open_collection() -> CollectionScreen:
	get_viewport().gui_release_focus()
	$Margin.hide()
	var screen := CollectionScreen.create(CollectionScreen.COLLECTION)
	screen.closed.connect(func() -> void:
		$Margin.show()
		%CollectionButton.grab_focus.call_deferred())
	add_child(screen)
	return screen


## LOADOUT saved as it closed: the stats follow what you wear now.
func _on_loadout_closed() -> void:
	_loadout_screen = null
	$Margin.show()
	_refresh()
	%LoadoutButton.grab_focus()


func _refresh() -> void:
	for box: Container in [%StatsGrid, %SkillsList, %LifetimeGrid]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_fill_stats()
	_fill_skills()
	_fill_lifetime()


## Shows the SKILLS or the LIFETIME STATS tab.
func show_tab(which: int) -> void:
	(%SkillsTab as Button).set_pressed_no_signal(which == SKILLS)
	(%StatsTab as Button).set_pressed_no_signal(which == STATS)
	%SkillsScroll.visible = which == SKILLS
	%SkillsHint.visible = which == SKILLS
	%LifetimeScroll.visible = which == STATS


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
	_row(grid, "Experience", Progression.xp_text(GameState.xp, GameState.level) + ("  ·  %s more for level %d" % [
		UiFormat.thousands(Progression.xp_for_level(GameState.level + 1) - GameState.xp), GameState.level + 1]
		if GameState.level < Progression.max_level() else "  ·  the top level"), Color.WHITE).name = "XpText"
	var health: HealthConfig = load("res://data/config/health.tres")
	_row(grid, "Health", "%d HP over 7 body parts" % health.max_total(), Color.WHITE)
	Consumables.recover_profile()
	var tuning := Consumables.CONFIG
	var low := GameState.energy <= tuning.low_threshold or GameState.hydration <= tuning.low_threshold
	_row(grid, "Energy / water", "%d / %d  ·  %d / %d  (+%d an hour in the hideout)" % [ceili(GameState.energy), roundi(tuning.max_energy),
		ceili(GameState.hydration), roundi(tuning.max_hydration), roundi(Consumables.hideout_recovery_rate() * 60.0)],
		Color(0.95, 0.7, 0.3) if low else Color.WHITE)
	_row(grid, "Roubles", UiFormat.money(GameState.roubles), Color.WHITE)
	_row(grid, "Dollars", UiFormat.money(GameState.dollars, "USD"), Color.WHITE)
	_row(grid, "Drip", UiFormat.thousands(GameState.drip), Player.TRICK_COLOR)
	_row(grid, "Scav karma", karma_text(), KARMA_LOW if ScavRuns.hostile(ScavRuns.karma()) else Color.WHITE).name = "ScavKarma"
	var tricks: Dictionary = GameState.trick_shots
	_row(grid, "Trick Shots", "%s kill%s  ·  %s hit%s (360)" % [UiFormat.thousands(tricks.kills), "" if tricks.kills == 1 else "s",
		UiFormat.thousands(tricks.hits), "" if tricks.hits == 1 else "s"], Player.TRICK_COLOR if tricks.kills > 0 else Color.WHITE)
	_stash_count = _row(grid, "Items in stash", str(GameState.stash.items.size()), Color.WHITE)
	_stash_count.name = "StashCount"


## SKILLS: a row per skill: its name, "Lv 12", a bar toward the next level and the points, then its
## bonus now (dim at level 0) and what trains it.
func _fill_skills() -> void:
	for skill in Skills.all():
		var id := str(skill.id)
		var row := VBoxContainer.new()
		row.name = "Skill_" + id
		row.add_theme_constant_override("separation", 2)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 14)
		var name := Label.new()
		name.text = str(skill.name)
		name.custom_minimum_size.x = 190
		var level := Label.new()
		level.name = "Level"
		level.text = "Lv %d" % Skills.level(id)
		level.custom_minimum_size.x = 60
		level.add_theme_color_override("font_color", MenuEntryButton.ACCENT if Skills.level(id) > 0 else DIM)
		var bar := ProgressBar.new()
		bar.name = "Progress"
		bar.custom_minimum_size = Vector2(180, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.value = Skills.progress(id) * 100.0
		var points := Label.new()
		points.theme_type_variation = &"DimLabel"
		points.text = "top level" if Skills.level(id) >= Skills.MAX_LEVEL else "%d / %d" % [floori(Skills.points(id)), roundi(Skills.points_to_next(Skills.level(id)))]
		for control: Control in [name, level, bar, points]:
			top.add_child(control)
		row.add_child(top)
		var bonus := Label.new()
		bonus.name = "Bonus"
		bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bonus.text = Skills.bonuses_text(id) if Skills.level(id) > 0 else "At level 50: " + Skills.bonuses_text(id, Skills.MAX_LEVEL)
		bonus.add_theme_font_size_override("font_size", 15)
		bonus.add_theme_color_override("font_color", Color(1, 1, 1, 0.78) if Skills.level(id) > 0 else DIM)
		row.add_child(bonus)
		var info := Label.new()
		info.name = "Info"
		info.theme_type_variation = &"DimLabel"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = "Trained by " + Skills.trains(id).to_lower()
		info.add_theme_font_size_override("font_size", 14)
		row.add_child(info)
		%SkillsList.add_child(row)


## LIFETIME STATS: Stats.rows(), a dim heading over each group.
func _fill_lifetime() -> void:
	var grid: GridContainer = %LifetimeGrid
	var heading := ""
	for row: Array in Stats.rows():
		if row[0] != heading:
			heading = row[0]
			for text: String in [heading, ""]:
				var label := Label.new()
				label.text = text
				label.theme_type_variation = &"AccentLabel"
				grid.add_child(label)
		_row(grid, row[1], row[2], Color.WHITE).name = ("Stat_" + str(row[1])).validate_node_name()


## The Scav karma row again (every second: the Scav cooldown counts down while the screen is open).
func _update_karma() -> void:
	var row := find_child("ScavKarma", true, false) as Label
	if row == null:
		return
	var text := karma_text()
	if row.text != text:
		row.text = text
	row.add_theme_color_override("font_color", (KARMA_LOW if ScavRuns.hostile(ScavRuns.karma()) else Color.WHITE).lerp(Color.WHITE, 0.25))


## The Scav karma row (DESIGN.md §2, ScavRuns): "+1.6 (Mole LL2)  ·  Standard kit  ·  Scav ready in 12:30".
static func karma_text() -> String:
	var karma := ScavRuns.karma()
	var trader := ScavRuns.karma_trader()
	return "%s (%s LL%d)  ·  %s kit  ·  %s" % [ScavRuns.number_text(karma, true), TraderTable.display_name(trader),
		int(GameState.trader_loyalty.get(trader, {}).get("level", 1)), ScavRuns.tier_name(ScavRuns.kit_tier(karma)), ScavRuns.ready_text()]


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
