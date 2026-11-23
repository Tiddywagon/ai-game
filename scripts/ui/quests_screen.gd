class_name QuestsScreen
extends MenuScreen
## The quest log (DESIGN.md §11, §16): QUESTS on the main menu and on TRADERS, and from the pause menu
## (or the quest log key) in a raid. Three tabs, ACTIVE (active and ready to turn in), AVAILABLE (open
## to accept, and locked ones with what they need) and COMPLETED, a trader filter, the list on the left
## and the picked quest on the right: its trader, state, chain ("after Old Unit ✓ · level 10 ✗"),
## briefing, each objective with its progress (live in a raid: QuestRaid), rewards, what it unlocks and
## what it leads to. Out of raid ACCEPT, HAND OVER, TURN IN and TAKE MARKER AGAIN work here as on the
## trader's TASKS tab; TRACK puts it on the HUD tracker (up to QuestLog.MAX_TRACKED), in a raid too.

const ACTIVE := 0
const AVAILABLE := 1
const COMPLETED := 2
const TAB_NAMES := ["ACTIVE", "AVAILABLE", "COMPLETED"]
const STATE_NAMES := {"locked": "LOCKED", "available": "AVAILABLE", "active": "ACTIVE", "ready": "READY TO TURN IN", "completed": "COMPLETED"}
const DONE_COLOR := Color(0.55, 0.9, 0.55)
const OPEN_COLOR := Color(0.92, 0.9, 0.8)
const LOCKED_COLOR := Color(0.6, 0.6, 0.58)

var tab := ACTIVE
## "" for every trader, else the trader id shown.
var trader_filter := ""
## The quest picked (its id; "" picks the first in the list).
var selected := ""
## Set in a raid: the raid's live progress, and no accepting or turning in.
var raid: RaidController

var _tabs: Array[Button] = []
var _filter: OptionButton
var _list: VBoxContainer
var _detail: VBoxContainer
var _status: Label


## A quest log; `in_raid` the raid it's opened in (null out of raid), `trader` a filter to start on.
static func create(in_raid: RaidController = null, trader := "") -> QuestsScreen:
	var screen := QuestsScreen.new()
	screen.raid = in_raid
	screen.trader_filter = trader
	return screen


func _ready() -> void:
	name = "QuestsScreen"
	process_mode = Node.PROCESS_MODE_ALWAYS  # It opens over a paused raid.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.02, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	layout.add_child(_header())
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 24)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size.x = 440
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.name = "QuestList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_list)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.name = "Detail"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail)
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"DimLabel"
	layout.add_child(_status)
	show_tab(tab)


func _header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "QUESTS"
	title.theme_type_variation = &"HeadingLabel"
	header.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	header.add_child(gap)
	for i in TAB_NAMES.size():
		var button := Button.new()
		button.name = TAB_NAMES[i].capitalize() + "Tab"
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(170, 48)
		button.pressed.connect(show_tab.bind(i))
		header.add_child(button)
		_tabs.append(button)
	_filter = OptionButton.new()
	_filter.name = "TraderFilter"
	_filter.custom_minimum_size = Vector2(220, 48)
	_filter.add_item("All traders")
	_filter.set_item_metadata(0, "")
	for id in TraderTable.ids():
		if not QuestLog.for_trader(id).is_empty() or id == trader_filter:
			_filter.add_item(TraderTable.display_name(id))
			_filter.set_item_metadata(_filter.item_count - 1, id)
	_sync_filter()
	_filter.item_selected.connect(func(index: int) -> void: set_trader(str(_filter.get_item_metadata(index))))
	header.add_child(_filter)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(140, 48)
	back.pressed.connect(close)
	header.add_child(back)
	return header


## Shows tab `which` (ACTIVE, AVAILABLE, COMPLETED).
func show_tab(which: int) -> void:
	tab = which
	for i in _tabs.size():
		_tabs[i].button_pressed = i == which
		_tabs[i].text = "%s (%d)" % [TAB_NAMES[i], quests_on(i).size()]
	_refresh()


