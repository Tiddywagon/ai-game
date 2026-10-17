extends Node
## Autoload "InputHub" (DESIGN.md §17.1): one input system for keyboard and mouse, controllers and
## touch at the same time. Every action goes through Godot's InputMap (touch controls press the same
## actions), so gameplay code never asks which device it came from. This tracks the device used last
## (`device`, `device_changed`) and the controller family (Xbox, PlayStation, Nintendo or generic) so
## on-screen prompts show keys, face buttons or touch buttons (label(), prompt()); plays vibration and
## haptics (pulse()); and has the per-device stick settings, aim assist strength, whether touch controls
## are on, the screen's safe area (notches) and whether it's a phone.

## The device used last changed (prompts switch).
signal device_changed(device: Device)
## The screen's safe area changed (the phone was turned round): controls fitted to it are refitted.
signal safe_area_changed

enum Device { KEYBOARD_MOUSE, CONTROLLER, TOUCH }

## A stick or trigger counts as "used" past this (so a resting stick doesn't steal the prompts).
const AXIS_USE := 0.5
## Mouse motion shorter than this (pixels) doesn't count (a bumped desk).
const MOUSE_USE := 3.0
## Aim assist strength on touch, when it's on (light; controllers have their own slider).
const TOUCH_AIM_ASSIST := 0.35
## Below this screen diagonal (inches) a touch screen is a phone: bigger buttons and text.
const PHONE_INCHES := 7.5
## Seconds between checks of the safe area on phones and tablets.
const SAFE_AREA_CHECK := 0.5

## Controller button names by family, by SDL button index; triggers are axes 4 (left) and 5 (right).
const PAD_NAMES := {
	"xbox": ["A", "B", "X", "Y", "View", "Xbox", "Menu", "LS", "RS", "LB", "RB", "D-pad up", "D-pad down", "D-pad left", "D-pad right"],
	"playstation": ["Cross", "Circle", "Square", "Triangle", "Create", "PS", "Options", "L3", "R3", "L1", "R1", "D-pad up", "D-pad down", "D-pad left", "D-pad right"],
	"nintendo": ["B", "A", "Y", "X", "-", "Home", "+", "LS", "RS", "L", "R", "D-pad up", "D-pad down", "D-pad left", "D-pad right"],
}
const TRIGGER_NAMES := {"xbox": ["LT", "RT"], "playstation": ["L2", "R2"], "nintendo": ["ZL", "ZR"]}
## Touch buttons' names, by action (what a prompt says when you play by touch).
const TOUCH_NAMES := {
	"shoot": "Fire", "aim": "Aim", "reload": "Reload", "roll": "Roll", "crouch": "Crouch", "interact": "Interact",
	"melee": "Melee", "use_item": "Quick item", "toggle_inventory": "Inventory", "map_view": "Map",
	"hotkey_wheel": "Hotkeys", "hotkey_1": "Hotkeys", "hotkey_2": "Hotkeys", "hotkey_3": "Hotkeys", "hotkey_4": "Hotkeys",
	"hotkey_5": "Hotkeys", "flashlight": "Hotkeys", "binoculars": "Hotkeys", "show_extracts": "Hotkeys",
	"take_cover": "Cover", "pause": "Menu", "sprint": "Move stick (push all the way)",
}
## Actions on the hotkey wheel: a controller reaches them there when they have no button of their own.
const WHEEL_ACTIONS := ["hotkey_1", "hotkey_2", "hotkey_3", "hotkey_4", "hotkey_5", "flashlight", "binoculars", "show_extracts"]
## Vibration and haptics: kind -> [weak motor, strong motor, seconds, phone vibration ms].
const PULSES := {
	"hit": [0.25, 0.0, 0.07, 18],
	"damage": [0.55, 0.85, 0.22, 70],
	"extract": [0.45, 0.45, 0.6, 260],
	"melee": [0.35, 0.55, 0.12, 30],
	"parry": [0.6, 0.3, 0.15, 40],
}

