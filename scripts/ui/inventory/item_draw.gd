class_name ItemDraw
extends RefCounted
## Draws one inventory item into a rectangle (DESIGN.md §7): the rarity-coloured background and border,
## its icon (turned when the item is), a name strip, the stack count and the rarity letter, so colour is
## never the only cue. Used by grids, equipment slots and the drag preview.

const TEXT_COLOR := Color(0.92, 0.91, 0.86)
const NAME_STRIP := 18.0


static func draw(canvas: CanvasItem, item: ItemInstance, rect: Rect2, turned: bool, alpha := 1.0, count := -1) -> void:
	var color := Palette.rarity_color(item.data.rarity)
	canvas.draw_rect(rect, Color(color.darkened(0.7), 0.9 * alpha))
	var icon := item.data.get_icon()
	var fit := _fit(Vector2(icon.get_size()) if not turned else Vector2(icon.get_height(), icon.get_width()), rect.grow(-3.0))
	if turned:
		canvas.draw_set_transform(fit.get_center(), PI / 2.0)
		var size := Vector2(fit.size.y, fit.size.x)
		canvas.draw_texture_rect(icon, Rect2(-size / 2.0, size), false, Color(1, 1, 1, alpha))
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect(icon, fit, false, Color(1, 1, 1, alpha))
	canvas.draw_rect(rect, Color(color, alpha), false, 2.0)
	var font := ThemeDB.fallback_font
	if canvas is Control:
		font = canvas.get_theme_default_font()
	if rect.size.y >= 40.0:
		canvas.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, NAME_STRIP)), Color(0, 0, 0, 0.6 * alpha))
		canvas.draw_string(font, rect.position + Vector2(5, 15), short_name(item.data.display_name, rect.size.x), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 12, Color(TEXT_COLOR, alpha))
	canvas.draw_string(font, rect.position + Vector2(5, rect.size.y - 5), Palette.RARITY_SHORT[item.data.rarity], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color.lightened(0.2), alpha))
	var shown := item.count if count < 0 else count
	if shown > 1 or item.data.max_stack > 1:
		canvas.draw_string(font, rect.position + Vector2(0, rect.size.y - 5), str(shown), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 5, 13, Color(TEXT_COLOR, alpha))
	if item.contents and not item.contents.items.is_empty():
		# A small dot: there's something inside.
		canvas.draw_circle(rect.position + Vector2(rect.size.x - 8, NAME_STRIP + 10), 3.5, Color(TEXT_COLOR, 0.8 * alpha))


## Hover text for an item.
static func tooltip(item: ItemInstance) -> String:
	var lines := [item.data.display_name + (" ×%d" % item.count if item.count > 1 else ""),
		"%s  ·  %s  ·  %s" % [Palette.RARITY_NAMES[item.data.rarity], Settings.format_weight(item.weight()), UiFormat.money(item.value())],
		"Right-click: examine" + ("  ·  Double-click: open" if item.contents else "")]
	return "\n".join(lines)


static func short_name(name: String, width: float) -> String:
	var max_chars := int(width / 7.0)
	return name if name.length() <= max_chars else name.substr(0, maxi(max_chars - 1, 1)) + "…"


## `size` scaled to fit inside `area`, centred.
static func _fit(size: Vector2, area: Rect2) -> Rect2:
	var scale_by := minf(area.size.x / size.x, area.size.y / size.y)
	var fitted := size * scale_by
	return Rect2(area.position + (area.size - fitted) / 2.0, fitted)
