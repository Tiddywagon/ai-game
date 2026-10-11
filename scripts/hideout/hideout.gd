extends Node3D
## Placeholder hideout (DESIGN.md §9). Esc returns to the main menu.

const MAIN_MENU_SCENE := "res://ui/main_menu.tscn"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
