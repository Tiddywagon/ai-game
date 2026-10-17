class_name PlayerVision
extends Node
## The player's vision, Project Zomboid style (DESIGN.md §13.6). Several times a second (update_rate in
## vision.tres) it traces what the player sees (VisionSystem.visibility_polygon), draws that area into
## a mask seen from above and hands it to a full-screen shader that darkens and greys out everything
## else, leaving the layout faintly visible in the dark (nothing seen before is remembered). Enemies and
## loot outside the view aren't drawn, sounds from things the player can't see are passed on to the HUD
## as direction markers, and hostile rounds coming at the player glow faintly through the dark
## (show_incoming(), BulletGlow).

## A sound the player hears but can't see the source of. `source_id` is 0 when there's no source node.
signal sound_heard(position: Vector3, kind: StringName, source_id: int)

const SHADER := preload("res://assets/shaders/vision.gdshader")
const MASK_CANVAS := preload("res://scripts/world/vision_mask_canvas.gd")
const MAX_DARK_ZONES := 8
## Mask colours: red = visible, green = in the flashlight beam.
const VISIBLE := Color(1, 0, 0)
const VISIBLE_LIT := Color(1, 1, 0)

@export var player: Player
## Off: no fog of war and everyone drawn (debugging; F10 in the test level).
@export var enabled := true:
	set(value):
		enabled = value
		if _quad:
			_quad.visible = value
		if is_inside_tree():
			_update()

## What the player sees (last update).
var view: VisionView
## Last traced area: see VisionSystem.visibility_polygon().
var area := {}

var _seen := {}
var _timer := 0.0
var _bounds := Rect2()
var _resolution := 1024.0
var _visible_canvas: Node2D
var _glow: BulletGlow
var _quad: MeshInstance3D
var _material: ShaderMaterial


func _ready() -> void:
	add_to_group("player_vision")
	NoiseSystem.noise_emitted.connect(_on_noise)
	_setup.call_deferred()  # Once the camera is current and every occluder has registered.


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer += 1.0 / VisionSystem.config.update_rate
		_update()


## True if the player saw `actor` at the last update.
func sees(actor: Node) -> bool:
	return _seen.get(actor.get_instance_id(), false)


## True if `position` (flat) was inside the visible area at the last update.
func is_point_visible(position: Vector3) -> bool:
	if area.is_empty():
		return false
	return Geometry2D.is_point_in_polygon(Vector2(position.x, position.z), area.points)


func _setup() -> void:
	var config := VisionSystem.config
	_bounds = VisionSystem.world_bounds()
	_resolution = config.mask_resolution
	_visible_canvas = _make_mask(SubViewport.CLEAR_MODE_ALWAYS, "visible_mask")
	_material.shader = SHADER
	_material.render_priority = Material.RENDER_PRIORITY_MAX
	_material.set_shader_parameter("bounds", Vector4(_bounds.position.x, _bounds.position.y, _bounds.size.x, _bounds.size.y))
	_material.set_shader_parameter("dark_brightness", config.dark_brightness)
	_material.set_shader_parameter("dark_saturation", config.dark_saturation)
	_material.set_shader_parameter("dark_room_shading", config.dark_room_shading)
	var zones: Array[Vector4] = []
	for zone in VisionSystem.dark_zones().slice(0, MAX_DARK_ZONES):
		var rect: Rect2 = zone.flat_rect()
		zones.append(Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	_material.set_shader_parameter("dark_zone_count", zones.size())
	zones.resize(MAX_DARK_ZONES)
	_material.set_shader_parameter("dark_zones", zones)

	# A screen-covering quad (its vertex shader ignores the camera) drawn after everything else.
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	quad_mesh.material = _material
	_quad = MeshInstance3D.new()
	_quad.name = "VisionMask"
	_quad.mesh = quad_mesh
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 16384.0
	_quad.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_quad.visible = enabled
	var camera := get_viewport().get_camera_3d()
	if camera:
		camera.add_child(_quad)
		_quad.position = Vector3(0.0, 0.0, -1.0)
	# Incoming rounds glow over the fog, under the HUD.
	var layer := CanvasLayer.new()
	layer.name = "IncomingFire"
	layer.layer = -1
	add_child(layer)
	_glow = BulletGlow.new()
	_glow.name = "BulletGlow"
	_glow.vision = self
	layer.add_child(_glow)
	_update()


## A round fired at (or past) the player from `from` to `to` by someone hostile (Ballistics): its path
## glows faintly where the player can't see it.
func show_incoming(from: Vector3, to: Vector3) -> void:
	if _glow:
		_glow.add(from, to)


## The incoming-fire glow (null until set up).
func bullet_glow() -> BulletGlow:
	return _glow


## A mask viewport (transparent, 2D only, square over the level) with a canvas to draw into, bound to
## shader parameter `parameter`.
func _make_mask(clear_mode: SubViewport.ClearMode, parameter: String) -> Node2D:
	if _material == null:
		_material = ShaderMaterial.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(_resolution), int(_resolution))
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.msaa_2d = Viewport.MSAA_4X
	viewport.render_target_clear_mode = clear_mode
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas: Node2D = MASK_CANVAS.new()
	viewport.add_child(canvas)
	_material.set_shader_parameter(parameter, viewport.get_texture())
	return canvas


func _update() -> void:
	if player == null or not is_instance_valid(player) or player.is_dead or _visible_canvas == null:
		return
	view = VisionSystem.view_for(player)
	area = VisionSystem.visibility_polygon(view)
	_draw_masks()
	for node: Node3D in get_tree().get_nodes_in_group("vision_hideable"):
		if node == player:
			continue
		var seen := not enabled
		if not seen:
			seen = VisionSystem.can_see(view, node) if node is Actor else VisionSystem.can_see_point(view, node.global_position)
		var id := node.get_instance_id()
		if _seen.get(id) != seen:
			node.set_seen(seen)
			_seen[id] = seen


## The visible area as a triangle fan around the player, plus the lit strips on top of walls being
## looked at, in mask pixels.
func _draw_masks() -> void:
	var origin := _to_mask(area.origin)
	var points: PackedVector2Array = area.points
	var lit: PackedByteArray = area.lit
	var faces: PackedVector2Array = area.faces
	var triangles := PackedVector2Array()
	var colors := PackedColorArray()
	var count := points.size()
	for i in count:
		var j := (i + 1) % count
		var color := VISIBLE_LIT if lit[i] and lit[j] else VISIBLE
		triangles.append_array([origin, _to_mask(points[i]), _to_mask(points[j])])
		colors.append_array([color, color, color])
	for k in range(0, faces.size(), 4):
		var a := _to_mask(faces[k])
		var b := _to_mask(faces[k + 1])
		var c := _to_mask(faces[k + 2])
		var d := _to_mask(faces[k + 3])
		triangles.append_array([a, b, c, a, c, d])
		for n in 6:
			colors.append(VISIBLE)
	_visible_canvas.set_triangles(triangles, colors)


func _to_mask(point: Vector2) -> Vector2:
	return (point - _bounds.position) / _bounds.size * _resolution


func _on_noise(position: Vector3, radius: float, source: Node, kind: StringName) -> void:
	if player == null or not is_instance_valid(player) or player.is_dead or source == player or not enabled:
		return
	if player.global_position.distance_to(position) > radius * player.hearing_multiplier():
		return  # Too far to hear (a headset hears further, a helmet muffles).
	if source is Actor:
		if sees(source):
			return
	elif is_point_visible(position):
		return
	sound_heard.emit(position, kind, source.get_instance_id() if source else 0)
