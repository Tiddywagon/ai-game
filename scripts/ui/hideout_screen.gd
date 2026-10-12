extends MenuScreen
## HIDEOUT screen (DESIGN.md §9): every station with its level; the next level's requirements
## (roubles, other stations, items: those with the found-in-raid checkmark only take found-in-raid
## items) and UPGRADE; and the crafts it has unlocked, inputs → output, with CRAFT. Crafted items go to
## the stash and are found in raid. Upgrades and crafts are instant for now. Each one saves the game.

## Item cells in craft rows: pixels per grid cell, and the most room one may take.
const CELL := 30.0
const MAX_CELL := Vector2(150, 64)

var _buttons: Array[Button] = []
var _station: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(close)
	var group := ButtonGroup.new()
	for station in Hideout.stations():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 56
		button.pressed.connect(_show.bind(station))
		button.focus_entered.connect(_show.bind(station))
		%StationList.add_child(button)
		_buttons.append(button)
	_update_list()
	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()
		_show(Hideout.stations()[0])


func _update_list() -> void:
	for i in _buttons.size():
		var station := Hideout.stations()[i]
		var level := Hideout.level(station)
		_buttons[i].text = "%s   ·   %s" % [station.name, "not built" if level == 0 else "level %d / %d" % [level, Hideout.max_level(station)]]
	%Money.text = "%s      %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")]


func _show(station: Dictionary) -> void:
	if station == _station:
		return
	_station = station
	_buttons[Hideout.stations().find(station)].set_pressed_no_signal(true)
	_refresh()


func _refresh() -> void:
	_update_list()
	var station := _station
	for child in %Details.get_children():
		%Details.remove_child(child)
		child.queue_free()
	var level := Hideout.level(station)
	_heading("%s  ·  %s" % [station.name.to_upper(), "NOT BUILT" if level == 0 else "LEVEL %d" % level])
	_note(station.get("description", ""))
	var next := Hideout.next_level(station)
	if next.is_empty():
		_heading("FULLY UPGRADED", true)
	else:
		_heading("%s LEVEL %d" % ["BUILD" if level == 0 else "UPGRADE TO", int(next.level)], true)
		if int(next.get("roubles", 0)) > 0:
			_note("%s  (you have %s)" % [UiFormat.money(int(next.roubles)), UiFormat.money(GameState.roubles)])
		var needed_stations: Dictionary = next.get("stations", {})
		for other: String in needed_stations:
			var have := int(GameState.hideout.get(other, 0))
			_note("%s level %d  (%s)" % [Hideout.find(other).get("name", other), int(needed_stations[other]),
				"built" if have >= int(needed_stations[other]) else "not yet"])
		for wanted in Hideout.requirements(next):
			%Details.add_child(RequirementRow.create(wanted))
		%Details.add_child(_action_button("UPGRADE" if level > 0 else "BUILD", Hideout.upgrade_block_reason(station),
			func() -> String: return Hideout.upgrade(station)))
	if station.id == GearUpgrades.WORKBENCH:
		_build_gear_upgrades(level)
	var recipes := Hideout.all_crafts(station)
	if not recipes.is_empty():
		%Details.add_child(HSeparator.new())
		_heading("CRAFTS  (the result is found in raid)", true)
	for entry in recipes:
		var unlock_level: int = entry[0]
		var recipe: Dictionary = entry[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var inputs := VBoxContainer.new()
		inputs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for wanted in Requirement.list(recipe.inputs):
			inputs.add_child(RequirementRow.create(wanted))
		row.add_child(inputs)
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 28)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(arrow)
		var output := FoundInRaid.make(str(recipe.output.item), int(recipe.output.get("count", 1)), FoundInRaid.Source.CRAFT)
		var result := VBoxContainer.new()
		result.custom_minimum_size.x = 170
		result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cell := ItemCell.new()
		var fit := Vector2(output.data.size) * CELL
		cell.box = fit * minf(1.0, minf(MAX_CELL.x / fit.x, MAX_CELL.y / fit.y))
		cell.item = output
		result.add_child(cell)
		var name := Label.new()
		name.text = output.data.display_name + ("  ×%d" % output.count if output.count > 1 else "")
		result.add_child(name)
		row.add_child(result)
		var blocked := Hideout.craft_block_reason(station, recipe)
		if level < unlock_level:
			blocked = "Needs %s level %d" % [station.name, unlock_level]
		row.add_child(_action_button("CRAFT", blocked, func() -> String: return Hideout.craft(station, recipe)))
		%Details.add_child(row)


## The Workbench's gear upgrades: every piece of upgradable gear you own, with what the next level
## costs here (GearUpgradeRow).
func _build_gear_upgrades(level: int) -> void:
	%Details.add_child(HSeparator.new())
	_heading("GEAR UPGRADES  (up to +%d at this level)" % GearUpgrades.source_max_level(GearUpgrades.WORKBENCH) if level > 0 else "GEAR UPGRADES  (build the Workbench first)", true)
	_note("Raise armor, helmets, face shields, headsets, rigs and backpacks a level at a time: more durability, less blunt damage, more room, less weight, better hearing. Level 1 upgrades to +2, level 2 to +4, level 3 to +5; rarer gear goes higher.")
	for gear in GearUpgrades.owned():
		var row := GearUpgradeRow.create(gear, GearUpgrades.WORKBENCH)
		row.upgraded.connect(func(_item: ItemInstance) -> void: _refresh.call_deferred())
		%Details.add_child(row)


func _heading(text: String, small := false) -> void:
	var label := Label.new()
	label.theme_type_variation = &"AccentLabel" if small else &"HeadingLabel"
	label.text = text
	%Details.add_child(label)


func _note(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Details.add_child(label)


## A button that runs `action` (returns "" or why it failed), saves and refreshes. Disabled with the
## reason as its tooltip when `blocked` isn't "".
func _action_button(text: String, blocked: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = blocked != ""
	button.tooltip_text = blocked
	button.pressed.connect(func() -> void:
		var result: String = action.call()
		if result == "":
			SaveManager.save_game()
		%Status.text = result if result != "" else "Done."
		_refresh.call_deferred())
	return button
