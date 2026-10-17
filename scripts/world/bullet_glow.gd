class_name BulletGlow
extends Node2D
## Hostile rounds coming your way, glowing faintly through the dark (DESIGN.md §13.6). PlayerVision
## hands it each round that passes near the player (from the muzzle to where it passes or hits them);
## the stretches of its path you can't see right now are drawn as a soft streak over the fog, fading
## out over VisionConfig.incoming_glow_time. Where you can see, the round's own tracer shows instead.
## Drawn on a canvas layer under the HUD, from the round's world positions, so it stays put as the
## camera moves.

## Pieces each round's path is cut into to decide which parts are in the dark.
const PIECES := 24
## The bright core's share of the glow's width, and how much brighter it is.
const CORE_WIDTH := 0.3
const CORE_BOOST := 1.6

var vision: PlayerVision
## Rounds glowing now: [{"from", "to", "age", "dark": PackedByteArray (1 per piece in the dark)}].
var streaks: Array[Dictionary] = []


func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


## Shows the round from `from` to `to`: its pieces you can't see glow. Nothing if all of it is in view
## (or the fog of war is off).
func add(from: Vector3, to: Vector3) -> void:
	var dark := PackedByteArray()
	var any := false
	for i in PIECES:
		var middle := from.lerp(to, (i + 0.5) / PIECES)
		var hidden := vision != null and vision.enabled and not vision.is_point_visible(middle)
		dark.append(1 if hidden else 0)
		any = any or hidden
	if any:
		streaks.append({"from": from, "to": to, "age": 0.0, "dark": dark})
		queue_redraw()


func _process(delta: float) -> void:
	if streaks.is_empty():
		return
	var life := VisionSystem.config.incoming_glow_time
	for streak in streaks:
		streak.age += delta
	streaks = streaks.filter(func(streak: Dictionary) -> bool: return streak.age < life)
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var config := VisionSystem.config
	for streak in streaks:
		var fade := 1.0 - float(streak.age) / config.incoming_glow_time
		var glow := Color(config.incoming_glow_color, config.incoming_glow_color.a * fade)
		var core := Color(glow, minf(glow.a * CORE_BOOST, 1.0))
		for run in dark_runs(streak.dark):
			var a: Vector3 = streak.from.lerp(streak.to, float(run.x) / PIECES)
			var b: Vector3 = streak.from.lerp(streak.to, float(run.y) / PIECES)
			if camera.is_position_behind(a) or camera.is_position_behind(b):
				continue
			var p := camera.unproject_position(a)
			var q := camera.unproject_position(b)
			draw_line(p, q, glow, config.incoming_glow_width, true)
			draw_line(p, q, core, config.incoming_glow_width * CORE_WIDTH, true)


## The stretches of a path in the dark, as piece ranges [start, end): one stroke each, so nothing is
## drawn twice where pieces meet.
static func dark_runs(dark: PackedByteArray) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var start := -1
	for i in dark.size() + 1:
		var hidden := i < dark.size() and dark[i] == 1
		if hidden and start < 0:
			start = i
		elif not hidden and start >= 0:
			runs.append(Vector2i(start, i))
			start = -1
	return runs
