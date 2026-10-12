extends SceneTree
## Run under Xvfb: xvfb-run ... --fixed-fps 60 --rendering-driver opengl3 -s res://_menu_test.gd
## Uses no class names (test scripts compile before autoloads exist).

var fails := 0
var gs
var settings
var sounds


func _tank(actor) -> void:
	for part in 7:
		actor.health.hp[part] = 100000.0


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _action(action: String, pressed := true) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	root.push_input(e)


func _tap(action: String) -> void:
	_action(action, true)
	_action(action, false)


func _joy(button: int) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		root.push_input(e)


func _escape() -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_ESCAPE
		e.physical_keycode = KEY_ESCAPE
		e.pressed = pressed
		root.push_input(e)


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("/tmp/claude-0/-home-user-ai-game/05c27abf-2ac1-5871-9067-de052a7048f4/scratchpad/ui_%s.png" % name)


func _setting(tab: String, key: String, value) -> void:
	var values: Dictionary = settings.values.duplicate(true)
	values[tab][key] = value
	settings.apply(values)


func _run() -> void:
	gs = root.get_node("GameState")
	settings = root.get_node("Settings")
	sounds = root.get_node("UiSounds")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	settings.apply(settings.defaults())

	print("Main menu")
	change_scene_to_file("res://ui/main_menu.tscn")
	await _frames(30)
	var menu := current_scene
	check(menu.get_node("%FactionPicker").visible, "first launch asks for a faction")
	_shot("faction")
	check(_focus() == menu.get_node("%UsecButton"), "faction picker has keyboard focus")
	_tap("ui_left")
	await _frames(2)
	check(_focus() == menu.get_node("%BearButton"), "left arrow moves to BEAR")
	_joy(0)  # Controller A on BEAR.
	await _frames(5)
	check(gs.faction == 1 and not menu.get_node("%FactionPicker").visible, "controller A picks BEAR")
	check(menu.get_node("%FactionLabel").text == "BEAR" and menu.get_node("%LevelLabel").text == "LEVEL 1", "top-right shows faction and level")
	check(menu.get_node("%MoneyLabel").text.contains("500,000") and menu.get_node("%MoneyLabel").text.contains("$ 0"), "top-right shows roubles and dollars: " + menu.get_node("%MoneyLabel").text)
	var music: AudioStreamPlayer = menu.get_node("Music")
	check(music.playing and music.bus == &"Music" and music.stream.loop, "ambient music loops on the Music bus")
	await _frames(200)
	_shot("main_menu")
	check(_focus() == menu.get_node("%EnterRaidButton"), "ENTER RAID has focus")
	var enter: Button = menu.get_node("%EnterRaidButton")
	var character: Button = menu.get_node("%CharacterButton")
	check(enter.get_theme_font_size("font_size") > character.get_theme_font_size("font_size"), "ENTER RAID is the largest button")
	var hover_before: int = sounds._last_hover_ms
	_tap("ui_down")
	await _frames(15)
	var hideout: Button = menu.get_node("%HideoutButton")
	check(_focus() == hideout, "down arrow -> HIDEOUT")
	check(sounds._last_hover_ms > hover_before, "focus change plays the hover sound")
	check(hideout.get_theme_stylebox("normal").content_margin_left > 30.0, "focused button slides right (margin %.0f)" % hideout.get_theme_stylebox("normal").content_margin_left)
	check(hideout.get_theme_stylebox("normal").shadow_color.a > 0.2, "...and glows")
	_tap("ui_down")
	await _frames(3)
	check(_focus() == character, "down -> CHARACTER")
	_tap("ui_down")
	_tap("ui_down")
	await _frames(3)
	check(_focus() == menu.get_node("%QuitButton"), "down -> TRADERS -> QUIT")
	_tap("ui_down")
	await _frames(3)
	check(_focus() == menu.get_node("%SettingsButton"), "down from QUIT -> settings gear")
	_tap("ui_up")
	await _frames(2)
	_tap("ui_accept")
	await _frames(3)
	var quit_dialog: ConfirmationDialog = menu.get_node("%QuitDialog")
	check(quit_dialog.visible, "QUIT asks 'Are you sure?'")
	_shot("quit_dialog")
	quit_dialog.get_cancel_button().pressed.emit()
	await _frames(3)
	check(not quit_dialog.visible, "Cancel keeps the game running")

	print("Screens")
	for name in ["HideoutButton", "CharacterButton", "TradersButton", "SettingsButton"]:
		menu.get_node("%" + name).grab_focus()
		_tap("ui_accept")
		await _frames(10)
		var host: Control = menu.get_node("%ScreenHost")
		check(host.get_child_count() == 1 and not menu.get_node("%Menu").visible, "%s opens %s" % [name, host.get_child(0).name])
		_shot(host.get_child(0).name.to_snake_case())
		_joy(1)  # Controller B backs out.
		await _frames(5)
		check(host.get_child_count() == 0 and _focus() == menu.get_node("%" + name), "  controller B closes it and focus returns")
	menu.get_node("%CharacterButton").pressed.emit()
	await _frames(5)
	var stash = menu.get_node("%ScreenHost").get_child(0).get_node("%StashGrid")
	check(stash._get_tooltip(Vector2(30, 30)).begins_with("AK-74N"), "stash tooltip on the AK: " + stash._get_tooltip(Vector2(30, 30)).replace("\n", " | "))
	check(stash._get_tooltip(Vector2(30, 1000)) == "", "no tooltip on empty cells")
	menu.get_node("%ScreenHost").get_child(0).close()
	await _frames(3)

	print("Settings take effect")
	_setting("interface", "colorblind_mode", "deuteranopia")
	check(root.get_node("Settings")._filter.visible, "colorblind mode turns on the screen filter")
	var palette = load("res://scripts/ui/palette.gd")
	check(palette.rarity_color(1) == Color("56b4e9"), "...and switches Uncommon to the colorblind-safe blue")
	_setting("interface", "colorblind_mode", "none")
	check(not root.get_node("Settings")._filter.visible and palette.rarity_color(1) == Color("5fae5a"), "off again: filter hidden, green Uncommon")
	_setting("graphics", "brightness", 1.2)
	check(root.get_node("Settings")._filter.visible and is_equal_approx(root.get_node("Settings")._filter.material.get_shader_parameter("brightness"), 1.2), "brightness uses the filter")
	_setting("graphics", "brightness", 1.0)
	_setting("graphics", "fps_limit", 60)
	check(Engine.max_fps == 60, "FPS limit 60")
	_setting("graphics", "fps_limit", 0)
	_setting("graphics", "render_scale", 0.75)
	check(is_equal_approx(root.scaling_3d_scale, 0.75), "render scale 75%")
	_setting("graphics", "render_scale", 1.0)
	_setting("graphics", "anti_aliasing", "fxaa")
	check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA and root.msaa_3d == Viewport.MSAA_DISABLED, "FXAA")
	_setting("graphics", "anti_aliasing", "msaa")
	check(root.msaa_3d == Viewport.MSAA_4X and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "MSAA 4x")
	var sun: DirectionalLight3D = menu.get_node("Backdrop/Sun")
	_setting("graphics", "shadows", "off")
	check(not sun.shadow_enabled, "shadows off turns light shadows off")
	_setting("graphics", "shadows", "high")
	check(sun.shadow_enabled, "...and back on")
	var env: Environment = menu.get_node("Backdrop/WorldEnvironment").environment
	_setting("graphics", "bloom", false)
	check(not env.glow_enabled, "bloom off")
	_setting("graphics", "bloom", true)
	var menu_camera: Camera3D = menu.get_node("Backdrop/Camera3D")
	_setting("graphics", "view_distance", "low")
	check(menu_camera.far == 60.0, "view distance low: camera far 60 m")
	_setting("graphics", "dof_quality", "off")
	check(not menu_camera.attributes.dof_blur_far_enabled, "depth of field off")
	settings.apply(settings.defaults())
	check(menu_camera.far == 160.0 and menu_camera.attributes.dof_blur_far_enabled, "defaults restore view distance and DoF")
	_setting("audio", "music", 0.0)
	check(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))) < 0.001, "music volume 0")
	_setting("audio", "music", 0.5)
	settings._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(AudioServer.is_bus_mute(0), "losing focus mutes")
	settings._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not AudioServer.is_bus_mute(0), "regaining focus unmutes")
	_setting("interface", "show_fps", true)
	await _frames(2)
	check(root.get_node("Settings")._fps_label.visible and root.get_node("Settings")._fps_label.text.ends_with("FPS"), "FPS counter")
	_setting("interface", "show_fps", false)
	_setting("graphics", "display_mode", "borderless")
	await _frames(5)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "borderless -> fullscreen window")
	_setting("graphics", "display_mode", "windowed")
	_setting("graphics", "resolution", "1280x720")
	await _frames(5)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_size() == Vector2i(1280, 720), "windowed 1280x720 (%s)" % DisplayServer.window_get_size())
	_setting("graphics", "resolution", "1920x1080")
	await _frames(5)

	print("Enter raid as a Scav")
	menu.get_node("%EnterRaidButton").grab_focus()
	_tap("ui_accept")
	await _frames(5)
	var setup = menu.get_node("%ScreenHost").get_child(0)
	_shot("raid_map")
	_tap("ui_down")
	await _frames(2)
	check(setup._map.id == "customs_yard" and setup.get_node("%NextButton").disabled, "arrowing down previews Customs Yard (in development)")
	_tap("ui_up")
	await _frames(2)
	setup.get_node("%NextButton").pressed.emit()
	await _frames(3)
	_shot("raid_side")
	setup.get_node("%ScavButton").pressed.emit()
	await _frames(3)
	check(setup._step == 2 and setup.get_node("%Checks").text.contains("Scav run"), "Scav -> loadout check explains the Scav run")
	_shot("raid_loadout")
	_joy(1)
	await _frames(2)
	check(setup._step == 1, "B steps back to PMC or Scav")
	setup.get_node("%ScavButton").pressed.emit()
	await _frames(2)
	setup.get_node("%NextButton").pressed.emit()
	await _frames(8)
	check(current_scene.name == "LoadingScreen", "READY -> loading screen")
	_shot("loading")
	await _frames(150)
	check(current_scene.name == "TestLevel", "-> raid")
	var level := current_scene
	var player = level.get_node("Player")
	check(player.side == 1, "playing as a Scav")
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse captured in raid")
	var scav = level.get_node("ScavEast")
	var pmc = level.get_node("PMC")
	check(not scav.is_hostile(player) and pmc.is_hostile(player), "AI Scavs friendly, AI PMC hostile")
	scav.take_hit(1.0, player, scav.chest_point())
	check(scav.is_hostile(player), "shoot a Scav and it turns hostile")
	check(level.get_node("HUD/%RaidInfo").text.begins_with("TEST YARD  ·  SCAV  ·  DAY  ·  CLEAR
") and level.get_node("HUD/%RaidInfo").text.contains("LEFT  ·  EXTRACT: NORTH-EAST GATE"), "HUD shows the raid, time, weather, time left and extract: " + level.get_node("HUD/%RaidInfo").text.replace("
", " | "))

	print("Reticle and controls")
	for bot in level.get_tree().get_nodes_in_group("bots"):
		bot.ai_enabled = false
	_tank(player)
	var start: Vector2 = player.cursor_position
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 40)
	root.push_input(motion)
	check(player.cursor_position.is_equal_approx(start + Vector2(100, 40)), "mouse moves the reticle 1:1 at sensitivity 1.0")
	_setting("controls", "mouse_sensitivity", 2.0)
	_setting("controls", "invert_mouse", true)
	start = player.cursor_position
	root.push_input(motion)
	check(player.cursor_position.is_equal_approx(start + Vector2(200, -80)), "sensitivity 2.0 + inverted Y")
	_setting("controls", "invert_mouse", false)
	_setting("controls", "mouse_sensitivity", 1.0)
	Input.action_press("aim")
	await _frames(2)
	start = player.cursor_position
	root.push_input(motion)
	check(player.cursor_position.is_equal_approx(start + Vector2(60, 24)), "aiming uses aim sensitivity 0.6")
	Input.action_release("aim")
	_setting("controls", "sprint_mode", "toggle")
	Input.action_press("move_right")
	_tap("sprint")
	await _frames(40)
	check(player.move_state == 2, "toggle sprint: one press keeps sprinting")
	Input.action_release("move_right")
	await _frames(20)
	Input.action_press("move_right")
	await _frames(20)
	check(player.move_state == 1, "...stopping ends it")
	Input.action_release("move_right")
	_setting("controls", "sprint_mode", "hold")
	_setting("controls", "crouch_mode", "hold")
	Input.action_press("crouch")
	await _frames(3)
	check(player.is_crouching, "hold crouch: crouched while held")
	Input.action_release("crouch")
	await _frames(3)
	check(not player.is_crouching, "...stands when released")
	_setting("controls", "crouch_mode", "toggle")
	_setting("accessibility", "hold_alternatives", true)
	check(settings.is_toggle("sprint_mode") and settings.is_toggle("aim_mode"), "'Press instead of hold' makes sprint and aim toggles")
	_setting("accessibility", "hold_alternatives", false)
	var cam = level.get_node("Camera3D")
	cam.add_shake(1.0)
	check(cam._shake > 0.9, "camera shake")
	cam._shake = 0.0
	_setting("accessibility", "screen_shake_off", true)
	cam.add_shake(1.0)
	check(cam._shake == 0.0, "'Turn off screen shake' wins over the slider")
	_setting("accessibility", "screen_shake_off", false)
	_setting("accessibility", "high_contrast_outlines", true)
	check(pmc.get_node("Body/Capsule").material_overlay != null, "high-contrast outline on enemies")
	_setting("accessibility", "high_contrast_outlines", false)
	check(pmc.get_node("Body/Capsule").material_overlay == null, "...and off")
	_setting("gameplay", "units", "imperial")
	await _frames(2)
	check(level.get_node("HUD/%MoveState").text.contains(" ft"), "imperial units on the HUD: " + level.get_node("HUD/%MoveState").text)
	_setting("gameplay", "units", "metric")
	_setting("interface", "hud_scale", 1.25)
	_setting("interface", "hud_opacity", 0.5)
	check(level.get_node("HUD/%BottomLeft").scale == Vector2(1.25, 1.25) and is_equal_approx(level.get_node("HUD/%HudRoot").modulate.a, 0.5), "HUD scale and opacity")
	_setting("interface", "hud_scale", 1.0)
	_setting("interface", "hud_opacity", 1.0)

	print("Hit markers and damage numbers")
	_setting("gameplay", "damage_numbers", true)
	player.global_position = Vector3(-2, 0, 6)
	player.reset_physics_interpolation()
	pmc.global_position = Vector3(-2, 0, 0)
	pmc.reset_physics_interpolation()
	await _frames(5)
	var ballistics = load("res://scripts/combat/ballistics.gd")
	var labels_before := level.find_children("*", "Label3D", true, false).size()
	ballistics.fire(player, Vector3(-2, 1.3, 6), Vector3.FORWARD, player.weapon.ammo, Vector3(-2, 1.3, 5.5))
	check(level.get_node("HUD/%Reticle")._hit_time > 0.0, "hit marker on a hit")
	check(level.find_children("*", "Label3D", true, false).size() == labels_before + 1, "damage number pops up")
	_setting("gameplay", "damage_numbers", false)
	_setting("accessibility", "reduce_flashing", true)
	ballistics.fire(player, Vector3(-2, 1.3, 6), Vector3.FORWARD, player.weapon.ammo, Vector3(-2, 1.3, 5.5))
	var tracers := level.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh is BoxMesh and m.mesh.size.x < 0.05)
	check(not tracers.is_empty(), "reduce flashing: thin dim tracers")
	_setting("accessibility", "reduce_flashing", false)
	player.cursor_position = cam.unproject_position(pmc.chest_point())
	await _frames(15)
	_shot("raid_hud")

	print("Pause menu")
	_escape()
	await _frames(3)
	var pause = level.get_node("PauseMenu")
	check(pause.visible and paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Esc pauses and frees the mouse")
	check(_focus() == pause.get_node("%ResumeButton"), "RESUME has focus")
	_shot("pause")
	pause.get_node("%SettingsButton").pressed.emit()
	await _frames(5)
	var host: Control = pause.get_node("%ScreenHost")
	check(host.get_child_count() == 1, "Settings opens from the pause menu")
	_tap("ui_tab_next")
	await _frames(2)
	check(host.get_child(0).get_node("%Tabs").current_tab == 1, "E / RB switches to the Audio tab")
	_tap("ui_tab_next")
	await _frames(3)
	_shot("settings_controls")
	_escape()
	await _frames(3)
	check(host.get_child_count() == 0 and pause.visible and paused, "Esc closes Settings, still paused")
	_escape()
	await _frames(3)
	check(not pause.visible and not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Esc again resumes and recaptures the mouse")
	_tap("pause")
	await _frames(2)
	pause.get_node("%LeaveButton").pressed.emit()
	await _frames(2)
	check(pause.get_node("%LeaveDialog").visible, "LEAVE RAID asks first")
	pause.get_node("%LeaveDialog").get_ok_button().pressed.emit()
	await _frames(10)
	check(current_scene.name == "MainMenu" and not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "back at the main menu, unpaused, mouse free")

	print("\n%s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	quit(1 if fails else 0)
