class_name StimIcons
extends Control
## The stims working on the player, as a row of icons with countdown timers (DESIGN.md §13.8): each
## stim's icon with a ring for its phase (grey: waiting for its delay, green: buffs running, red: only
## side effects left) and the time until that phase ends under it; a red "OD" icon while an Overdose
## runs. Hidden when no stim is working.

const SIZE := 44.0
const GAP := 8.0
const TIMER_HEIGHT := 18.0

var health: BodyHealth

var _entries: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	_entries = Stims.active(health) if health and not health.is_dead else []
	visible = not _entries.is_empty()
	var width := _entries.size() * (SIZE + GAP)
	if not is_equal_approx(custom_minimum_size.x, width):
		custom_minimum_size = Vector2(width, SIZE + TIMER_HEIGHT + 4.0)
	queue_redraw()


## What's shown: Stims.active() for the player's body.
func entries() -> Array:
	return _entries


func _draw() -> void:
	var font := get_theme_default_font()
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		var box := Rect2(Vector2(i * (SIZE + GAP), 0.0), Vector2(SIZE, SIZE))
		var ring := Stims.color(str(entry.phase))
		draw_rect(box, Color(0.05, 0.05, 0.06, 0.85))
		if entry.source == Stims.OVERDOSE:
			draw_rect(box.grow(-6.0), Color(ring, 0.35))
			draw_string(font, Vector2(box.position.x, box.position.y + SIZE * 0.66), "OD", HORIZONTAL_ALIGNMENT_CENTER, SIZE, 18, ring)
		else:
			var data := ItemDB.get_item(str(entry.source))
			if data:
				draw_texture_rect(data.get_icon(), box.grow(-5.0), false, Color(1, 1, 1, 0.55 if entry.phase == "pending" else 1.0))
		draw_rect(box, ring, false, 2.0)
		var seconds := ceili(float(entry.left))
		var text := "%d:%02d" % [seconds / 60, seconds % 60]
		if entry.phase == "pending":
			text = "in %d" % seconds
		draw_string(font, Vector2(box.position.x, SIZE + TIMER_HEIGHT - 2.0), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 13, ring)

