extends Node
## Autoload "Settings": every player option (DESIGN.md §17), saved to user://settings.cfg and applied
## to the engine. SCHEMA lists each option once (tab, default, type, choices); the settings menu is
## built from it. Code reads options with Settings.get_value("tab", "key") and listens to `applied`.

## Emitted after apply(), so HUDs, cameras and players can pick up new values.
signal applied

const PATH := "user://settings.cfg"
const TABS := ["graphics", "audio", "controls", "gameplay", "interface", "accessibility"]
const TAB_TITLES := ["Graphics", "Audio", "Controls", "Gameplay", "Interface", "Accessibility"]

## Remappable actions in Controls-tab order, with display names.
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"],
	["move_right", "Move right"], ["sprint", "Sprint"], ["crouch", "Crouch"], ["roll", "Combat roll"],
	["take_cover", "Take cover"], ["aim", "Aim / peek"], ["shoot", "Shoot"], ["reload", "Reload"],
	["interact", "Interact"], ["use_item", "Use item"], ["toggle_inventory", "Inventory"],
	["hotkey_1", "Hotkey 1"], ["hotkey_2", "Hotkey 2"], ["hotkey_3", "Hotkey 3"], ["hotkey_4", "Hotkey 4"],
	["hotkey_5", "Hotkey 5"], ["flashlight", "Flashlight"], ["binoculars", "Binoculars"],
]

## What each graphics quality preset sets.
const PRESETS := {
	"low": {"shadows": "low", "textures": "low", "anti_aliasing": "off", "ambient_occlusion": false,
		"bloom": false, "view_distance": "low", "dof_quality": "off"},
	"medium": {"shadows": "medium", "textures": "medium", "anti_aliasing": "fxaa", "ambient_occlusion": false,
		"bloom": true, "view_distance": "medium", "dof_quality": "low"},
	"high": {"shadows": "high", "textures": "high", "anti_aliasing": "msaa", "ambient_occlusion": true,
		"bloom": true, "view_distance": "high", "dof_quality": "medium"},
	"ultra": {"shadows": "ultra", "textures": "ultra", "anti_aliasing": "taa", "ambient_occlusion": true,
		"bloom": true, "view_distance": "ultra", "dof_quality": "high"},
}

const LEVELS_4 := [["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra"]]

