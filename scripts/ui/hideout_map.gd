class_name HideoutMap
extends Control
## The HIDEOUT screen's plan (DESIGN.md §9, §16.1): the hideout from above, every station a room
## (Hideout.room(), in rules.json "plan" cells) that is a button: its name, its level and its state
## (state_of(): locked, can be built, items missing, building with a countdown, crafting, ready to
## collect, built, fully upgraded), coloured by it. Mouse, touch and controller focus all work on the
## rooms; pressing one emits station_pressed. The floor, the corridors, the walls, the lighting and
## the poster wall follow the cosmetics bought (Hideout.cosmetic_in()). refresh() redraws the states.

signal station_pressed(station: Dictionary)

## Room colours by state.
const STATE_COLORS := {
	"ready": Color(0.25, 0.55, 0.3), "building": Color(0.62, 0.45, 0.15), "crafting": Color(0.2, 0.38, 0.6),
	"can_build": Color(0.22, 0.45, 0.32), "missing": Color(0.45, 0.28, 0.18), "locked": Color(0.17, 0.17, 0.18),
	"built": Color(0.24, 0.27, 0.27), "max": Color(0.3, 0.3, 0.26),
}
## The bare hideout, before cosmetics: floor, corridors, walls.
const FLOOR := Color(0.11, 0.115, 0.11)
const HALL := Color(0.16, 0.16, 0.15)
const WALL := Color(0.42, 0.42, 0.4)
## Rooms keep this many pixels clear of the walls.
const INSET := 3.0

var rooms: Dictionary = {}
var _group := ButtonGroup.new()


func _ready() -> void:
	for station in Hideout.stations():
		var button := Button.new()
		button.name = "Room_" + str(station.id)
		button.toggle_mode = true
		button.button_group = _group
		button.clip_text = true
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func() -> void: station_pressed.emit(station))
		add_child(button)
		rooms[station.id] = button
	resized.connect(_layout)
	_layout()
	refresh()


## Marks `station`'s room as the one shown.
func select(station: Dictionary) -> void:
	if rooms.has(station.get("id")):
		(rooms[station.id] as Button).set_pressed_no_signal(true)


## Pixels per plan cell, and where the plan's top-left corner is.
func cell_size() -> float:
	var plan := Vector2(Hideout.plan_size())
	return minf(size.x / plan.x, size.y / plan.y)


## Centred across, at the top.
func origin() -> Vector2:
	return Vector2((size.x - Hideout.plan_size().x * cell_size()) / 2.0, 0.0)


func _layout() -> void:
	var cell := cell_size()
	for station in Hideout.stations():
		var rect := Hideout.room(station)
		var button: Button = rooms[station.id]
		button.position = origin() + Vector2(rect.position) * cell + Vector2(INSET, INSET)
		button.size = Vector2(rect.size) * cell - Vector2(INSET, INSET) * 2.0
	queue_redraw()


## The rooms' text, colours and hover text, from the hideout as it is now.
func refresh() -> void:
	for station in Hideout.stations():
		var button: Button = rooms[station.id]
		var state := state_of(station)
		var level := Hideout.level(station)
		button.text = "%s\n%s\n%s" % [str(station.name).to_upper(), "Not built" if level == 0 else "Level %d / %d" % [level, Hideout.max_level(station)],
			state_text(station)]
		button.tooltip_text = "%s: %s" % [station.name, state_text(station)]
		var color: Color = STATE_COLORS.get(state, STATE_COLORS.built)
		for kind in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = color.lightened(0.12 if kind.begins_with("hover") else 0.0)
			box.border_color = color.lightened(0.45) if kind.ends_with("pressed") else color.lightened(0.2)
			box.set_border_width_all(3 if kind.ends_with("pressed") else 1)
			box.set_corner_radius_all(3)
			box.content_margin_left = 6.0
			box.content_margin_right = 6.0
			button.add_theme_stylebox_override(kind, box)
	queue_redraw()


## What `station` is doing, for its room: "ready" (crafts or production to collect), "building",
## "crafting", "can_build" (its next level can start now), "missing" (only items or roubles short),
## "locked" (not built, and another station's level, a trader's loyalty level or your level short),
## "built" (its next level locked like that), "max".
static func state_of(station: Dictionary) -> String:
	if not HideoutWork.ready(station).is_empty() or (station.id in [Hideout.WATER_COLLECTOR, Hideout.BITCOIN_FARM] and HideoutWork.production(station.id).waiting > 0):
		return "ready"
	if Hideout.is_building(station):
		return "building"
	if not HideoutWork.queue(station).is_empty():
		return "crafting"
	var reason := Hideout.upgrade_block_reason(station)
	if reason == "":
		return "can_build"
	if reason == "Fully upgraded":
		return "max"
	if reason == "Missing items" or reason == "Not enough roubles":
		return "missing"
	return "locked" if Hideout.level(station) == 0 else "built"


