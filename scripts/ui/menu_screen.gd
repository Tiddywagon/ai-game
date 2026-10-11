class_name MenuScreen
extends Control
## Base for screens opened from the main or pause menu (DESIGN.md §16). Esc / B goes back, and
## `closed` tells the menu underneath to show itself again.

signal closed


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


## What Esc / B does. Closes the screen; override to step back first.
func _on_cancel() -> void:
	close()


func close() -> void:
	closed.emit()
	queue_free()
