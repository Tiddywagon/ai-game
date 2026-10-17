@tool
class_name Door
extends Node3D
## A door in a doorway (DESIGN.md §5): F opens or closes it, swinging the panel 90° on its hinge.
## Closed, it blocks movement, sight and bullets (wood ones can be shot through, metal ones can't).
## A locked door needs its key (`key_id`) on you: F unlocks it, using one of the key's uses (the key is
## gone when they run out), and it stays unlocked for the raid. The AI opens unlocked doors it walks
## up to, and never paths through locked ones (RaidLevel bakes them shut). A door can instead be shut
## until the map's power comes on (`needs_power`: a blast door) or until a Lever is pulled (`lever_id`:
## a bunker's shutter); then it unlocks and swings open by itself (DESIGN.md §5.2). The node's origin is the
## middle of the doorway at floor level; the panel lies along local X, opening toward local -Z (or +Z
## with `opens_back`).

const SWING_TIME := 0.35
## AI within this distance of a closed, unlocked door opens it.
const AI_OPEN_DISTANCE := 1.4
const LOCKED_COLOR := Color(0.75, 0.2, 0.15)
const POWER_COLOR := Color(0.95, 0.65, 0.15)
const LEVER_COLOR := Color(0.35, 0.55, 0.85)
## Seconds between checks whether the power or lever has opened a shut door.
const MECHANISM_CHECK := 0.25

@export var width := 1.2:
	set(value):
		width = value
		_build()
@export var height := 2.2:
	set(value):
		height = value
		_build()
@export_enum("Wood", "Concrete", "Metal") var cover_material := 0:
	set(value):
		cover_material = value
		_build()
@export var opens_back := false
@export var locked := false:
	set(value):
		locked = value
		_build()
## The key that unlocks it (an item id), if locked.
@export var key_id := ""
## Locked (no key) until the map's power is on, or until the lever with this id is pulled.
@export var needs_power := false
@export var lever_id := ""
## For the map and prompts: "Office door".
@export var door_name := "Door"

var is_open := false
## The player who last looked at it, for the prompt (set by can_interact()).
var _viewer: Player
var _mechanism_timer := 0.0

var _pivot: Node3D
var _panel: StaticBody3D
var _tween: Tween

