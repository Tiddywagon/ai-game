extends MenuScreen
## ENTER RAID flow (DESIGN.md §16.3): map select, then PMC or Scav, then a loadout check, then the
## loading screen. Back (or Esc / B) steps back; from the map list it returns to the main menu.

enum Step { MAP, SIDE, LOADOUT }

const LOADING_SCENE := "res://ui/loading_screen.tscn"
const WARNING_COLOR := Color(0.95, 0.6, 0.3)

var _step := Step.MAP
var _maps: Array[MapInfo] = []
var _map: MapInfo
var _side := "pmc"
var _loadout := {}
var _map_buttons: Array[Button] = []

@onready var _steps: Array[Control] = [%MapStep, %SideStep, %LoadoutStep]
@onready var _step_labels: Array[Label] = [%MapStepLabel, %SideStepLabel, %LoadoutStepLabel]
@onready var _next: Button = %NextButton


func _ready() -> void:
	_maps = MapInfo.load_all()
	var group := ButtonGroup.new()
	for map in _maps:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 52
		button.text = map.display_name if map.is_playable() else "%s   ·   in development" % map.display_name
		button.pressed.connect(_select_map.bind(map))
		button.focus_entered.connect(_select_map.bind(map))
		%MapList.add_child(button)
		_map_buttons.append(button)
	var side_group := ButtonGroup.new()
	for button: Button in [%PmcButton, %ScavButton]:
		button.toggle_mode = true
		button.button_group = side_group
	%PmcButton.pressed.connect(_choose_side.bind("pmc"))
	%ScavButton.pressed.connect(_choose_side.bind("scav"))
	%PmcButton.focus_entered.connect(_choose_side.bind("pmc", false))
	%ScavButton.focus_entered.connect(_choose_side.bind("scav", false))
	%BackButton.pressed.connect(_on_cancel)
	_next.pressed.connect(_on_next)
	var first_playable := _maps.find_custom(func(map: MapInfo) -> bool: return map.is_playable())
	_select_map(_maps[maxi(first_playable, 0)])
	_show_step(Step.MAP)


func _on_cancel() -> void:
	if _step == Step.MAP:
		close()
	else:
		_show_step((_step - 1) as Step)


func _on_next() -> void:
	match _step:
		Step.MAP:
			if _map.is_playable():
				_show_step(Step.SIDE)
		Step.SIDE:
			_show_step(Step.LOADOUT)
		Step.LOADOUT:
			_start_raid()


func _show_step(step: Step) -> void:
	_step = step
	for i in _steps.size():
		_steps[i].visible = i == step
		_step_labels[i].theme_type_variation = &"AccentLabel" if i == step else &"DimLabel"
	_next.text = "READY" if step == Step.LOADOUT else "NEXT"
	_next.disabled = step == Step.MAP and not _map.is_playable()
	match step:
		Step.MAP:
			_map_buttons[_maps.find(_map)].grab_focus.call_deferred()
		Step.SIDE:
			(%PmcButton if _side == "pmc" else %ScavButton).grab_focus.call_deferred()
		Step.LOADOUT:
			_loadout = GameState.pmc_loadout() if _side == "pmc" else GameState.scav_loadout()
			_show_loadout()
			_next.grab_focus.call_deferred()


func _select_map(map: MapInfo) -> void:
	_map = map
	_map_buttons[_maps.find(map)].set_pressed_no_signal(true)
	%MapName.text = map.display_name.to_upper()
	%MapDescription.text = map.description
	%MapStats.text = "Size: %s\nRaid time: %d min\nPlayers: %s\nExtracts: %s\nBoss: %s" % [
		map.size, map.raid_minutes, map.players, map.extracts, map.boss]
	%MapStatus.text = "" if map.is_playable() else "In development: not playable yet."
	if _step == Step.MAP:
		_next.disabled = not map.is_playable()


func _choose_side(side: String, advance := true) -> void:
	_side = side
	(%PmcButton if side == "pmc" else %ScavButton).set_pressed_no_signal(true)
	if advance and _step == Step.SIDE:
		_show_step(Step.LOADOUT)


func _show_loadout() -> void:
	var gear: GridContainer = %GearGrid
	for child in gear.get_children():
		child.queue_free()
	var equipment: Dictionary = _loadout.equipment
	var weight := 0.0
	for slot in GameState.SLOTS:
		var item_id: String = equipment.get(slot[0], "")
		var item: ItemData = ItemDB.get_item(item_id) if item_id != "" else null
		weight += item.weight_kg if item else 0.0
		_add_row(gear, slot[1], item.display_name if item else "—", Palette.rarity_color(item.rarity) if item else Color(1, 1, 1, 0.35))
	var ammo: ItemData = ItemDB.get_item(_loadout.weapon_ammo) if _loadout.weapon_ammo != "" else null
	_add_row(gear, "Loaded ammo", ammo.display_name if ammo else "—", Palette.rarity_color(ammo.rarity) if ammo else Color(1, 1, 1, 0.35))
	var has_meds := false
	for i in GameState.POCKET_COUNT:
		var pocket: Dictionary = _loadout.pockets[i] if i < _loadout.pockets.size() else {}
		var item: ItemData = ItemDB.get_item(pocket.id) if pocket.has("id") else null
		if item:
			weight += item.weight_kg * pocket.count
			has_meds = has_meds or item.category == ItemData.Category.MEDS
		var text := "—" if item == null else ("%s ×%d" % [item.display_name, pocket.count] if pocket.count > 1 else item.display_name)
		_add_row(gear, "Pocket %d" % (i + 1), text, Palette.rarity_color(item.rarity) if item else Color(1, 1, 1, 0.35))
	%WeightLabel.text = "Carried weight: %s" % Settings.format_weight(weight)

	var checks: Array[String] = []
	if _side == "scav":
		checks.append("Scav run: random gear. Nothing from your stash is at risk.")
		checks.append("AI Scavs leave you alone unless you shoot them.")
	else:
		if equipment.get("armor", "") == "":
			checks.append("No body armor: every hit goes straight to your health.")
		if equipment.get("helmet", "") == "":
			checks.append("No helmet.")
		if not has_meds:
			checks.append("No meds in your pockets.")
		if equipment.get("backpack", "") == "":
			checks.append("No backpack: loot only fits in your pockets.")
		checks.append("If you die, everything you bring is lost.")
	%Checks.text = "\n".join(checks.map(func(line: String) -> String: return "•  " + line))
	%Checks.add_theme_color_override("font_color", WARNING_COLOR if _side == "pmc" else MenuEntryButton.TEXT)
	%RaidSummary.text = "%s  ·  %d min  ·  %s" % [_map.display_name, _map.raid_minutes, "PMC" if _side == "pmc" else "Scav"]


func _add_row(grid: GridContainer, name: String, value: String, color: Color) -> void:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = name
	var item_label := Label.new()
	item_label.text = value
	item_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
	grid.add_child(label)
	grid.add_child(item_label)


func _start_raid() -> void:
	GameState.raid = {"map": _map.id, "side": _side, "loadout": _loadout}
	get_tree().change_scene_to_file(LOADING_SCENE)
