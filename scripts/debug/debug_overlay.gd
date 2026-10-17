class_name DebugOverlay
extends CanvasLayer
## In-raid debug overlay (F12, `debug_overlay`): the raid (map, side, seed, clock, power), the
## player's position and extract countdown, the AI (alive, heading for an extract, already left; the
## boss and its guards; Scav waves; what each bot is doing: its state), and
## every extract on the map with its id, type, what it takes and its state this raid: open or closed,
## known or unknown, locked behind a quest, paid, flare fired, and the mark the player sees. Pressed again
## it shows the points of interest (DESIGN.md §5.2): each one's tier, focus, loot multiplier, how many of
## its spawn points are active this raid and what they spawned, its heat, and the raid events (when the
## rest are due, what happened where); in the world, a marker over every spawn point (green with what
## spawned, grey when inactive) and each POI's name. A third press hides it. Every RaidLevel has one; it
## starts hidden.

const REFRESH := 0.25
const ACTIVE_COLOR := Color(0.45, 1.0, 0.5)
const STATE_NAMES := ["idle", "investigating", "fighting", "searching", "extracting", "patrolling", "looting", "fleeing"]
const INACTIVE_COLOR := Color(0.6, 0.6, 0.6, 0.8)

## 0: the raid, 1: points of interest (while visible).
var page := 0

var _label: Label
var _timer := 0.0
var _markers: Node3D
var _marker_age := 0.0


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 56)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_label = Label.new()
	_label.name = "Text"
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		cycle()
		get_viewport().set_input_as_handled()


## Hidden → the raid page → the POI page → hidden.
func cycle() -> void:
	if not visible:
		visible = true
		page = 0
	elif page == 0:
		page = 1
	else:
		visible = false
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_marker_age += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		refresh()


func refresh() -> void:
	_label.text = (poi_text() if page == 1 else text()) if visible else ""
	_update_markers(visible and page == 1)


## The raid page's text.
func text() -> String:
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	if raid == null:
		return "DEBUG  ·  no raid"
	var lines := PackedStringArray()
	var left := ceili(raid.time_left)
	lines.append("DEBUG  (F12)  ·  %d FPS" % Engine.get_frames_per_second())
	lines.append("Raid: %s  ·  %s  ·  seed %s  ·  %d:%02d left  ·  power %s%s" % [raid.map.display_name if raid.map else raid.map_id,
		raid.side().to_upper(), str(GameState.raid.get("seed", "random")), left / 60, left % 60, raid.power_state(),
		"  ·  OVER: %s" % RaidOutcome.TITLES[raid.outcome.status] if raid.outcome else ""])
	var player := raid.player
	if player:
		var at := player.global_position
		var extracting := ""
		if raid.extract_zone:
			extracting = "  ·  in %s: %s" % [raid.extract_zone.extract_name,
				"%.1f / %.1f s" % [raid.extract_time, raid.config.extract_seconds] if raid.extract_remaining() >= 0.0 else raid.extract_block()]
		lines.append("Player: (%.1f, %.1f, %.1f)%s" % [at.x, at.y, at.z, extracting])
	var scavs := 0
	var pmcs := 0
	var leaving := PackedStringArray()
	for bot: Bot in get_tree().get_nodes_in_group("bots"):
		if bot.is_dead:
			continue
		if bot.side == Actor.Side.SCAV:
			scavs += 1
		else:
			pmcs += 1
		if bot.extract_goal() != "":
			leaving.append("%s → %s (%d%%)" % [bot.name, bot.extract_goal(), roundi(bot.extract_progress() * 100.0)])
	lines.append("AI: %d Scavs, %d PMCs alive  ·  heading out: %s  ·  left: %s" % [scavs, pmcs,
		", ".join(leaving) if not leaving.is_empty() else "none",
		", ".join(raid.ai_extracts.map(func(entry: Dictionary) -> String: return "%s (%s)" % [entry.name, entry.extract])) if not raid.ai_extracts.is_empty() else "none"])
	lines.append("Boss: %s  ·  Scav waves: %d so far, %s" % [boss_text(), raid.waves,
		"next at %d:%02d" % [int(raid.next_wave) / 60, int(raid.next_wave) % 60] if raid.next_wave >= 0.0 else "no more"])
	var doing := {}
	for bot: Bot in get_tree().get_nodes_in_group("bots"):
		if not bot.is_dead:
			var state: String = STATE_NAMES[bot.state] if bot.state < STATE_NAMES.size() else str(bot.state)
			doing[state] = doing.get(state, 0) + 1
	lines.append("AI states: %s" % ", ".join(doing.keys().map(func(state: String) -> String: return "%d %s" % [doing[state], state])))
	lines.append("EXTRACTS")
	for zone: ExtractZone in get_tree().get_nodes_in_group("extract_zones"):
		lines.append("  " + extract_line(zone, player))
	return "\n".join(lines)


