extends CanvasLayer
## Opens the inventory in a raid (DESIGN.md §7): Tab (or Back on a controller) toggles it. Searching a
## container or body (F) opens it with that loot beside you; walking away closes it. The game keeps
## running: you can still walk, but not shoot or aim, while it's open.

const SCREEN := preload("res://ui/inventory_screen.tscn")
## Searching closes once you're this much farther than the reach you opened it from.
const LOOT_LEEWAY := 1.0

@export var player: Player

var _screen: InventoryScreen
var _loot_source: Node3D


func _ready() -> void:
	layer = 40  # Under the pause menu.
	if player:
		player.died.connect(close)
		player.loot_requested.connect(_on_loot_requested)


func is_open() -> bool:
	return _screen != null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and not is_open() and player and not player.is_dead and not get_tree().paused:
		open()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _screen and is_instance_valid(_loot_source):
		var offset := _loot_source.global_position - player.global_position
		if Vector2(offset.x, offset.z).length() > Player.INTERACT_RANGE + LOOT_LEEWAY:
			close()


## Opens the inventory; with `loot` (a container's grid or a body's Inventory) shown beside it.
func open(loot: Variant = null, title := "", source: Node3D = null) -> void:
	if _screen:
		close()
	_screen = SCREEN.instantiate()
	_screen.inventory = player.inventory
	_screen.loot = loot
	_screen.loot_title = title
	_screen.loot_search = source.get("search") if source else null
	_loot_source = source
	_screen.closed.connect(_on_closed)
	add_child(_screen)
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if _screen:
		_screen.close()


func _on_loot_requested(title: String, loot: Variant, source: Node3D) -> void:
	if not player.is_dead and not get_tree().paused:
		open(loot, title, source)


func _on_closed() -> void:
	_screen = null
	_loot_source = null
	player.ui_open = false
	if not player.is_dead and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