## Every option. "choice" options list [value, label] pairs ("dynamic" ones are filled in at runtime);
## "slider" options have min/max/step and a display format; "note" is shown under the option.
const SCHEMA := {
	"graphics": [
		{"key": "display_mode", "label": "Display mode", "type": "choice", "default": "windowed",
			"options": [["windowed", "Windowed"], ["borderless", "Borderless"], ["fullscreen", "Fullscreen"]]},
		{"key": "resolution", "label": "Resolution", "type": "choice", "default": "1920x1080", "options": "dynamic",
			"note": "Windowed mode. Borderless and fullscreen use the monitor's resolution: lower Render scale instead."},
		{"key": "monitor", "label": "Monitor", "type": "choice", "default": 0, "options": "dynamic"},
		{"key": "vsync", "label": "V-Sync", "type": "toggle", "default": true},
		{"key": "fps_limit", "label": "FPS limit", "type": "choice", "default": 0,
			"options": [[30, "30"], [60, "60"], [120, "120"], [144, "144"], [240, "240"], [0, "Unlimited"]]},
		{"key": "render_scale", "label": "Render scale", "type": "slider", "default": 1.0,
			"min": 0.5, "max": 1.5, "step": 0.05, "format": "percent",
			"note": "Resolution of the 3D scene; the interface stays sharp."},
		{"key": "preset", "label": "Quality preset", "type": "choice", "default": "high",
			"options": [["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra"], ["custom", "Custom"]],
			"note": "Sets the options below. Changing one of them switches to Custom."},
		{"key": "shadows", "label": "Shadows", "type": "choice", "default": "high",
			"options": [["off", "Off"], ["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra"]]},
		{"key": "textures", "label": "Textures", "type": "choice", "default": "high", "options": LEVELS_4},
		{"key": "anti_aliasing", "label": "Anti-aliasing", "type": "choice", "default": "msaa",
			"options": [["off", "Off"], ["fxaa", "FXAA"], ["msaa", "MSAA 4x"], ["taa", "TAA"]],
			"note": "TAA needs the Forward+ renderer."},
		{"key": "ambient_occlusion", "label": "Ambient occlusion", "type": "toggle", "default": true,
			"note": "Needs the Forward+ renderer."},
		{"key": "bloom", "label": "Bloom", "type": "toggle", "default": true},
		{"key": "motion_blur", "label": "Motion blur", "type": "toggle", "default": false,
			"note": "Not available yet: Godot has no built-in motion blur. Saved for when it's added."},
		{"key": "view_distance", "label": "View distance", "type": "choice", "default": "high", "options": LEVELS_4},
		{"key": "dof_quality", "label": "Depth of field quality", "type": "choice", "default": "medium",
			"options": [["off", "Off"], ["low", "Low"], ["medium", "Medium"], ["high", "High"]],
			"note": "Blur on out-of-focus areas, such as the main menu background."},
		{"key": "brightness", "label": "Brightness", "type": "slider", "default": 1.0,
			"min": 0.5, "max": 1.5, "step": 0.05, "format": "percent"},
		{"key": "gamma", "label": "Gamma", "type": "slider", "default": 1.0,
			"min": 0.6, "max": 1.6, "step": 0.05, "format": "decimal"},
	],
	"audio": [
		{"key": "master", "label": "Master volume", "type": "slider", "default": 0.8, "min": 0.0, "max": 1.0, "step": 0.01, "format": "percent"},
		{"key": "music", "label": "Music", "type": "slider", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01, "format": "percent"},
		{"key": "effects", "label": "Effects", "type": "slider", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01, "format": "percent"},
		{"key": "voice", "label": "Voice", "type": "slider", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01, "format": "percent"},
		{"key": "ui", "label": "Interface", "type": "slider", "default": 0.7, "min": 0.0, "max": 1.0, "step": 0.01, "format": "percent"},
		{"key": "ambient", "label": "Ambient", "type": "slider", "default": 0.8, "min": 0.0, "max": 1.0, "step": 0.01, "format": "percent"},
		{"key": "output_device", "label": "Output device", "type": "choice", "default": "Default", "options": "dynamic"},
		{"key": "mute_unfocused", "label": "Mute when the window loses focus", "type": "toggle", "default": true},
	],
	"controls": [
		{"key": "mouse_sensitivity", "label": "Mouse sensitivity", "type": "slider", "default": 1.0,
			"min": 0.1, "max": 3.0, "step": 0.05, "format": "decimal",
			"note": "Speed of the in-raid aiming reticle."},
		{"key": "aim_sensitivity", "label": "Aim (optics) sensitivity", "type": "slider", "default": 0.6,
			"min": 0.1, "max": 2.0, "step": 0.05, "format": "decimal",
			"note": "Reticle speed while aiming or peeking."},
		{"key": "invert_mouse", "label": "Invert mouse (vertical)", "type": "toggle", "default": false},
		{"key": "sprint_mode", "label": "Sprint", "type": "choice", "default": "hold", "options": [["hold", "Hold"], ["toggle", "Toggle"]]},
		{"key": "crouch_mode", "label": "Crouch", "type": "choice", "default": "toggle", "options": [["hold", "Hold"], ["toggle", "Toggle"]]},
		{"key": "aim_mode", "label": "Aim / peek", "type": "choice", "default": "hold", "options": [["hold", "Hold"], ["toggle", "Toggle"]]},
		{"key": "keybinds", "label": "Key bindings", "type": "keybinds"},
		{"key": "controller_enabled", "label": "Controller", "type": "toggle", "default": true,
			"note": "Left stick moves, right stick aims, triggers aim and shoot, A rolls, B crouches, LB takes cover, Start pauses."},
		{"key": "controller_sensitivity", "label": "Controller sensitivity", "type": "slider", "default": 1.0,
			"min": 0.2, "max": 3.0, "step": 0.05, "format": "decimal"},
		{"key": "controller_dead_zone", "label": "Stick dead zone", "type": "slider", "default": 0.2,
			"min": 0.05, "max": 0.5, "step": 0.01, "format": "percent"},
	],
	"gameplay": [
		{"key": "camera_shake", "label": "Camera shake", "type": "slider", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05, "format": "percent"},
		{"key": "damage_numbers", "label": "Show damage numbers", "type": "toggle", "default": false},
		{"key": "hit_markers", "label": "Hit markers", "type": "toggle", "default": true},
		{"key": "auto_reload", "label": "Auto-reload", "type": "toggle", "default": true,
			"note": "Reload by pulling the trigger on an empty magazine."},
		{"key": "auto_equip", "label": "Auto-equip on pickup", "type": "toggle", "default": true,
			"note": "Takes effect once looting is in the game."},
		{"key": "confirm_sell_valuables", "label": "Confirm before selling valuables", "type": "toggle", "default": true,
			"note": "Takes effect once trading is in the game."},
		{"key": "language", "label": "Language", "type": "choice", "default": "en", "options": [["en", "English"]],
			"note": "More languages once the text is translated."},
		{"key": "units", "label": "Units", "type": "choice", "default": "metric",
			"options": [["metric", "Metric (m, kg)"], ["imperial", "Imperial (ft, lb)"]]},
	],
	"interface": [
		{"key": "hud_scale", "label": "HUD scale", "type": "slider", "default": 1.0, "min": 0.75, "max": 1.5, "step": 0.05, "format": "percent"},
		{"key": "hud_opacity", "label": "HUD opacity", "type": "slider", "default": 1.0, "min": 0.3, "max": 1.0, "step": 0.05, "format": "percent"},
		{"key": "show_fps", "label": "Show FPS counter", "type": "toggle", "default": false},
		{"key": "reticle_style", "label": "Reticle", "type": "choice", "default": "bloom",
			"options": [["dot", "Dot"], ["cross", "Cross"], ["circle", "Circle"], ["bloom", "Bloom (circle shows your spread)"]]},
		{"key": "reticle_color", "label": "Reticle color", "type": "choice", "default": "white",
			"options": [["white", "White"], ["green", "Green"], ["yellow", "Yellow"], ["cyan", "Cyan"], ["red", "Red"], ["magenta", "Magenta"]]},
		{"key": "colorblind_mode", "label": "Colorblind mode", "type": "choice", "default": "none",
			"options": [["none", "Off"], ["protanopia", "Protanopia"], ["deuteranopia", "Deuteranopia"], ["tritanopia", "Tritanopia"]],
			"note": "Adjusts the whole picture and switches rarity colors to a palette that stays distinct."},
		{"key": "subtitles", "label": "Subtitles", "type": "toggle", "default": true,
			"note": "For voice lines once the game has them."},
		{"key": "subtitle_size", "label": "Subtitle size", "type": "choice", "default": "medium",
			"options": [["small", "Small"], ["medium", "Medium"], ["large", "Large"]]},
	],
	"accessibility": [
		{"key": "reduce_flashing", "label": "Reduce flashing effects", "type": "toggle", "default": false,
			"note": "Dimmer tracers, a smaller muzzle flash without light, and no flashing hit markers."},
		{"key": "screen_shake_off", "label": "Turn off screen shake", "type": "toggle", "default": false,
			"note": "Overrides the Camera shake slider."},
		{"key": "high_contrast_outlines", "label": "High-contrast outlines", "type": "toggle", "default": false,
			"note": "Bright outlines on enemies now, and on items once they can lie on the ground."},
		{"key": "hold_alternatives", "label": "Press instead of hold", "type": "toggle", "default": false,
			"note": "Sprint, crouch and aim all become press-to-toggle, whatever the Controls tab says."},
	],
}

