class_name Actor
extends CharacterBody3D
## Shared body of the player and the AI (DESIGN.md §4, §13): movement, stamina, combat roll, cover,
## hitbox, health and shooting. Subclasses decide what to do in _think(); Actor carries it out.

signal died
## A roll just ended. `direction` is the way it went.
signal roll_finished(direction: Vector3)
## Something the controller asked for can't happen, e.g. "Can't roll: leg fracture".
signal action_blocked(reason: String)

enum Side { PMC, SCAV }
enum Move { IDLE, WALK, SPRINT, CROUCH, ROLL, COVER }

## Physics layer bits (named in Project Settings > Layer Names > 3D Physics).
const WORLD_MASK := 1
const ACTOR_MASK := 2
const HITBOX_MASK := 4
const BODY_RADIUS := 0.35
## Gun height as a share of body height (1.3 m when standing).
const GUN_HEIGHT_RATIO := 0.72
## Top speed when stepping into a cover spot or leaning out of it.
const COVER_SNAP_SPEED := 5.0
## Shots only go off when the body faces within this angle of the aim point.
const MAX_AIM_ERROR_DEGREES := 25.0
const FOOTSTEP_INTERVAL := 0.4
## Health of a player character (DESIGN.md §13.4).
const DEFAULT_MAX_HEALTH := 200.0

@export var side := Side.PMC
## Roll, cover and bullet tuning shared by everyone.
@export var config: CombatConfig = preload("res://data/config/combat.tres")
@export var max_health := DEFAULT_MAX_HEALTH
## Weapon and ammo item ids from ItemDB.
@export var weapon_id := "ak_74n"
@export var ammo_id := "ammo_545_ps"
## Random spread of each shot, in degrees.
@export var spread_degrees := 0.5

@export_group("Speed")
## Metres per second.
@export var walk_speed := 3.5
@export var sprint_speed := 6.0
@export var crouch_speed := 1.6
## How quickly the actor speeds up and slows down (m/s²). Lower feels heavier.
@export var acceleration := 25.0
## How fast the body turns toward the aim point (degrees per second).
@export var turn_speed := 720.0

@export_group("Stamina")
@export var max_stamina := 100.0
## Stamina used per second of sprinting.
@export var sprint_cost := 15.0
## Stamina recovered per second once recovery starts.
@export var regen_rate := 12.0
## Seconds after sprinting or rolling before stamina starts to recover.
@export var regen_delay := 1.0
## After stamina runs out, sprinting and rolling stay locked until stamina is back to this value.
@export var recover_threshold := 25.0

@export_group("Noise")
## How far away footsteps can be heard, in metres (DESIGN.md §4).
@export var walk_noise := 10.0
@export var sprint_noise := 20.0
@export var crouch_noise := 4.0

@export_group("Height")
@export var stand_height := 1.8
@export var crouch_height := 1.1

@export_group("Weight")
## Above this carried weight the actor is overweight and can't roll (DESIGN.md §7).
@export var overweight_kg := 40.0

# What the controller wants this physics tick. Set in _think().
## Flat world direction to move in, length up to 1.
var move_input := Vector3.ZERO
var sprint_input := false
var fire_input := false
## Hold to peek out of cover.
var peek_input := false
## World point to face and shoot at; only used when has_aim is true.
var aim_point := Vector3.ZERO
var has_aim := false

var health := 0.0
var is_dead := false
## Set by the health system once body parts exist (DESIGN.md §13). Blocks rolling.
var has_leg_fracture := false
## Set by the inventory once it exists.
var carried_weight_kg := 0.0
var stamina := 0.0
var is_crouching := false
## True after stamina runs out, until it recovers to recover_threshold.
var is_exhausted := false
var is_rolling := false
var move_state := Move.IDLE
## How far footsteps can be heard right now, in metres.
var noise_radius := 0.0
## The cover spot in use, or null.
var cover: CoverPoint
var is_peeking := false
## Actors that attacked this one: hostile even if they'd normally be friendly (a player Scav who
## shoots an AI Scav).
var enemies: Array[Actor] = []

