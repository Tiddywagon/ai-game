class_name Ballistics
extends RefCounted
## Hitscan bullets (DESIGN.md §13.4). A round stops at concrete and metal, goes through wood if its
## penetration is high enough, damages the first hitbox it reaches, and warns everyone it passes
## close to that they're under fire. Every shot is also a loud noise for AI. Each surface or body a
## round hits gets a small impact burst (ImpactEffects). Guns call this through Weapon.

const MAX_RANGE := 150.0
## Actors this close to a bullet's path are told they're under fire.
const NEAR_MISS_DISTANCE := 2.0
## Most surfaces a round can pass through before it's spent.
const MAX_SURFACES := 4
const TRACER_TIME := 0.08

static var _tracer_material: StandardMaterial3D
static var _dim_tracer_material: StandardMaterial3D


## Fires one round from `origin` along `direction`. `muzzle` is only where the tracer starts. `gun`
## (the stats it's fired with, if any) scales the range and the energy kept through wood by its muzzle
## velocity, and how far the shot is heard by its noise (a suppressor). `damage_multiplier` scales the
## round's damage as it leaves the muzzle (a 360 trick shot), before wood, cover or armor reduce it.
## Returns {"end": where it stopped, "hit": the Actor hit or null, "passed_through": wood surfaces crossed}.
static func fire(shooter: Actor, origin: Vector3, direction: Vector3, ammo: ItemData, muzzle: Vector3,
		gun: WeaponData = null, damage_multiplier := 1.0) -> Dictionary:
	var config := shooter.config
	var space := shooter.get_world_3d().direct_space_state
	var damage := float(ammo.stats.get("damage", 40)) * damage_multiplier
	var penetration := float(ammo.stats.get("penetration", 20))
	var velocity := gun.velocity_multiplier if gun else 1.0
	var exclude: Array[RID] = [shooter.get_rid(), shooter.hitbox_rid()]
	var end := origin + direction * MAX_RANGE * velocity
	var result := {"end": end, "hit": null, "passed_through": 0}
	var from := origin
	for i in MAX_SURFACES:
		var query := PhysicsRayQueryParameters3D.create(from, end, Actor.WORLD_MASK | Actor.HITBOX_MASK, exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		result.end = hit.position
		var target: Actor = (hit.collider as Node).get_parent() as Actor if hit.collider is Area3D else null
		if target and target.body_part_at(hit.position, origin) < 0:
			exclude.append(hit.rid)  # Beside the head, over the shoulder: a near miss.
			from = hit.position
			continue
		if target:
			target.take_hit(damage, shooter, hit.position)
			shooter.on_hit_landed(target, damage, hit.position)
			result.hit = target
			ImpactEffects.spawn(shooter.get_tree(), hit.position, hit.normal, ImpactEffects.Kind.FLESH)
			break
		var material := material_of(hit.collider)
		ImpactEffects.spawn(shooter.get_tree(), hit.position, hit.normal, ImpactEffects.kind_for(material))
		if material == CoverBox.CoverMaterial.WOOD and penetration >= config.wood_min_penetration:
			exclude.append(hit.rid)
			damage *= minf(config.wood_damage_kept * velocity, 1.0)
			penetration -= config.wood_penetration_loss
			result.passed_through += 1
			result.end = end
			from = hit.position
			continue
		break
	_warn_nearby(shooter, origin, result.end)
	_spawn_tracer(shooter, muzzle, result.end)
	NoiseSystem.emit_noise(origin, config.gunshot_noise * (gun.noise_multiplier if gun else 1.0), shooter, &"gunshot")
	return result


## Cover material of whatever a bullet hit: a CoverBox's, a "cover_material" meta (solid loot
## containers), or concrete for anything else.
static func material_of(collider: Object) -> CoverBox.CoverMaterial:
	if collider is CoverBox:
		return collider.cover_material
	if collider.has_meta("cover_material"):
		return collider.get_meta("cover_material")
	return CoverBox.CoverMaterial.CONCRETE


static func _warn_nearby(shooter: Actor, from: Vector3, to: Vector3) -> void:
	for node in shooter.get_tree().get_nodes_in_group("actors"):
		var actor := node as Actor
		if actor == shooter or actor.is_dead:
			continue
		var chest := actor.chest_point()
		if chest.distance_to(Geometry3D.get_closest_point_to_segment(chest, from, to)) <= NEAR_MISS_DISTANCE:
			actor.on_bullet_near(shooter)


static func _spawn_tracer(shooter: Actor, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	if _tracer_material == null:
		_tracer_material = _make_tracer_material(Color(1.0, 0.9, 0.55))
		_dim_tracer_material = _make_tracer_material(Color(0.62, 0.56, 0.42))
	# "Reduce flashing effects" draws thinner, dimmer tracers.
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	var width := 0.035 if reduced else 0.06
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	tracer.material_override = _dim_tracer_material if reduced else _tracer_material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Placed once and never moved: don't let physics interpolation slide it in from the origin.
	tracer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	shooter.get_tree().current_scene.add_child(tracer)
	var direction := (to - from) / length
	tracer.look_at_from_position((from + to) / 2.0, to, Vector3.FORWARD if absf(direction.y) > 0.99 else Vector3.UP)
	shooter.get_tree().create_timer(TRACER_TIME).timeout.connect(tracer.queue_free)


static func _make_tracer_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
