extends Control
## Loading screen (DESIGN.md §16.3): shows the map, your side and a tip while the raid scene loads
## on a background thread, then switches to it.

const MAIN_MENU := "res://ui/main_menu.tscn"
## Stays up at least this long so the screen doesn't just flash.
const MIN_TIME := 1.5
const TIPS := [
	"Roll toward cover and you snap into it when the roll ends.",
	"Wood stops 5.45 PS rounds, but armor-piercing BS goes straight through.",
	"Crouching cuts how far your footsteps carry from 10 m to 4 m.",
	"Rolls are loud: anyone within 25 m hears them.",
	"Hold right-click in cover to peek and aim. Let go to duck back down.",
	"PMCs roll out of the line of fire. Scavs just keep shooting.",
	"Low cover hides you while you duck; standing up to shoot exposes your head and chest.",
	"At tall cover you can only lean out near an end.",
]

var _path := ""
var _elapsed := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var map := MapInfo.find(GameState.raid.get("map", ""))
	if map == null or not map.is_playable():
		push_error("Loading screen: no playable map in GameState.raid")
		get_tree().change_scene_to_file.call_deferred(MAIN_MENU)
		return
	_path = map.scene_path
	%MapName.text = map.display_name.to_upper()
	%Details.text = "%s  ·  %d min raid  ·  %s" % [
		"PMC" if GameState.raid.get("side") == "pmc" else "SCAV", map.raid_minutes, map.players]
	%Tip.text = TIPS.pick_random()
	ResourceLoader.load_threaded_request(_path)


func _process(delta: float) -> void:
	if _path == "":
		return
	_elapsed += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_path, progress)
	%Progress.value = minf(progress[0] if not progress.is_empty() else 0.0, _elapsed / MIN_TIME) * 100.0
	if status == ResourceLoader.THREAD_LOAD_LOADED and _elapsed >= MIN_TIME:
		set_process(false)
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(_path))
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		push_error("Loading screen: couldn't load %s" % _path)
		get_tree().change_scene_to_file(MAIN_MENU)