var _roll_direction := Vector3.ZERO
var _roll_time := 0.0
var _roll_cooldown := 0.0
var _regen_cooldown := 0.0
var _fire_cooldown := 0.0
var _footstep_timer := 0.0
var _height := 0.0
var _weapon: ItemData
var _ammo: ItemData

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _hitbox: Area3D = $Hitbox
@onready var _hitbox_shape: CollisionShape3D = $Hitbox/CollisionShape3D
@onready var _body: Node3D = $Body
@onready var _muzzle: Node3D = $Body/Gun/Muzzle


func _ready() -> void:
	add_to_group("actors")
	health = max_health
	stamina = max_stamina
	_weapon = ItemDB.get_item(weapon_id)
	set_ammo(ammo_id)
	_set_height(stand_height)
	_update_hitbox()


func _exit_tree() -> void:
	CoverSystem.release(self)


## Override in subclasses: set move_input, sprint_input, fire_input, peek_input and aim_point,
## and call try_roll(), enter_cover() or exit_cover() as needed.
func _think(_delta: float) -> void:
	pass


## Called when a bullet passes within a couple of metres (or hits). Override to react.
func on_bullet_near(_shooter: Actor) -> void:
	pass


## Called when one of this actor's bullets hits someone. Override for hit markers and the like.
func on_hit_landed(_target: Actor, _damage: float, _position: Vector3) -> void:
	pass


## Called after each shot this actor fires. Override for recoil, camera shake and the like.
func _on_fired() -> void:
	pass


func _physics_process(delta: float) -> void:
	if is_dead:
		_step_dead(delta)
		return
	_think(delta)
	_roll_cooldown = maxf(_roll_cooldown - delta, 0.0)
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if is_rolling:
		_step_roll(delta)
	elif cover:
		_step_cover(delta)
	else:
		_step_free(delta)
	_update_hitbox()
	_update_facing(delta)
	_update_firing()
	_update_footsteps(delta)


# --- Actions --------------------------------------------------------------------------------

func set_crouching(value: bool) -> void:
	if cover == null:
		is_crouching = value


func is_overweight() -> bool:
	return carried_weight_kg > overweight_kg


## Why a roll isn't possible right now, or "" if it is.
func roll_block_reason() -> String:
	if is_dead or is_rolling:
		return "busy"
	if has_leg_fracture:
		return "leg fracture"
	if is_overweight():
		return "overweight"
	if _roll_cooldown > 0.0:
		return "cooldown"
	if is_exhausted or stamina < config.roll_stamina_cost:
		return "not enough stamina"
	return ""


## Starts a combat roll along `direction` (flattened). Returns false, and emits action_blocked
## with the reason, if a roll isn't allowed.
func try_roll(direction: Vector3) -> bool:
	direction.y = 0.0
	var reason := roll_block_reason()
	if reason == "busy" or direction.is_zero_approx():
		return false
	if reason != "":
		action_blocked.emit("Can't roll: " + reason)
		return false
	exit_cover()
	is_rolling = true
	_roll_direction = direction.normalized()
	_roll_time = 0.0
	stamina -= config.roll_stamina_cost
	_regen_cooldown = regen_delay
	rotation.y = _yaw_toward(_roll_direction)
	NoiseSystem.emit_noise(global_position, config.roll_noise, self)
	return true


func enter_cover(point: CoverPoint) -> void:
	if point == null or is_dead:
		return
	is_crouching = false
	cover = point
	CoverSystem.claim(self, point)


func exit_cover() -> void:
	if cover == null:
		return
	cover = null
	is_peeking = false
	CoverSystem.release(self)


func set_ammo(id: String) -> void:
	ammo_id = id
	_ammo = ItemDB.get_item(id)


## Short ammo description for the HUD, e.g. "5.45x39 PS (pen 28)".
func ammo_label() -> String:
	if _ammo == null:
		return "no ammo"
	return "%s (pen %d)" % [_ammo.display_name, int(_ammo.stats.get("penetration", 0))]


