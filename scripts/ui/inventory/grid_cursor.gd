class_name GridCursor
extends Control
## The controller cursor for the inventory and stash (DESIGN.md §17.1): a highlight that jumps cell by
## cell across every grid and equipment slot on screen (d-pad or left stick; it carries on into the
## next grid or slot in that direction). It works the mouse for you, so drag and drop, stacking and
## equipping all behave as with a mouse: `inv_select` (A) picks up the item under it and puts it down
## again, `inv_quick_move` (X) quick-moves it to the stash (or back to you) or, while holding one, turns
## it, `inv_examine` (View) examines it. A legend along the bottom shows the buttons. Only on while you
## play with a controller. Its mouse events are marked as emulated, so they don't count as using the
## mouse (InputHub).

const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.09
const COLOR := Color(0.95, 0.75, 0.3)
## How far a synthetic drag moves before coming back (so Godot starts dragging).
const DRAG_NUDGE := 24.0

var screen: InventoryScreen
var active := false
## The cursor's place (global pixels) and what it's on: {"rect", "pos", "control", "local"} (`local`: the
## rect in the control, so the cursor follows when the grids scroll or are rebuilt).
var at := Vector2.ZERO
var target := {}
## True while an item picked up with the cursor is being carried.
var holding := false

var _repeat := Vector2.ZERO
var _repeat_time := 0.0
var _legend: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_legend()
	InputHub.device_changed.connect(func(_device: int) -> void: _refresh_active())
	_refresh_active.call_deferred()


func _refresh_active() -> void:
	active = InputHub.is_controller() and Settings.get_value("controls", "controller_enabled")
	visible = active
	if active and target.is_empty():
		var all := targets()
		if not all.is_empty():
			_set_target(all[0])


## Everything the cursor can land on: each cell of every visible grid, and each equipment slot, as
## {"rect" (global), "pos" (its centre), "control", "local"}.
func targets() -> Array:
	var list := []
	for node in screen.find_children("*", "InventoryGridView", true, false):
		var view := node as InventoryGridView
		if view.grid == null or not view.is_visible_in_tree():
			continue
		var origin := view.global_position
		for y in view.grid.size.y:
			for x in view.grid.size.x:
				var local := Rect2(Vector2(x, y) * view.cell_size, Vector2.ONE * view.cell_size)
				var rect := Rect2(origin + local.position, local.size)
				list.append({"rect": rect, "pos": rect.get_center(), "control": view, "local": local})
	for node in screen.find_children("*", "EquipmentSlotView", true, false):
		var slot := node as EquipmentSlotView
		if slot.is_visible_in_tree():
			var rect := slot.get_global_rect()
			list.append({"rect": rect, "pos": rect.get_center(), "control": slot, "local": Rect2(Vector2.ZERO, slot.size)})
	return list


func _input(event: InputEvent) -> void:
	if not active or screen == null or not screen.cursor_allowed():
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return  # Arrow keys and the mouse are left alone (and switch the prompts back to the keyboard).
	var handled := true
	var direction := _direction_of(event)
	if direction != Vector2.ZERO:
		if direction != _repeat:  # A held stick sends a stream of these: move once, then repeat.
			move(direction)
			_repeat = direction
			_repeat_time = -REPEAT_DELAY
	elif _is_direction_release(event):
		_repeat = Vector2.ZERO
	elif event.is_action_pressed("inv_select"):
		select()
	elif event.is_action_pressed("inv_quick_move"):
		quick_move()
	elif event.is_action_pressed("inv_examine"):
		examine()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not active:
		return
	_follow_target()
	if _repeat != Vector2.ZERO:
		_repeat_time += delta
		if _repeat_time >= REPEAT_RATE:
			_repeat_time = 0.0
			move(_repeat)
	queue_redraw()


## Moves to the nearest target in `direction` (screen axes).
func move(direction: Vector2) -> void:
	var best := {}
	var best_score := INF
	for candidate: Dictionary in targets():
		var offset: Vector2 = candidate.pos - at
		var along := offset.dot(direction)
		if along < 4.0:
			continue
		var across := absf(offset.cross(direction))
		var score := along + across * 2.5
		if score < best_score:
			best = candidate
			best_score = score
	if not best.is_empty():
		_set_target(best)


