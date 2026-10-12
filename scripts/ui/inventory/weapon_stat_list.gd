class_name WeaponStatList
extends GridContainer
## A gun's stats in the modding screen and the examine panel (DESIGN.md §12.1): name, a bar where one
## helps, the value, and while a change is being previewed (a part hovered or dragged over a slot) the
## new value with how much it changes, in green if it's better and red if it's worse, with ▲ / ▼ so
## colour is never the only cue. Rows come from WeaponStats.rows().

const BETTER_COLOR := Color(0.45, 0.85, 0.45)
const WORSE_COLOR := Color(0.95, 0.42, 0.36)
const BAR_SIZE := Vector2(150, 8)
const FONT_SIZE := 15


func _ready() -> void:
	columns = 4
	add_theme_constant_override("h_separation", 16)
	add_theme_constant_override("v_separation", 0)


## Shows `rows`; with `preview` (rows for the changed gun), the changes too.
func show_rows(rows: Array[Dictionary], preview: Array[Dictionary] = []) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for i in rows.size():
		var row := rows[i]
		var after: Dictionary = preview[i] if i < preview.size() else row
		var change := 0
		if not preview.is_empty() and WeaponStats.format_delta(row.key, after.value - row.value) != "":
			change = int(signf(after.value - row.value)) * int(row.better)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.theme_type_variation = &"DimLabel"
		label.text = row.name
		add_child(label)
		var bar := StatBar.new()
		bar.value = row.bar
		bar.preview = after.bar
		bar.visible_bar = row.bar >= 0.0
		add_child(bar)
		var value := Label.new()
		value.add_theme_font_size_override("font_size", FONT_SIZE)
		value.name = "Value_" + str(row.key)
		value.text = after.text
		value.custom_minimum_size.x = 150
		if change != 0:
			value.add_theme_color_override("font_color", BETTER_COLOR if change > 0 else WORSE_COLOR)
		add_child(value)
		var delta := Label.new()
		delta.add_theme_font_size_override("font_size", FONT_SIZE)
		delta.name = "Delta_" + str(row.key)
		delta.custom_minimum_size.x = 110
		if not preview.is_empty():
			var text := WeaponStats.format_delta(row.key, after.value - row.value)
			if text != "":
				delta.text = ("▲ " if change > 0 else "▼ " if change < 0 else "") + text
				if change != 0:
					delta.add_theme_color_override("font_color", BETTER_COLOR if change > 0 else WORSE_COLOR)
		add_child(delta)


## A thin bar: the stat now, and where the preview would take it.
class StatBar:
	extends Control

	var value := 0.0
	var preview := 0.0
	var visible_bar := true

	func _init() -> void:
		custom_minimum_size = BAR_SIZE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if not visible_bar:
			return
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(1, 1, 1, 0.08))
		var now := clampf(value, 0.0, 1.0)
		var then := clampf(preview, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * minf(now, then), size.y)), Color(0.85, 0.85, 0.78, 0.75))
		if then > now:
			draw_rect(Rect2(Vector2(size.x * now, 0), Vector2(size.x * (then - now), size.y)), Color(0.85, 0.85, 0.78, 0.35))
		elif then < now:
			draw_rect(Rect2(Vector2(size.x * then, 0), Vector2(size.x * (now - then), size.y)), Color(0.85, 0.85, 0.78, 0.2))
			draw_rect(Rect2(Vector2(size.x * then, 0), Vector2(size.x * (now - then), size.y)), Color(1, 1, 1, 0.3), false, 1.0)
