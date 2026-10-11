extends Node
## Autoload "UiSounds": hover and click sounds for every button, slider and dropdown in every menu,
## played on the UI audio bus (DESIGN.md §16). Works while the game is paused.

const HOVER_SOUND := preload("res://assets/audio/ui/hover.wav")
const CLICK_SOUND := preload("res://assets/audio/ui/click.wav")
## Hover sounds closer together than this are skipped, so sweeping the mouse over a list isn't noisy.
const MIN_HOVER_GAP_MS := 45

var _hover := AudioStreamPlayer.new()
var _click := AudioStreamPlayer.new()
var _last_hover_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for player: AudioStreamPlayer in [_hover, _click]:
		player.bus = &"UI"
		add_child(player)
	_hover.stream = HOVER_SOUND
	_click.stream = CLICK_SOUND
	get_tree().node_added.connect(_on_node_added)


func play_hover() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms >= MIN_HOVER_GAP_MS:
		_last_hover_ms = now
		_hover.play()


func play_click() -> void:
	_click.play()


func _on_node_added(node: Node) -> void:
	if not (node is BaseButton or node is Slider):
		return
	var control := node as Control
	control.mouse_entered.connect(_on_hovered.bind(control))
	control.focus_entered.connect(_on_hovered.bind(control))
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play_click)


func _on_hovered(control: Control) -> void:
	if control.is_visible_in_tree() and not (control is BaseButton and (control as BaseButton).disabled):
		play_hover()
