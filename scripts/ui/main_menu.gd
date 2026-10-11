extends Control
## Main menu. Play will lead to the hideout, the start of the core loop (DESIGN.md §2).
## Until the hideout exists, Play opens the movement test level.

const PLAY_SCENE := "res://maps/test_level.tscn"

@onready var play_button: Button = %PlayButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_button.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(PLAY_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
