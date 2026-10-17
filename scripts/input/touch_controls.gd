class_name TouchControls
extends CanvasLayer
## In-raid touch controls (DESIGN.md §17.1). Everything presses InputMap actions (parsed
## InputEventActions, with strength for the sticks), so the player can't tell them from a keyboard or a
## controller. Multi-touch: every finger is tracked on its own.
## - A floating move stick: touch anywhere on the left half (off a button) and it appears under your
##   finger; push all the way to sprint.
## - An aim stick on the right: it points the reticle like a controller's right stick (spin it a full
##   circle for a 360 trick shot) and fires while pushed past its outer ring, or, with "Separate Fire
##   button" in Settings, a Fire button does.
## - Buttons: Aim, Reload, Roll, Crouch, Melee (hold: parry), Quick item, Hotkeys (the radial wheel),
##   Inventory, Map, Menu.
## - Context buttons, only when needed: Interact (near loot, a body, a door, a switch: it says what it
##   would do), Extract (in an extract zone: pays or fires the flare if that's what it needs, otherwise
##   shows your extracts), Cover (next to cover, or in it).
## Places, sizes and opacity come from the active touch layout (Settings, TouchLayout). Hidden when touch
## controls are off, while a menu, the inventory or the map is open, and when you're dead. While they're
## up, touches aren't turned into mouse clicks (those would fire).

const FIRE_RING := 0.88
const SPRINT_PUSH := 0.95
## The move stick appears for touches on this share of the screen from the left.
const MOVE_ZONE := 0.5
## The aim stick takes touches this many of its radii from its centre.
const AIM_GRAB := 1.5
## Analog changes smaller than this aren't sent again.
const ANALOG_STEP := 0.02
## Seconds between checks for which context buttons are needed.
const CONTEXT_INTERVAL := 0.15
const FILL := Color(0.06, 0.065, 0.07)
const EDGE := Color(0.9, 0.9, 0.86)
const PRESSED := Color(0.95, 0.75, 0.3)
const FIRE_COLOR := Color(0.95, 0.35, 0.3)
const CONTEXT_COLOR := Color(0.45, 0.95, 0.5)

var player: Player
var wheel: HotkeyWheel
## Each widget's place on screen: {id: {"centre": Vector2, "radius": float, "opacity": float, "shown": bool}}.
var widgets := {}
## Finger index -> widget id, and what each held widget pressed.
var _fingers := {}
var _held_actions := {}
var _move_base := Vector2.ZERO
var _move := Vector2.ZERO
var _aim := Vector2.ZERO
var _sent := {}
var _firing := false
var _sprinting := false
var _labels := {}
var _context_timer := 0.0
var _canvas: Control


func _exit_tree() -> void:
	Input.emulate_mouse_from_touch = true


func _ready() -> void:
	layer = 20
	_canvas = Control.new()
	_canvas.name = "Touch"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	Settings.applied.connect(layout_widgets)
	get_viewport().size_changed.connect(layout_widgets)
	InputHub.safe_area_changed.connect(layout_widgets)
	layout_widgets()


## True while the controls are on screen and take touches (also while a finger on Hotkeys holds the
## wheel open, so it can slide to a slice).
func is_active() -> bool:
	if not InputHub.touch_controls_visible() or player == null or player.is_dead or get_tree().paused:
		return false
	return not player.ui_open or (wheel != null and wheel.is_open and "hotkeys" in _fingers.values())


## Places every widget from the active layout on the screen's safe area.
func layout_widgets() -> void:
	InputHub.fit_to_safe_area(_canvas)
	var margins := InputHub.safe_margins(get_viewport())
	var area := get_viewport().get_visible_rect().size - Vector2(margins.left + margins.right, margins.top + margins.bottom)
	var layout := Settings.touch_layout()
	var stick_size := float(Settings.get_value("controls", "joystick_size"))
	for id: String in TouchLayout.WIDGETS:
		var widget: Dictionary = TouchLayout.WIDGETS[id]
		var place: Dictionary = layout[id]
		var radius := TouchLayout.radius_of(id, place.scale, stick_size)
		var shown: bool = widgets.get(id, {}).get("shown", widget.kind != "context")
		widgets[id] = {"centre": Vector2(place.x, place.y) * area, "radius": radius, "opacity": place.opacity, "shown": shown}
	widgets.fire.shown = Settings.get_value("controls", "touch_fire_mode") == "button"
	_canvas.queue_redraw()