## Filters the log to trader `id` ("" for all of them); the dropdown follows.
func set_trader(id: String) -> void:
	trader_filter = id
	_sync_filter()
	show_tab(tab)


## The trader dropdown shows the filter in use (opened from TRADERS, or set_trader()).
func _sync_filter() -> void:
	if _filter == null:
		return
	for index in _filter.item_count:
		if str(_filter.get_item_metadata(index)) == trader_filter:
			_filter.select(index)
			return
	_filter.select(0)


## The quests tab `which` lists, with the trader filter: ACTIVE active and ready ones, AVAILABLE those
## open to accept then the locked ones, COMPLETED the completed ones.
func quests_on(which: int) -> Array[Dictionary]:
	var states: Array = [["active", "ready"], ["available", "locked"], ["completed"]][which]
	var result: Array[Dictionary] = []
	for state in states:
		for quest in QuestLog.shown():
			if (trader_filter == "" or quest.trader == trader_filter) and QuestLog.state(quest) == state:
				result.append(quest)
	return result


func select(id: String) -> void:
	selected = id
	_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var shown := quests_on(tab)
	if not shown.any(func(quest: Dictionary) -> bool: return quest.id == selected):
		selected = shown[0].id if not shown.is_empty() else ""
	for quest in shown:
		var button := Button.new()
		button.name = "Quest_" + quest.id
		button.toggle_mode = true
		button.button_pressed = quest.id == selected
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var marks: String = ("●  " if QuestLog.is_tracked(quest) else "") + quest.name
		button.text = "%s   ·   %s%s" % [marks, TraderTable.display_name(quest.trader), "   ·   READY" if QuestLog.state(quest) == "ready" else ""]
		if QuestLog.state(quest) == "locked":
			button.add_theme_color_override("font_color", LOCKED_COLOR)
		button.pressed.connect(select.bind(quest.id))
		_list.add_child(button)
	if shown.is_empty():
		_list.add_child(_line("Nothing here.", LOCKED_COLOR))
	_build_detail(QuestLog.find(selected) if selected != "" else {})


## The picked quest: everything about it, and what can be done with it.
func _build_detail(quest: Dictionary) -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if quest.is_empty():
		return
	var state := QuestLog.state(quest)
	var title := Label.new()
	title.name = "QuestTitle"
	title.theme_type_variation = &"HeadingLabel"
	title.text = quest.name.to_upper()
	_detail.add_child(title)
	_detail.add_child(_line("%s  ·  %s%s" % [TraderTable.display_name(quest.trader), STATE_NAMES[state],
		"  ·  %s only" % Factions.display_name(QuestLog.faction_of(quest)) if QuestLog.faction_of(quest) != &"" else ""], OPEN_COLOR))
	var chain := QuestLog.prerequisites(quest)
	if not chain.is_empty():
		var links := chain.map(func(link: Dictionary) -> String: return "%s %s" % [link.name, "✓" if link.done else "✗"])
		var line := _line("Chain: " + "  ·  ".join(links), DONE_COLOR if chain.all(func(link: Dictionary) -> bool: return link.done) else LOCKED_COLOR)
		line.name = "Chain"
		_detail.add_child(line)
	if QuestLog.map_note(quest) != "":
		var note := _line(QuestLog.map_note(quest) + ".", LOCKED_COLOR)
		note.name = "MapNote"
		_detail.add_child(note)
	_detail.add_child(_wrapped(str(quest.get("description", ""))))
	if state == "completed" and quest.has("success"):
		_detail.add_child(_wrapped("\"%s\"" % quest.success))
	_detail.add_child(_section("OBJECTIVES"))
	for i in quest.objectives.size():
		_detail.add_child(_objective(quest, i, state))
	_detail.add_child(_section("REWARDS"))
	_detail.add_child(_wrapped("  ·  ".join(QuestLog.reward_lines(quest))))
	var unlocks := QuestLog.unlocks(quest)
	if not unlocks.is_empty():
		_detail.add_child(_section("UNLOCKS"))
		for unlock: Dictionary in unlocks:
			_detail.add_child(_wrapped(unlock.text))
	var next := QuestLog.followers(quest)
	if not next.is_empty():
		_detail.add_child(_line("Leads to: " + ", ".join(next.map(func(each: Dictionary) -> String: return each.name)), LOCKED_COLOR))
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 12)
	_detail.add_child(actions)
	if state in ["active", "ready"]:
		var track := _button("TrackButton", "UNTRACK" if QuestLog.is_tracked(quest) else "TRACK", "", func() -> String:
			return QuestLog.set_tracked(quest, not QuestLog.is_tracked(quest)))
		actions.add_child(track)
	if raid != null:
		if state != "completed":
			_detail.add_child(_line("Accept, hand over and turn in at the trader or here once out of the raid.", LOCKED_COLOR))
		return
	match state:
		"available":
			actions.add_child(_button("AcceptButton", "ACCEPT", QuestLog.accept_block_reason(quest), func() -> String:
				return "" if QuestLog.accept(quest) else QuestLog.accept_block_reason(quest)))
		"ready":
			actions.add_child(_button("TurnInButton", "TURN IN", QuestLog.complete_block_reason(quest), func() -> String: return QuestLog.complete(quest)))
		"locked":
			_detail.add_child(_line(QuestLog.lock_reason(quest) + ".", LOCKED_COLOR))
	if QuestLog.can_retake_marker(quest):
		actions.add_child(_button("RetakeButton", "TAKE MARKER AGAIN", "", func() -> String: return QuestLog.retake_marker(quest)))


