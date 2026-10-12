class_name SpinTracker
extends RefCounted
## Watches the aim turn around the shooter for 360 trick shots (DESIGN.md §13.4): feed it the aim's
## direction every tick and it reports when the aim has made a full turn in one direction within
## `spin_time` seconds. Turning back more than `reverse_tolerance` starts over in the new direction,
## so sweeping back and forth never counts.

## Seconds a full turn has to fit in.
var spin_time := 1.5
## How far the aim may turn back (radians) before the spin starts over.
var reverse_tolerance := deg_to_rad(20.0)

## Turned so far in the current direction (radians, unwrapped), and the direction (+1, -1, 0).
var _angle := 0.0
var _direction := 0
var _reverse := 0.0
var _last_yaw := NAN
var _time := 0.0
## (time, turned so far) samples over the last `spin_time`.
var _samples: Array[Vector2] = []


## Forgets the spin so far.
func reset() -> void:
	_angle = 0.0
	_direction = 0
	_reverse = 0.0
	_last_yaw = NAN
	_samples.clear()


## The aim points at `yaw` (radians around the up axis) `delta` seconds after the last call. Returns
## true when that completes a full turn in one direction within `spin_time` (and starts over).
func feed(yaw: float, delta: float) -> bool:
	_time += delta
	if is_nan(_last_yaw):
		_last_yaw = yaw
		_samples = [Vector2(_time, _angle)]
		return false
	var step := angle_difference(_last_yaw, yaw)
	_last_yaw = yaw
	var turn := signi(int(signf(step)))
	if turn != 0:
		if _direction == 0:
			_direction = turn
		if turn == _direction:
			_angle += absf(step)
			_reverse = 0.0
		else:
			_reverse += absf(step)
			if _reverse > reverse_tolerance:
				# Turned back too far: a new spin the other way, starting with this turn back.
				_direction = turn
				_angle = _reverse
				_reverse = 0.0
				_samples = [Vector2(_time - delta, 0.0)]
			else:
				_angle -= absf(step)
	_samples.append(Vector2(_time, _angle))
	while _samples.size() > 1 and _samples[1].x <= _time - spin_time:
		_samples.pop_front()
	if turned() >= TAU:
		var direction := _direction
		reset()
		_last_yaw = yaw
		_samples = [Vector2(_time, 0.0)]
		_direction = direction
		return true
	return false


## How far the aim has turned one way within the last `spin_time`, in radians.
func turned() -> float:
	if _samples.is_empty():
		return 0.0
	# Where the aim was `spin_time` ago, between the two samples around that moment.
	var start := _samples[0].y
	var window_start := _time - spin_time
	if _samples.size() > 1 and _samples[0].x < window_start:
		start = lerpf(_samples[0].y, _samples[1].y, inverse_lerp(_samples[0].x, _samples[1].x, window_start))
	return maxf(_angle - start, 0.0)


## Share of a full turn made within the last `spin_time`, 0-1.
func progress() -> float:
	return clampf(turned() / TAU, 0.0, 1.0)
