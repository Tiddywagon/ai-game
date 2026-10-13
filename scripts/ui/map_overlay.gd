class_name MapOverlay
extends CanvasLayer
## The map item (DESIGN.md §5): a paper map of one raid map, opened with M in a raid if you carry it
## (anywhere on you), or with VIEW MAP when examining it. It shows the layout (walls, low cover,
## catwalks, stairs, doors with the locked ones in red, named places and landmarks) and your extracts:
## those your side can use (quest extracts once unlocked), each with what it takes, and in a raid its
## mark: Open (green), Unknown (grey: a random one you haven't seen yet), Closed (red) or what it still
## needs (amber). Scav areas and high-value loot rooms are marked too. It doesn't show where you are. M, Esc or CLOSE closes it; the raid goes on underneath.

const PAPER := Color(0.13, 0.14, 0.13, 0.97)
const INK := Color(0.82, 0.8, 0.72)
const CONCRETE := Color(0.72, 0.71, 0.66)
const WOOD := Color(0.6, 0.46, 0.3)
const METAL := Color(0.45, 0.52, 0.6)
const FLOOR := Color(0.55, 0.6, 0.65, 0.35)
const DOOR := Color(0.95, 0.75, 0.35)
const LOCKED := Color(0.9, 0.3, 0.25)
const SCAV := Color(0.85, 0.35, 0.3, 0.16)
const LOOT := Color(1.0, 0.8, 0.3)
const MARGIN := 40.0

var layout: MapLayout
var map: MapInfo
## In a raid: whose extracts these are, and the live RaidController (statuses).
var player: Player
var raid: RaidController
var side := ""

var _canvas: Control
var _title: Label
var _legend: VBoxContainer


## True if `inventory` holds a map of `map_id` (anywhere, the secure container too).
static func carries_map(inventory: Inventory, map_id: String) -> bool:
	if inventory == null:
		return false
	return inventory.all_items().any(func(item: ItemInstance) -> bool: return is_map_of(item.data, map_id))


static func is_map(data: ItemData) -> bool:
	return data != null and str(data.stats.get("type", "")) == "map"


static func is_map_of(data: ItemData, map_id: String) -> bool:
	return is_map(data) and str(data.stats.get("map", "")) == map_id


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.03, 0.03, 0.97)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = MARGIN
	root.offset_top = MARGIN
	root.offset_right = -MARGIN
	root.offset_bottom = -MARGIN
	root.add_theme_constant_override("separation", 24)
	add_child(root)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	left.add_child(_title)
	_canvas = Control.new()
	_canvas.name = "MapCanvas"
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_map)
	left.add_child(_canvas)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 420
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)
	var heading := Label.new()
	heading.theme_type_variation = &"AccentLabel"
	heading.text = "EXTRACTS"
	right.add_child(heading)
	_legend = VBoxContainer.new()
	_legend.name = "Legend"
	_legend.add_theme_constant_override("separation", 8)
	right.add_child(_legend)
	var key := Label.new()
	key.theme_type_variation = &"DimLabel"
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key.text = "Doors: orange, locked red.  Hatched: catwalks and stairs.  Red areas: Scavs.  Gold outline: high-value loot.  The map doesn't show where you are."
	right.add_child(key)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "CLOSE  (%s)" % Settings.key_label("map_view")
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(close)
	right.add_child(close_button)


func _process(_delta: float) -> void:
	if raid and is_instance_valid(raid):
		_fill_legend()  # Statuses change (power, paying).
		_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map_view") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## The live map of `level` in a raid, with `who`'s extracts and their statuses.
func show_level(level: Node, info: MapInfo, who: Player) -> void:
	map = info
	player = who
	raid = level.get_tree().get_first_node_in_group("raid_controller") as RaidController
	side = raid.side() if raid else "pmc"
	layout = MapLayout.from_level(level)
	if player:
		player.ui_open = true
	_show()


## The map of `map_id` out of raid (read from its scene): every extract, with what it takes.
func show_map(map_id: String) -> bool:
	map = MapInfo.find(map_id)
	if map == null or not map.is_playable():
		return false
	var scene := load(map.scene_path) as PackedScene
	var level := scene.instantiate()
	layout = MapLayout.from_level(level, map_id)
	level.free()
	_show()
	return true


func close() -> void:
	if player and is_instance_valid(player):
		var inventory_open := false
		var layer := player.get_tree().current_scene.get_node_or_null("InventoryLayer") if player.is_inside_tree() else null
		if layer and layer.has_method("is_open"):
			inventory_open = layer.is_open()
		player.ui_open = inventory_open
	queue_free()


## The extracts shown: those your side can use (all of them out of raid).
func shown_extracts() -> Array:
	return layout.extracts.filter(func(entry: Dictionary) -> bool: return side == "" or entry.sides == "Both" or entry.sides.to_lower() == side)


func _show() -> void:
	_title.text = "%s  ·  MAP" % (map.display_name.to_upper() if map else "MAP")
	_fill_legend()
	_canvas.queue_redraw()