func take_hit(damage: float, from: Actor) -> void:
	if is_dead:
		return
	if from and from != self and not is_hostile(from):
		enemies.append(from)  # Provoked: whoever shot us is an enemy from now on.
	health = maxf(health - damage, 0.0)
	if health == 0.0:
		die()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_rolling = false
	exit_cover()
	CoverSystem.release(self)  # Also frees a spot it was only heading to.
	velocity = Vector3.ZERO
	# Corpses don't block anyone or take hits, but stay on the ground.
	collision_layer = 0
	collision_mask = WORLD_MASK
	_hitbox.collision_layer = 0
	# Lie the placeholder body flat.
	_body.scale = Vector3.ONE
	_body.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_body.position.y = BODY_RADIUS
	_body.reset_physics_interpolation()
	died.emit()


func is_hostile(other: Actor) -> bool:
	if other == self:
		return false
	return other in enemies or not (side == Side.SCAV and other.side == Side.SCAV)


# --- Body points ----------------------------------------------------------------------------

func gun_height() -> float:
	return _height * GUN_HEIGHT_RATIO


func eye_point() -> Vector3:
	return global_position + Vector3.UP * _height * 0.92


func chest_point() -> Vector3:
	return global_position + Vector3.UP * _hitbox_height() * 0.65


func head_point() -> Vector3:
	return global_position + Vector3.UP * maxf(_hitbox_height() - 0.15, 0.1)


func hitbox_rid() -> RID:
	return _hitbox.get_rid()


## The point of `other` this actor can see (chest first, then head), or null if neither is visible.
func visible_point_of(other: Actor) -> Variant:
	var eye := eye_point()
	for point in [other.chest_point(), other.head_point()]:
		var query := PhysicsRayQueryParameters3D.create(eye, point, WORLD_MASK)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return point
	return null


# --- Per-tick movement ----------------------------------------------------------------------

func _step_free(delta: float) -> void:
	var moving := not move_input.is_zero_approx()
	# Shooting stops a sprint; sprinting from a crouch stands you up.
	var sprint_held := moving and sprint_input and not fire_input
	if sprint_held and is_crouching:
		is_crouching = false
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

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(move_input * speed, acceleration * delta)
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	_apply_gravity(delta)
	move_and_slide()
	_set_height(crouch_height if is_crouching else stand_height)


func _step_roll(delta: float) -> void:
	_update_stamina(false, delta)
	var start := _roll_time / config.roll_duration
	_roll_time += delta
	var progress := minf(_roll_time / config.roll_duration, 1.0)
	# Ease-out: fast at the start, slowing to a stop. Covers exactly roll_distance.
	var step := config.roll_distance * (_ease_out(progress) - _ease_out(start))
	var roll_velocity := _roll_direction * step / delta
	velocity = Vector3(roll_velocity.x, velocity.y, roll_velocity.z)
	_apply_gravity(delta)
	move_and_slide()
	move_state = Move.ROLL
	noise_radius = config.roll_noise  # Shown on the HUD; the noise itself is made once, in try_roll().
	_set_height(crouch_height)
	if progress >= 1.0:
		is_rolling = false
		_roll_cooldown = config.roll_cooldown
		velocity = Vector3(0.0, velocity.y, 0.0)
		roll_finished.emit(_roll_direction)


func _step_cover(delta: float) -> void:
	_update_stamina(false, delta)
	# Moving away from the cover leaves it.
	if move_input.dot(cover.normal) > 0.7:
		exit_cover()
		_step_free(delta)
		return
	is_peeking = peek_input and cover.can_peek
	var sliding := false
	if not is_peeking:
		# Slide along the cover with sideways input.
		var along := move_input.dot(cover.tangent)
		if absf(along) > 0.3:
			var next := CoverSystem.point_on_face(cover.box, cover.face, cover.position + cover.tangent * signf(along) * config.cover_move_speed * delta)
			if next and next.position.distance_to(cover.position) > 0.001 and CoverSystem.is_available(next, self):
				enter_cover(next)
				sliding = true
	var goal := cover.position + (cover.peek_offset if is_peeking else Vector3.ZERO)
	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	var cover_velocity := (to_goal / delta).limit_length(COVER_SNAP_SPEED)
	velocity = Vector3(cover_velocity.x, velocity.y, cover_velocity.z)
	_apply_gravity(delta)
	move_and_slide()
	move_state = Move.COVER
	noise_radius = crouch_noise if sliding or to_goal.length() > 0.05 else 0.0
	_set_height(config.duck_height if cover.is_low and not is_peeking else stand_height)