const BUS_FOR_SLIDER := {"master": "Master", "music": "Music", "effects": "Effects", "voice": "Voice", "ui": "UI", "ambient": "Ambient"}
const SHADOW_ATLAS := {"off": 1024, "low": 1024, "medium": 2048, "high": 4096, "ultra": 8192}
const SHADOW_FILTER := {
	"off": RenderingServer.SHADOW_QUALITY_HARD, "low": RenderingServer.SHADOW_QUALITY_HARD,
	"medium": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "high": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	"ultra": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
}
const MIPMAP_BIAS := {"low": 1.0, "medium": 0.5, "high": 0.0, "ultra": 0.0}
const ANISOTROPY := {
	"low": Viewport.ANISOTROPY_2X, "medium": Viewport.ANISOTROPY_4X,
	"high": Viewport.ANISOTROPY_8X, "ultra": Viewport.ANISOTROPY_16X,
}
const VIEW_DISTANCE := {"low": 60.0, "medium": 100.0, "high": 160.0, "ultra": 300.0}
const DOF_QUALITY := {
	"low": RenderingServer.DOF_BLUR_QUALITY_VERY_LOW, "medium": RenderingServer.DOF_BLUR_QUALITY_LOW,
	"high": RenderingServer.DOF_BLUR_QUALITY_HIGH,
}
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const RETICLE_COLORS := {
	"white": Color(1, 1, 1), "green": Color(0.35, 1, 0.45), "yellow": Color(1, 0.9, 0.3),
	"cyan": Color(0.3, 0.95, 1), "red": Color(1, 0.3, 0.3), "magenta": Color(1, 0.35, 0.95),
}
const COLORBLIND_INDEX := {"none": 0, "protanopia": 1, "deuteranopia": 2, "tritanopia": 3}
const SUBTITLE_SIZES := {"small": 22, "medium": 28, "large": 36}

