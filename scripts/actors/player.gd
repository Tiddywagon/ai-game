class_name Player
extends Actor
## The player (DESIGN.md §13). Turns input into Actor intents: WASD moves relative to the screen,
## the body faces the in-raid reticle, Shift sprints, C crouches, Space rolls, Q takes or leaves cover,
## right-click peeks out of cover, left-click fires and R reloads.
## In a raid the mouse is captured and moves the reticle (`cursor_position`) at the sensitivity set in
## Settings; a controller's right stick moves it too. Sprint, crouch and aim can hold or toggle.

## Emitted when one of the player's bullets hits someone (hit markers, damage numbers).
signal hit_landed(target: Actor, damage: float, position: Vector3)

## Right stick: how far from the player it puts the reticle, and how fast the reticle gets there.
const STICK_AIM_RADIUS := 360.0
const STICK_AIM_SPEED := 2600.0
## Camera shake strength per hit taken (0-1, scaled by Settings). Each gun sets its own kick per shot.
const HIT_SHAKE := 0.45

## Where the reticle is, in viewport pixels.
var cursor_position := Vector2.ZERO
## Enemies killed this raid.
var kills := 0

var _roll_requested := false
var _cover_requested := false
var _sprint_toggled := false
var _aim_toggled := false
var _reload_requested := false


func _ready() -> void:
	super()
	roll_finished.connect(_on_roll_finished)
	cursor_position = get_viewport().get_visible_rect().size * Vector2(0.5, 0.38)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: Vector2 = event.relative * _sensitivity()
			if Settings.get_value("controls", "invert_mouse"):
				motion.y = -motion.y
			_move_cursor(motion)
		return
	if event.is_action_pressed("crouch") and Settings.is_toggle("crouch_mode"):
		set_crouching(not is_crouching)
	elif event.is_action_pressed("sprint") and Settings.is_toggle("sprint_mode"):
		_sprint_toggled = not _sprint_toggled
	elif event.is_action_pressed("aim") and Settings.is_toggle("aim_mode"):
		_aim_toggled = not _aim_toggled
	elif event.is_action_pressed("roll"):
		_roll_requested = true
	elif event.is_action_pressed("take_cover"):
		_cover_requested = true
	elif event.is_action_pressed("reload"):
		_reload_requested = true


func _process(delta: float) -> void:
	if not Settings.get_value("controls", "controller_enabled"):
		return
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var camera := get_viewport().get_camera_3d()
	if stick != Vector2.ZERO and camera:
		# Twin-stick aiming: the stick points the reticle out from the player.
		var center := camera.unproject_position(global_position + Vector3.UP * gun_height())
		var speed: float = STICK_AIM_SPEED * Settings.get_value("controls", "controller_sensitivity")
		_move_cursor(cursor_position.move_toward(center + stick * STICK_AIM_RADIUS, speed * delta) - cursor_position)


func _think(_delta: float) -> void:
	move_input = _input_direction()
	var moving := not move_input.is_zero_approx()
	if Settings.is_toggle("sprint_mode"):
		_sprint_toggled = _sprint_toggled and moving  # Stopping ends a toggled sprint.
		sprint_input = _sprint_toggled
	else:
		sprint_input = Input.is_action_pressed("sprint")
	if not Settings.is_toggle("crouch_mode") and cover == null:
		set_crouching(Input.is_action_pressed("crouch") and not (sprint_input and moving))
	fire_input = Input.is_action_pressed("shoot")
	auto_reload = Settings.get_value("gameplay", "auto_reload")
	if _reload_requested:
		_reload_requested = false
		try_reload()
	peek_input = _aim_toggled if Settings.is_toggle("aim_mode") else Input.is_action_pressed("aim")
	_update_aim()
	if _roll_requested:
		_roll_requested = false
		# Roll the way you're moving, or toward the reticle when standing still.
		try_roll(move_input if moving else aim_point - global_position)
	if _cover_requested:
		_cover_requested = false
		if cover:
			exit_cover()
		else:
			var spot := CoverSystem.find_snap_point(self, config.cover_snap_distance)
			if spot:
				enter_cover(spot)
			else:
				action_blocked.emit("No cover nearby")


func on_hit_landed(target: Actor, damage: float, hit_position: Vector3) -> void:
	if target.is_dead:
		kills += 1  # Corpses can't be hit, so this hit was the kill.
	hit_landed.emit(target, damage, hit_position)
	if Settings.get_value("gameplay", "damage_numbers"):
		_spawn_damage_number(hit_position, damage)


func take_hit(damage: float, from: Actor, hit_position: Vector3) -> void:
	super(damage, from, hit_position)
	_shake_camera(HIT_SHAKE)


func _on_fired() -> void:
	_shake_camera(weapon.data.camera_kick)


## A roll that ends right next to cover, heading into it, snaps into that cover.
func _on_roll_finished(direction: Vector3) -> void:
	enter_cover(CoverSystem.find_snap_point(self, config.roll_snap_distance, direction))


func _sensitivity() -> float:
	return Settings.get_value("controls", "aim_sensitivity" if peek_input else "mouse_sensitivity")


func _move_cursor(motion: Vector2) -> void:
	cursor_position = (cursor_position + motion).clamp(Vector2.ZERO, get_viewport().get_visible_rect().size)


## WASD as a direction on the ground, relative to the screen: W always moves up the screen.
func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0.0, input.y)
	var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var screen_up := Vector3(camera.global_basis.y.x, 0.0, camera.global_basis.y.z).normalized()
	return right * input.x - screen_up * input.y


## Aims at the chest of whoever is under the reticle, or else level with the gun at the ground point
## under it.
func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		has_aim = false
		return
	var from := camera.project_ray_origin(cursor_position)
	var direction := camera.project_ray_normal(cursor_position)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 200.0, HITBOX_MASK, [hitbox_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target := (hit.collider as Node).get_parent() as Actor if not hit.is_empty() else null
	if target:
		# Centre mass: the reticle picks who, spread and sway decide which body part gets hit.
		aim_point = target.chest_point()
		has_aim = true
		return
	var ground: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(from, direction)
	has_aim = ground != null
	if has_aim:
		aim_point = ground + Vector3.UP * gun_height()


func _shake_camera(amount: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("add_shake"):
		camera.add_shake(amount)


func _spawn_damage_number(at: Vector3, damage: float) -> void:
	var label := Label3D.new()
	label.text = str(roundi(damage))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 42
	label.outline_size = 10
	label.modulate = Color(1.0, 0.85, 0.4)
	label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().current_scene.add_child(label)
	label.global_position = at + Vector3.UP * 0.3
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
