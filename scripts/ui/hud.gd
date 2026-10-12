extends CanvasLayer
## In-raid HUD (DESIGN.md §13, §17): body silhouette with status effects, a red vignette while in
## pain, stamina bar, movement state, a shield icon in cover,
## short messages such as "Can't roll: overweight", the raid name, the ammo panel (rounds in the
## magazine, spare rounds, loaded ammo, reload progress), the aiming reticle and hit markers.
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

## The player whose status is shown.
@export var player: Player

var _message_time := 0.0

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
	var raid := GameState.raid
	var map := MapInfo.find(raid.get("map", ""))
	%RaidInfo.text = "%s  ·  %s" % [map.display_name.to_upper() if map else "TEST YARD", "SCAV" if raid.get("side") == "scav" else "PMC"]
	Settings.applied.connect(_apply_settings)
	_apply_settings()


## Shows `text` above the stamina panel for `duration` seconds.
func show_message(text: String, duration := MESSAGE_TIME) -> void:
	_message.text = text
	_message_time = duration


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
	if player == null:
		return
	_bar.max_value = player.max_stamina
	_bar.value = player.stamina
	_fill.bg_color = EXHAUSTED_COLOR if player.is_exhausted else NORMAL_COLOR
	var text := "%s  ·  noise %s" % [_move_text(), Settings.format_distance(player.noise_radius)]
	if player.is_exhausted:
		text += "  ·  exhausted"
	_state.text = text
	_update_health(delta)
	_update_ammo()

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


func _update_ammo() -> void:
	var weapon := player.weapon
	%BottomRight.visible = weapon.has_gun()
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