## Current, applied values: values[tab][key]. Keybind overrides live in values["keybinds"].
var values := {}

var _default_bindings := {}  # action -> binding code ("key:87", "mouse:2") from project.godot
var _overlay: CanvasLayer
var _filter: ColorRect
var _fps_label: Label
var _subtitle_label: Label
var _focused := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for pair in REBINDABLE:
		_default_bindings[pair[0]] = _first_binding(pair[0])
	_build_overlay()
	values = load_settings()
	get_tree().node_added.connect(_apply_to_node)
	apply(values)


func _process(_delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_apply_master_mute()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_apply_master_mute()


# --- Reading ------------------------------------------------------------------------------

func get_value(tab: String, key: String) -> Variant:
	return values[tab][key]


## A fresh copy of every default value, keybinds included (empty: no overrides).
func defaults() -> Dictionary:
	var result := {"keybinds": {}}
	for tab: String in SCHEMA:
		result[tab] = {}
		for entry: Dictionary in SCHEMA[tab]:
			if entry.has("default"):
				result[tab][entry.key] = entry.default
	return result


func schema_entry(tab: String, key: String) -> Dictionary:
	for entry: Dictionary in SCHEMA[tab]:
		if entry.key == key:
			return entry
	return {}


## [value, label] pairs for a choice option, including the runtime ones (resolutions, monitors, devices).
func choices(tab: String, key: String) -> Array:
	var options: Variant = schema_entry(tab, key).get("options", [])
	if options is Array:
		return options
	match key:
		"resolution":
			var screen := DisplayServer.screen_get_size(clampi(int(values.get("graphics", {}).get("monitor", 0)), 0, DisplayServer.get_screen_count() - 1))
			var list := []
			for res: String in RESOLUTIONS:
				var size := _parse_resolution(res)
				if screen == Vector2i.ZERO or (size.x <= screen.x and size.y <= screen.y):
					list.append([res, res.replace("x", " × ")])
			return list if not list.is_empty() else [["1280x720", "1280 × 720"]]
		"monitor":
			var list := []
			for i in DisplayServer.get_screen_count():
				var size := DisplayServer.screen_get_size(i)
				list.append([i, "Monitor %d (%d × %d)" % [i + 1, size.x, size.y]])
			return list
		"output_device":
			return Array(AudioServer.get_output_device_list()).map(func(device: String) -> Array: return [device, device])
	return []


## True if sprint / crouch / aim ("sprint_mode", "crouch_mode", "aim_mode") should toggle on press.
func is_toggle(mode_key: String) -> bool:
	return values.accessibility.hold_alternatives or values.controls[mode_key] == "toggle"


## Camera shake multiplier, 0 when shake is turned off in Accessibility.
func camera_shake_scale() -> float:
	return 0.0 if values.accessibility.screen_shake_off else float(values.gameplay.camera_shake)


func reticle_color() -> Color:
	return RETICLE_COLORS.get(values.interface.reticle_color, Color.WHITE)


func format_distance(metres: float) -> String:
	if values.gameplay.units == "imperial":
		return "%d ft" % roundi(metres * 3.28084)
	return "%d m" % roundi(metres)


func format_weight(kg: float) -> String:
	if values.gameplay.units == "imperial":
		return "%.1f lb" % (kg * 2.20462)
	return "%.1f kg" % kg


# --- Key bindings -------------------------------------------------------------------------

## Binding code for `action` given a set of overrides, e.g. "key:87" or "mouse:2".
func binding_of(action: String, keybinds: Dictionary) -> String:
	return keybinds.get(action, _default_bindings.get(action, ""))


func default_binding(action: String) -> String:
	return _default_bindings.get(action, "")


## Binding code for a key or mouse-button press, or "" if it can't be bound.
func code_from_event(event: InputEvent) -> String:
	if event is InputEventKey and event.physical_keycode != KEY_NONE:
		return "key:%d" % event.physical_keycode
	if event is InputEventKey and event.keycode != KEY_NONE:
		return "key:%d" % event.keycode
	if event is InputEventMouseButton and event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return "mouse:%d" % event.button_index
	return ""


func event_from_code(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var key := InputEventKey.new()
		key.physical_keycode = int(parts[1]) as Key
		return key
	if parts[0] == "mouse":
		var button := InputEventMouseButton.new()
		button.button_index = int(parts[1]) as MouseButton
		return button
	return null


## Readable name of a binding code, using the player's keyboard layout ("W", "Left mouse"...).
func binding_label(code: String) -> String:
	var parts := code.split(":")
	if parts.size() != 2:
		return "Unbound"
	if parts[0] == "mouse":
		return {"1": "Left mouse", "2": "Right mouse", "3": "Middle mouse", "8": "Mouse 4", "9": "Mouse 5"}.get(parts[1], "Mouse %s" % parts[1])
	var physical := int(parts[1]) as Key
	var on_layout := KEY_NONE
	if DisplayServer.get_name() != "headless":
		on_layout = DisplayServer.keyboard_get_keycode_from_physical(physical)
	return OS.get_keycode_string(on_layout if on_layout != KEY_NONE else physical)


## Readable name of the key currently bound to `action`, e.g. "R" for reload (for on-screen hints).
func key_label(action: String) -> String:
	return binding_label(binding_of(action, values.keybinds))


# --- Saving and applying ------------------------------------------------------------------

## Reads user://settings.cfg. Missing or invalid entries fall back to their defaults.
func load_settings() -> Dictionary:
	var result := defaults()
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return result
	for tab: String in SCHEMA:
		for entry: Dictionary in SCHEMA[tab]:
			if not entry.has("default") or not file.has_section_key(tab, entry.key):
				continue
			var saved: Variant = file.get_value(tab, entry.key)
			if _is_valid(entry, saved):
				result[tab][entry.key] = saved
	for pair in REBINDABLE:
		var saved: Variant = file.get_value("keybinds", pair[0], "")
		if saved is String and event_from_code(saved) != null:
			result.keybinds[pair[0]] = saved
	return result


func save_settings() -> void:
	var file := ConfigFile.new()
	for tab: String in SCHEMA:
		for key: String in values[tab]:
			file.set_value(tab, key, values[tab][key])
	for action: String in values.keybinds:
		file.set_value("keybinds", action, values.keybinds[action])
	var err := file.save(PATH)
	if err != OK:
		push_error("Settings: can't save %s (%s)" % [PATH, error_string(err)])


## Makes `new_values` the current settings and applies them everywhere.
func apply(new_values: Dictionary) -> void:
	values = new_values.duplicate(true)
	_apply_graphics()
	_apply_audio()
	_apply_controls()
	_apply_interface()
	TranslationServer.set_locale(values.gameplay.language)
	for node in get_tree().root.find_children("*", "", true, false):
		_apply_to_node(node)
	applied.emit()


func _is_valid(entry: Dictionary, value: Variant) -> bool:
	match entry.type:
		"toggle":
			return value is bool
		"slider":
			return (value is float or value is int) and value >= entry.min and value <= entry.max
		"choice":
			if typeof(value) != typeof(entry.default):
				return false
			if entry.options is String:
				return true  # Runtime lists (monitors, devices) are checked when applied.
			return entry.options.any(func(option: Array) -> bool: return option[0] == value)
	return false


func _can_change_window() -> bool:
	return DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor()


func _apply_graphics() -> void:
	var g: Dictionary = values.graphics
	var root := get_tree().root
	if _can_change_window():
		var screen := clampi(int(g.monitor), 0, DisplayServer.get_screen_count() - 1)
		if DisplayServer.window_get_current_screen() != screen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_current_screen(screen)
		match g.display_mode:
			"fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			"borderless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			_:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var usable := DisplayServer.screen_get_usable_rect(screen)
				var size := _parse_resolution(g.resolution).min(usable.size)
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if g.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(g.fps_limit)
	root.scaling_3d_scale = g.render_scale
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if g.anti_aliasing == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	root.msaa_3d = Viewport.MSAA_4X if g.anti_aliasing == "msaa" else Viewport.MSAA_DISABLED
	root.use_taa = g.anti_aliasing == "taa"
	root.texture_mipmap_bias = MIPMAP_BIAS[g.textures]
	root.anisotropic_filtering_level = ANISOTROPY[g.textures]
	root.positional_shadow_atlas_size = SHADOW_ATLAS[g.shadows]
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[g.shadows], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER[g.shadows])
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTER[g.shadows])
	if g.dof_quality != "off":
		RenderingServer.camera_attributes_set_dof_blur_quality(DOF_QUALITY[g.dof_quality], true)
	var color_mode: int = COLORBLIND_INDEX[values.interface.colorblind_mode]
	var material := _filter.material as ShaderMaterial
	material.set_shader_parameter("brightness", g.brightness)
	material.set_shader_parameter("gamma", g.gamma)
	material.set_shader_parameter("colorblind_mode", color_mode)
	_filter.visible = not (is_equal_approx(g.brightness, 1.0) and is_equal_approx(g.gamma, 1.0) and color_mode == 0)


