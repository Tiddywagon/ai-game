extends MenuScreen
## ENTER RAID flow (DESIGN.md §16.3): map select, then PMC or Scav, then a loadout check (with
## INSURE GEAR for a PMC: Insurance), then the loading screen. Back (or Esc / B) steps back; from the
## map list it returns to the main menu.

enum Step { MAP, SIDE, LOADOUT }

const LOADING_SCENE := "res://ui/loading_screen.tscn"
const WARNING_COLOR := Color(0.95, 0.6, 0.3)

var _step := Step.MAP
var _maps: Array[MapInfo] = []
var _map: MapInfo
var _side := "pmc"
var _loadout: Inventory
var _map_buttons: Array[Button] = []
var _insure: Button
var _insure_note: Label

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
	_insure = Button.new()
	_insure.name = "InsureButton"
	_insure.custom_minimum_size = Vector2(0, 44)
	_insure.pressed.connect(_insure_gear)
	%GearGrid.get_parent().add_child(_insure)
	_insure_note = Label.new()
	_insure_note.theme_type_variation = &"DimLabel"
	_insure_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insure_note.custom_minimum_size.x = 560
	%GearGrid.get_parent().add_child(_insure_note)
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
	for slot in Inventory.SLOTS:
		var item: ItemInstance = _loadout.equipment[slot[0]]
		var text := "—"
		if item:
			text = item.data.display_name
			if item.insured:
				text += "  · insured"
			if item.contents:
				text += "  (%s)" % _contents_text(item.contents)
		_add_row(gear, slot[1], text, Palette.rarity_color(item.data.rarity) if item else Color(1, 1, 1, 0.35))
	var weapon_slot := _loadout.weapon_slot()
	var gun: ItemInstance = _loadout.equipment[weapon_slot] if weapon_slot != "" else null
	var ammo: ItemData = ItemDB.get_item(gun.loaded_ammo) if gun and gun.loaded_ammo != "" else null
	_add_row(gear, "Loaded ammo", ammo.display_name if ammo else "—", Palette.rarity_color(ammo.rarity) if ammo else Color(1, 1, 1, 0.35))
	_add_row(gear, "Pockets", _contents_text(_loadout.pockets), Color(1, 1, 1, 0.9))
	var weight := _loadout.total_weight()
	var config: InventoryConfig = load("res://data/config/inventory.tres")
	%WeightLabel.text = "Carried weight: %s" % Settings.format_weight(weight)

	var checks: Array[String] = []
	if _side == "scav":
		checks.append("Scav run: random gear. Nothing from your stash is at risk.")
		checks.append("AI Scavs leave you alone unless you shoot them.")
	else:
		if _loadout.equipment.armor == null:
			checks.append("No body armor: every hit goes straight to your health.")
		if _loadout.equipment.helmet == null:
			checks.append("No helmet.")
		if not _loadout.has_category(ItemData.Category.MEDS):
			checks.append("No meds.")
		if _loadout.equipment.backpack == null:
			checks.append("No backpack: loot only fits in your pockets and rig.")
		if weight >= config.overweight_kg:
			checks.append("Overweight: you can't sprint or roll.")
		elif weight > config.encumbered_kg:
			checks.append("Heavy load: you'll move slower and tire faster.")
		if gun and gun.is_gun():
			var missing := WeaponMods.missing_part(gun)
			if missing != "":
				checks.append("Your %s can't fire: no %s. Fit one in the modding screen." % [gun.data.display_name, missing.to_lower()])
			elif gun.durability < gun.data.weapon.malfunction_threshold:
				checks.append("Your %s is worn (%d / %d): it may jam. Repair it in the modding screen." % [gun.data.display_name,
					roundi(gun.durability), roundi(gun.max_durability)])
		checks.append("If you die, everything you bring is lost, except your secure container and insured gear.")
	%Checks.text = "\n".join(checks.map(func(line: String) -> String: return "•  " + line))
	%Checks.add_theme_color_override("font_color", WARNING_COLOR if _side == "pmc" else MenuEntryButton.TEXT)
	%RaidSummary.text = "%s  ·  %d min  ·  %s" % [_map.display_name, _map.raid_minutes, "PMC" if _side == "pmc" else "Scav"]
	_update_insurance()


## INSURE GEAR: insures every insurable item you'd take that isn't yet (in the profile, which the
## loadout is a copy of), for its price; or says everything is.
func _update_insurance() -> void:
	_insure.visible = _side == "pmc"
	_insure_note.visible = _side == "pmc"
	if _side != "pmc":
		return
	var uninsured := Insurance.uninsured(GameState.inventory)
	var cost := Insurance.total_price(uninsured)
	if uninsured.is_empty():
		_insure.text = "ALL GEAR INSURED"
		_insure.disabled = true
	else:
		_insure.text = "INSURE GEAR  ·  %d item%s  ·  %s" % [uninsured.size(), "" if uninsured.size() == 1 else "s", UiFormat.money(cost)]
		_insure.disabled = GameState.roubles < cost
	_insure.tooltip_text = "You have %s" % UiFormat.money(GameState.roubles)
	_insure_note.text = "Insured gear you lose comes back to your stash after the raid (guns with their parts, rigs and backpacks empty). %d%% of an item's value, at least %s each." % [
		roundi(Insurance.CONFIG.insurance_rate * 100.0), UiFormat.money(Insurance.CONFIG.insurance_min_price)]


func _insure_gear() -> void:
	if Insurance.insure(Insurance.uninsured(GameState.inventory)) == "":
		SaveManager.save_game()
	_loadout = GameState.pmc_loadout()
	_show_loadout()


## "Bandage, 5.45x39 PS ×60" or "empty".
func _contents_text(grid: InventoryGrid) -> String:
	if grid.items.is_empty():
		return "empty"
	return ", ".join(grid.items.map(func(item: ItemInstance) -> String:
		return item.data.display_name + (" ×%d" % item.count if item.count > 1 else "")))


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
