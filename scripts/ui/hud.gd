extends CanvasLayer
## In-raid HUD (DESIGN.md §13, §17): body silhouette with status effects, a red vignette while in
## pain, stamina bar, movement state, a shield icon in cover,
## short messages such as "Can't roll: overweight", the raid name, the ammo panel (rounds in the
## magazine, spare rounds, loaded ammo, reload progress), the aiming reticle and hit markers.
## Vision (DESIGN.md §13.6): direction markers for sounds you can't see, a white-out while blinded,
## time of day and weather next to the raid name, and the sight in use or the binoculars.
## Raid (DESIGN.md §2): the time left and the extract under the raid name, an "F  Search ..." prompt
## when a container, body or item is in reach, and a countdown while extracting.
## HUD scale, opacity, units and reticle come from Settings.

const NORMAL_COLOR := Color(0.85, 0.85, 0.75)
const EXHAUSTED_COLOR := Color(0.85, 0.3, 0.25)
## Shield colour while peeking, i.e. exposed.
const PEEK_COLOR := Color(0.95, 0.7, 0.3)
## Round count colours: a third of a magazine or less, and empty.
const LOW_AMMO_COLOR := Color(0.95, 0.7, 0.3)
const EMPTY_COLOR := Color(0.85, 0.3, 0.25)
const MESSAGE_TIME := 2.0
## Indexed by CoverBox.CoverMaterial.
const MATERIAL_NAMES := ["wood", "concrete", "metal"]
const EXTRACT_COLOR := Color(0.45, 0.95, 0.5)

## The player whose status is shown.
@export var player: Player

var _message_time := 0.0
var _raid: RaidController
var _raid_line := ""
var _prompt: Label
var _extract: Label

@onready var _root: Control = %HudRoot
@onready var _bottom_left: Control = %BottomLeft
@onready var _bar: ProgressBar = %StaminaBar
@onready var _fill: StyleBoxFlat = _bar.get_theme_stylebox("fill")
@onready var _state: Label = %MoveState
@onready var _message: Label = %Message
@onready var _cover_panel: Control = %CoverPanel
@onready var _cover_icon = %CoverIcon  # cover_icon.gd
@onready var _cover_label: Label = %CoverLabel
@onready var _reticle = %Reticle  # reticle.gd


func _ready() -> void:
	_reticle.player = player
	if player:
		%Silhouette.health = player.health
		player.action_blocked.connect(show_message)
		player.died.connect(show_message.bind("KILLED IN ACTION", 10.0))
		player.hit_landed.connect(func(target: Actor, _damage: float, _at: Vector3) -> void:
			if Settings.get_value("gameplay", "hit_markers"):
				_reticle.show_hit_marker(target.is_dead))
	%SoundMarkers.player = player
	_prompt = _add_center_label(-210.0, 22, NORMAL_COLOR)
	_extract = _add_center_label(-470.0, 40, EXTRACT_COLOR)
	VisionSystem.conditions_changed.connect(_update_raid_info)
	_update_raid_info()
	_connect_vision.call_deferred()
	Settings.applied.connect(_apply_settings)
	_apply_settings()


## Shows `text` above the stamina panel for `duration` seconds.
func show_message(text: String, duration := MESSAGE_TIME) -> void:
	_message.text = text
	_message_time = duration


func _update_raid_info() -> void:
	var raid := GameState.raid
	var map := MapInfo.find(raid.get("map", ""))
	_raid_line = "%s  ·  %s  ·  %s  ·  %s" % [map.display_name.to_upper() if map else "TEST YARD",
		"SCAV" if raid.get("side") == "scav" else "PMC", VisionSystem.time_name(VisionSystem.time_of_day).to_upper(),
		VisionSystem.weather_name(VisionSystem.weather).to_upper()]
	_update_raid_clock()


## The raid name line, plus the time left and where to extract.
func _update_raid_clock() -> void:
	if _raid == null:
		_raid = get_tree().get_first_node_in_group("raid_controller") as RaidController
	var text := _raid_line
	if _raid:
		var seconds := ceili(_raid.time_left)
		var zones := get_tree().get_nodes_in_group("extract_zones")
		text += "\n%d:%02d LEFT  ·  EXTRACT: %s" % [seconds / 60, seconds % 60,
			", ".join(zones.map(func(zone: Node) -> String: return zone.extract_name.to_upper())) if not zones.is_empty() else "NONE"]
	if %RaidInfo.text != text:
		%RaidInfo.text = text


## The F prompt and the extract countdown.
func _update_raid_prompts() -> void:
	var target := player.focused_interactable if player and not player.ui_open and not player.is_dead else null
	_prompt.visible = target != null
	if target:
		_prompt.text = "%s   %s" % [Settings.key_label("interact"), target.interact_text()]
	var left := _raid.extract_remaining() if _raid else -1.0
	_extract.visible = left >= 0.0
	if left >= 0.0:
		_extract.text = "EXTRACTING  %.1f" % left


