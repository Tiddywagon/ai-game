extends Node
## Main menu (DESIGN.md §16): a slowly panning dusk scene with ambient music, the title top-left,
## the main buttons stacked on the left, the profile top-right and Settings bottom-right.
## Each button opens a screen on top of the menu; screens emit `closed` when the player backs out.
## On first launch the player picks a faction, which creates the profile. After a raid's summary it
## opens straight on the hideout (GameState.menu_return).

const RAID_SETUP_SCENE := preload("res://ui/raid_setup.tscn")
const CHARACTER_SCENE := preload("res://ui/character_screen.tscn")
const HIDEOUT_SCENE := preload("res://ui/hideout_screen.tscn")
const TRADERS_SCENE := preload("res://ui/traders_screen.tscn")
const SETTINGS_SCENE := preload("res://ui/settings_menu.tscn")
const MUSIC_FADE_IN := 3.0

var _return_focus: Control

@onready var _menu: Control = %Menu
@onready var _host: Control = %ScreenHost
@onready var _music: AudioStreamPlayer = $Music
@onready var _quit_dialog: ConfirmationDialog = %QuitDialog
@onready var _faction_picker: Control = %FactionPicker


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_music.stream as AudioStreamOggVorbis).loop = true
	_music.volume_db = -40.0
	_music.play()
	InputHub.fit_to_safe_area(_menu)  # Clear of notches on phones and tablets.
	create_tween().tween_property(_music, "volume_db", 0.0, MUSIC_FADE_IN).set_ease(Tween.EASE_OUT)
	%EnterRaidButton.pressed.connect(_open.bind(RAID_SETUP_SCENE, %EnterRaidButton))
	%HideoutButton.pressed.connect(_open.bind(HIDEOUT_SCENE, %HideoutButton))
	%CharacterButton.pressed.connect(_open.bind(CHARACTER_SCENE, %CharacterButton))
	%TradersButton.pressed.connect(_open.bind(TRADERS_SCENE, %TradersButton))
	%SettingsButton.pressed.connect(_open.bind(SETTINGS_SCENE, %SettingsButton))
	%QuitButton.pressed.connect(_ask_quit)
	_quit_dialog.confirmed.connect(get_tree().quit)
	%BearButton.pressed.connect(_choose_faction.bind(GameState.Faction.BEAR))
	%UsecButton.pressed.connect(_choose_faction.bind(GameState.Faction.USEC))
	_load_profile()


func _unhandled_input(event: InputEvent) -> void:
	# Back out of the main menu itself: ask before quitting.
	if event.is_action_pressed("ui_cancel") and _host.get_child_count() == 0 and not _faction_picker.visible:
		_ask_quit()
		get_viewport().set_input_as_handled()


func _load_profile() -> void:
	if GameState.faction == GameState.Faction.NONE and SaveManager.has_save():
		SaveManager.load_game()
	var has_profile := GameState.faction != GameState.Faction.NONE
	if has_profile and not GameState.insurance_pending.is_empty() and Insurance.deliver_pending() > 0:
		SaveManager.save_game()  # Insured items that were waiting for room in the stash arrived.
	_faction_picker.visible = not has_profile
	_menu.visible = has_profile
	_refresh_profile()
	if has_profile and GameState.menu_return == "hideout":
		GameState.menu_return = ""
		_open(HIDEOUT_SCENE, %HideoutButton)
	else:
		(%EnterRaidButton if has_profile else %UsecButton).grab_focus.call_deferred()


func _choose_faction(faction: int) -> void:
	GameState.new_profile(faction)
	SaveManager.save_game()
	_faction_picker.hide()
	_menu.show()
	_refresh_profile()
	%EnterRaidButton.grab_focus()


func _refresh_profile() -> void:
	var has_profile := GameState.faction != GameState.Faction.NONE
	%FactionLabel.text = GameState.Faction.find_key(GameState.faction) if has_profile else ""
	%LevelLabel.text = "LEVEL %d" % GameState.level if has_profile else ""
	%MoneyLabel.text = "%s      %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")] if has_profile else ""


func _open(scene: PackedScene, from: Control) -> void:
	_return_focus = from
	_menu.hide()
	var screen := scene.instantiate()
	screen.closed.connect(_on_screen_closed)
	_host.add_child(screen)


func _on_screen_closed() -> void:
	_menu.show()
	_refresh_profile()
	_return_focus.grab_focus()


func _ask_quit() -> void:
	_quit_dialog.popup_centered()
	_quit_dialog.get_cancel_button().grab_focus()
