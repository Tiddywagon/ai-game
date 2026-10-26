extends CanvasLayer
## The raid summary (DESIGN.md §2, §16.5), after every raid: SURVIVED, RUN THROUGH, KILLED IN ACTION or
## MISSING IN ACTION; the map, side and time in raid; kills (by side); the loot you carried out (or
## lost) and its value; experience with where it came from (kills, looting, trick shots, extracting;
## none for a Run Through) and the level you reached if it went up ("Level 11 → 12"); what happened
## to your gear (kept, lost, insured items coming back); and the loot that is now found in raid, each
## with its checkmark turned solid. A Run Through or MIA explains why nothing gained the checkmark. TO
## THE HIDEOUT goes back to the hideout (the profile is already saved: loot, gear, found-in-raid status,
## quest progress, level).

const MAIN_MENU := "res://ui/main_menu.tscn"
const FADE_TIME := 0.5
const COLORS := [Color(0.45, 0.9, 0.5), Color(0.95, 0.75, 0.3), Color(0.88, 0.26, 0.2), Color(0.88, 0.26, 0.2)]
## Item cells in the found-in-raid list are drawn at this size per grid cell.
const CELL := 52.0
const XP_PART_NAMES := {"kills": "Kills", "looting": "Looting", "trick_shots": "Trick shots", "exploration": "Exploration",
	"survived": "Extracted"}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%MenuButton.pressed.connect(_to_hideout)
	%Root.modulate.a = 0.0
	create_tween().tween_property(%Root, "modulate:a", 1.0, FADE_TIME)


func show_outcome(outcome: RaidOutcome, raid: RaidController) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var status := outcome.status
	%Title.text = RaidOutcome.TITLES[status]
	%Title.add_theme_color_override("font_color", COLORS[status])
	match status:
		RaidOutcome.Status.SURVIVED:
			%Subtitle.text = "Extracted at %s." % (outcome.extract_name if outcome.extract_name != "" else "an extract")
		RaidOutcome.Status.RUN_THROUGH:
			%Subtitle.text = "Extracted at %s, but too quickly: a Run Through." % (outcome.extract_name if outcome.extract_name != "" else "an extract")
		RaidOutcome.Status.KILLED:
			%Subtitle.text = "You didn't make it out."
		_:
			%Subtitle.text = "The raid ended before you got out."
	for line in summary_lines(outcome, raid):
		_stat(line[0], line[1])
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
			var config := raid.config if raid else load("res://data/config/raid.tres") as RaidConfig
			notes.append("Run Through: you keep your loot, but nothing became found in raid and you earned no experience. Stay in the raid for %d minutes or earn %d experience before extracting." % [
				int(config.run_through_seconds / 60.0), config.run_through_xp])
		RaidOutcome.Status.MIA:
			notes.append("Missing in action: nothing you picked up became found in raid.")
		RaidOutcome.Status.KILLED:
			notes.append("Killed: nothing you picked up became found in raid.")
		_:
			if not outcome.found.is_empty():
				notes.append("These now carry the found-in-raid checkmark: quests, hideout upgrades and some barters only take items with it.")
	%Note.text = "\n".join(notes)
	%Note.visible = not notes.is_empty()
	%MenuButton.grab_focus()


## The summary rows, [name, value]: map, side, time, kills, loot, experience (and where it came from),
## the level if it went up, gear and insurance.
static func summary_lines(outcome: RaidOutcome, raid: RaidController = null) -> Array:
	var lines := []
	var map := raid.map if raid else MapInfo.find(GameState.raid.get("map", ""))
	lines.append(["Map", map.display_name if map else "Test Yard"])
	lines.append(["Side", outcome.side_text()])
	lines.append(["Time in raid", "%d:%02d" % [int(outcome.seconds) / 60, int(outcome.seconds) % 60]])
	lines.append(["Kills", outcome.kills_text()])
	var loot := "%s  ·  %d item%s" % [UiFormat.money(outcome.loot_value), outcome.loot_count, "" if outcome.loot_count == 1 else "s"]
	if outcome.loot_count == 0:
		loot = "Nothing picked up"
	elif outcome.survived():
		loot += ", carried out"
	else:
		loot += ", lost"
	lines.append(["Loot", loot])
	if outcome.status == RaidOutcome.Status.RUN_THROUGH:
		lines.append(["Experience", "None (Run Through)"])
	else:
		lines.append(["Experience", "+%s" % UiFormat.thousands(outcome.xp)])
		for part: String in XP_PART_NAMES:
			var amount := int(outcome.xp_parts.get(part, 0))
			if amount > 0:
				lines.append(["    " + XP_PART_NAMES[part], "+%s" % UiFormat.thousands(amount)])
	if outcome.level_after > outcome.level_before:
		lines.append(["Level", "%d → %d" % [outcome.level_before, outcome.level_after]])
	if outcome.trick_hits > 0:
		lines.append(["Trick shots", "%d hits, %d kills  ·  +%d Drip" % [outcome.trick_hits, outcome.trick_kills, outcome.drip]])
	if outcome.side == "scav":
		if outcome.survived():
			lines.append(["Moved to stash", "%d items" % outcome.moved_to_stash.size()])
			if not outcome.left_behind.is_empty():
				lines.append(["Left behind", "%d items (no room in the stash)" % outcome.left_behind.size()])
		else:
			lines.append(["Gear", "Scav kit lost; nothing from your stash was at risk"])
	elif outcome.survived():
		lines.append(["Gear", "Kept"])
	else:
		lines.append(["Gear", "Lost, except your secure container (%s)" % UiFormat.money(outcome.lost_value) if outcome.lost_value > 0 else "Lost, except your secure container"])
		if outcome.insurance_returned.is_empty() and outcome.insurance_taken.is_empty():
			lines.append(["Insurance", "Nothing insured"])
		if not outcome.insurance_returned.is_empty():
			var count := outcome.insurance_returned.size()
			lines.append(["Insurance", "%d insured item%s (%s) on the way back with %s: in your stash in %s" % [count, "" if count == 1 else "s",
				UiFormat.money(outcome.insurance_value()), Insurance.insurer_name(outcome.insurance_returned[0].insurer), Insurance._clock(outcome.insurance_seconds)]])
		if not outcome.insurance_taken.is_empty():
			var taken := outcome.insurance_taken.size()
			lines.append(["Taken", "%d insured item%s taken off your body: gone for good" % [taken, "" if taken == 1 else "s"]])
	return lines


func _stat(name: String, value: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = name
	var value_label := Label.new()
	value_label.text = value
	%Stats.add_child(label)
	%Stats.add_child(value_label)


func _to_hideout() -> void:
	get_tree().paused = false
	GameState.raid = {}
	GameState.menu_return = "hideout"
	get_tree().change_scene_to_file(MAIN_MENU)
