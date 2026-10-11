class_name Player
extends CharacterBody3D
## The player character (DESIGN.md §13, §15). WASD moves relative to the screen and the body
## turns to face the mouse cursor. Walk, sprint (Shift, uses stamina), crouch (C toggles; slower, quieter).

enum Move { IDLE, WALK, SPRINT, CROUCH }

@export_group("Speed")
## Metres per second.
@export var walk_speed := 3.5
@export var sprint_speed := 6.0
@export var crouch_speed := 1.6
## How quickly the player speeds up and slows down (m/s²). Lower feels heavier.
@export var acceleration := 25.0
## How fast the body turns toward the cursor (degrees per second).
@export var turn_speed := 720.0

@export_group("Stamina")
@export var max_stamina := 100.0
## Stamina used per second of sprinting.
@export var sprint_cost := 15.0
## Stamina recovered per second once recovery starts.
@export var regen_rate := 12.0
## Seconds after sprinting before stamina starts to recover.
@export var regen_delay := 1.0
## After stamina runs out, sprint stays locked until stamina is back to this value.
@export var recover_threshold := 25.0

@export_group("Noise")
## How far away footsteps can be heard, in metres. Scavs will use this for hearing (DESIGN.md §4).
@export var walk_noise := 10.0
@export var sprint_noise := 20.0
@export var crouch_noise := 4.0

@export_group("Height")
@export var stand_height := 1.8
@export var crouch_height := 1.1

var stamina := 0.0
var is_crouching := false
## True after stamina runs out, until it recovers to recover_threshold.
var is_exhausted := false
var move_state := Move.IDLE
## How far footsteps can be heard right now, in metres (0 when standing still).
var noise_radius := 0.0

var _regen_cooldown := 0.0

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body: Node3D = $Body


func _ready() -> void:
	stamina = max_stamina
	_set_height(stand_height)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("crouch"):
		_set_crouching(not is_crouching)


func _physics_process(delta: float) -> void:
	var direction := _input_direction()
	var moving := not direction.is_zero_approx()
	var sprint_held := moving and Input.is_action_pressed("sprint")
	# Sprinting from a crouch stands you up.
	if sprint_held and is_crouching:
		_set_crouching(false)
	var sprinting := sprint_held and not is_exhausted
	_update_stamina(sprinting, delta)

	var speed := 0.0
	if not moving:
		move_state = Move.IDLE
		noise_radius = 0.0
	elif is_crouching:
		move_state = Move.CROUCH
		speed = crouch_speed
		noise_radius = crouch_noise
	elif sprinting:
		move_state = Move.SPRINT
		speed = sprint_speed
		noise_radius = sprint_noise
	else:
		move_state = Move.WALK
		speed = walk_speed
		noise_radius = walk_noise

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * speed, acceleration * delta)
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	_turn_toward_cursor(delta)


## WASD as a direction on the ground, relative to the screen: W always moves up the screen.
func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0.0, input.y)
	var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var screen_up := Vector3(camera.global_basis.y.x, 0.0, camera.global_basis.y.z).normalized()
	return right * input.x - screen_up * input.y


## Turns the body toward the point on the ground under the mouse cursor.
func _turn_toward_cursor(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var ground := Plane(Vector3.UP, global_position.y)
	var hit: Variant = ground.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		return
	var to_cursor: Vector3 = hit - global_position
	if Vector2(to_cursor.x, to_cursor.z).length() < 0.2:
		return  # Cursor is on the player: keep the current facing.
	# The model faces -Z; this is the turn that points -Z at the cursor.
	var target_yaw := atan2(-to_cursor.x, -to_cursor.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, deg_to_rad(turn_speed) * delta)


func _update_stamina(sprinting: bool, delta: float) -> void:
	if sprinting:
		stamina = maxf(stamina - sprint_cost * delta, 0.0)
		_regen_cooldown = regen_delay
		if stamina == 0.0:
			is_exhausted = true
	elif _regen_cooldown > 0.0:
		_regen_cooldown -= delta
	else:
		stamina = minf(stamina + regen_rate * delta, max_stamina)
		if is_exhausted and stamina >= recover_threshold:
			is_exhausted = false


func _set_crouching(value: bool) -> void:
	is_crouching = value
	_set_height(crouch_height if value else stand_height)


## Resizes the collision capsule and squashes the placeholder model to match.
func _set_height(height: float) -> void:
	var capsule := _collision.shape as CapsuleShape3D
	capsule.height = height
	_collision.position.y = height / 2.0
	_body.scale.y = height / stand_height
