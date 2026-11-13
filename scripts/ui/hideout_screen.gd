extends MenuScreen
## HIDEOUT screen (DESIGN.md §9, §16.1): the hideout plan (HideoutMap: every station a room showing its
## state) and the station panel beside it. The panel: what the station does and gives now; the upgrade
## tree, every level with its requirements as green checks or red crosses (other stations' levels,
## trader loyalty levels (a locked trader says "(locked)"), your level, roubles, items), the next one
## with HAND OVER per item (handed / needed), its build time, what it gives and BUILD, or the build's
## countdown; the craft list with the queue, timers and COLLECT; the generator's fuel gauge, switch and
## ADD FUEL; the farm's cards and coins; the Water Collector's water; the Gym's sessions; the Shooting
## Range's PRACTICE; the Workbench's gear upgrades. DECOR lists the cosmetics. Every action saves the
## game. A timer brings the hideout up to date every second: countdowns tick, and the panel is drawn
## again when something finished (focus stays on the button it was on).

const LOADING_SCENE := "res://ui/loading_screen.tscn"
## Item cells in craft rows: pixels per grid cell, and the most room one may take.
const CELL := 30.0
const MAX_CELL := Vector2(150, 64)

var _station: Dictionary = {}
## True while the panel shows the cosmetics instead of a station.
var _decor := false
## Labels that tick every second: [Callable that updates one].
var _live: Array[Callable] = []
var _signature := ""
var _timer: Timer


func _ready() -> void:
	%BackButton.pressed.connect(close)
	%DecorButton.pressed.connect(_show_decor)
	%Map.station_pressed.connect(_show)
	HideoutWork.update()
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	var first := Hideout.stations()[0]
	_show(first)
	(%Map.rooms[first.id] as Button).grab_focus.call_deferred()


## The station whose panel is shown.
func station() -> Dictionary:
	return _station


func _show(which: Dictionary) -> void:
	_decor = false
	_station = which
	%Map.select(which)
	_refresh()


func _show_decor() -> void:
	_decor = true
	_refresh()


func _tick() -> void:
	HideoutWork.update()
	%Map.refresh()
	_update_header()
	if _state_signature() != _signature:
		_refresh()
	else:
		for update in _live:
			update.call()


## What changes the panel's buttons: levels, builds, queues, what's ready, fuel, cards, power, the Gym.
func _state_signature() -> String:
	var state := GameState.hideout_state
	var counts := []
	for key: String in ["crafts", "ready"]:
		for id: String in state.get(key, {}):
			counts.append("%s:%s:%d" % [key, id, state[key][id].size()])
	for id: String in state.get("production", {}):
		counts.append("p:%s:%d" % [id, int(state.production[id].waiting)])
	return str([GameState.hideout, state.get("builds", {}).keys(), counts, state.get("fuel", []).size(), state.get("cards", []).size(),
		HideoutWork.has_power(), HideoutWork.train_block_reason() == "", GameState.roubles, state.get("handed", {}), state.get("cosmetics", [])])


func _update_header() -> void:
	%Money.text = "%s      %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")]
	if Hideout.level(Hideout.find(Hideout.GENERATOR)) == 0:
		%Power.text = "NO POWER  ·  build the Generator"
	elif HideoutWork.has_power():
		%Power.text = "POWER ON  ·  fuel for %s" % UiFormat.duration(HideoutWork.fuel_seconds_left())
	else:
		%Power.text = "NO POWER  ·  %s" % ("switched off" if not HideoutWork.power_on() else "out of fuel")
	%Power.add_theme_color_override("font_color", RequirementRow.MET_COLOR if HideoutWork.has_power() else RequirementRow.MISSING_COLOR)


func _refresh() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focus_name := String(focused.name) if focused and %Details.is_ancestor_of(focused) else ""
	_signature = _state_signature()
	_live.clear()
	%Map.refresh()
	_update_header()
	for child in %Details.get_children():
		%Details.remove_child(child)
		child.queue_free()
	if _decor:
		_build_decor()
	else:
		_build_station(_station)
	if focus_name != "":
		var again := %Details.find_child(focus_name, true, false) as Control
		if again and again.focus_mode != Control.FOCUS_NONE and not (again is BaseButton and again.disabled):
			again.grab_focus.call_deferred()
		else:
			(%Map.rooms[_station.id] as Button).grab_focus.call_deferred()