var device := Device.KEYBOARD_MOUSE
## The controller used last (-1 for none) and its family.
var joypad := -1
var family := "xbox"
## The last vibration or haptic pulse asked for: {"kind", "device", "weak", "strong", "seconds", "ms"}
## (played or not: "played").
var last_pulse := {}
## Controls kept inside the safe area: [weak reference, how ("fit", "pad" or "nudge")], and the
## margins they were fitted to.
var _safe_controls: Array = []
var _safe_margins := {}
var _safe_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile") and DisplayServer.is_touchscreen_available():
		device = Device.TOUCH
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		joypad = pads[0]
		family = family_of(joypad)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	set_process(OS.has_feature("mobile"))


## On phones and tablets: refits everything to the safe area when it changes.
func _process(delta: float) -> void:
	_safe_timer -= delta
	if _safe_timer > 0.0:
		return
	_safe_timer = SAFE_AREA_CHECK
	var margins := safe_margins(get_viewport())
	if margins == _safe_margins:
		return
	_safe_margins = margins
	for watched: Array in _safe_controls.duplicate():
		var control := (watched[0] as WeakRef).get_ref() as Control
		if control == null:
			_safe_controls.erase(watched)
			continue
		match watched[1]:
			"pad":
				pad_to_safe_area(control)
			"nudge":
				nudge_to_safe_area(control)
			_:
				fit_to_safe_area(control)
	safe_area_changed.emit()


func _input(event: InputEvent) -> void:
	var used := -1
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		used = Device.TOUCH
	elif event is InputEventKey and event.pressed:
		used = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		used = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and event.relative.length() >= MOUSE_USE:
		used = Device.KEYBOARD_MOUSE
	elif event is InputEventJoypadButton and event.pressed:
		used = Device.CONTROLLER
		joypad = event.device
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= AXIS_USE:
		used = Device.CONTROLLER
		joypad = event.device
	if used >= 0:
		set_device(used)


func set_device(used: Device) -> void:
	if used == Device.CONTROLLER and joypad >= 0:
		family = family_of(joypad)
	if used == device:
		return
	device = used
	device_changed.emit(device)


func is_controller() -> bool:
	return device == Device.CONTROLLER


func is_touch() -> bool:
	return device == Device.TOUCH


## "xbox", "playstation", "nintendo" or "generic", from the controller's name.
static func family_of(pad: int) -> String:
	var name := Input.get_joy_name(pad).to_lower()
	for hint in ["playstation", "dualshock", "dualsense", "ps4", "ps5", "sony", "ps3"]:
		if hint in name:
			return "playstation"
	for hint in ["nintendo", "switch", "pro controller", "joy-con"]:
		if hint in name:
			return "nintendo"
	for hint in ["xbox", "xinput", "x-box", "microsoft"]:
		if hint in name:
			return "xbox"
	return "generic"


func _on_joy_connection_changed(pad: int, connected: bool) -> void:
	if connected:
		joypad = pad
		family = family_of(pad)
	elif pad == joypad:
		var pads := Input.get_connected_joypads()
		joypad = pads[0] if not pads.is_empty() else -1
		if device == Device.CONTROLLER and joypad < 0:
			set_device(Device.TOUCH if touch_controls_enabled() and DisplayServer.is_touchscreen_available() else Device.KEYBOARD_MOUSE)


# --- Prompts -------------------------------------------------------------------------------------

## What to call the input for `action` on the device used last: "F" or "Left mouse", "A" / "Cross" /
## "RT", or the touch button ("Interact").
func label(action: String, on := -1) -> String:
	match device if on < 0 else on:
		Device.CONTROLLER:
			var padbinds: Dictionary = Settings.values.get("padbinds", {})
			var code := Settings.pad_binding_of(action, padbinds)
			if code == "" and action == "map_view":
				return pad_label(Settings.pad_binding_of("hotkey_wheel", padbinds), family) + " (tap)"
			if code == "" and action in WHEEL_ACTIONS:
				return "Hotkey wheel"
			return pad_label(code, family)
		Device.TOUCH:
			return TOUCH_NAMES.get(action, action.capitalize())
	return Settings.keyboard_label(action)


