class_name QuestSite
extends Node3D
## Where a quest's place or mark objective wants its item (DESIGN.md §11): the RaidController puts one
## at each such location on the map at the start of a PMC raid. Stand in it and hold the interact key
## for the objective's "seconds" (QuestLog.PLACE_SECONDS if it doesn't say): moving, being hit or letting
## go cancels it. When the time is up the item leaves your inventory and the objective counts
## (QuestRaid.place()). A thin yellow post with a ring on the ground while there's something to place.

## The furthest reach a site has, in metres (a point of interest's site is at its centre).
const MAX_REACH := 3.0
## Moving faster than this (metres a second) cancels the placement.
const STILL_SPEED := 0.5
const COLOR := Color(1.0, 0.82, 0.3)

var raid: RaidController
var quest: Dictionary
var index := 0
var radius := 2.0
## Seconds held so far (-1: not placing), and who is placing.
var held := -1.0
var _player: Player
var _post: MeshInstance3D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("quest_sites")
	_post = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = 0.06
	mesh.height = 1.6
	_post.mesh = mesh
	_post.position.y = 0.8
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR * 0.6
	_post.material_override = material
	add_child(_post)


## Seconds the placement takes.
func seconds() -> float:
	return float(quest.objectives[index].get("seconds", QuestLog.PLACE_SECONDS))


func is_done() -> bool:
	return raid.quest_raid.progress(quest, index) >= QuestLog.objective_count(quest, index)


## How far through the placement it is (0-1), -1 when not placing (the HUD's ring).
func place_progress() -> float:
	return held / seconds() if held >= 0.0 else -1.0


func interact_reach() -> float:
	return radius


func interact_text() -> String:
	return "Hold to place %s (%s)" % [ExtractTable.item_name(QuestLog.place_item(quest, index)), quest.get("name", "")]


func can_interact(_who: Player) -> bool:
	return not is_done() and held < 0.0


## Starts placing: from here the key has to stay held (_physics_process()).
func interact(who: Player) -> void:
	if not who.inventory.all_items().any(func(item: ItemInstance) -> bool: return item.data.id == QuestLog.place_item(quest, index)):
		who.action_blocked.emit("You need %s on you" % ExtractTable.item_name(QuestLog.place_item(quest, index)))
		return
	_player = who
	held = 0.0
	if not who.hurt.is_connected(_on_hurt):
		who.hurt.connect(_on_hurt)


## Stops placing with `reason` shown.
func cancel(reason: String) -> void:
	if held < 0.0:
		return
	held = -1.0
	if _player:
		_player.action_blocked.emit(reason)


func _on_hurt(_damage: float) -> void:
	cancel("Hit: placing cancelled")


func _physics_process(delta: float) -> void:
	_post.visible = not is_done()
	if held < 0.0 or _player == null:
		return
	if _player.is_dead or raid.outcome:
		held = -1.0
		return
	if not Input.is_action_pressed("interact"):
		cancel("Let go: placing cancelled")
		return
	if Vector2(_player.velocity.x, _player.velocity.z).length() > STILL_SPEED:
		cancel("Moved: placing cancelled")
		return
	var offset := _player.global_position - global_position
	if Vector2(offset.x, offset.z).length() > radius:
		cancel("Left the spot: placing cancelled")
		return
	held += delta
	if held >= seconds():
		held = -1.0
		var reason := raid.quest_raid.place(quest, index, _player.inventory)
		if reason != "":
			_player.action_blocked.emit(reason)
