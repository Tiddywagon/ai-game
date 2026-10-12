extends Control
## Read-only view of the stash grid (DESIGN.md §8): every item at its cell position with its icon
## (a rarity-coloured placeholder until there's art), short name, rarity letter and stack count. Hover an item for details.
## Moving items around comes with the inventory system.

const CELL := 52
const LINE_COLOR := Color(1, 1, 1, 0.07)
const TEXT_COLOR := Color(0.9, 0.89, 0.84)

@export var columns := 10
@export var rows := 30


func _ready() -> void:
	custom_minimum_size = Vector2(columns, rows) * CELL
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color(0, 0, 0, 0.35))
	for x in columns + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, rows * CELL), LINE_COLOR)
	for y in rows + 1:
		draw_line(Vector2(0, y * CELL), Vector2(columns * CELL, y * CELL), LINE_COLOR)
	var font := get_theme_default_font()
	for entry: Dictionary in GameState.stash:
		var item := ItemDB.get_item(entry.id)
		if item == null:
			continue
		var rect := _rect_of(entry, item)
		var color := Palette.rarity_color(item.rarity)
		if entry.get("rotated", false):
			# Rotated items: draw the icon turned a quarter turn to fit the swapped footprint.
			draw_set_transform(rect.get_center(), PI / 2.0)
			draw_texture_rect(item.get_icon(), Rect2(-Vector2(rect.size.y, rect.size.x) / 2.0, Vector2(rect.size.y, rect.size.x)), false, Color(1, 1, 1, 0.85))
			draw_set_transform(Vector2.ZERO)
		else:
			draw_texture_rect(item.get_icon(), rect, false, Color(1, 1, 1, 0.85))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 19)), Color(0, 0, 0, 0.6))  # Keeps the name readable.
		draw_string(font, rect.position + Vector2(5, 15), _short_name(item, rect.size.x), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 12, TEXT_COLOR)
		draw_string(font, rect.position + Vector2(5, rect.size.y - 5), Palette.RARITY_SHORT[item.rarity], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
		if int(entry.count) > 1:
			draw_string(font, rect.position + Vector2(0, rect.size.y - 5), str(entry.count), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 5, 12, TEXT_COLOR)


func _get_tooltip(at_position: Vector2) -> String:
	for entry: Dictionary in GameState.stash:
		var item := ItemDB.get_item(entry.id)
		if item and _rect_of(entry, item).has_point(at_position):
			var lines := [item.display_name, "%s  ·  %s  ·  %s" % [
				Palette.RARITY_NAMES[item.rarity], Settings.format_weight(item.weight_kg * int(entry.count)),
				UiFormat.money(item.base_value * int(entry.count))]]
			if item.description != "":
				lines.append(item.description)
			return "\n".join(lines)
	return ""


func _rect_of(entry: Dictionary, item: ItemData) -> Rect2:
	var size := Vector2(item.size.y, item.size.x) if entry.get("rotated", false) else Vector2(item.size)
	return Rect2(Vector2(entry.x, entry.y) * CELL, size * CELL).grow(-3.0)


func _short_name(item: ItemData, width: float) -> String:
	var name := item.display_name
	var max_chars := int(width / 7.0)
	return name if name.length() <= max_chars else name.substr(0, maxi(max_chars - 1, 1)) + "…"
