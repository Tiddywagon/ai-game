class_name ImpactEffects
extends RefCounted
## Placeholder bullet-impact effects (DESIGN.md §13.4): a short one-shot burst of particles where a
## round hits, coloured by what it hit. Grey dust off concrete, bright sparks off metal, splinters
## off wood, a red puff off a body.

enum Kind { CONCRETE, WOOD, METAL, FLESH }

## Per kind: particle colour, count, speed range (m/s), lifetime (s) and gravity scale.
const STYLES := {
	Kind.CONCRETE: {"color": Color(0.72, 0.68, 0.6), "amount": 10, "speed": Vector2(1.5, 3.5), "lifetime": 0.35, "gravity": 0.6},
	Kind.WOOD: {"color": Color(0.55, 0.38, 0.2), "amount": 10, "speed": Vector2(2.0, 4.0), "lifetime": 0.4, "gravity": 1.0},
	Kind.METAL: {"color": Color(1.0, 0.82, 0.4), "amount": 14, "speed": Vector2(3.0, 7.0), "lifetime": 0.25, "gravity": 0.8},
	Kind.FLESH: {"color": Color(0.5, 0.04, 0.04), "amount": 12, "speed": Vector2(1.0, 2.5), "lifetime": 0.3, "gravity": 0.5},
}
## Particles leave within this angle of the surface normal.
const SPREAD_DEGREES := 40.0
const PARTICLE_SIZE := Vector2(0.035, 0.07)

static var _mesh: BoxMesh
static var _shrink: Curve


## Spawns a burst at `position` (in the current scene), pointing away from the surface along `normal`.
static func spawn(tree: SceneTree, position: Vector3, normal: Vector3, kind: Kind) -> void:
	var scene := tree.current_scene
	if scene == null:
		return
	if _mesh == null:
		_build_shared()
	var style: Dictionary = STYLES[kind]
	var particles := CPUParticles3D.new()
	particles.emitting = false  # Start only once it's in place (see below).
	particles.mesh = _mesh
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = style.amount
	particles.lifetime = style.lifetime
	particles.direction = Vector3.UP
	particles.spread = SPREAD_DEGREES
	particles.initial_velocity_min = style.speed.x
	particles.initial_velocity_max = style.speed.y
	particles.gravity = Vector3.DOWN * 9.8 * style.gravity
	particles.scale_amount_min = PARTICLE_SIZE.x
	particles.scale_amount_max = PARTICLE_SIZE.y
	particles.scale_amount_curve = _shrink
	particles.color = style.color
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Placed once and never moved: don't let physics interpolation slide it in from the origin.
	particles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Emit along the surface normal (particles.direction is local +Y). Positioned before entering the
	# tree, as the particles would otherwise start from the world origin.
	var up := normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	var basis := Basis(Vector3.RIGHT, PI) if up.y < -0.999 else Basis(Quaternion(Vector3.UP, up))
	particles.top_level = true
	particles.transform = Transform3D(basis, position + up * 0.02)
	scene.add_child(particles)
	particles.restart()
	tree.create_timer(style.lifetime + 0.1, false).timeout.connect(particles.queue_free)


## What kind of burst a bullet makes on a CoverBox material.
static func kind_for(material: CoverBox.CoverMaterial) -> Kind:
	match material:
		CoverBox.CoverMaterial.WOOD:
			return Kind.WOOD
		CoverBox.CoverMaterial.METAL:
			return Kind.METAL
	return Kind.CONCRETE


static func _build_shared() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true  # Takes each particle's colour.
	_mesh = BoxMesh.new()
	_mesh.size = Vector3.ONE
	_mesh.material = material
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0.0, 1.0))
	_shrink.add_point(Vector2(1.0, 0.0))