const THICKNESS := 0.1


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("doors")


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("interactables")
	VisionSystem.register_occluder(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		VisionSystem.unregister_occluder(self)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _tween and _tween.is_running():
		VisionSystem.mark_dirty()  # Sight follows the swinging panel.
	if locked and is_mechanical():
		_mechanism_timer -= delta
		if _mechanism_timer <= 0.0:
			_mechanism_timer = MECHANISM_CHECK
			if mechanism_ready():
				locked = false
				set_open(true)
		return
	if is_open or locked:
		return
	for bot in get_tree().get_nodes_in_group("bots"):
		if bot is Bot and not bot.is_dead and bot.ai_enabled and _flat_distance(bot.global_position) < AI_OPEN_DISTANCE:
			set_open(true)
			return


## Opens or closes the door (swinging; sight and movement follow the panel).
func set_open(open: bool) -> void:
	if open == is_open:
		return
	is_open = open
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var angle := (90.0 if not opens_back else -90.0) if open else 0.0
	_tween.tween_property(_pivot, "rotation_degrees:y", angle, SWING_TIME)
	_tween.tween_callback(VisionSystem.mark_dirty)


# --- Interaction ---------------------------------------------------------------------------------

func interact_reach() -> float:
	return maxf(2.0, width)


func can_interact(player: Player) -> bool:
	_viewer = player
	return not player.is_dead


## True for a door the power or a lever opens (rather than a key).
func is_mechanical() -> bool:
	return needs_power or lever_id != ""


## True once what opens a mechanical door has happened: the power is on, or its lever is pulled.
func mechanism_ready() -> bool:
	if needs_power:
		var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
		return raid != null and raid.power_state() == "on"
	return lever_id != "" and Lever.is_pulled(get_tree(), lever_id)


func interact_text() -> String:
	if locked and needs_power:
		return "Shut: the %s has no power" % door_name.to_lower()
	if locked and lever_id != "":
		return "Shut: the %s opens with a lever" % door_name.to_lower()
	if locked:
		var key := key_name()
		return "Unlock with the %s" % key if _held_key(_viewer) else "Locked: needs the %s" % key
	return ("Close the " if is_open else "Open the ") + door_name.to_lower()


func interact(player: Player) -> void:
	if not locked:
		set_open(not is_open)
		return
	if is_mechanical():
		player.action_blocked.emit(interact_text())
		return
	var key := _held_key(player)
	if key == null:
		player.action_blocked.emit("Locked: needs the %s" % key_name())
		return
	var left := Keys.use(key, player.inventory)
	locked = false
	set_open(true)
	player.action_blocked.emit("Unlocked: %s" % ("the %s is used up" % key.data.display_name if left <= 0 else "%d use%s left on the key" % [left, "" if left == 1 else "s"]))


func key_name() -> String:
	var data := ItemDB.get_item(key_id) if ItemDB.has_item(key_id) else null
	return data.display_name if data else "key"


func _held_key(player: Player) -> ItemInstance:
	if player == null or player.inventory == null or key_id == "":
		return null
	for item in player.inventory.all_items():
		if item.data.id == key_id:
			return item
	return null


## A box the AI's navigation is baked against while the door is locked (RaidLevel frees it after).
func nav_blocker() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("nav_bake_only")
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width + 0.2, height, 0.6)
	shape.shape = box
	body.add_child(shape)
	body.transform = global_transform.translated_local(Vector3(0, height / 2.0, 0))
	return body


# --- Vision occluder -----------------------------------------------------------------------------

func vision_corners() -> PackedVector2Array:
	return BoxFootprint.corners(_panel.global_transform, Vector3(width, height, THICKNESS))


func vision_height_span() -> Vector2:
	return Vector2(global_position.y, global_position.y + height)


func vision_depth(normal: Vector3) -> float:
	return BoxFootprint.depth(_panel.global_basis, Vector3(width, height, THICKNESS), normal)


# --- Look ----------------------------------------------------------------------------------------

func _build() -> void:
	if not is_inside_tree():
		return
	if _pivot:
		_pivot.free()
	_pivot = Node3D.new()
	_pivot.position = Vector3(-width / 2.0, 0, 0)
	add_child(_pivot)
	_panel = StaticBody3D.new()
	_panel.position = Vector3(width / 2.0, height / 2.0, 0)
	_panel.collision_layer = 1 | 8  # World and vision.
	_panel.collision_mask = 0
	_panel.set_meta("cover_material", cover_material)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, THICKNESS)
	shape.shape = box
	_panel.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = [Color(0.55, 0.4, 0.25), Color(0.7, 0.7, 0.66), Color(0.4, 0.45, 0.5)][cover_material]
	material.roughness = 0.8
	mesh.material_override = material
	_panel.add_child(mesh)
	if locked:
		var plate := MeshInstance3D.new()  # A red lock plate by the handle.
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(0.14, 0.22, THICKNESS + 0.04)
		plate.mesh = plate_mesh
		plate.position = Vector3(width / 2.0 - 0.18, 0.0, 0)
		var red := StandardMaterial3D.new()
		var plate_color := POWER_COLOR if needs_power else LEVER_COLOR if lever_id != "" else LOCKED_COLOR
		red.albedo_color = plate_color
		red.emission_enabled = true
		red.emission = plate_color * 0.5
		plate.material_override = red
		_panel.add_child(plate)
	_pivot.add_child(_panel)


func _flat_distance(at: Vector3) -> float:
	return Vector2(at.x - global_position.x, at.z - global_position.z).length()
