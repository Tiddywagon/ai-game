class_name Ballistics
extends RefCounted
## Hitscan bullets (DESIGN.md §13.4, §6.4). A round stops at concrete and metal, goes through wood if its
## penetration is high enough, hits the first hitbox it reaches (where armor may stop it: ArmorRules),
## and warns everyone it passes close to that they're under fire. How far it reaches and how much
## damage it keeps with distance and through wood depend on its velocity. Every shot is also a loud
## noise for AI. Each surface or body a round hits gets a small impact burst (ImpactEffects); tracer
## rounds draw a bright coloured streak and give the shooter away from further off. Guns call this
## through Weapon.

const MAX_RANGE := 150.0
## Actors this close to a bullet's path are told they're under fire.
const NEAR_MISS_DISTANCE := 2.0
## Most surfaces a round can pass through before it's spent.
const MAX_SURFACES := 4
const TRACER_TIME := 0.08

static var _tracer_material: StandardMaterial3D
static var _dim_tracer_material: StandardMaterial3D
static var _tracer_materials := {}
## Tracer rounds' colours, by their "tracer" stat.
const TRACER_COLORS := {"red": Color(1.0, 0.25, 0.18), "green": Color(0.35, 1.0, 0.35)}


## Fires one round from `origin` along `direction`. `muzzle` is only where the tracer starts. The
## round's speed out of `gun` (the stats it's fired with, if any: WeaponStats.shot_speed()) sets its
## range, its damage falloff and the energy it keeps through wood; the gun's noise (a suppressor) how
## far the shot is heard. `damage_multiplier` scales the
## round's damage as it leaves the muzzle (a 360 trick shot), before wood, cover or armor reduce it.
## A shot shell calls this once per pellet, with `sound` only on the first, so the shot is heard once;
## subsonic ammo (its "noise" stat) is heard less far. Returns {"end": where it stopped, "hit": the
## Actor hit or null, "passed_through": wood surfaces crossed}.
static func fire(shooter: Actor, origin: Vector3, direction: Vector3, ammo: ItemData, muzzle: Vector3,
		gun: WeaponData = null, damage_multiplier := 1.0, sound := true) -> Dictionary:
	var config := shooter.config
	var space := shooter.get_world_3d().direct_space_state
	var damage := float(ammo.stats.get("damage", 40)) * damage_multiplier
	var penetration := float(ammo.stats.get("penetration", 20))
	var speed := WeaponStats.shot_speed(gun, ammo)
	var energy := minf(speed / config.reference_velocity, 1.0)
	var reach := MAX_RANGE * clampf(speed / config.reference_velocity, config.min_range_factor, 1.0)
	var exclude: Array[RID] = [shooter.get_rid(), shooter.hitbox_rid()]
	var end := origin + direction * reach
	var result := {"end": end, "hit": null, "passed_through": 0, "outcome": {}}
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
			var arriving := damage * damage_kept(config, origin.distance_to(hit.position), reach)
			var outcome := target.take_hit(arriving, shooter, hit.position, ArmorRules.shot(ammo, penetration))
			if not outcome.is_empty():
				shooter.on_hit_landed(target, float(outcome.damage), hit.position, outcome)
			result.hit = target
			result.outcome = outcome
			var stopped: bool = not outcome.get("penetrated", true)
			ImpactEffects.spawn(shooter.get_tree(), hit.position, hit.normal, ImpactEffects.Kind.METAL if stopped else ImpactEffects.Kind.FLESH)
			break
		var material := material_of(hit.collider)
		ImpactEffects.spawn(shooter.get_tree(), hit.position, hit.normal, ImpactEffects.kind_for(material))
		if material == CoverBox.CoverMaterial.WOOD and penetration >= config.wood_min_penetration:
			exclude.append(hit.rid)
			damage *= minf(config.wood_damage_kept * energy, 1.0)
			penetration -= config.wood_penetration_loss
			result.passed_through += 1
			result.end = end
			from = hit.position
			continue
		break
	var tracer := str(ammo.stats.get("tracer", ""))
	_warn_nearby(shooter, origin, result.end, config.tracer_warn_distance if tracer != "" else NEAR_MISS_DISTANCE)
	_spawn_tracer(shooter, muzzle, result.end, tracer, config.tracer_time)
	if sound:
		var loudness := (gun.noise_multiplier if gun else 1.0) * float(ammo.stats.get("noise", 1.0))
		NoiseSystem.emit_noise(origin, config.gunshot_noise * loudness, shooter, &"gunshot")
	return result


## Cover material of whatever a bullet hit: a CoverBox's, a "cover_material" meta (solid loot
## containers), or concrete for anything else.
static func material_of(collider: Object) -> CoverBox.CoverMaterial:
	if collider is CoverBox:
		return collider.cover_material
	if collider.has_meta("cover_material"):
		return collider.get_meta("cover_material")
	return CoverBox.CoverMaterial.CONCRETE


## Share of its damage a round keeps after `distance` metres of its `reach`: all of it up to the
## falloff start, then less in a straight line down to range_damage_kept at the end of its range.
static func damage_kept(config: CombatConfig, distance: float, reach: float) -> float:
	var start := reach * config.falloff_start
	if distance <= start:
		return 1.0
	return lerpf(1.0, config.range_damage_kept, clampf((distance - start) / maxf(reach - start, 0.01), 0.0, 1.0))


static func _warn_nearby(shooter: Actor, from: Vector3, to: Vector3, distance: float) -> void:
	for node in shooter.get_tree().get_nodes_in_group("actors"):
		var actor := node as Actor
		if actor == shooter or actor.is_dead:
			continue
		var chest := actor.chest_point()
		if chest.distance_to(Geometry3D.get_closest_point_to_segment(chest, from, to)) <= distance:
			actor.on_bullet_near(shooter)


## The streak a round leaves. Tracer rounds (`tracer` "red" or "green") draw a thicker, brighter
## streak in their colour that lasts `tracer_time`.
static func _spawn_tracer(shooter: Actor, from: Vector3, to: Vector3, tracer := "", tracer_time := 0.0) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	if _tracer_material == null:
		_tracer_material = _make_tracer_material(Color(1.0, 0.9, 0.55))
		_dim_tracer_material = _make_tracer_material(Color(0.62, 0.56, 0.42))
		for color_name: String in TRACER_COLORS:
			_tracer_materials[color_name] = _make_tracer_material(TRACER_COLORS[color_name])
	# "Reduce flashing effects" draws thinner, dimmer tracers.
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	var lit := tracer != "" and _tracer_materials.has(tracer)
	var width := (0.035 if reduced else 0.06) * (1.6 if lit else 1.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	var streak := MeshInstance3D.new()
	streak.mesh = mesh
	if lit:
		streak.material_override = _tracer_materials[tracer]
	else:
		streak.material_override = _dim_tracer_material if reduced else _tracer_material
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Placed once and never moved: don't let physics interpolation slide it in from the origin.
	streak.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	shooter.get_tree().current_scene.add_child(streak)
	var direction := (to - from) / length
	streak.look_at_from_position((from + to) / 2.0, to, Vector3.FORWARD if absf(direction.y) > 0.99 else Vector3.UP)
	shooter.get_tree().create_timer(maxf(tracer_time, TRACER_TIME) if lit else TRACER_TIME).timeout.connect(streak.queue_free)


static func _make_tracer_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