func _build_station(which: Dictionary) -> void:
	var level := Hideout.level(which)
	_heading("%s  ·  %s" % [str(which.name).to_upper(), "NOT BUILT" if level == 0 else "LEVEL %d / %d" % [level, Hideout.max_level(which)]])
	_note(which.get("description", ""))
	if Hideout.needs_power(which):
		_met_note("Needs power: %s" % ("on" if HideoutWork.has_power() else "off, so it works at %d%% speed%s" % [roundi(Hideout.unpowered_rate(which) * 100.0),
			"" if Hideout.unpowered_rate(which) > 0.0 else " (stopped)"]), HideoutWork.has_power()).name = "PowerNote"
	if level > 0:
		var now := Hideout.gives(which, Hideout.level_entry(which, level))
		if not now.is_empty():
			_note("Now: " + "  ·  ".join(now)).name = "Gives"
	match str(which.id):
		Hideout.GENERATOR:
			_build_generator(level)
		Hideout.BITCOIN_FARM:
			_build_farm(level)
		Hideout.WATER_COLLECTOR:
			_build_production(which, level)
		Hideout.GYM:
			_build_gym(level)
		Hideout.SHOOTING_RANGE:
			_build_range(level)
		Hideout.STASH:
			var cells := GameState.stash.size
			_note("Your stash: %d × %d" % [cells.x, cells.y]).name = "StashSize"
	_build_tree(which)
	if which.id == GearUpgrades.WORKBENCH:
		_build_gear_upgrades(level)
	_build_crafts(which, level)


# --- The upgrade tree ---------------------------------------------------------------------------

func _build_tree(which: Dictionary) -> void:
	%Details.add_child(HSeparator.new())
	_heading("UPGRADES", true)
	var built := Hideout.level(which)
	var next := int(Hideout.next_level(which).get("level", 0))
	for entry: Dictionary in which.levels:
		var number := int(entry.level)
		var title: String
		if number <= built:
			title = "LEVEL %d  ·  BUILT" % number
		elif Hideout.is_building(which) and number == next:
			title = "LEVEL %d  ·  BUILDING" % number
		else:
			title = "LEVEL %d  ·  %s to build" % [number, UiFormat.duration(Hideout.build_seconds(entry))]
		var heading := _heading(title, true)
		heading.name = "Level_%d" % number
		if number <= built and Hideout.start_level(which) >= number:
			heading.text += "  (every profile starts with it)"
		var gives := Hideout.gives(which, entry)
		if not gives.is_empty():
			_note("Gives: " + "  ·  ".join(gives))
		if number <= built:
			continue
		if Hideout.is_building(which) and number == next:
			var countdown := _note("")
			countdown.name = "BuildCountdown"
			var update := func() -> void: countdown.text = "Done in %s" % UiFormat.countdown(Hideout.build_seconds_left(which))
			update.call()
			_live.append(update)
			continue
		_requirements(which, entry, number == next)
		if number == next:
			_action("Build", "BUILD" if built == 0 else "UPGRADE TO LEVEL %d" % number, Hideout.upgrade_block_reason(which),
				func() -> String: return Hideout.upgrade(which))


## Level `entry`'s requirements: stations, traders, your level and roubles with a check or a cross,
## then the items: on the next level each with how many are handed over and HAND OVER.
func _requirements(which: Dictionary, entry: Dictionary, is_next: bool) -> void:
	var needed_stations: Dictionary = entry.get("stations", {})
	for other: String in needed_stations:
		var built := not Hideout.find(other).is_empty() and Hideout.level(Hideout.find(other)) >= int(needed_stations[other])
		_met_line("%s level %d  (%s)" % [Hideout.find(other).get("name", other), int(needed_stations[other]), "built" if built else "not yet"], built)
	var needed_traders: Dictionary = entry.get("traders", {})
	for trader: String in needed_traders:
		var have := Hideout.loyalty(trader)
		var state := "locked" if not TraderTable.is_unlocked(trader) else "reached" if have >= int(needed_traders[trader]) else "you're LL%d" % have
		_met_line("%s loyalty level %d  (%s)" % [TraderTable.display_name(trader), int(needed_traders[trader]), state],
			have >= int(needed_traders[trader])).name = "Trader_" + trader
	if entry.has("player_level"):
		_met_line("Player level %d  (you're %d)" % [int(entry.player_level), GameState.level], GameState.level >= int(entry.player_level))
	if int(entry.get("roubles", 0)) > 0:
		_met_line("%s  (you have %s)" % [UiFormat.money(int(entry.roubles)), UiFormat.money(GameState.roubles)], GameState.roubles >= int(entry.roubles))
	for wanted in Hideout.requirements(entry):
		if not is_next:
			_met_line("%s ×%d%s" % [wanted.item_data().display_name, wanted.count, "  (found in raid)" if wanted.fir else ""], wanted.have() >= wanted.count)
			continue
		var row := _handover_row(which, wanted)
		var button := _button("HandOver_" + wanted.item_id, "HAND OVER", Hideout.hand_over_block_reason(which, wanted),
			func() -> String: return Hideout.hand_over(which, wanted))
		button.custom_minimum_size = Vector2(150, 40)
		row.add_child(button)
		%Details.add_child(row)