## A controller binding code ("joy:0", "axis:5:+") as `pad_family` calls it ("A", "Cross", "RT"...).
static func pad_label(code: String, pad_family := "xbox") -> String:
	var parts := code.split(":")
	var names: Array = PAD_NAMES.get(pad_family, PAD_NAMES.xbox)
	if parts.size() >= 2 and parts[0] == "joy":
		var index := int(parts[1])
		return names[index] if index >= 0 and index < names.size() else "Button %d" % index
	if parts.size() == 3 and parts[0] == "axis":
		var triggers: Array = TRIGGER_NAMES.get(pad_family, TRIGGER_NAMES.xbox)
		match int(parts[1]):
			4:
				return triggers[0]
			5:
				return triggers[1]
		return "Stick"
	return "Unbound"


## What a prompt icon for `action` should draw: {"device", "text", "code" (controller binding),
## "family", "touch" (the touch button id)}.
func prompt(action: String) -> Dictionary:
	return {"device": device, "text": label(action), "code": Settings.pad_binding_of(action, Settings.values.get("padbinds", {})),
		"family": family, "touch": action}


# --- Vibration and haptics -----------------------------------------------------------------------

## A rumble on the controller or a vibration on the phone for `kind` ("hit", "damage", "extract",
## "melee", "parry"), if that's turned on for the device in use.
func pulse(kind: String) -> void:
	var spec: Array = PULSES.get(kind, PULSES.hit)
	var played := false
	if device == Device.CONTROLLER and joypad >= 0 and Settings.get_value("controls", "vibration"):
		Input.start_joy_vibration(joypad, spec[0], spec[1], spec[2])
		played = true
	elif device == Device.TOUCH and Settings.get_value("controls", "haptics"):
		Input.vibrate_handheld(int(spec[3]), clampf(spec[1] if spec[1] > 0.0 else spec[0], 0.1, 1.0))
		played = true
	last_pulse = {"kind": kind, "device": device, "weak": spec[0], "strong": spec[1], "seconds": spec[2], "ms": spec[3], "played": played}


# --- Sticks, aim assist, touch -------------------------------------------------------------------

## Reticle speed multiplier for stick aiming on the device in use (controller or touch).
func stick_sensitivity() -> float:
	return Settings.get_value("controls", "touch_sensitivity" if device == Device.TOUCH else "controller_sensitivity")


## How hard aim assist pulls the reticle onto targets (0 off): controllers by their slider, touch light.
func aim_assist_strength() -> float:
	match device:
		Device.CONTROLLER:
			return float(Settings.get_value("controls", "aim_assist_strength")) if Settings.get_value("controls", "controller_aim_assist") else 0.0
		Device.TOUCH:
			return TOUCH_AIM_ASSIST if Settings.get_value("controls", "touch_aim_assist") else 0.0
	return 0.0


## True when stick aiming (controller or touch) is in use at all.
func sticks_enabled() -> bool:
	return Settings.get_value("controls", "controller_enabled") or touch_controls_enabled()


## Touch controls on: "on", "off", or "auto" (only on a touch screen).
func touch_controls_enabled() -> bool:
	match str(Settings.get_value("controls", "touch_controls")):
		"on":
			return true
		"off":
			return false
	return DisplayServer.is_touchscreen_available()


## Whether the on-screen buttons show right now: touch controls on, and (in Auto) not while you're
## playing with a controller.
func touch_controls_visible() -> bool:
	if not touch_controls_enabled():
		return false
	return str(Settings.get_value("controls", "touch_controls")) == "on" or device != Device.CONTROLLER