func _process(delta: float) -> void:
	var active := is_active()
	if not active and not _fingers.is_empty():
		release_all()
	visible = active
	# While the controls are up, touches mustn't also click the mouse (a click fires); menus and the
	# inventory get mouse clicks from touches again.
	Input.emulate_mouse_from_touch = not active
	if active:
		_context_timer -= delta
		if _context_timer <= 0.0:
			_context_timer = CONTEXT_INTERVAL
			_update_context()
		_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	var touch := event as InputEventScreenTouch
	if touch:
		InputHub.set_device(InputHub.Device.TOUCH)  # Handled touches never reach InputHub.
		if touch.pressed:
			if _press_finger(touch.index, touch.position - _canvas.position):
				get_viewport().set_input_as_handled()
		elif _fingers.has(touch.index):
			_release_finger(touch.index)
			get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag and _fingers.has(drag.index):
		_drag_finger(drag.index, drag.position - _canvas.position)
		get_viewport().set_input_as_handled()


## Lets go of everything held (fingers, sticks, buttons).
func release_all() -> void:
	for index in _fingers.keys():
		_release_finger(index)
	_set_move(Vector2.ZERO)
	_set_aim(Vector2.ZERO)


## The widget a touch at `at` grabs ("" for none): a shown button or stick under it, else the move
## stick on the left of the screen.
func widget_at(at: Vector2) -> String:
	var best := ""
	var best_distance := INF
	for id: String in widgets:
		var widget: Dictionary = widgets[id]
		if id == "move_stick" or not widget.shown:
			continue
		var reach: float = widget.radius * (AIM_GRAB if id == "aim_stick" else 1.0)
		var distance: float = at.distance_to(widget.centre)
		if distance <= reach and distance / reach < best_distance:
			best = id
			best_distance = distance / reach
	if best == "" and at.x < _canvas.size.x * MOVE_ZONE:
		return "move_stick"
	return best


func _press_finger(index: int, at: Vector2) -> bool:
	var id := widget_at(at)
	if id == "" or id in _fingers.values():
		return false
	_fingers[index] = id
	match TouchLayout.WIDGETS[id].kind:
		"stick":
			if id == "move_stick":
				_move_base = at
				_set_move(Vector2.ZERO)
			else:
				_set_aim((at - widgets.aim_stick.centre) / widgets.aim_stick.radius)
		"wheel":
			if wheel:
				wheel.open_at(widgets[id].centre + _canvas.position, "touch")
		_:
			var action := _action_of(id)
			_held_actions[id] = action
			_send(action, true)
	return true


func _drag_finger(index: int, at: Vector2) -> void:
	var id: String = _fingers[index]
	match id:
		"move_stick":
			_set_move((at - _move_base) / widgets.move_stick.radius)
		"aim_stick":
			_set_aim((at - widgets.aim_stick.centre) / widgets.aim_stick.radius)
		"hotkeys":
			if wheel and wheel.is_open:
				wheel.point(at + _canvas.position - (widgets.hotkeys.centre + _canvas.position))


func _release_finger(index: int) -> void:
	var id: String = _fingers.get(index, "")
	_fingers.erase(index)
	match id:
		"move_stick":
			_set_move(Vector2.ZERO)
		"aim_stick":
			_set_aim(Vector2.ZERO)
		"hotkeys":
			if wheel and wheel.is_open:
				wheel.release_touch()
		"":
			pass
		_:
			if _held_actions.has(id):
				_send(_held_actions[id], false)
				_held_actions.erase(id)


## What a button presses: its action, except Extract, which pays or fires the flare when the extract
## needs it and otherwise shows your extracts.
func _action_of(id: String) -> String:
	if id == "extract":
		var raid := _raid()
		if raid and raid.extract_zone and raid.extract_zone.can_interact(player):
			return "interact"
	return TouchLayout.WIDGETS[id].get("action", "")


func _set_move(vector: Vector2) -> void:
	_move = _with_dead_zone(vector)
	_send_axis("move_right", maxf(_move.x, 0.0))
	_send_axis("move_left", maxf(-_move.x, 0.0))
	_send_axis("move_back", maxf(_move.y, 0.0))
	_send_axis("move_forward", maxf(-_move.y, 0.0))
	var sprint := _move.length() >= SPRINT_PUSH
	if sprint != _sprinting:
		_sprinting = sprint
		_send("sprint", sprint)