## The state as the room's last line: "Ready to collect", "Building 12:30", "Crafting 4:10", "Can be
## built", "Missing 3 / 5 in" (kinds of item handed over), "Locked: Generator 2", "Fully upgraded".
static func state_text(station: Dictionary) -> String:
	match state_of(station):
		"ready":
			return "READY TO COLLECT"
		"building":
			return "Building  %s" % UiFormat.countdown(Hideout.build_seconds_left(station))
		"crafting":
			var left := HideoutWork.seconds_until_done(station, 0)
			return "Crafting  %s" % (UiFormat.countdown(left) if left >= 0.0 else "stopped")
		"can_build":
			return "Can be built" if Hideout.level(station) == 0 else "Upgrade ready"
		"missing":
			var wanted := Hideout.requirements(Hideout.next_level(station))
			var done := wanted.size() - Hideout.outstanding(station).size()
			return "Missing  %d / %d in" % [done, wanted.size()] if not wanted.is_empty() else "Roubles missing"
		"locked":
			return "Locked: " + Hideout.upgrade_block_reason(station).trim_prefix("Needs ").replace(" level ", " ")
		"max":
			return "Fully upgraded"
	var reason := Hideout.upgrade_block_reason(station)
	return "Next: " + reason.trim_prefix("Needs ") if reason.begins_with("Needs") else "Built"


func _draw() -> void:
	var cell := cell_size()
	var top_left := origin()
	var plan := Rect2(top_left, Vector2(Hideout.plan_size()) * cell)
	var floor_look := Hideout.cosmetic_in("floor")
	var wall_look := Hideout.cosmetic_in("walls")
	var floor_color := _color(floor_look, FLOOR)
	draw_rect(plan, HALL if floor_look.is_empty() else floor_color.lightened(0.08))
	for station in Hideout.stations():
		var rect := Hideout.room(station)
		draw_rect(Rect2(top_left + Vector2(rect.position) * cell, Vector2(rect.size) * cell), floor_color)
		if floor_look:  # Tiles.
			for x in range(rect.position.x, rect.end.x):
				draw_line(top_left + Vector2(x, rect.position.y) * cell, top_left + Vector2(x, rect.end.y) * cell, Color(1, 1, 1, 0.04), 1.0)
	var wall_color := _color(wall_look, WALL)
	for station in Hideout.stations():
		var rect := Hideout.room(station)
		draw_rect(Rect2(top_left + Vector2(rect.position) * cell, Vector2(rect.size) * cell), wall_color, false, 3.0 if wall_look else 2.0)
	draw_rect(plan, wall_color, false, 4.0)
	var posters := Hideout.cosmetic_in("posters")
	if posters:  # Along the main hall's walls.
		var paper := _color(posters, Color.WHITE)
		for i in 9:
			var at := top_left + Vector2(1.0 + i * 3.4, 5.15) * cell
			draw_rect(Rect2(at, Vector2(1.6, 0.55) * cell), paper.lerp(Color(0.9, 0.85, 0.6), (i % 3) * 0.3))
			draw_rect(Rect2(at, Vector2(1.6, 0.55) * cell), Color(0, 0, 0, 0.5), false, 1.0)
	var lights := Hideout.cosmetic_in("lighting")
	if lights:  # Warm bulbs strung along both halls, and their glow over the whole plan.
		var bulb := _color(lights, Color.WHITE)
		draw_rect(plan, Color(bulb, 0.05))
		for row in [6.0, 14.0]:
			draw_line(top_left + Vector2(0.5, row) * cell, top_left + Vector2(31.5, row) * cell, Color(0.1, 0.1, 0.1, 0.8), 1.0)
			for i in 16:
				var at: Vector2 = top_left + Vector2(1.0 + i * 2.0, row) * cell
				draw_circle(at, maxf(cell * 0.3, 4.0), Color(bulb, 0.18))
				draw_circle(at, maxf(cell * 0.1, 2.0), Color(bulb, 0.95))
	_draw_legend(plan.end.y)


## Under the plan: what each room colour means.
func _draw_legend(below: float) -> void:
	var names := {"ready": "Ready to collect", "building": "Building", "crafting": "Crafting", "can_build": "Can be built",
		"missing": "Items missing", "locked": "Locked", "built": "Built", "max": "Fully upgraded"}
	var font := get_theme_default_font()
	var at := Vector2(origin().x, below + 22.0)
	for state: String in names:
		var width := 26.0 + font.get_string_size(names[state], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22.0
		if at.x + width > size.x:
			at = Vector2(origin().x, at.y + 26.0)
		draw_rect(Rect2(at + Vector2(0, -12), Vector2(16, 16)), STATE_COLORS[state])
		draw_rect(Rect2(at + Vector2(0, -12), Vector2(16, 16)), Color(STATE_COLORS[state].lightened(0.3)), false, 1.0)
		draw_string(font, at + Vector2(24, 2), names[state], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.85, 0.8))
		at.x += width


static func _color(entry: Dictionary, fallback: Color) -> Color:
	var rgb: Variant = entry.get("color")
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2])) if rgb is Array and rgb.size() == 3 else fallback
