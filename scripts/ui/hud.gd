extends CanvasLayer
## In-raid HUD (DESIGN.md §13): stamina bar, movement state, health and ammo, a shield icon while
## in cover, and short messages such as "Can't roll: overweight".

const NORMAL_COLOR := Color(0.85, 0.85, 0.75)
const EXHAUSTED_COLOR := Color(0.85, 0.3, 0.25)
## Shield colour while peeking, i.e. exposed.
const PEEK_COLOR := Color(0.95, 0.7, 0.3)
const MESSAGE_TIME := 2.0
## Indexed by CoverBox.CoverMaterial.
const MATERIAL_NAMES := ["wood", "concrete", "metal"]

## The player whose status is shown.
@export var player: Player

var _message_time := 0.0

@onready var _bar: ProgressBar = %StaminaBar
@onready var _fill: StyleBoxFlat = _bar.get_theme_stylebox("fill")
@onready var _state: Label = %MoveState
@onready var _status: Label = %Status
@onready var _message: Label = %Message
@onready var _cover_panel: Control = %CoverPanel
@onready var _cover_icon = %CoverIcon  # cover_icon.gd
@onready var _cover_label: Label = %CoverLabel


func _ready() -> void:
	if player:
		player.action_blocked.connect(show_message)
		player.died.connect(show_message.bind("KILLED IN ACTION", 10.0))


## Shows `text` above the stamina panel for `duration` seconds.
func show_message(text: String, duration := MESSAGE_TIME) -> void:
	_message.text = text
	_message_time = duration


func _process(delta: float) -> void:
	_message_time -= delta
	_message.visible = _message_time > 0.0
	if player == null:
		return
	_bar.max_value = player.max_stamina
	_bar.value = player.stamina
	_fill.bg_color = EXHAUSTED_COLOR if player.is_exhausted else NORMAL_COLOR
	var text := "%s  ·  noise %d m" % [_move_text(), roundi(player.noise_radius)]
	if player.is_exhausted:
		text += "  ·  exhausted"
	_state.text = text
	_status.text = "HP %d / %d  ·  %s" % [ceili(player.health), roundi(player.max_health), player.ammo_label()]

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
