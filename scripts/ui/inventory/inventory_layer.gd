extends CanvasLayer
## Opens the inventory in a raid (DESIGN.md §7): Tab (or Back on a controller) toggles it. The game
## keeps running: you can still walk, but not shoot or aim, while it's open.

const SCREEN := preload("res://ui/inventory_screen.tscn")

@export var player: Player

var _screen: InventoryScreen


func _ready() -> void:
	layer = 40  # Under the pause menu.
	if player:
		player.died.connect(close)


func is_open() -> bool:
	return _screen != null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and not is_open() and player and not player.is_dead and not get_tree().paused:
		open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_screen = SCREEN.instantiate()
	_screen.inventory = player.inventory
	_screen.closed.connect(_on_closed)
	add_child(_screen)
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if _screen:
		_screen.close()


func _on_closed() -> void:
	_screen = null
	player.ui_open = false
	if not player.is_dead and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
