class_name RaidLevel
extends Node3D
## A raid map (DESIGN.md §2, §5): bakes where the AI can walk (with locked doors blocked for it), then
## plays as the side picked in ENTER RAID (GameState.raid) with that loadout; run on its own it plays
## as a PMC and the raid's ending doesn't touch your profile. Extracting plays the extraction sound and
## fades to black; then the raid summary (after the death screen if you were killed), and from there
## back to the hideout. Opens the map of the area (M) if you carry one (MapOverlay), and has the debug
## overlay (F12, DebugOverlay). Every map scene has this (or a script extending it) on its root, with
## Player, HUD, RaidEnvironment, PlayerVision, Raid, InventoryLayer and a Navigation region holding the
## level geometry.

const DEATH_SCREEN := preload("res://ui/death_screen.tscn")
const RESULT_SCREEN := preload("res://ui/raid_result_screen.tscn")
## Seconds between dying and the death screen.
const DEATH_DELAY := 1.5
const EXTRACT_SOUND := preload("res://assets/audio/sfx/extract.wav")
## The fade to black after extracting sits under the raid summary (layer 60).
const FADE_LAYER := 58

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
	var overlay := DebugOverlay.new()
	overlay.name = "DebugOverlay"
	add_child(overlay)


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
	var map := _raid.map
	if map:
		_player.health.energy_climate = map.energy_drain_multiplier
		_player.health.hydration_climate = map.hydration_drain_multiplier
	var loadout: Variant = raid.get("loadout")
	_player.set_inventory(loadout if loadout is Inventory else Inventory.starter())


## A moment after dying, the death screen says what killed you (DESIGN.md §16.5).
func _on_player_died() -> void:
	if _raid.outcome and _raid.outcome.status != RaidOutcome.Status.KILLED:
		return  # Already out: extracted or missing.
	var raid_seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
	get_tree().create_timer(DEATH_DELAY).timeout.connect(func() -> void:
		_hud.visible = false
		var screen := DEATH_SCREEN.instantiate()
		add_child(screen)
		screen.show_death(_player, raid_seconds, _raid.outcome)
		screen.continued.connect(func() -> void:
			screen.queue_free()
			_show_summary(_raid.outcome)))


## Extracted (the extraction sound) or out of time: the raid pauses and fades to black, then the
## raid summary. (Killed: the death screen first, then the summary.)
func _on_raid_ended(outcome: RaidOutcome) -> void:
	if outcome.status == RaidOutcome.Status.KILLED:
		return  # The death screen handles that.
	var extracted := outcome.status in [RaidOutcome.Status.SURVIVED, RaidOutcome.Status.RUN_THROUGH]
	fade_out(extracted, _show_summary.bind(outcome))


## Pauses the raid and fades the screen to black (with the extraction sound if `extracted`), then
## calls `then`.
func fade_out(extracted: bool, then: Callable) -> void:
	$InventoryLayer.close()
	var map_overlay := get_node_or_null("MapOverlay")
	if map_overlay:
		map_overlay.close()
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.name = "ExtractFade"
	layer.layer = FADE_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	var title := Label.new()
	title.text = "EXTRACTED" if extracted else "OUT OF TIME"
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.45, 0.95, 0.5) if extracted else Color(0.9, 0.35, 0.3))
	title.modulate.a = 0.0
	layer.add_child(title)
	if extracted:
		var sound := AudioStreamPlayer.new()
		sound.name = "ExtractSound"
		sound.stream = EXTRACT_SOUND
		sound.bus = &"Effects"
		sound.process_mode = Node.PROCESS_MODE_ALWAYS
		layer.add_child(sound)
		sound.play()
	var seconds := _raid.config.extract_fade_seconds
	var tween := layer.create_tween()
	tween.tween_property(black, "color:a", 1.0, seconds)
	tween.parallel().tween_property(title, "modulate:a", 1.0, seconds * 0.6).set_delay(seconds * 0.4)
	tween.tween_callback(then)


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
	var map_id := str(_raid.map.id) if _raid.map else _raid.map_id
	if not MapOverlay.carries_map(_player.inventory, map_id):
		_player.action_blocked.emit("No map of %s" % (_raid.map.display_name if _raid.map else "this area"))
		return
	var overlay := MapOverlay.new()
	overlay.name = "MapOverlay"
	add_child(overlay)
	overlay.show_level(self, _raid.map, _player)
