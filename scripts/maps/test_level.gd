extends Node3D
## Test level for movement, cover and combat (DESIGN.md §13). Esc / Start opens the pause menu.
## Uses the side and loadout picked in ENTER RAID (GameState.raid); run on its own it plays as a PMC.
## Debug keys: F1 left leg fracture, F2 overweight, F3 swap ammo (PS / BS), F4 AI on/off, F5 heal.

const DEATH_SCREEN := preload("res://ui/death_screen.tscn")
## Seconds between dying and the death screen.
const DEATH_DELAY := 1.5
const AMMO_TYPES: Array[String] = ["ammo_545_ps", "ammo_545_bs"]

@onready var _player: Player = $Player
@onready var _hud := $HUD

var _start_msec := 0


func _ready() -> void:
	# Work out where the AI can walk from the level geometry, then rebuild cover points to match.
	($Navigation as NavigationRegion3D).bake_navigation_mesh(false)
	CoverSystem.mark_dirty()
	_apply_raid()
	_start_msec = Time.get_ticks_msec()
	_player.died.connect(_on_player_died)


## Plays as the side picked in ENTER RAID with that loadout's gun, loaded ammo, and the matching
## rounds from the pockets as spare ammo. Run on its own, the player keeps the default AK-74N.
func _apply_raid() -> void:
	var raid := GameState.raid
	if raid.get("side") == "scav":
		_player.side = Actor.Side.SCAV
	var loadout: Dictionary = raid.get("loadout", {})
	if loadout.is_empty():
		return
	var ammo: String = loadout.get("weapon_ammo", "")
	var spare := 0
	for pocket: Dictionary in loadout.get("pockets", []):
		if ammo != "" and pocket.get("id", "") == ammo:
			spare += int(pocket.get("count", 0))
	_player.equip_weapon(loadout.get("equipment", {}).get("primary", ""), ammo, spare)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			var leg := BodyHealth.Part.LEFT_LEG
			_player.health.set_fracture(leg, not _player.health.fractures[leg])
			_hud.show_message("Left leg fracture: %s" % ("on" if _player.health.fractures[leg] else "off"))
		KEY_F2:
			_player.carried_weight_kg = 0.0 if _player.is_overweight() else _player.overweight_kg + 10.0
			_hud.show_message("Carrying %s%s" % [Settings.format_weight(_player.carried_weight_kg), " (overweight)" if _player.is_overweight() else ""])
		KEY_F3:
			_player.set_ammo(AMMO_TYPES[(AMMO_TYPES.find(_player.ammo_id) + 1) % AMMO_TYPES.size()])
			_hud.show_message("Ammo: " + _player.ammo_label())
		KEY_F4:
			var bots := get_tree().get_nodes_in_group("bots")
			var enable: bool = bots.size() > 0 and not bots[0].ai_enabled
			for bot: Bot in bots:
				bot.ai_enabled = enable
			_hud.show_message("AI " + ("on" if enable else "off"))
		KEY_F5:
			if not _player.is_dead:
				_player.health.heal_all()
				_hud.show_message("Healed")


## A moment after dying, the death screen says what killed you (DESIGN.md §16.5).
func _on_player_died() -> void:
	var raid_seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
	get_tree().create_timer(DEATH_DELAY).timeout.connect(func() -> void:
		_hud.visible = false
		var screen := DEATH_SCREEN.instantiate()
		add_child(screen)
		screen.show_death(_player, raid_seconds))
