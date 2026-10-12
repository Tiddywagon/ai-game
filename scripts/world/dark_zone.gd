@tool
class_name DarkZone
extends Node3D
## A dark room or other unlit area (DESIGN.md §13.6): inside it, vision is as short as at night unless
## a flashlight lights the way, and it looks darker on screen. A box of `size` centred on this node;
## keep it unrotated (the screen shading treats it as axis-aligned).

@export var size := Vector3(8.0, 3.0, 8.0)
## Light level inside (0 = pitch dark, 1 = daylight). Below 0: use dark_room_light from vision.tres.
@export_range(-1.0, 1.0, 0.05) var light := -1.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		VisionSystem.register_dark_zone(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		VisionSystem.unregister_dark_zone(self)


func contains(point: Vector3) -> bool:
	var local := point - global_position
	return absf(local.x) <= size.x / 2.0 and absf(local.y) <= size.y / 2.0 and absf(local.z) <= size.z / 2.0


func light_level() -> float:
	return light if light >= 0.0 else VisionSystem.config.dark_room_light


## Flat rectangle covered (x, z).
func flat_rect() -> Rect2:
	return Rect2(global_position.x - size.x / 2.0, global_position.z - size.z / 2.0, size.x, size.z)
