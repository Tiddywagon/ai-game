class_name ThrownGrenade
extends Node3D
## A thrown grenade (DESIGN.md §13.4.2): it flies in an arc to where it was thrown (at most MAX_RANGE),
## lies there until its fuse runs out, then goes off. A frag hurts everyone within its radius who isn't
## behind something solid (more up close; no armor stops it); a flash is a Flashbang. Both are loud.
## Thrown from a hotkey or the hotkey wheel (Player.throw_item()).

## The grenade went off (`at`: where).
signal exploded(at: Vector3)

const MAX_RANGE := 20.0
## Horizontal throw speed (m/s) and how high the arc rises per metre thrown.
const THROW_SPEED := 14.0
const ARC_PER_METRE := 0.18
const NOISE_RADIUS := 70.0
const BLAST_COLOR := Color(1.0, 0.62, 0.25)

var thrower: Actor
## "frag" or "flash" (the item's "grenade" stat).
var kind := "frag"
var item_name := "Grenade"
var fuse := 3.0
var radius := 7.0
var damage := 140.0
## Where it lands.
var target := Vector3.ZERO
var has_exploded := false

var _from := Vector3.ZERO
var _flight := 0.5


## Throws a grenade of `data` from `actor` toward `at` (clamped to MAX_RANGE) and returns it.
static func throw(actor: Actor, data: ItemData, at: Vector3) -> ThrownGrenade:
	var grenade := ThrownGrenade.new()
	grenade.thrower = actor
	grenade.kind = str(data.stats.get("grenade", "frag"))
	grenade.item_name = data.display_name
	grenade.fuse = float(data.stats.get("fuse", 3.0))
	grenade.radius = float(data.stats.get("radius", 7.0))
	grenade.damage = float(data.stats.get("damage", 140.0))
	var start := actor.global_position + Vector3.UP * actor.gun_height()
	var flat := Vector3(at.x - start.x, 0.0, at.z - start.z)
	if flat.length() > MAX_RANGE:
		flat = flat.normalized() * MAX_RANGE
	grenade.target = Vector3(start.x + flat.x, actor.global_position.y + 0.1, start.z + flat.z)
	grenade._from = start
	actor.get_tree().current_scene.add_child(grenade)
	grenade.global_position = start
	return grenade


func _ready() -> void:
	var body := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = 0.09
	shape.height = 0.16
	body.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.33, 0.22) if kind == "frag" else Color(0.55, 0.58, 0.6)
	body.material_override = material
	add_child(body)
	var distance := Vector2(target.x - _from.x, target.z - _from.z).length()
	_flight = clampf(distance / THROW_SPEED, 0.2, 1.4)
	var rise := 0.5 + distance * ARC_PER_METRE
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		global_position = _from.lerp(target, t) + Vector3.UP * rise * 4.0 * t * (1.0 - t), 0.0, 1.0, _flight)
	tween.tween_interval(maxf(fuse - _flight, 0.1))
	tween.tween_callback(explode)


## Goes off where it is now.
func explode() -> void:
	if has_exploded:
		return
	has_exploded = true
	var at := global_position
	if kind == "flash":
		Flashbang.detonate(get_tree(), at)
	else:
		_blast(at)
		NoiseSystem.emit_noise(at, NOISE_RADIUS, thrower, &"explosion")
		_spawn_flash(at)
	exploded.emit(at)
	queue_free()


## Everyone within the radius in the open takes damage, falling off with distance.
func _blast(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("actors"):
		var actor := node as Actor
		if actor == null or actor.is_dead:
			continue
		var chest := actor.chest_point()
		var distance := chest.distance_to(at)
		if distance > radius:
			continue
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, chest, Actor.WORLD_MASK)
		if not space.intersect_ray(query).is_empty():
			continue  # Behind something solid.
		var hurt := damage * (1.0 - distance / radius)
		actor.take_blow(hurt, thrower, "explosion", item_name, chest)
		if is_instance_valid(thrower) and thrower != actor:
			thrower.on_hit_landed(actor, hurt, chest)
		actor.on_bullet_near(thrower)


func _spawn_flash(at: Vector3) -> void:
	var scene := get_tree().current_scene
	var light := OmniLight3D.new()
	light.light_color = BLAST_COLOR
	light.light_energy = 2.0 if Settings.get_value("accessibility", "reduce_flashing") else 8.0
	light.omni_range = radius * 1.6
	light.top_level = true
	scene.add_child(light)
	light.global_position = at + Vector3.UP * 0.6
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(BLAST_COLOR, 0.7)
	ball.material_override = material
	ball.top_level = true
	scene.add_child(ball)
	ball.global_position = at + Vector3.UP * 0.4
	var tween := scene.create_tween()
	tween.tween_property(ball, "scale", Vector3.ONE * radius * 0.5, 0.25)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.35)
	tween.tween_callback(ball.queue_free)
	tween.tween_callback(light.queue_free)
