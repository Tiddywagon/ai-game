class_name Player
extends Actor
## The player (DESIGN.md §13). Turns input into Actor intents: WASD moves relative to the screen,
## the body faces the mouse cursor, Shift sprints, C crouches, Space rolls, Q takes or leaves cover,
## holding right-click peeks out of cover, and left-click fires.

# Key presses arrive outside the physics tick; act on them in the next one.
var _roll_requested := false
var _cover_requested := false


func _ready() -> void:
	super()
	roll_finished.connect(_on_roll_finished)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("crouch"):
		set_crouching(not is_crouching)
	elif event.is_action_pressed("roll"):
		_roll_requested = true
	elif event.is_action_pressed("take_cover"):
		_cover_requested = true


func _think(_delta: float) -> void:
	move_input = _input_direction()
	sprint_input = Input.is_action_pressed("sprint")
	fire_input = Input.is_action_pressed("shoot")
	peek_input = Input.is_action_pressed("aim")
	_update_aim()
	if _roll_requested:
		_roll_requested = false
		# Roll the way you're moving, or toward the cursor when standing still.
		try_roll(move_input if not move_input.is_zero_approx() else aim_point - global_position)
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


## A roll that ends right next to cover, heading into it, snaps into that cover.
func _on_roll_finished(direction: Vector3) -> void:
	enter_cover(CoverSystem.find_snap_point(self, config.roll_snap_distance, direction))


## WASD as a direction on the ground, relative to the screen: W always moves up the screen.
func _input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0.0, input.y)
	var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var screen_up := Vector3(camera.global_basis.y.x, 0.0, camera.global_basis.y.z).normalized()
	return right * input.x - screen_up * input.y


## Aims at whoever is under the cursor, or else level with the gun at the ground point under it.
func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		has_aim = false
		return
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 200.0, HITBOX_MASK, [hitbox_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit.position
		has_aim = true
		return
	var ground: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(from, direction)
	has_aim = ground != null
	if has_aim:
		aim_point = ground + Vector3.UP * gun_height()