## "Iron Matvei (alive, 3 of 4 guards)", "not this raid (35%)" or "none on this map".
func boss_text() -> String:
	for node in get_tree().get_nodes_in_group("boss_spawns"):
		var spawn := node as BossSpawn
		if spawn.entry.is_empty():
			continue
		if spawn.boss == null:
			return "%s not this raid (%d%%)" % [spawn.entry.name, roundi(float(spawn.entry.chance) * 100.0)]
		var alive := spawn.guards.filter(func(guard: Bot) -> bool: return not guard.is_dead).size()
		return "%s (%s, %d of %d guards, %s)" % [spawn.boss.display_name(), "dead" if spawn.boss.is_dead else "alive", alive,
			spawn.guards.size(), STATE_NAMES[spawn.boss.state] if spawn.boss.state < STATE_NAMES.size() else ""]
	return "none on this map"


## The POI page's text: exploration, raid events, then a line per POI and what its spawn points rolled.
func poi_text() -> String:
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	var lines := PackedStringArray()
	var map_key := raid.map_key() if raid else ""
	lines.append("POINTS OF INTEREST  (F12)  ·  %s explored %d / %d (%d%%)  ·  this raid: %s" % [map_key, GameState.explored_count(map_key),
		PoiTable.for_map(map_key).size(), roundi(GameState.exploration(map_key) * 100.0),
		", ".join(raid.visited_pois) if raid and not raid.visited_pois.is_empty() else "none yet"])
	var events := get_tree().get_first_node_in_group("raid_events") as RaidEvents
	if events:
		var due := PackedStringArray()
		for at in events.schedule:
			due.append("%d:%02d" % [int(at) / 60, int(at) % 60])
		var done := PackedStringArray()
		for event: Dictionary in events.events:
			done.append("%s @ %s (%s)" % [RaidEvents.TITLES.get(event.kind, event.kind), event.poi_name, "ready" if event.ready else "coming"])
		lines.append("EVENTS: due at %s  ·  so far: %s" % [", ".join(due) if not due.is_empty() else "none",
			", ".join(done) if not done.is_empty() else "none"])
	var elapsed := raid.elapsed if raid else 0.0
	for node in get_tree().get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		var boost := poi.loot_boost()
		var parts := PackedStringArray([
			"%s [%s]" % [poi.poi_name(), poi.poi_id],
			"T%d %s" % [poi.tier(), ",".join(poi.focus())],
			"Rare+ x%.2f" % boost[ItemData.Rarity.RARE],
			"%d/%d active (%d%%)" % [poi.active_count(), poi.spots.size(), roundi(PoiTable.spawn_chance(poi.entry()) * 100.0)],
			"heat %.1f" % poi.heat(elapsed),
		])
		if poi.is_hidden():
			parts.append("hidden")
		var needs := PoiTable.requirement_text(poi.entry())
		if needs != "":
			parts.append("%s (%s)" % [needs, "met" if poi.requirement_met(raid.player if raid else null) else "not met"])
		var spawned := PackedStringArray()
		for path: String in poi.spots:
			var info: Dictionary = poi.spots[path]
			if info.active and not info.items.is_empty():
				spawned.append("%s: %s" % [info.name, ", ".join(info.items)])
		lines.append("  " + "  ·  ".join(parts))
		if not spawned.is_empty():
			lines.append("      " + "; ".join(spawned))
	return "\n".join(lines)


## Markers in the world over every POI spawn point (and each POI's name), while the POI page is up.
func _update_markers(show: bool) -> void:
	if not show:
		if _markers:
			_markers.queue_free()
			_markers = null
		return
	var level := get_parent() as Node3D
	if level == null or (_markers and _marker_age < 1.0):
		return
	_marker_age = 0.0
	if _markers:
		_markers.free()
	_markers = Node3D.new()
	_markers.name = "PoiMarkers"
	level.add_child(_markers)
	for node in get_tree().get_nodes_in_group("pois"):
		var poi := node as PointOfInterest
		_marker(poi.global_position + Vector3.UP * (poi.size.y + 0.6), "%s  (T%d)" % [poi.poi_name(), poi.tier()],
			MapOverlay.POI_COLORS[clampi(poi.tier(), 1, 3) - 1], 64)
		for path: String in poi.spots:
			var info: Dictionary = poi.spots[path]
			var text := "● %s" % ("\n".join(info.items) if not info.items.is_empty() else "(empty)") if info.active else "○ off"
			_marker(info.at + Vector3.UP * 1.4, text, ACTIVE_COLOR if info.active else INACTIVE_COLOR, 40)


func _marker(at: Vector3, text: String, color: Color, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	_markers.add_child(label)
	label.global_position = at


## One extract: "Office window [office_window]  ·  Random (40%)  ·  CLOSED  ·  unknown  ·  you: Unknown".
static func extract_line(zone: ExtractZone, player: Player) -> String:
	var parts := PackedStringArray([
		"%s [%s]" % [zone.extract_name, zone.extract_id if zone.extract_id != "" else "-"],
		zone.kind_text(),
	])
	if not zone.available:
		parts.append("LOCKED (quest %s)" % zone.quest)
		return "  ·  ".join(parts)
	parts.append("OPEN" if zone.open else "CLOSED")
	parts.append("known" if zone.confirmed else "unknown")
	if zone.price > 0:
		parts.append("paid" if zone.paid else "not paid")
	if zone.needs_flare:
		parts.append("flare fired" if zone.flare_fired else "no flare")
	if zone.sides != "Both":
		parts.append("%s only" % zone.sides)
	parts.append("you: %s" % zone.status_for(player))
	return "  ·  ".join(parts)