## Keeps the cursor on its cell when the grids move; picks the first target if its grid went away.
func _follow_target() -> void:
	var control: Control = target.get("control")
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		var all := targets()
		target = {}
		if not all.is_empty():
			_set_target(all[0])
		return
	var local: Rect2 = target.local
	target.rect = Rect2(control.global_position + local.position, local.size)
	target.pos = target.rect.get_center()
	at = target.pos


func _set_target(next: Dictionary) -> void:
	var from := at
	target = next
	at = next.pos
	_mouse_motion(at, at - from)
	queue_redraw()


## A: picks up the item under the cursor, or puts the carried one down here.
func select() -> void:
	if holding:
		_mouse_button(false)
		holding = false
		return
	if item_under_cursor() == null:
		return
	holding = true  # Before the motion, which carries the held button.
	_mouse_button(true)
	_mouse_motion(at + Vector2(DRAG_NUDGE, 0), Vector2(DRAG_NUDGE, 0))
	_check_drag.call_deferred()


## X: turns the carried item, or quick-moves the one under the cursor.
func quick_move() -> void:
	if holding:
		if InventoryDrag.current:
			InventoryDrag.current.rotate()
		return
	var item := item_under_cursor()
	if item:
		screen.quick_move(item)


## View: examines the item under the cursor.
func examine() -> void:
	var item := item_under_cursor()
	if item:
		screen.examine(item)


func item_under_cursor() -> ItemInstance:
	var control: Control = target.get("control")
	if not is_instance_valid(control):
		return null
	if control is InventoryGridView:
		return (control as InventoryGridView).item_at_position(at - control.global_position)
	if control is EquipmentSlotView:
		return (control as EquipmentSlotView).item()
	return null


## A frame after picking up: back onto the cell if the drag started (a frame apart, so Godot doesn't
## merge the two moves into none), else let go.
func _check_drag() -> void:
	await get_tree().process_frame
	if holding and not get_viewport().gui_is_dragging():
		_mouse_button(false)
		holding = false
	elif holding:
		_mouse_motion(at, Vector2(-DRAG_NUDGE, 0))


func _mouse_button(pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.device = InputEvent.DEVICE_ID_EMULATION
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = at
	click.global_position = at
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(click)


func _mouse_motion(to: Vector2, relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.position = to
	motion.global_position = to
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if holding else 0
	Input.parse_input_event(motion)


static func _direction_of(event: InputEvent) -> Vector2:
	for pair in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
		if event.is_action_pressed(pair[0], true):
			return pair[1]
	return Vector2.ZERO


static func _is_direction_release(event: InputEvent) -> bool:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		if event.is_action_released(action):
			return true
	return false


func _build_legend() -> void:
	var bar := PanelContainer.new()
	bar.name = "ControllerLegend"
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -56.0
	bar.offset_bottom = -12.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 18)
	bar.add_child(_legend)
	for pair in [["inv_select", "Pick up / put down"], ["inv_quick_move", "Quick move (holding: turn)"], ["inv_examine", "Examine"], ["toggle_inventory", "Close"]]:
		var icon := PromptIcon.new()
		icon.action = pair[0]
		icon.icon_size = 26.0
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_legend.add_child(icon)
		var label := Label.new()
		label.text = pair[1]
		_legend.add_child(label)


func _draw() -> void:
	if not active or target.is_empty() or not screen.cursor_allowed():
		return
	var rect: Rect2 = target.rect
	rect.position -= global_position
	draw_rect(rect.grow(1.0), Color(COLOR, 0.18))
	draw_rect(rect.grow(1.0), COLOR, false, 3.0)
	var tick := minf(rect.size.x, rect.size.y) * 0.3
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var inward := (rect.get_center() - corner).sign()
		draw_line(corner, corner + Vector2(inward.x * tick, 0), COLOR, 5.0)
		draw_line(corner, corner + Vector2(0, inward.y * tick), COLOR, 5.0)
