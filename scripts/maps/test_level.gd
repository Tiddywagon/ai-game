extends Node3D
## Test level for movement, cover and combat (DESIGN.md §13). Esc / Start opens the pause menu.
## Uses the side and loadout picked in ENTER RAID (GameState.raid); run on its own it plays as a PMC
## (and the raid's ending doesn't touch your profile). Search the containers and bodies (F), pick up
## loose loot, and extract at the green ring in the north-east corner (RaidController).
## Debug keys: F1 left leg fracture, F2 overweight, F3 swap ammo (PS / BS, adds 60 if you have none), F4 AI on/off, F5 heal,
## F6 cycle the gun's sight, F7 time of day, F8 weather, F9 flashbang at the reticle, F10 fog of war off.

const DEATH_SCREEN := preload("res://ui/death_screen.tscn")
const RESULT_SCREEN := preload("res://ui/raid_result_screen.tscn")
## Seconds between dying and the death screen.
const DEATH_DELAY := 1.5
const AMMO_TYPES: Array[String] = ["ammo_545_ps", "ammo_545_bs"]

@onready var _player: Player = $Player
@onready var _hud := $HUD
@onready var _environment: RaidEnvironment = $RaidEnvironment
@onready var _vision: PlayerVision = $PlayerVision
@onready var _raid: RaidController = $Raid

var _start_msec := 0


func _ready() -> void:
	# Work out where the AI can walk from the level geometry, then rebuild cover points to match.
	($Navigation as NavigationRegion3D).bake_navigation_mesh(false)
	CoverSystem.mark_dirty()
	_apply_raid()
	_start_msec = Time.get_ticks_msec()
	_player.died.connect(_on_player_died)
	_raid.raid_ended.connect(_on_raid_ended)


## Plays as the side picked in ENTER RAID, carrying that loadout (an Inventory). Run on its own, the
## player gets the starter kit.
func _apply_raid() -> void:
	var raid := GameState.raid
	if raid.get("side") == "scav":
		_player.side = Actor.Side.SCAV
	var loadout: Variant = raid.get("loadout")
	_player.set_inventory(loadout if loadout is Inventory else Inventory.starter())


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
			_player.debug_extra_weight = 0.0 if _player.is_overweight() else _player.inventory_config.overweight_kg + 10.0
			_hud.show_message("Carrying %s%s" % [Settings.format_weight(_player.carried_weight_kg), " (overweight)" if _player.is_overweight() else ""])
		KEY_F3:
			var ammo: String = AMMO_TYPES[(AMMO_TYPES.find(_player.ammo_id) + 1) % AMMO_TYPES.size()]
			if _player.inventory.count_of(ammo) == 0:
				var spare := ItemInstance.create(ammo, 60)  # Something to reload with.
				spare.brought_in = true  # A debug gift, not loot.
				_player.inventory.add(spare)
			_player.set_ammo(ammo)
			_player.weapon.spare_rounds = _player.inventory.count_of(ammo)
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
		KEY_F6:
			var sights := VisionConfig.Optic.BINOCULARS  # Every optic before the binoculars fits a gun.
			_player.weapon.optic = (_player.weapon.optic + 1) % sights
			_hud.show_message("Sight: " + VisionSystem.config.optic(_player.weapon.optic).display_name)
		KEY_F7:
			_environment.apply((_environment.time_of_day + 1) % VisionConfig.TimeOfDay.size(), _environment.weather)
			_hud.show_message("Time: " + VisionSystem.time_name(_environment.time_of_day))
		KEY_F8:
			_environment.apply(_environment.time_of_day, (_environment.weather + 1) % VisionConfig.Weather.size())
			_hud.show_message("Weather: " + VisionSystem.weather_name(_environment.weather))
		KEY_F9:
			if _player.has_aim:
				Flashbang.detonate(get_tree(), Vector3(_player.aim_point.x, 0.2, _player.aim_point.z))
		KEY_F10:
			_vision.enabled = not _vision.enabled
			_hud.show_message("Fog of war " + ("on" if _vision.enabled else "off"))


## A moment after dying, the death screen says what killed you (DESIGN.md §16.5).
func _on_player_died() -> void:
	var raid_seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
	get_tree().create_timer(DEATH_DELAY).timeout.connect(func() -> void:
		_hud.visible = false
		var screen := DEATH_SCREEN.instantiate()
		add_child(screen)
		screen.show_death(_player, raid_seconds, _raid.outcome))


## Extracted or out of time: the raid result screen over the paused raid.
func _on_raid_ended(outcome: RaidOutcome) -> void:
	if outcome.status == RaidOutcome.Status.KILLED:
		return  # The death screen handles that.
	$InventoryLayer.close()
	_hud.visible = false
	get_tree().paused = true
	var screen := RESULT_SCREEN.instantiate()
	add_child(screen)
	screen.show_outcome(outcome, _raid)