func _fill_legend() -> void:
	var lines := []
	for entry: Dictionary in shown_extracts():
		var color := _color_of(entry)
		var status: String = entry.kind
		if entry.zone and is_instance_valid(entry.zone) and raid:
			status = "%s  ·  %s" % [entry.zone.status_for(player), entry.kind]
		lines.append([entry.name, status, color])
	if _legend.get_child_count() == lines.size() * 2:
		for i in lines.size():
			_legend.get_child(i * 2 + 1).text = lines[i][1]
			_legend.get_child(i * 2).add_theme_color_override("font_color", lines[i][2])
		return
	for child in _legend.get_children():
		child.queue_free()
	for line in lines:
		var name_label := Label.new()
		name_label.text = line[0]
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", line[2])
		_legend.add_child(name_label)
		var detail := Label.new()
		detail.theme_type_variation = &"DimLabel"
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = line[1]
		_legend.add_child(detail)


# --- Drawing -------------------------------------------------------------------------------------

## World (x, z) to canvas pixels: the layout's bounds fitted into the canvas, north up.
func to_canvas(point: Vector2) -> Vector2:
	var area := layout.bounds.grow(2.0)
	var scale := minf(_canvas.size.x / area.size.x, _canvas.size.y / area.size.y)
	var offset := (_canvas.size - area.size * scale) / 2.0
	return offset + (point - area.position) * scale


func _scale() -> float:
	var area := layout.bounds.grow(2.0)
	return minf(_canvas.size.x / area.size.x, _canvas.size.y / area.size.y)


func _poly(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(to_canvas(point))
	return result


func _draw_map() -> void:
	if layout == null or layout.bounds.size == Vector2.ZERO:
		return
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), PAPER)
	var font := _canvas.get_theme_default_font()
	var s := _scale()
	for zone: Dictionary in layout.scav_zones:
		_canvas.draw_circle(to_canvas(zone.at), zone.radius * s, SCAV)
	for points: PackedVector2Array in layout.floors:
		_hatched(_poly(points), FLOOR)
	for points: PackedVector2Array in layout.stairs:
		_hatched(_poly(points), Color(INK, 0.5))
	for wall: Dictionary in layout.walls:
		var color: Color = [WOOD, CONCRETE, METAL][clampi(int(wall.material), 0, 2)]
		if wall.low:
			color = Color(color, 0.45)
		_canvas.draw_colored_polygon(_poly(wall.points), color)
	for door: Dictionary in layout.doors:
		_canvas.draw_line(to_canvas(door.from), to_canvas(door.to), LOCKED if door.locked else DOOR, maxf(3.0, s * 0.25))
	for zone: Dictionary in layout.loot_zones:
		var outline := _poly(zone.points)
		outline.append(outline[0])
		_canvas.draw_polyline(outline, LOOT, 2.0)
		_canvas.draw_string(font, outline[0] + Vector2(4, 16), zone.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LOOT)
	for label: Dictionary in layout.labels:
		var size := 18 if label.landmark else 14
		var at := to_canvas(label.at)
		var text: String = label.text.to_upper() if label.landmark else label.text
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_canvas.draw_string_outline(font, at - Vector2(width / 2.0, -size / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
		_canvas.draw_string(font, at - Vector2(width / 2.0, -size / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			Color(1.0, 0.85, 0.4) if label.landmark else INK)
	for entry: Dictionary in shown_extracts():
		var color := _color_of(entry)
		var at := to_canvas(entry.at)
		var radius := maxf(entry.radius * s, 8.0)
		var name: String = entry.name
		_canvas.draw_circle(at, radius, Color(color, 0.25))
		_canvas.draw_arc(at, radius, 0.0, TAU, 40, color, 3.0, true)
		var width := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_canvas.draw_string_outline(font, at + Vector2(-width / 2.0, -radius - 6.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.85))
		_canvas.draw_string(font, at + Vector2(-width / 2.0, -radius - 6.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	var compass := Vector2(_canvas.size.x - 30.0, 34.0)
	_canvas.draw_line(compass + Vector2(0, 14), compass + Vector2(0, -14), INK, 2.0)
	_canvas.draw_string(font, compass + Vector2(-5, -18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)


## In a raid, as its mark: green open, amber something's needed, red closed, grey unknown. Out of raid
## by type: green always open, grey random, amber conditional.
func _color_of(entry: Dictionary) -> Color:
	var zone: ExtractZone = entry.zone if entry.zone and is_instance_valid(entry.zone) else null
	if zone and raid:
		return ExtractZone.STATE_COLORS[zone.status_state(player)]
	return ExtractZone.STATE_COLORS[{"always": "open", "random": "unknown"}.get(entry.get("type", ""), "condition")]


## A filled outline with diagonal hatching, for catwalks and stairs.
func _hatched(points: PackedVector2Array, color: Color) -> void:
	_canvas.draw_colored_polygon(points, Color(color, color.a * 0.5))
	var outline := points.duplicate()
	outline.append(points[0])
	_canvas.draw_polyline(outline, color, 1.5)
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	var step := 7.0
	var x := box.position.x - box.size.y
	while x < box.end.x:
		var a := Vector2(x, box.end.y)
		var b := Vector2(x + box.size.y, box.position.y)
		var clipped := Geometry2D.clip_polyline_with_polygon(PackedVector2Array([a, b]), points)
		for piece: PackedVector2Array in clipped:
			_canvas.draw_polyline(piece, Color(color, color.a * 0.8), 1.0)
		x += step