func _add_center_label(from_bottom: float, size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = from_bottom
	label.offset_bottom = from_bottom + size * 1.6
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.hide()
	_root.add_child(label)
	return label


func _connect_vision() -> void:
	var vision := get_tree().get_first_node_in_group("player_vision")
	if vision:
		vision.sound_heard.connect(%SoundMarkers.add_marker)


func _apply_settings() -> void:
	_root.modulate.a = Settings.get_value("interface", "hud_opacity")
	var hud_scale: float = Settings.get_value("interface", "hud_scale")
	for control: Control in [_bottom_left, %TopRight, %BottomRight]:
		control.scale = Vector2.ONE * hud_scale


func _process(delta: float) -> void:
	# Scale the panels from the corner they're anchored to.
	_bottom_left.pivot_offset = Vector2(0.0, _bottom_left.size.y)
	%TopRight.pivot_offset = Vector2(%TopRight.size.x, 0.0)
	%BottomRight.pivot_offset = %BottomRight.size
	_message_time -= delta
	_message.visible = _message_time > 0.0
	_update_raid_clock()
	if player == null:
		return
	_update_raid_prompts()
	_bar.max_value = player.max_stamina
	_bar.value = player.stamina
	_fill.bg_color = EXHAUSTED_COLOR if player.is_exhausted else NORMAL_COLOR
	var text := "%s  ·  noise %s" % [_move_text(), Settings.format_distance(player.noise_radius)]
	if player.is_exhausted:
		text += "  ·  exhausted"
	if player.is_overweight():
		text += "  ·  overweight %s" % Settings.format_weight(player.carried_weight_kg)
	elif player.is_encumbered():
		text += "  ·  heavy %s" % Settings.format_weight(player.carried_weight_kg)
	_state.text = text
	_update_health(delta)
	_update_ammo()
	_update_blind()

	var cover := player.cover
	_cover_panel.visible = cover != null
	if cover:
		var cover_text := "%s cover · %s" % ["Low" if cover.is_low else "High", MATERIAL_NAMES[cover.material]]
		if player.is_peeking:
			cover_text += " · peeking"
		elif not cover.can_peek:
			cover_text += " · no peek here"
		_cover_label.text = cover_text
		_cover_icon.color = PEEK_COLOR if player.is_peeking else NORMAL_COLOR


func _update_health(delta: float) -> void:
	var health := player.health
	%HealthTotal.text = "HP %d / %d" % [ceili(health.total()), roundi(health.max_total())]
	var lines := health.status_lines()
	%StatusList.text = "\n".join(lines)
	%StatusList.visible = not lines.is_empty()
	# Pain: dark red edges, slowly pulsing (steady with "reduce flashing").
	var target := 0.0
	if health.has_pain() and not player.is_dead:
		target = 1.0 if Settings.get_value("accessibility", "reduce_flashing") else 0.8 + 0.2 * sin(Time.get_ticks_msec() / 400.0)
	%PainVignette.modulate.a = move_toward(%PainVignette.modulate.a, target, delta * 2.0)


func _update_blind() -> void:
	var amount := clampf(player.blind_fraction() * 1.5, 0.0, 1.0) if player.is_blind() else 0.0
	%BlindOverlay.visible = amount > 0.0
	# "Reduce flashing effects": fade to dark instead of a white flash.
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	%BlindOverlay.color = Color(0.03, 0.03, 0.03, amount * 0.92) if reduced else Color(1.0, 1.0, 0.97, amount)


func _update_ammo() -> void:
	var weapon := player.weapon
	%BottomRight.visible = weapon.has_gun() or player.using_binoculars
	var gear: Array[String] = []
	if player.using_binoculars:
		gear.append("Binoculars in hand: can't shoot")
	else:
		var optic := VisionSystem.config.optic(weapon.optic)
		gear.append(optic.display_name if optic else "Iron sights")
	if player.flashlight_on:
		gear.append("flashlight on")
	%GearLine.text = "  ·  ".join(gear)
	if not weapon.has_gun():
		return
	var magazine := weapon.data.magazine_size
	%WeaponName.text = weapon.display_name().to_upper()
	%Rounds.text = str(weapon.rounds)
	var color := NORMAL_COLOR
	if weapon.rounds == 0:
		color = EMPTY_COLOR
	elif weapon.rounds * 3 <= magazine:
		color = LOW_AMMO_COLOR
	%Rounds.add_theme_color_override("font_color", color if not weapon.is_reloading else Color(color, 0.45))
	%MagSize.text = "/ %d" % magazine
	%Spare.text = "+%d" % weapon.spare_rounds if weapon.spare_rounds >= 0 else ""
	%Spare.add_theme_color_override("font_color", EMPTY_COLOR if weapon.spare_rounds == 0 else Color(NORMAL_COLOR, 0.8))
	%AmmoType.text = "RELOADING" if weapon.is_reloading else "%s  ·  %s" % [player.ammo_label(), "auto" if weapon.data.automatic else "semi"]
	%ReloadBar.visible = weapon.is_reloading
	%ReloadBar.value = weapon.reload_progress()


func _move_text() -> String:
	if player.is_dead:
		return "Dead"
	match player.move_state:
		Actor.Move.ROLL:
			return "Rolling"
		Actor.Move.COVER:
			return "Peeking" if player.is_peeking else "In cover"
	if player.is_crouching:
		return "Crouching"
	match player.move_state:
		Actor.Move.WALK:
			return "Walking"
		Actor.Move.SPRINT:
			return "Sprinting"
	return "Standing"