## One objective: what it asks for, its progress (live in a raid, with the part that waits for the
## extract) and, for a hand-in out of raid, HAND OVER.
func _objective(quest: Dictionary, index: int, state: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Objective_%d" % index
	row.add_theme_constant_override("separation", 12)
	var count := QuestLog.objective_count(quest, index)
	var done := raid.quest_raid.progress(quest, index) if raid and raid.quest_raid else QuestLog.progress(quest, index)
	var text := QuestLog.objective_text(quest, index)
	if quest.objectives[index].get("survive", false):
		text += " (survive the raid)"
	var label := _wrapped(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var shown := "%d / %d" % [done, count] if state != "available" and state != "locked" else "×%d" % count
	if QuestLog.objective_type(quest, index) == "roubles":
		shown = "%s / %s" % [UiFormat.money(done), UiFormat.money(count)] if state in ["active", "ready", "completed"] else UiFormat.money(count)
	var progress := _line(shown if state != "completed" else "✓", DONE_COLOR if done >= count or state == "completed" else OPEN_COLOR)
	progress.name = "Progress"
	row.add_child(progress)
	if raid and raid.quest_raid and raid.quest_raid.pending_of(quest, index) > 0:
		row.add_child(_line("+%d on extract" % raid.quest_raid.pending_of(quest, index), LOCKED_COLOR))
	if raid == null and state == "active" and QuestLog.objective_type(quest, index) in QuestLog.HAND_TYPES and done < count:
		row.add_child(_button("HandOver", "HAND OVER", "", func() -> String: return "" if QuestLog.hand_in(quest, index) > 0 else "Nothing to hand over"))
	return row


func _button(node_name: String, text: String, blocked: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(180, 44)
	button.disabled = blocked != ""
	button.tooltip_text = blocked
	button.pressed.connect(func() -> void:
		var reason: String = action.call()
		_status.text = reason
		var keep := selected
		show_tab(tab)
		if keep != selected and reason == "":
			for i in TAB_NAMES.size():  # The quest moved tab (accepted, turned in): follow it.
				if quests_on(i).any(func(each: Dictionary) -> bool: return each.id == keep):
					selected = keep
					show_tab(i)
					break)
	return button


func _section(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"AccentLabel"
	label.text = text
	return label


func _line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label


func _wrapped(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
