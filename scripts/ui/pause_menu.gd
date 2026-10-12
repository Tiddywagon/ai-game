extends CanvasLayer
## In-raid pause menu (DESIGN.md §16.5): Esc or Start pauses the game and frees the mouse.
## Resume, Settings, Leave raid (asks first) and Quit game (asks first).

const MAIN_MENU := "res://ui/main_menu.tscn"
const SETTINGS_SCENE := preload("res://ui/settings_menu.tscn")

@onready var _panel: Control = %Panel
@onready var _host: Control = %ScreenHost
@onready var _leave_dialog: ConfirmationDialog = %LeaveDialog
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	%ResumeButton.pressed.connect(close)
	%SettingsButton.pressed.connect(_open_settings)
	%LeaveButton.pressed.connect(_ask.bind(_leave_dialog))
	%QuitButton.pressed.connect(_ask.bind(_quit_dialog))
	_leave_dialog.confirmed.connect(_leave_raid)
	_quit_dialog.confirmed.connect(get_tree().quit)


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
	var settings := SETTINGS_SCENE.instantiate()
	settings.closed.connect(func() -> void:
		_panel.show()
		%SettingsButton.grab_focus())
	_host.add_child(settings)


func _ask(dialog: ConfirmationDialog) -> void:
	dialog.popup_centered()
	dialog.get_cancel_button().grab_focus()


## Leaving counts as missing in action (DESIGN.md §2): a PMC loses everything but the secure container.
func _leave_raid() -> void:
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	if raid:
		raid.end_raid(RaidOutcome.Status.MIA)
	get_tree().paused = false
	GameState.raid = {}
	get_tree().change_scene_to_file(MAIN_MENU)
