extends Node
## Main menu (DESIGN.md §16): a slowly panning dusk scene with ambient music, the title top-left,
## the main buttons stacked on the left, the profile top-right (faction, "LEVEL 10 · 36,250 / 39,500
## XP" with a thin bar toward the next level, money) and Settings bottom-right.
## Each button opens a screen on top of the menu; screens emit `closed` when the player backs out.
## On first launch the player picks a faction, which creates the profile. After a raid's summary it
## opens straight on the hideout (GameState.menu_return). Insured items on their way back (Insurance)
## show a countdown under the profile and arrive in the stash when due, whatever screen is open (the
## stash views redraw; a notice over the screen says what came back).

const RAID_SETUP_SCENE := preload("res://ui/raid_setup.tscn")
const CHARACTER_SCENE := preload("res://ui/character_screen.tscn")
const HIDEOUT_SCENE := preload("res://ui/hideout_screen.tscn")
const TRADERS_SCENE := preload("res://ui/traders_screen.tscn")
const SETTINGS_SCENE := preload("res://ui/settings_menu.tscn")
const MUSIC_FADE_IN := 3.0
## Seconds "Bulat returned 2 insured items to your stash" stays up.
const ARRIVAL_TIME := 8.0

var _return_focus: Control
## Insurance returns: the countdown / arrival line under the profile, checked every second.
var _insurance_label: Label
var _insurance_timer: Timer
var _arrival_text := ""
var _arrival_left := 0.0
## The same arrival line over an open screen, top centre.
var _notice: PanelContainer

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
	_insurance_label = Label.new()
	_insurance_label.name = "InsuranceLabel"
	_insurance_label.theme_type_variation = &"DimLabel"
	_insurance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	%MoneyLabel.add_sibling(_insurance_label)
	_notice = PanelContainer.new()
	_notice.name = "InsuranceNotice"
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.add_child(Label.new())
	_notice.hide()
	_host.add_sibling(_notice)  # Over the screens, under the dialogs.
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_insurance_timer = Timer.new()
	_insurance_timer.wait_time = 1.0
	_insurance_timer.timeout.connect(_check_insurance.bind(1.0))
	add_child(_insurance_timer)
	_insurance_timer.start()
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
	_check_insurance(0.0)
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
	%LevelLabel.text = "LEVEL %d   ·   %s" % [GameState.level, Progression.xp_text(GameState.xp, GameState.level)] if has_profile else ""
	%XpBar.value = Progression.level_progress(GameState.xp, GameState.level) * 100.0
	%XpBar.visible = has_profile
	%MoneyLabel.text = "%s      %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")] if has_profile else ""


## Delivers insurance returns that are due, on time whatever screen is open (grid views redraw when
## the stash changes, and a drag only moves its item when dropped), and updates the line under the
## profile: "Bulat returned 2 insured items to your stash" for a while (also over an open screen),
## else "Insurance returns in 1:42".
func _check_insurance(delta: float) -> void:
	if GameState.faction == GameState.Faction.NONE:
		_insurance_label.text = ""
		return
	if not GameState.insurance_pending.is_empty():
		var arrived := Insurance.deliver_due()
		if not arrived.is_empty():
			SaveManager.save_game()
			_arrival_text = Insurance.arrival_text(arrived)
			_arrival_left = ARRIVAL_TIME
			UiSounds.play_click()
	_arrival_left -= delta
	_notice.visible = _arrival_left > 0.0 and _host.get_child_count() > 0
	(_notice.get_child(0) as Label).text = _arrival_text
	var countdown := Insurance.countdown_text()
	if _arrival_left > 0.0:
		_insurance_label.text = _arrival_text
	elif countdown != "":
		_insurance_label.text = "Insurance returns in %s" % countdown if Insurance.next_due() > 0.0 else "Insurance returns waiting for room in the stash"
	else:
		_insurance_label.text = ""


func _open(scene: PackedScene, from: Control) -> void:
	_return_focus = from
	_menu.hide()
	var screen := scene.instantiate()
	screen.closed.connect(_on_screen_closed)
	_host.add_child(screen)


func _on_screen_closed() -> void:
	_menu.show()
	_check_insurance(0.0)
	_notice.hide()  # The line under the profile has it now.
	_refresh_profile()
	_return_focus.grab_focus()


func _ask_quit() -> void:
	_quit_dialog.popup_centered()
	_quit_dialog.get_cancel_button().grab_focus()
