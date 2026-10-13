class_name RaidLevel
extends Node3D
## A raid map (DESIGN.md §2, §5): bakes where the AI can walk (with locked doors blocked for it), then
## plays as the side picked in ENTER RAID (GameState.raid) with that loadout; run on its own it plays
## as a PMC and the raid's ending doesn't touch your profile. Shows the death screen and the raid
## summary, and opens the map of the area (M) if you carry one (MapOverlay). Every map scene has this
## (or a script extending it) on its root, with Player, HUD, RaidEnvironment, PlayerVision, Raid,
## InventoryLayer and a Navigation region holding the level geometry.

const DEATH_SCREEN := preload("res://ui/death_screen.tscn")
const RESULT_SCREEN := preload("res://ui/raid_result_screen.tscn")
## Seconds between dying and the death screen.
const DEATH_DELAY := 1.5

@onready var _player: Player = $Player
@onready var _hud := $HUD
@onready var _environment: RaidEnvironment = $RaidEnvironment
@onready var _vision: PlayerVision = $PlayerVision
@onready var _raid: RaidController = $Raid

var _start_msec := 0


func _ready() -> void:
	# Work out where the AI can walk from the level geometry (locked doors closed to it), then
	# rebuild cover points to match.
	for door in get_tree().get_nodes_in_group("doors"):
		if door.locked:
			$Navigation.add_child(door.nav_blocker())
	($Navigation as NavigationRegion3D).bake_navigation_mesh(false)
	get_tree().call_group("nav_bake_only", "queue_free")
	CoverSystem.mark_dirty()
	_apply_raid()
	_start_msec = Time.get_ticks_msec()
	_player.died.connect(_on_player_died)
	_raid.raid_ended.connect(_on_raid_ended)


## Plays as the side picked in ENTER RAID, carrying that loadout (an Inventory). Run on its own, the
## player gets the starter kit. A PMC brings the profile's energy and hydration (DESIGN.md §13.7); a
## Scav starts full. The map's climate sets how fast they drain.
func _apply_raid() -> void:
	var raid := GameState.raid
	var tuning := Consumables.CONFIG
	if raid.get("side") == "scav":
		_player.side = Actor.Side.SCAV
		_player.health.start_metabolism(tuning, tuning.max_energy, tuning.max_hydration)
	else:
		Consumables.recover_profile()
		_player.health.start_metabolism(tuning, GameState.energy, GameState.hydration)
	_player.health.metabolism_skill = Consumables.skill_multiplier()
	var map := MapInfo.find(raid.get("map", "test_yard"))
	if map:
		_player.health.energy_climate = map.energy_drain_multiplier
		_player.health.hydration_climate = map.hydration_drain_multiplier
	var loadout: Variant = raid.get("loadout")
	_player.set_inventory(loadout if loadout is Inventory else Inventory.starter())


## A moment after dying, the death screen says what killed you (DESIGN.md §16.5).
func _on_player_died() -> void:
	var raid_seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
	get_tree().create_timer(DEATH_DELAY).timeout.connect(func() -> void:
		_hud.visible = false
		var screen := DEATH_SCREEN.instantiate()
		add_child(screen)
		screen.show_death(_player, raid_seconds, _raid.outcome)
		screen.continued.connect(func() -> void:
			screen.queue_free()
			_show_summary(_raid.outcome)))


## Extracted or out of time: the raid summary over the paused raid. (Killed: the death screen first,
## then the summary.)
func _on_raid_ended(outcome: RaidOutcome) -> void:
	if outcome.status == RaidOutcome.Status.KILLED:
		return  # The death screen handles that.
	_show_summary(outcome)


func _show_summary(outcome: RaidOutcome) -> void:
	$InventoryLayer.close()
	_hud.visible = false
	get_tree().paused = true
	var screen := RESULT_SCREEN.instantiate()
	add_child(screen)
	screen.show_outcome(outcome, _raid)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map_view") and not _player.is_dead and not _raid.is_over():
		get_viewport().set_input_as_handled()
		toggle_map()


## Opens (or closes) the map of this area if the player carries one; says so if they don't.
func toggle_map() -> void:
	var open := get_node_or_null("MapOverlay")
	if open:
		open.close()
		return
	var map_id := str(_raid.map.id) if _raid.map else "test_yard"
	if not MapOverlay.carries_map(_player.inventory, map_id):
		_player.action_blocked.emit("No map of %s" % (_raid.map.display_name if _raid.map else "this area"))
		return
	var overlay := MapOverlay.new()
	overlay.name = "MapOverlay"
	add_child(overlay)
	overlay.show_level(self, _raid.map, _player)