func _apply_audio() -> void:
	for key: String in BUS_FOR_SLIDER:
		var bus := AudioServer.get_bus_index(BUS_FOR_SLIDER[key])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(values.audio[key], 0.0001)))
	_apply_master_mute()
	var device: String = values.audio.output_device
	if device in AudioServer.get_output_device_list():
		AudioServer.output_device = device


func _apply_master_mute() -> void:
	if values.is_empty():
		return
	var muted: bool = values.audio.master <= 0.0 or (not _focused and values.audio.mute_unfocused)
	AudioServer.set_bus_mute(0, muted)


func _apply_controls() -> void:
	for pair in REBINDABLE:
		var action: String = pair[0]
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				InputMap.action_erase_event(action, event)
		var event := event_from_code(binding_of(action, values.keybinds))
		if event:
			InputMap.action_add_event(action, event)
	var dead_zone: float = values.controls.controller_dead_zone
	for action in ["move_forward", "move_back", "move_left", "move_right", "aim_left", "aim_right", "aim_up", "aim_down"]:
		InputMap.action_set_deadzone(action, dead_zone)


func _apply_interface() -> void:
	_fps_label.visible = values.interface.show_fps
	_subtitle_label.add_theme_font_size_override("font_size", SUBTITLE_SIZES[values.interface.subtitle_size])