## One item of the next level: its cell, name and found-in-raid mark, "3 / 5 handed over" and how many
## you have that count, a check or a cross (all in or not), then HAND OVER (added by the caller).
func _handover_row(which: Dictionary, wanted: Requirement) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cell := ItemCell.new()
	cell.box = Vector2(40, 40)
	cell.item = wanted.sample()
	row.add_child(cell)
	var name := Label.new()
	name.text = "%s ×%d" % [wanted.item_data().display_name, wanted.count]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name)
	if wanted.fir:
		row.add_child(FirMark.new())
	var handed := Hideout.handed(which, wanted.item_id)
	var count := Label.new()
	count.name = "Count"
	count.text = "%d / %d in  ·  have %d" % [handed, wanted.count, wanted.have()]
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count.add_theme_color_override("font_color", RequirementRow.MET_COLOR if handed >= wanted.count or wanted.have() > 0 else RequirementRow.MISSING_COLOR)
	count.tooltip_text = "Handed over / needed, and how many you have that count%s" % (" (found in raid only)" if wanted.fir else "")
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(count)
	var mark := MetMark.new()
	mark.met = Hideout.still_needed(which, wanted) == 0
	mark.tooltip_text = "All handed over" if mark.met else "%d more to hand over" % Hideout.still_needed(which, wanted)
	row.add_child(mark)
	return row


# --- Station-specific parts ---------------------------------------------------------------------

func _build_generator(level: int) -> void:
	if level == 0:
		return
	%Details.add_child(HSeparator.new())
	_heading("FUEL", true)
	var gauge := ProgressBar.new()
	gauge.name = "FuelGauge"
	gauge.max_value = 1.0
	gauge.step = 0.001
	gauge.custom_minimum_size = Vector2(0, 26)
	gauge.show_percentage = false
	%Details.add_child(gauge)
	var label := _note("")
	label.name = "FuelLeft"
	var update := func() -> void:
		gauge.value = HideoutWork.fuel_fraction()
		label.text = "%d / %d fuel slots  ·  %s of power left at ×%s efficiency%s" % [GameState.hideout_state.fuel.size(), HideoutWork.fuel_slots(),
			UiFormat.countdown(HideoutWork.fuel_seconds_left()), str(snappedf(HideoutWork.fuel_efficiency(), 0.01)), "" if HideoutWork.power_on() else "  ·  switched off"]
	update.call()
	_live.append(update)
	var row := _row()
	var switch := CheckButton.new()
	switch.name = "PowerSwitch"
	switch.text = "GENERATOR ON"
	switch.button_pressed = HideoutWork.power_on()
	switch.toggled.connect(func(on: bool) -> void:
		HideoutWork.set_power(on)
		SaveManager.save_game()
		%Status.text = "The generator is %s." % ("on" if on else "off")
		_refresh.call_deferred())
	row.add_child(switch)
	row.add_child(_button("AddFuel", "ADD FUEL CAN", HideoutWork.add_fuel_block_reason(), HideoutWork.add_fuel))
	_note("A fuel can gives %s of power at level 1; it burns only while the generator is on. Without power, stations that need it work at half speed, the farm stops and the Intelligence Center's bonuses are off." %
		UiFormat.duration(float(HideoutWork.fuel_items().get("fuel_can", 240)) * 60.0))


func _build_farm(level: int) -> void:
	if level == 0:
		return
	%Details.add_child(HSeparator.new())
	_heading("GRAPHICS CARDS  ·  %d / %d" % [HideoutWork.card_count(), HideoutWork.card_slots()], true).name = "Cards"
	_note("Speed ×%s: one card makes a coin a day, each card after the first adds a quarter." % str(snappedf(HideoutWork.production_speed(Hideout.BITCOIN_FARM), 0.01)))
	var row := _row()
	row.add_child(_button("InstallCard", "INSTALL CARD", HideoutWork.install_card_block_reason(), HideoutWork.install_card))
	row.add_child(_button("RemoveCard", "REMOVE CARD", "" if HideoutWork.card_count() > 0 else "No cards in the farm", HideoutWork.remove_card))
	_build_production(Hideout.find(Hideout.BITCOIN_FARM), level)


