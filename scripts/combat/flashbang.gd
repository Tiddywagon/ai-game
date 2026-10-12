class_name Flashbang
extends RefCounted
## A flashbang going off (DESIGN.md §13.6): blinds everyone within range who has a clear line to it,
## longest up close and looking at it, and makes a loud noise. There's no grenade to throw yet; the
## test level sets one off at the reticle with F9.

const NOISE_RADIUS := 80.0
const FLASH_TIME := 0.12


static func detonate(tree: SceneTree, position: Vector3) -> void:
	var vision := VisionSystem.config
	var ground := Vector2(position.x, position.z)
	for node in tree.get_nodes_in_group("actors"):
		var actor := node as Actor
		if actor.is_dead:
			continue
		var to := ground - Vector2(actor.global_position.x, actor.global_position.z)
		var distance := to.length()
		if distance > vision.flashbang_radius:
			continue
		var space := actor.get_world_3d().direct_space_state
		if not VisionSystem.line_clear(space, actor.global_position, Vector3(position.x, actor.global_position.y, position.z), false):
			continue
		# Looking at it: full effect; facing away: a fraction.
		var facing := clampf(actor.vision_facing().dot(to / maxf(distance, 0.01)), 0.0, 1.0)
		var look := lerpf(vision.flashbang_facing_away, 1.0, facing)
		actor.blind(vision.flashbang_max_blind * (1.0 - distance / vision.flashbang_radius) * look)
	NoiseSystem.emit_noise(position, NOISE_RADIUS, null, &"flashbang")
	_spawn_flash(tree, position)


static func _spawn_flash(tree: SceneTree, position: Vector3) -> void:
	var scene := tree.current_scene
	if scene == null:
		return
	# "Reduce flashing effects": a much dimmer flash.
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	var light := OmniLight3D.new()
	light.light_energy = 3.0 if reduced else 16.0
	light.omni_range = 14.0
	light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	light.top_level = true
	light.position = position + Vector3.UP * 0.5
	scene.add_child(light)
	tree.create_timer(FLASH_TIME, false).timeout.connect(light.queue_free)
