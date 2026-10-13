extends CanvasLayer
## In-raid pause menu (DESIGN.md §16.5): Esc or Start pauses the game and frees the mouse.
## Resume, Settings, Leave raid (asks first) and Quit game (asks first). Beside them, your extracts
## (DESIGN.md §5), each marked Open, Unknown, Closed or with what it still needs.

const MAIN_MENU := "res://ui/main_menu.tscn"
const SETTINGS_SCENE := preload("res://ui/settings_menu.tscn")

@onready var _panel: Control = %Panel
@onready var _host: Control = %ScreenHost
@onready var _leave_dialog: ConfirmationDialog = %LeaveDialog
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog

var _extracts: RichTextLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	%ResumeButton.pressed.connect(close)
	%SettingsButton.pressed.connect(_open_settings)
	%LeaveButton.pressed.connect(_ask.bind(_leave_dialog))
	%QuitButton.pressed.connect(_ask.bind(_quit_dialog))
	_leave_dialog.confirmed.connect(_leave_raid)
	_quit_dialog.confirmed.connect(get_tree().quit)
	_build_extract_panel()


func _unhandled_input(event: InputEvent) -> void:
	var toggle := event.is_action_pressed("pause")
	var back := event.is_action_pressed("ui_cancel") and visible
	if not (toggle or back) or _host.get_child_count() > 0:
		return
	var player := get_tree().get_first_node_in_group("player") as Actor
	if player and player.is_dead and not visible:
		return  # The death screen is up instead.
	if visible:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	_extracts.text = extracts_text()
	_extracts.get_parent().get_parent().visible = _extracts.text != ""
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%ResumeButton.grab_focus()


func close() -> void:
	hide()
	get_tree().paused = false
	var player := get_tree().get_first_node_in_group("player") as Actor
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if player and not player.is_dead else Input.MOUSE_MODE_VISIBLE


func _open_settings() -> void:
	_panel.hide()
	_extracts.get_parent().get_parent().hide()
	var settings := SETTINGS_SCENE.instantiate()
	settings.closed.connect(func() -> void:
		_panel.show()
		_extracts.get_parent().get_parent().visible = _extracts.text != ""
		%SettingsButton.grab_focus())
	_host.add_child(settings)


func _ask(dialog: ConfirmationDialog) -> void:
	dialog.popup_centered()
	dialog.get_cancel_button().grab_focus()


## Your extracts as BBCode lines: "Gate 3  ·  Open", coloured like the HUD's list ("" outside a raid).
func extracts_text() -> String:
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	if raid == null:
		return ""
	var lines := PackedStringArray()
	for zone in raid.available_extracts():
		var color: Color = ExtractZone.STATE_COLORS[zone.status_state(raid.player)]
		lines.append("[color=#%s]%s  ·  %s[/color]" % [color.to_html(false), zone.extract_name, zone.status_for(raid.player)])
	return "\n".join(lines)


func _build_extract_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "ExtractPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560.0
	panel.offset_right = -60.0
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH  # As tall as its list, centred.
	add_child(panel)
	move_child(panel, _host.get_index())  # Under settings when they're open.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "EXTRACTS"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_extracts = RichTextLabel.new()
	_extracts.name = "ExtractList"
	_extracts.bbcode_enabled = true
	_extracts.fit_content = true
	_extracts.scroll_active = false
	_extracts.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(_extracts)


## Leaving counts as missing in action (DESIGN.md §2): a PMC loses everything but the secure container.
func _leave_raid() -> void:
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	if raid:
		raid.end_raid(RaidOutcome.Status.MIA)
	get_tree().paused = false
	GameState.raid = {}
	get_tree().change_scene_to_file(MAIN_MENU)