func _set_aim(vector: Vector2) -> void:
	_aim = _with_dead_zone(vector)
	_send_axis("aim_right", maxf(_aim.x, 0.0))
	_send_axis("aim_left", maxf(-_aim.x, 0.0))
	_send_axis("aim_down", maxf(_aim.y, 0.0))
	_send_axis("aim_up", maxf(-_aim.y, 0.0))
	var fire: bool = Settings.get_value("controls", "touch_fire_mode") == "stick" and vector.length() >= FIRE_RING
	if fire != _firing:
		_firing = fire
		_send("shoot", fire)


## A stick vector clamped to the ring, with the touch dead zone.
func _with_dead_zone(vector: Vector2) -> Vector2:
	vector = vector.limit_length(1.0)
	var dead: float = Settings.get_value("controls", "touch_dead_zone")
	return Vector2.ZERO if vector.length() <= dead else vector


func _send_axis(action: String, strength: float) -> void:
	var previous: float = _sent.get(action, 0.0)
	if strength == previous or (strength > 0.0 and absf(strength - previous) < ANALOG_STEP):
		return
	_sent[action] = strength
	var event := InputEventAction.new()
	event.action = action
	event.pressed = strength > 0.0
	event.strength = strength
	Input.parse_input_event(event)


func _send(action: String, pressed: bool) -> void:
	if action == "":
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


## Shows the context buttons that are needed now, with what they'd do.
func _update_context() -> void:
	var raid := _raid()
	var target := player.focused_interactable
	widgets.interact.shown = target != null and not target is ExtractZone
	_labels.interact = target.interact_text() if widgets.interact.shown else ""
	widgets.extract.shown = raid != null and raid.extract_zone != null and not raid.is_over()
	if widgets.extract.shown:
		var left := raid.extract_remaining()
		_labels.extract = "EXTRACTING %.1f" % left if left >= 0.0 else raid.extract_block()
	widgets.cover.shown = player.cover != null or CoverSystem.find_snap_point(player, player.config.cover_snap_distance) != null
	_labels.cover = "Leave cover" if player.cover else "Take cover"


func _raid() -> RaidController:
	return get_tree().get_first_node_in_group("raid_controller") as RaidController


func _draw_controls() -> void:
	var font := _canvas.get_theme_default_font()
	for id: String in widgets:
		var widget: Dictionary = widgets[id]
		if not widget.shown:
			continue
		var kind: String = TouchLayout.WIDGETS[id].kind
		var alpha: float = widget.opacity
		var held: bool = id in _fingers.values()
		if kind == "stick":
			_draw_stick(id, widget, alpha, held)
			continue
		var centre: Vector2 = widget.centre
		var radius: float = widget.radius
		var tint := CONTEXT_COLOR if kind == "context" else (PRESSED if held else EDGE)
		_canvas.draw_circle(centre, radius, Color(FILL, alpha * (0.9 if held else 0.6)))
		_canvas.draw_arc(centre, radius - 1.5, 0.0, TAU, 40, Color(tint, alpha), 3.0, true)
		TouchIcons.draw(_canvas, id, centre, radius * 1.0, Color(tint, minf(alpha + 0.25, 1.0)))
		var label: String = _labels.get(id, "") if kind == "context" else TouchLayout.WIDGETS[id].label
		if label != "":
			var size := 13 if kind != "context" else 16
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var at := centre + Vector2(-width / 2.0, radius + size + 4.0)
			_canvas.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, alpha))
			_canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(tint, minf(alpha + 0.3, 1.0)))


func _draw_stick(id: String, widget: Dictionary, alpha: float, held: bool) -> void:
	var radius: float = widget.radius
	var base: Vector2 = _move_base if id == "move_stick" and held else widget.centre
	var vector := _move if id == "move_stick" else _aim
	if id == "move_stick" and not held:
		alpha *= 0.5  # Where it'll appear: faint until you touch the left side.
	_canvas.draw_circle(base, radius, Color(FILL, alpha * 0.35))
	_canvas.draw_arc(base, radius, 0.0, TAU, 48, Color(EDGE, alpha * 0.8), 2.5, true)
	if id == "aim_stick" and Settings.get_value("controls", "touch_fire_mode") == "stick":
		_canvas.draw_arc(base, radius * FIRE_RING, 0.0, TAU, 48, Color(FIRE_COLOR, alpha * (1.0 if _firing else 0.5)), 2.0, true)
	var knob := base + vector * radius
	_canvas.draw_circle(knob, radius * 0.38, Color(FIRE_COLOR if id == "aim_stick" and _firing else EDGE, alpha * (0.9 if held else 0.55)))
	if not held:
		TouchIcons.draw(_canvas, id, base, radius * 0.6, Color(FILL, 0.9))