# --- Screen ---------------------------------------------------------------------------------------

## The screen's safe area (notches, rounded corners, the home bar) as margins in `viewport`'s canvas
## units: {"left", "top", "right", "bottom"}. All 0 on desktops.
func safe_margins(viewport: Viewport) -> Dictionary:
	var margins := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if DisplayServer.get_name() == "headless" or not OS.has_feature("mobile"):
		return margins
	var window := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var canvas := viewport.get_visible_rect().size
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0:
		return margins
	var scale := canvas / Vector2(window)
	var screen_origin := DisplayServer.window_get_position()
	var local := Rect2(Vector2(safe.position - screen_origin) * scale, Vector2(safe.size) * scale)
	margins.left = maxf(local.position.x, 0.0)
	margins.top = maxf(local.position.y, 0.0)
	margins.right = maxf(canvas.x - local.end.x, 0.0)
	margins.bottom = maxf(canvas.y - local.end.y, 0.0)
	return margins


## Applies the safe area to a full-screen `control` (anchored to all four edges; others are left
## alone) through its offsets, so nothing sits under a notch. Refitted when the safe area changes.
func fit_to_safe_area(control: Control) -> void:
	if control == null or control.anchor_left != 0.0 or control.anchor_top != 0.0 or control.anchor_right != 1.0 \
			or control.anchor_bottom != 1.0:
		return
	_watch(control, "fit")
	var margins := safe_margins(control.get_viewport())
	control.offset_left = margins.left
	control.offset_top = margins.top
	control.offset_right = -margins.right
	control.offset_bottom = -margins.bottom


## Adds the safe area to a full-screen MarginContainer's own margins (a menu screen's content, so its
## dimmed background still fills the screen). Refitted when the safe area changes.
func pad_to_safe_area(container: MarginContainer) -> void:
	if container == null:
		return
	_watch(container, "pad")
	var margins := safe_margins(container.get_viewport())
	for side: String in margins:
		var key := "margin_" + side
		if not container.has_meta(key):
			container.set_meta(key, container.get_theme_constant(key))
		container.add_theme_constant_override(key, int(container.get_meta(key)) + roundi(margins[side]))


## Moves a control anchored to screen edges or corners (a HUD panel) in from those edges by the safe
## area. Refitted when the safe area changes.
func nudge_to_safe_area(control: Control) -> void:
	if control == null:
		return
	_watch(control, "nudge")
	if not control.has_meta("safe_offsets"):
		control.set_meta("safe_offsets", [control.offset_left, control.offset_top, control.offset_right, control.offset_bottom])
	var base: Array = control.get_meta("safe_offsets")
	var margins := safe_margins(control.get_viewport())
	control.offset_left = base[0] + lerpf(margins.left, -margins.right, control.anchor_left)
	control.offset_top = base[1] + lerpf(margins.top, -margins.bottom, control.anchor_top)
	control.offset_right = base[2] + lerpf(margins.left, -margins.right, control.anchor_right)
	control.offset_bottom = base[3] + lerpf(margins.top, -margins.bottom, control.anchor_bottom)


func _watch(control: Control, how: String) -> void:
	for watched: Array in _safe_controls:
		if (watched[0] as WeakRef).get_ref() == control:
			return
	_safe_controls.append([weakref(control), how])


## True on a small touch screen (a phone rather than a tablet).
func is_phone() -> bool:
	if not DisplayServer.is_touchscreen_available() or DisplayServer.get_name() == "headless":
		return false
	var dpi := maxf(float(DisplayServer.screen_get_dpi()), 1.0)
	var size := Vector2(DisplayServer.screen_get_size())
	return size.length() / dpi < PHONE_INCHES


## The interface size multiplier for "Auto": bigger on phones.
func auto_ui_scale() -> float:
	return 1.25 if is_phone() else 1.0