func _step_dead(delta: float) -> void:
	velocity = Vector3(0.0, velocity.y, 0.0)
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta


func _update_stamina(sprinting: bool, delta: float) -> void:
	if sprinting:
		stamina = maxf(stamina - sprint_cost * delta, 0.0)
		_regen_cooldown = regen_delay
	elif _regen_cooldown > 0.0:
		_regen_cooldown -= delta
	else:
		stamina = minf(stamina + regen_rate * delta, max_stamina)
		if is_exhausted and stamina >= recover_threshold:
			is_exhausted = false
	if stamina == 0.0:
		is_exhausted = true


func _update_facing(delta: float) -> void:
	if is_rolling or not has_aim:
		return
	var to_aim := aim_point - global_position
	if Vector2(to_aim.x, to_aim.z).length() < 0.2:
		return  # Aim point is on the actor: keep the current facing.
	rotation.y = rotate_toward(rotation.y, _yaw_toward(to_aim), deg_to_rad(turn_speed) * delta)


func _update_firing() -> void:
	if not fire_input or not has_aim or _fire_cooldown > 0.0 or _ammo == null or _weapon == null:
		return
	if is_rolling or (cover and not is_peeking):
		return  # Can't shoot mid-roll or while hidden behind cover.
	var to_aim := aim_point - global_position
	if absf(angle_difference(rotation.y, _yaw_toward(to_aim))) > deg_to_rad(MAX_AIM_ERROR_DEGREES):
		return  # Still turning toward the target.
	_fire_cooldown = 60.0 / float(_weapon.stats.get("fire_rate", 600))
	# Bullets start at the body's centre line, so a gun poking into a wall can't shoot through it.
	var origin := global_position + Vector3.UP * gun_height()
	var direction := (aim_point - origin).normalized()
	Ballistics.fire(self, origin, _spread(direction), _ammo, _muzzle.global_position)
	_on_fired()


func _update_footsteps(delta: float) -> void:
	if noise_radius <= 0.0 or is_rolling:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = FOOTSTEP_INTERVAL
		NoiseSystem.emit_noise(global_position, noise_radius, self)


## Sizes the body collision and squashes the placeholder model to `height`.
func _set_height(height: float) -> void:
	if is_equal_approx(height, _height):
		return
	_height = height
	var capsule := _collision.shape as CapsuleShape3D
	capsule.height = height
	_collision.position.y = height / 2.0
	_body.scale.y = height / stand_height


## The hitbox follows the body, but shrinks for the first moments of a roll (harder to hit).
func _update_hitbox() -> void:
	var height := _height
	var radius := BODY_RADIUS
	if is_rolling and _roll_time <= config.roll_evade_time:
		height = config.roll_evade_height
		radius = config.roll_evade_radius
	var capsule := _hitbox_shape.shape as CapsuleShape3D
	if not is_equal_approx(capsule.height, height) or not is_equal_approx(capsule.radius, radius):
		capsule.radius = radius
		capsule.height = height
		_hitbox_shape.position.y = height / 2.0


func _hitbox_height() -> float:
	return (_hitbox_shape.shape as CapsuleShape3D).height


func _spread(direction: Vector3) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var side_axis := direction.cross(Vector3.UP).normalized()
	if side_axis.is_zero_approx():
		side_axis = Vector3.RIGHT
	var up_axis := side_axis.cross(direction).normalized()
	var angle := deg_to_rad(spread_degrees) * sqrt(randf())
	var around := randf() * TAU
	return direction.rotated(side_axis, angle * sin(around)).rotated(up_axis, angle * cos(around)).normalized()


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


## The yaw that points the model's front (-Z) along `direction`.
static func _yaw_toward(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
