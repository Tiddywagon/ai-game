class_name DebugOverlay
extends CanvasLayer
## In-raid debug overlay (F12, `debug_overlay`): the raid (map, side, seed, clock, power), the
## player's position and extract countdown, the AI (alive, heading for an extract, already left), and
## every extract on the map with its id, type, what it takes and its state this raid: open or closed,
## known or unknown, locked behind a quest, paid, flare fired, and the mark the player sees. Every
## RaidLevel has one; it starts hidden.

const REFRESH := 0.25

var _label: Label
var _timer := 0.0


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
		visible = not visible
		refresh()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		refresh()


func refresh() -> void:
	_label.text = text()


## The overlay's text.
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
	lines.append("EXTRACTS")
	for zone: ExtractZone in get_tree().get_nodes_in_group("extract_zones"):
		lines.append("  " + extract_line(zone, player))
	return "\n".join(lines)


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