## Settings that live on scene nodes: lights, environments, cameras. Runs for every node that
## enters the tree, so new levels pick them up too.
func _apply_to_node(node: Node) -> void:
	if values.is_empty():
		return
	var g: Dictionary = values.graphics
	var light := node as Light3D
	var world := node as WorldEnvironment
	var camera := node as Camera3D
	if light:
		# Only lights that were set up to cast shadows get them back when shadows are turned on.
		if not light.has_meta("_casts_shadows"):
			light.set_meta("_casts_shadows", light.shadow_enabled)
		light.shadow_enabled = light.get_meta("_casts_shadows") and g.shadows != "off"
	elif world and world.environment:
		world.environment.ssao_enabled = g.ambient_occlusion
		world.environment.glow_enabled = g.bloom
	elif camera:
		camera.far = VIEW_DISTANCE[g.view_distance]
		var attributes := camera.attributes as CameraAttributesPractical
		if attributes:
			if not camera.has_meta("_dof_far"):
				camera.set_meta("_dof_far", attributes.dof_blur_far_enabled)
			attributes.dof_blur_far_enabled = camera.get_meta("_dof_far") and g.dof_quality != "off"


func _first_binding(action: String) -> String:
	for event in InputMap.action_get_events(action):
		var code := code_from_event(event)
		if code != "":
			return code
	return ""


func _parse_resolution(text: String) -> Vector2i:
	var parts := text.split("x")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(1920, 1080)


## Screen-wide filter (brightness, gamma, colorblind correction), FPS counter and subtitle line,
## drawn above everything else.
func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 128
	add_child(_overlay)
	_filter = ColorRect.new()
	_filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/screen_filter.gdshader")
	_filter.material = material
	_overlay.add_child(_filter)
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 8)
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_overlay.add_child(_fps_label)
	_subtitle_label = Label.new()
	_subtitle_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.position.y -= 140
	_subtitle_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_subtitle_label.add_theme_constant_override("outline_size", 6)
	_overlay.add_child(_subtitle_label)


## Shows a subtitle line for `seconds` if subtitles are on (for voice lines, once there are any).
func show_subtitle(text: String, seconds := 3.0) -> void:
	if not values.interface.subtitles:
		return
	_subtitle_label.text = text
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func() -> void:
		if _subtitle_label.text == text:
			_subtitle_label.text = "")