## What a producing station has made: waiting / cap, a bar to the next one, COLLECT.
func _build_production(which: Dictionary, level: int) -> void:
	if level == 0:
		return
	var made: Dictionary = Hideout.built_value(which.id, "produces", {})
	var item := ItemDB.get_item(str(made.get("item", "")))
	%Details.add_child(HSeparator.new())
	_heading("%s  ·  %d / %d WAITING" % [item.display_name.to_upper() if item else "?", HideoutWork.production(which.id).waiting, int(made.get("cap", 0))], true).name = "Waiting"
	var bar := ProgressBar.new()
	bar.name = "ProductionBar"
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	%Details.add_child(bar)
	var label := _note("")
	var update := func() -> void:
		var left := HideoutWork.seconds_to_next(which.id)
		bar.value = HideoutWork.production(which.id).progress
		label.text = "Next one in %s" % UiFormat.countdown(left) if left >= 0.0 else ("Full: collect to make more" if HideoutWork.production(which.id).waiting >= int(made.get("cap", 0))
			else "Stopped: %s" % ("no cards" if which.id == Hideout.BITCOIN_FARM and HideoutWork.card_count() == 0 else "no power"))
	update.call()
	_live.append(update)
	_row().add_child(_button("CollectProduction", "COLLECT", "" if HideoutWork.production(which.id).waiting > 0 else "Nothing to collect",
		func() -> String: return HideoutWork.collect_production(which.id)))


func _build_gym(level: int) -> void:
	if level == 0:
		return
	%Details.add_child(HSeparator.new())
	var training: Dictionary = Hideout.built_value(Hideout.GYM, "training", {})
	_heading("TRAINING  ·  %d points a session" % int(training.get("points", 0)), true)
	var blocked := HideoutWork.train_block_reason()
	var label := _note("")
	label.name = "GymRest"
	var update := func() -> void:
		var reason := HideoutWork.train_block_reason()
		label.text = reason if reason != "" else "Ready to train (Strength %d, Endurance %d)" % [Skills.level("strength"), Skills.level("endurance")]
	update.call()
	_live.append(update)
	var row := _row()
	row.add_child(_button("TrainStrength", "TRAIN STRENGTH", blocked, func() -> String: return HideoutWork.train("strength")))
	row.add_child(_button("TrainEndurance", "TRAIN ENDURANCE", blocked, func() -> String: return HideoutWork.train("endurance")))


func _build_range(level: int) -> void:
	if level == 0:
		return
	%Details.add_child(HSeparator.new())
	_heading("PRACTICE", true)
	_note("Takes a copy of your gear to the Test Yard: nothing is lost, nothing is gained, no experience.")
	_row().add_child(_button("Practice", "PRACTICE", "", func() -> String:
		var raid := Hideout.practice_raid()
		if raid.is_empty():
			return "Build the Shooting Range first"
		GameState.raid = raid
		get_tree().change_scene_to_file.call_deferred(LOADING_SCENE)
		return ""))


## The Workbench's gear upgrades: every piece of upgradable gear you own, with what the next level
## costs here (GearUpgradeRow).
func _build_gear_upgrades(level: int) -> void:
	%Details.add_child(HSeparator.new())
	_heading("GEAR UPGRADES  (up to +%d at this level)" % GearUpgrades.source_max_level(GearUpgrades.WORKBENCH) if level > 0 else "GEAR UPGRADES  (build the Workbench first)", true)
	_note("Raise armor, helmets, face shields, ballistic masks, headsets, rigs and backpacks a level at a time: more durability, less blunt damage, more room, less weight, better hearing. Level 1 upgrades to +2, level 2 to +4, level 3 to +5; rarer gear goes higher.")
	for gear in GearUpgrades.owned():
		var row := GearUpgradeRow.create(gear, GearUpgrades.WORKBENCH)
		row.upgraded.connect(func(_item: ItemInstance) -> void: _refresh.call_deferred())
		%Details.add_child(row)


# --- Crafts -------------------------------------------------------------------------------------

