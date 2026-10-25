class_name TopDownCamera
extends Camera3D
## Top-down camera that smoothly follows a target from a fixed angle (DESIGN.md §1, §15).
## It never turns, so "up" on the screen is always the same direction in the world. Looking through a
## scope pulls it out and leads it toward the aim point (focus_offset, zoom; DESIGN.md §13.6).
## It carries the ears (an AudioListener3D, `ears`) down at the target: positional sounds (voices, raid
## events, a flare) are as loud as they are far from the player, not from the camera up in the air,
## and pan the way the screen faces.

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

## Flat offset of the followed point, e.g. toward the aim point while looking through a scope.
var focus_offset := Vector3.ZERO
## Distance multiplier, e.g. pulled out while looking through a scope.
var zoom := 1.0

## Where positional sounds are heard from: at the target, facing the way the screen does (null without
## a target).
var ears: AudioListener3D

var _follow_position := Vector3.ZERO
var _offset_now := Vector3.ZERO
var _zoom_now := 1.0
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
		ears = AudioListener3D.new()
		ears.name = "Ears"
		ears.top_level = true  # Its own place and facing, not the camera's.
		ears.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(ears)
		ears.global_transform = Transform3D(Basis.IDENTITY, _ears_position())
		ears.make_current()


## Shakes the camera. `amount` is 0-1 and adds up; Settings scales it (or turns it off).
func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount * Settings.camera_shake_scale(), 0.0, 1.0)


## Roughly half the ground area on screen at `zoom_factor` (x: across the screen, y: up and down it),
## in metres around the followed point.
func ground_half_extents(zoom_factor: float) -> Vector2:
	var half_height := tan(deg_to_rad(fov) / 2.0) * distance * zoom_factor
	var aspect := get_viewport().get_visible_rect().size.aspect()
	return Vector2(half_height * aspect, half_height / sin(deg_to_rad(pitch_degrees)))


func _process(delta: float) -> void:
	if target == null:
		return
	_time += delta
	# Exponential smoothing: the same feel at any frame rate.
	var view_blend := 1.0 - exp(-VisionSystem.config.camera_follow_speed * delta)
	_offset_now = _offset_now.lerp(focus_offset, view_blend)
	_zoom_now = lerpf(_zoom_now, zoom, view_blend)
	_follow_position = _follow_position.lerp(_goal_position(), 1.0 - exp(-follow_speed * delta))
	var offset := Vector3.ZERO
	if _shake > 0.0:
		var strength := _shake * _shake * shake_distance
		offset = (global_basis.x * sin(_time * 53.0) + global_basis.y * cos(_time * 47.0)) * strength
		_shake = maxf(_shake - delta * 1.8, 0.0)
	global_position = _follow_position + offset
	if ears:
		ears.global_position = _ears_position()


## The target's head, where it hears from.
func _ears_position() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * focus_height if target else global_position


func _goal_position() -> Vector3:
	var focus := target.get_global_transform_interpolated().origin + Vector3.UP * focus_height + _offset_now
	return focus + global_basis.z * distance * _zoom_now
