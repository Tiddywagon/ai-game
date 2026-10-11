class_name TopDownCamera
extends Camera3D
## Top-down camera that smoothly follows a target from a fixed angle (DESIGN.md §1, §15).
## It never turns, so "up" on the screen is always the same direction in the world.

## The node to follow, usually the player.
@export var target: Node3D
## Angle down from the horizon; 90 would look straight down.
@export_range(30.0, 89.0) var pitch_degrees := 60.0
## Distance from the followed point, in metres.
@export var distance := 18.0
## Height above the target's feet to keep centred on screen, in metres.
@export var focus_height := 1.0
## Higher follows more tightly, lower trails further behind.
@export var follow_speed := 6.0
## How far the camera moves at full shake, in metres.
@export var shake_distance := 0.35

var _follow_position := Vector3.ZERO
var _shake := 0.0
var _time := 0.0


func _ready() -> void:
	rotation_degrees = Vector3(-pitch_degrees, 0.0, 0.0)
	# This camera moves every frame using the target's already-smoothed position,
	# so Godot's physics interpolation must not smooth it a second time.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_follow_position = global_position
	if target:
		_follow_position = _goal_position()
		global_position = _follow_position


## Shakes the camera. `amount` is 0-1 and adds up; Settings scales it (or turns it off).
func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount * Settings.camera_shake_scale(), 0.0, 1.0)


func _process(delta: float) -> void:
	if target == null:
		return
	_time += delta
	# Exponential smoothing: the same feel at any frame rate.
	_follow_position = _follow_position.lerp(_goal_position(), 1.0 - exp(-follow_speed * delta))
	var offset := Vector3.ZERO
	if _shake > 0.0:
		var strength := _shake * _shake * shake_distance
		offset = (global_basis.x * sin(_time * 53.0) + global_basis.y * cos(_time * 47.0)) * strength
		_shake = maxf(_shake - delta * 1.8, 0.0)
	global_position = _follow_position + offset


func _goal_position() -> Vector3:
	var focus := target.get_global_transform_interpolated().origin + Vector3.UP * focus_height
	return focus + global_basis.z * distance