func _build_crafts(which: Dictionary, level: int) -> void:
	var recipes := Hideout.all_crafts(which)
	if recipes.is_empty():
		return
	%Details.add_child(HSeparator.new())
	_heading("CRAFTS  ·  QUEUE %d / %d  (the result is found in raid)" % [HideoutWork.queue(which).size(), Hideout.craft_queue_size()], true).name = "CraftsHeading"
	for index in HideoutWork.queue(which).size():
		var entry: Dictionary = HideoutWork.queue(which)[index]
		var label := _note("")
		label.name = "Queue_%d" % index
		var update := func() -> void:
			var left := HideoutWork.seconds_until_done(which, index)
			label.text = "%s  %s  ·  %s" % ["▶" if index == 0 else "·", _output_text(entry.output),
				("done in " + UiFormat.countdown(left)) if left >= 0.0 else "stopped: no power"]
		update.call()
		_live.append(update)
	var ready := HideoutWork.ready(which)
	if not ready.is_empty():
		var names := ready.map(func(entry: Dictionary) -> String: return _output_text(entry.output))
		_met_note("Ready: " + ", ".join(names), true)
		_row().add_child(_button("Collect", "COLLECT", "", func() -> String: return HideoutWork.collect(which)))
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
		name.text = "%s%s\n%s" % [output.data.display_name, "  ×%d" % output.count if output.count > 1 else "", UiFormat.duration(HideoutWork.craft_seconds(recipe))]
		result.add_child(name)
		row.add_child(result)
		var blocked := HideoutWork.craft_block_reason(which, recipe)
		if level < unlock_level:
			blocked = "Needs %s level %d" % [which.name, unlock_level]
		row.add_child(_button("Craft_" + str(recipe.id), "CRAFT", blocked, func() -> String: return HideoutWork.craft(which, recipe)))
		%Details.add_child(row)


static func _output_text(output: Dictionary) -> String:
	var data := ItemDB.get_item(str(output.get("item", "")))
	return (data.display_name if data else str(output.get("item", "?"))) + (" ×%d" % int(output.count) if int(output.get("count", 1)) > 1 else "")


# --- Cosmetics ----------------------------------------------------------------------------------

func _build_decor() -> void:
	_heading("DECOR")
	_note("Purely for looks: each changes how the hideout plan looks, once bought.")
	for entry in Hideout.cosmetics():
		%Details.add_child(HSeparator.new())
		_heading("%s  ·  %s%s" % [str(entry.name).to_upper(), str(entry.slot), "  ·  DONE" if Hideout.has_cosmetic(str(entry.id)) else ""], true)
		_note(str(entry.get("description", "")))
		if Hideout.has_cosmetic(str(entry.id)):
			continue
		_met_line("%s  (you have %s)" % [UiFormat.money(int(entry.get("roubles", 0))), UiFormat.money(GameState.roubles)], GameState.roubles >= int(entry.get("roubles", 0)))
		for wanted in Requirement.list(entry.get("requires", [])):
			%Details.add_child(RequirementRow.create(wanted))
		_row().add_child(_button("Buy_" + str(entry.id), "BUY", Hideout.cosmetic_block_reason(str(entry.id)), func() -> String: return Hideout.buy_cosmetic(str(entry.id))))


# --- Building blocks ----------------------------------------------------------------------------

func _heading(text: String, small := false) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"AccentLabel" if small else &"HeadingLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Details.add_child(label)
	return label


func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Details.add_child(label)
	return label


## A note that's green when `met`, red when not.
func _met_note(text: String, met: bool) -> Label:
	var label := _note(text)
	label.add_theme_color_override("font_color", RequirementRow.MET_COLOR if met else RequirementRow.MISSING_COLOR)
	return label


## A requirement that isn't an item on hand: a green check or a red cross, then the text.
func _met_line(text: String, met: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var mark := MetMark.new()
	mark.met = met
	mark.tooltip_text = "Met" if met else "Not met yet"
	row.add_child(mark)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", RequirementRow.MET_COLOR if met else RequirementRow.MISSING_COLOR)
	row.add_child(label)
	%Details.add_child(row)
	return row


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	%Details.add_child(row)
	return row


## A button at the end of a row in the panel.
func _action(id: String, text: String, blocked: String, action: Callable) -> Button:
	var button := _button(id, text, blocked, action)
	_row().add_child(button)
	return button


## A button named `id` that runs `action` (returns "" or why it failed), saves and draws the panel
## again. Disabled with the reason as its tooltip when `blocked` isn't "".
func _button(id: String, text: String, blocked: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size = Vector2(170, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = blocked != ""
	button.tooltip_text = blocked
	button.pressed.connect(func() -> void:
		var reason: String = action.call()
		if reason == "":
			SaveManager.save_game()
		%Status.text = reason if reason != "" else "Done."
		_refresh.call_deferred())
	return button
