class_name VisionView
extends RefCounted
## What one viewer (the player or a bot) can see right now (DESIGN.md §13.6): where they stand and
## look, their vision cones and awareness circle. Built by VisionSystem.view_for().
##
## Each cone is a Vector3: x = half angle (radians), y = range (metres, weather already applied),
## z = 1 if the cone brings its own light (a flashlight), so darkness doesn't shorten it.

## Feet position of the viewer.
var origin := Vector3.ZERO
## Flat unit direction the cones point in (x, z).
var facing := Vector2(0, -1)
var cones: Array[Vector3] = []
## Seen in every direction up to this distance (walls still block).
var awareness := 0.0
## Crouched, ducked or lying: sight lines run below low cover.
var low := false
## Physics space for sight-line rays.
var space: PhysicsDirectSpaceState3D


## How far this viewer sees in flat direction `direction` when the light there is `light` (0-1).
## `ignore_cones` treats every direction as inside the widest-reaching cone (a bot tracking its target).
func range_toward(direction: Vector2, light: float, config: VisionConfig, ignore_cones := false) -> float:
	var reach := awareness
	var offset := absf(facing.angle_to(direction)) if not direction.is_zero_approx() else 0.0
	for cone in cones:
		if ignore_cones or offset <= cone.x:
			reach = maxf(reach, cone.y if cone.z > 0.5 else cone.y * config.light_multiplier(light))
	return reach


## True if `direction` is inside a cone that brings its own light (the flashlight beam).
func lit_toward(direction: Vector2) -> bool:
	var offset := absf(facing.angle_to(direction))
	for cone in cones:
		if cone.z > 0.5 and offset <= cone.x:
			return true
	return false


## The longest reach of any cone (before darkness), or the awareness radius.
func max_range() -> float:
	var reach := awareness
	for cone in cones:
		reach = maxf(reach, cone.y)
	return reach
