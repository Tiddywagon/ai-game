extends Node3D
## Test level for movement, cover and combat (DESIGN.md §13). Esc returns to the main menu.
## Debug keys: F1 leg fracture, F2 overweight, F3 swap ammo (PS / BS), F4 AI on/off.

const MAIN_MENU_SCENE := "res://ui/main_menu.tscn"
const RESTART_DELAY := 3.0
const AMMO_TYPES: Array[String] = ["ammo_545_ps", "ammo_545_bs"]

@onready var _player: Player = $Player
@onready var _hud := $HUD


func _ready() -> void:
	# Work out where the AI can walk from the level geometry, then rebuild cover points to match.
	($Navigation as NavigationRegion3D).bake_navigation_mesh(false)
	CoverSystem.mark_dirty()
	_player.died.connect(_on_player_died)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_player.has_leg_fracture = not _player.has_leg_fracture
			_hud.show_message("Leg fracture: %s" % ("on" if _player.has_leg_fracture else "off"))
		KEY_F2:
			_player.carried_weight_kg = 0.0 if _player.is_overweight() else _player.overweight_kg + 10.0
			_hud.show_message("Carrying %d kg%s" % [_player.carried_weight_kg, " (overweight)" if _player.is_overweight() else ""])
		KEY_F3:
			_player.set_ammo(AMMO_TYPES[(AMMO_TYPES.find(_player.ammo_id) + 1) % AMMO_TYPES.size()])
			_hud.show_message("Ammo: " + _player.ammo_label())
		KEY_F4:
			var bots := get_tree().get_nodes_in_group("bots")
			var enable: bool = bots.size() > 0 and not bots[0].ai_enabled
			for bot: Bot in bots:
				bot.ai_enabled = enable
			_hud.show_message("AI " + ("on" if enable else "off"))


func _on_player_died() -> void:
	get_tree().create_timer(RESTART_DELAY).timeout.connect(get_tree().reload_current_scene)
