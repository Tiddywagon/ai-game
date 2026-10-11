extends CanvasLayer
## In-raid HUD: stamina bar plus the current movement state (DESIGN.md §13).

const NORMAL_COLOR := Color(0.85, 0.85, 0.75)
const EXHAUSTED_COLOR := Color(0.85, 0.3, 0.25)

## The player whose stamina is shown.
@export var player: Player

@onready var _bar: ProgressBar = %StaminaBar
@onready var _fill: StyleBoxFlat = _bar.get_theme_stylebox("fill")
@onready var _state: Label = %MoveState


func _process(_delta: float) -> void:
	if player == null:
		return
	_bar.max_value = player.max_stamina
	_bar.value = player.stamina
	_fill.bg_color = EXHAUSTED_COLOR if player.is_exhausted else NORMAL_COLOR
	var text := "%s  ·  noise %d m" % [_move_text(), roundi(player.noise_radius)]
	if player.is_exhausted:
		text += "  ·  exhausted"
	_state.text = text


func _move_text() -> String:
	if player.is_crouching:
		return "Crouching"
	match player.move_state:
		Player.Move.WALK:
			return "Walking"
		Player.Move.SPRINT:
			return "Sprinting"
	return "Standing"
