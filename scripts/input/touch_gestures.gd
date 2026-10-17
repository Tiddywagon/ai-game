class_name TouchGestures
extends Node
## Touch gestures for the inventory, stash and trader screens (DESIGN.md §17.1). One finger already
## works as the mouse (Godot turns touches into clicks and drags: tap to select, drag and drop). On top
## of that: a long press (LONG_PRESS seconds without moving) is a right-click, which examines; a quick tap
## with a second finger (while the first drags an item) is `two_finger_tap` (the inventory turns the
## item); two fingers spreading or pinching is `pinched` (the stash zooms).

signal long_pressed(at: Vector2)
signal two_finger_tap(at: Vector2)
signal pinched(factor: float, centre: Vector2)

const LONG_PRESS := 0.5
## A finger that moves further than this (pixels) isn't pressing or tapping any more.
const MOVE_SLOP := 14.0
const TAP_TIME := 0.3
## Pinch changes smaller than this aren't reported.
const PINCH_STEP := 0.02

## Fingers down: index -> {"start", "at", "time"}.
var _touches := {}
var _long_index := -1
var _long_time := -1.0
var _pinch_distance := 0.0
var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta
	if _long_time < 0.0:
		return
	_long_time += delta
	if _long_time >= LONG_PRESS:
		_long_time = -1.0
		if _touches.has(_long_index) and _touches.size() == 1 and not get_viewport().gui_is_dragging():
			var at: Vector2 = _touches[_long_index].at
			_right_click(at)
			long_pressed.emit(at)


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch:
		if touch.pressed:
			_touches[touch.index] = {"start": touch.position, "at": touch.position, "time": _clock}
			if _touches.size() == 1:
				_long_index = touch.index
				_long_time = 0.0
			else:
				_long_time = -1.0
				if _touches.size() == 2:
					_pinch_distance = _spread()
		elif _touches.has(touch.index):
			var finger: Dictionary = _touches[touch.index]
			if _touches.size() >= 2 and touch.index != _long_index and _clock - float(finger.time) <= TAP_TIME \
					and touch.position.distance_to(finger.start) < MOVE_SLOP:
				two_finger_tap.emit(touch.position)
			_touches.erase(touch.index)
			if touch.index == _long_index:
				_long_time = -1.0
			if _touches.size() < 2:
				_pinch_distance = 0.0
		return
	var drag := event as InputEventScreenDrag
	if drag and _touches.has(drag.index):
		_touches[drag.index].at = drag.position
		if drag.index == _long_index and drag.position.distance_to(_touches[drag.index].start) > MOVE_SLOP:
			_long_time = -1.0
		if _touches.size() == 2 and _pinch_distance > 0.0:
			var spread := _spread()
			var factor := spread / _pinch_distance
			if absf(factor - 1.0) >= PINCH_STEP:
				pinched.emit(factor, _centre())
				_pinch_distance = spread


func _spread() -> float:
	var points: Array = _touches.values()
	return (points[0].at as Vector2).distance_to(points[1].at) if points.size() >= 2 else 0.0


func _centre() -> Vector2:
	var points: Array = _touches.values()
	return ((points[0].at as Vector2) + (points[1].at as Vector2)) / 2.0


## A right mouse click at `at` (what a long press means).
func _right_click(at: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.device = InputEvent.DEVICE_ID_EMULATION
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
