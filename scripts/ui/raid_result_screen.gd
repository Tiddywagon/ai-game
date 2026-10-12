extends CanvasLayer
## The end of a raid you didn't die in (DESIGN.md §2): SURVIVED, RUN THROUGH or MISSING IN ACTION, the
## raid's numbers, and the loot that is now found in raid, each with its checkmark turned solid.
## A Run Through explains why nothing gained the checkmark. BACK TO MENU leaves.

const MAIN_MENU := "res://ui/main_menu.tscn"
const FADE_TIME := 0.5
const COLORS := [Color(0.45, 0.9, 0.5), Color(0.95, 0.75, 0.3), Color(0.88, 0.26, 0.2), Color(0.88, 0.26, 0.2)]
## Item cells in the found-in-raid list are drawn at this size per grid cell.
const CELL := 52.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%MenuButton.pressed.connect(_to_menu)
	%Root.modulate.a = 0.0
	create_tween().tween_property(%Root, "modulate:a", 1.0, FADE_TIME)


func show_outcome(outcome: RaidOutcome, raid: RaidController) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var status := outcome.status
	%Title.text = RaidOutcome.TITLES[status]
	%Title.add_theme_color_override("font_color", COLORS[status])
	match status:
		RaidOutcome.Status.SURVIVED:
			%Subtitle.text = "Extracted at %s." % (raid.extract_zone.extract_name if raid and raid.extract_zone else "an extract")
		RaidOutcome.Status.RUN_THROUGH:
			%Subtitle.text = "Extracted, but too quickly: a Run Through."
		_:
			%Subtitle.text = "The raid ended before you got out."
	var map := raid.map if raid else null
	_stat("Map", map.display_name if map else "Test Yard")
	_stat("Side", "Scav" if outcome.side == "scav" else "PMC")
	_stat("Time in raid", "%d:%02d" % [int(outcome.seconds) / 60, int(outcome.seconds) % 60])
	_stat("Kills", str(outcome.kills))
	_stat("Experience", "+%s" % UiFormat.thousands(outcome.xp))
	if outcome.trick_hits > 0:
		_stat("Trick shots", "%d hits, %d kills  ·  +%d Drip" % [outcome.trick_hits, outcome.trick_kills, outcome.drip])
	if outcome.side == "scav" and outcome.survived():
		_stat("Moved to stash", "%d items" % outcome.moved_to_stash.size())
		if not outcome.left_behind.is_empty():
			_stat("Left behind", "%d items (no room in the stash)" % outcome.left_behind.size())
	if status == RaidOutcome.Status.MIA:
		_stat("Gear", "Lost, except your secure container" if outcome.side == "pmc" else "Nothing from your stash was at risk")
	var notes: Array[String] = []
	if outcome.found.is_empty():
		%FoundTitle.text = "FOUND IN RAID: NOTHING"
	else:
		%FoundTitle.text = "FOUND IN RAID  ·  %d ITEMS  ·  %s" % [outcome.found.size(), UiFormat.money(outcome.found_value())]
		for item in outcome.found:
			var cell := ItemCell.new()
			cell.item = item
			cell.cell_size = CELL
			%FoundItems.add_child(cell)
	match status:
		RaidOutcome.Status.RUN_THROUGH:
			notes.append("Nothing you picked up became found in raid. Stay in the raid for %d minutes or earn %d experience before extracting." % [
				int(raid.config.run_through_seconds / 60.0) if raid else 7, raid.config.run_through_xp if raid else 200])
		RaidOutcome.Status.MIA:
			notes.append("Missing in action: nothing you picked up became found in raid.")
		_:
			if not outcome.found.is_empty():
				notes.append("These now carry the found-in-raid checkmark: quests, hideout upgrades and some barters only take items with it.")
	%Note.text = "\n".join(notes)
	%Note.visible = not notes.is_empty()
	%MenuButton.grab_focus()


func _stat(name: String, value: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = name
	var value_label := Label.new()
	value_label.text = value
	%Stats.add_child(label)
	%Stats.add_child(value_label)


func _to_menu() -> void:
	get_tree().paused = false
	GameState.raid = {}
	get_tree().change_scene_to_file(MAIN_MENU)
