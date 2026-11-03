class_name DebugOverlay
extends CanvasLayer
## In-raid debug overlay (F12, `debug_overlay`): the raid (map, side, seed, clock, power), the
## player's position and extract countdown, the AI (alive: Scavs, and PMCs by faction in how many
## squads; heading for an extract, already left; the boss and its guards; Scav waves; what each bot is
## doing: its state), and
## every extract on the map with its id, type, what it takes and its state this raid: open or closed,
## known or unknown, locked behind a quest, paid, flare fired, and the mark the player sees. Pressed again
## it shows the points of interest (DESIGN.md §5.2): each one's tier, focus, loot multiplier, how many of
## its spawn points are active this raid and what they spawned, its heat, and the raid events (when the
## rest are due, what happened where); in the world, a marker over every spawn point (green with what
## spawned, grey when inactive) and each POI's name. A third press shows the AI PMCs (DESIGN.md §4.4):
## each one's name, faction, squad and leader, personality, what it's doing (its goal), the next POI and
## how many are left, the planned extract and leave time, how full its bags are and its gear tier, and
## the late arrivals; in the world, each squad's planned route as a line in the squad's colour from its
## leader along the way it's walking, through its remaining POIs to its extract, with labels. A fourth
## press hides it. Every RaidLevel has one; it starts hidden.

const REFRESH := 0.25
const ACTIVE_COLOR := Color(0.45, 1.0, 0.5)
const STATE_NAMES := ["idle", "investigating", "fighting", "searching", "extracting", "patrolling", "looting", "fleeing",
	"travelling", "healing", "avoiding"]
## A colour per AI PMC squad (by its number) for its route.
const SQUAD_COLORS := [Color(1.0, 0.55, 0.15), Color(0.3, 0.8, 1.0), Color(0.95, 0.3, 0.85), Color(0.55, 1.0, 0.35),
	Color(1.0, 0.9, 0.25), Color(0.65, 0.5, 1.0), Color(1.0, 0.4, 0.4), Color(0.3, 1.0, 0.8)]
## The route line's width and height above the floor (metres), and its labels' size (pixels, and metres
## a pixel: readable from the camera pulled out over a whole map).
const ROUTE_WIDTH := 0.22
const ROUTE_HEIGHT := 0.3
const ROUTE_LABEL_SIZE := 72
const ROUTE_LABEL_PIXEL := 0.008
## Metres between the labels of squads that share a stop.
const ROUTE_LABEL_STEP := 0.8
const INACTIVE_COLOR := Color(0.6, 0.6, 0.6, 0.8)

## 0: the raid, 1: points of interest, 2: AI PMCs (while visible).
var page := 0

var _label: Label
var _timer := 0.0
var _markers: Node3D
var _marker_age := 0.0
var _routes: Node3D
var _route_age := 0.0


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


## Hidden → the raid page → the POI page → the AI PMC page → hidden.
func cycle() -> void:
	if not visible:
		visible = true
		page = 0
	elif page < 2:
		page += 1
	else:
		visible = false
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_marker_age += delta
	_route_age += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		refresh()


func refresh() -> void:
	_label.text = ([text(), poi_text(), pmc_text()][page] if page >= 0 and page <= 2 else text()) if visible else ""
	_update_markers(visible and page == 1)
	_update_routes(visible and page == 2)


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
	var pmcs := {}
	var leaving := PackedStringArray()
	for bot: Bot in get_tree().get_nodes_in_group("bots"):
		if bot.is_dead:
			continue
		if bot.side == Actor.Side.SCAV:
			scavs += 1
		else:
			var faction := Factions.display_name(bot.faction) if bot.faction != &"" else "PMC"
			pmcs[faction] = pmcs.get(faction, 0) + 1
		if bot.extract_goal() != "":
			leaving.append("%s → %s (%d%%)" % [bot.name, bot.extract_goal(), roundi(bot.extract_progress() * 100.0)])
	var pmc_text := ", ".join(pmcs.keys().map(func(faction: String) -> String: return "%d %s" % [pmcs[faction], faction])) if not pmcs.is_empty() else "0 PMCs"
	var squads := raid.ai_squads.filter(func(squad: Squad) -> bool: return not squad.alive().is_empty()).size()
	lines.append("AI: %d Scavs, %s alive (%d PMC squads)  ·  heading out: %s  ·  left: %s" % [scavs, pmc_text, squads,
		", ".join(leaving) if not leaving.is_empty() else "none",
		", ".join(raid.ai_extracts.map(func(entry: Dictionary) -> String: return "%s (%s)" % [entry.name, entry.extract])) if not raid.ai_extracts.is_empty() else "none"])
	lines.append("Boss: %s  ·  Scav waves: %d so far, %s (%d of %d Scavs alive, the boss squad not counted)" % [boss_text(), raid.waves,
		"next at %d:%02d" % [int(raid.next_wave) / 60, int(raid.next_wave) % 60] if raid.next_wave >= 0.0 else "no more",
		raid.scavs_alive(), raid.config.scav_max_alive])
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


func _marker(at: Vector3, text: String, color: Color, size: int, parent: Node3D = null) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	(parent if parent else _markers).add_child(label)
	label.global_position = at


## The AI PMC page's text: how many are alive in how many squads, the late arrivals (due and come),
## then a line per AI PMC.
func pmc_text() -> String:
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	var lines := PackedStringArray()
	if raid == null:
		return "AI PMCs  (F12)  ·  no raid"
	var alive := 0
	var spawned := 0
	var squads := 0
	for squad in raid.ai_squads:
		alive += squad.alive().size()
		spawned += squad.size()
		squads += 0 if squad.alive().is_empty() else 1
	var due := PackedStringArray()
	for entry: Dictionary in raid.pmc_schedule:
		due.append("%s (%d %s)" % [_clock(float(entry.time)), int(entry.size), Factions.display_name(entry.faction)])
	var came := PackedStringArray()
	for entry: Dictionary in raid.late_arrivals:
		came.append("gave up" if entry.get("gave_up", false) else "squad %d at %s, %s" % [int(entry.squad), _clock(float(entry.spawned_at)), entry.point])
	lines.append("AI PMCs  (F12)  ·  %d of %d alive in %d squads (%d this raid by schedule)  ·  late arrivals due: %s  ·  came: %s" % [alive,
		spawned, squads, raid.ai_pmcs, ", ".join(due) if not due.is_empty() else "none", ", ".join(came) if not came.is_empty() else "none"])
	for bot: Bot in get_tree().get_nodes_in_group("bots"):
		if not bot.is_dead and bot.side == Actor.Side.PMC:
			lines.append("  " + pmc_line(bot))
	return "\n".join(lines)


## One AI PMC: "AIPMC1  ·  USEC  ·  squad 1, leader  ·  Looter  ·  loot  ·  next Signal hut  ·  2 POIs left  ·
## exit North-east gate at 9:30  ·  bags 34%  ·  Good" (bags: how much of the room its kit left it has
## filled with loot, Bot.loot_fill(); then any POIs it skipped).
static func pmc_line(bot: Bot) -> String:
	var parts := PackedStringArray([str(bot.name), Factions.display_name(bot.faction) if bot.faction != &"" else "PMC"])
	var squad := bot.squad
	if squad:
		parts.append("squad %d, %s" % [squad.number, "leader" if squad.leader == bot else "led by %s" % squad.leader.name if squad.leader else "no leader"])
	var plan := bot.plan()
	if plan == null:
		parts.append_array(["no plan", bot.goal_name(), "bags %d%%" % roundi(bot.loot_fill() * 100.0)])
		return "  ·  ".join(parts)
	if not plan.chosen:
		parts.append_array([plan.personality_name(), bot.goal_name(), "route not planned yet", "leaves at %s" % _clock(plan.leave_at),
			"bags %d%%" % roundi(bot.loot_fill() * 100.0), plan.tier_name()])
		return "  ·  ".join(parts)
	var next := plan.next_poi()
	parts.append_array([plan.personality_name(), bot.goal_name(), "next %s" % (next.poi_name() if next else "none"),
		"%d POI%s left" % [plan.pois_left(), "" if plan.pois_left() == 1 else "s"],
		"exit %s at %s%s" % [plan.extract.extract_name if is_instance_valid(plan.extract) else "?", _clock(plan.leave_at),
			" (out: %s)" % plan.reason if plan.reason != "" else ""],
		"bags %d%%" % roundi(bot.loot_fill() * 100.0), plan.tier_name()])
	if not plan.skipped.is_empty():
		parts.append("skipped %s" % ", ".join(plan.skipped))  # POIs it couldn't get to.
	return "  ·  ".join(parts)


## "9:30" for raid seconds.
static func _clock(seconds: float) -> String:
	var whole := maxi(int(seconds), 0)
	return "%d:%02d" % [whole / 60, whole % 60]


## Each AI PMC squad's planned route in the world while the PMC page is up (redrawn every second): a line
## in the squad's colour from its leader along the way it's walking, through its remaining POIs to its
## extract, a label over the leader and at each stop.
func _update_routes(show: bool) -> void:
	if not show:
		if _routes:
			_routes.queue_free()
			_routes = null
		return
	var level := get_parent() as Node3D
	if level == null or (_routes and _route_age < 1.0):
		return
	_route_age = 0.0
	if _routes:
		_routes.free()
	_routes = Node3D.new()
	_routes.name = "PmcRoutes"
	level.add_child(_routes)
	var raid := get_tree().get_first_node_in_group("raid_controller") as RaidController
	if raid == null:
		return
	for squad in raid.ai_squads:
		var lead := squad.leader
		if squad.plan == null or lead == null or not is_instance_valid(lead) or lead.is_dead or not lead.is_inside_tree():
			continue
		var color: Color = SQUAD_COLORS[(squad.number - 1) % SQUAD_COLORS.size()]
		var points := route_points(squad)
		var line := _route_line(points, color)
		line.name = "Route%d" % squad.number
		_routes.add_child(line)
		_route_label(lead.global_position + Vector3.UP * 2.6, "Squad %d · %s · %s" % [squad.number, squad.plan.personality_name(), lead.goal_name()], color)
		var plan := squad.plan
		# Squads sharing a stop list it one under the other (south is down the screen).
		var stagger := Vector3.BACK * ROUTE_LABEL_STEP * ((squad.number - 1) % SQUAD_COLORS.size())
		for i in range(plan.index, plan.pois.size()):
			if is_instance_valid(plan.pois[i]):
				_route_label(RaidPlan.poi_point(plan.pois[i]) + Vector3.UP * 1.2 + stagger, "%d. %s" % [i - plan.index + 1, plan.pois[i].poi_name()], color)
		if is_instance_valid(plan.extract):
			_route_label(plan.extract.global_position + Vector3.UP * 1.6 + stagger, "EXIT %s · %s" % [plan.extract.extract_name, _clock(plan.leave_at)], color)


## A route label: big enough to read from a camera pulled out over the map, its text drawn over its
## outline and over the route lines.
func _route_label(at: Vector3, text: String, color: Color) -> void:
	_marker(at, text, color, ROUTE_LABEL_SIZE, _routes)
	var label := _routes.get_child(-1) as Label3D
	label.pixel_size = ROUTE_LABEL_PIXEL
	label.outline_size = 16
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED  # Sorted by priority (cut-out text can lose to its own outline).
	label.outline_render_priority = 20
	label.render_priority = 21


## The points of `squad`'s planned route: its leader, the rest of the route it's walking (to a POI or
## its extract), its remaining POIs, its extract.
static func route_points(squad: Squad) -> PackedVector3Array:
	var lead := squad.leader
	var plan := squad.plan
	var points := PackedVector3Array([lead.global_position])
	if lead.state in [Bot.State.TRAVEL, Bot.State.EXTRACT] and lead.route.size() >= 2:
		points.append_array(lead.route.slice(mini(lead._route_index, lead.route.size() - 1)))
	if lead.state != Bot.State.EXTRACT:
		for i in range(plan.index, plan.pois.size()):
			if is_instance_valid(plan.pois[i]):
				points.append(RaidPlan.poi_point(plan.pois[i]))
	if is_instance_valid(plan.extract):
		points.append(plan.extract.global_position)
	return points


## A flat ribbon through `points` (ROUTE_WIDTH wide, ROUTE_HEIGHT up), drawn over everything.
static func _route_line(points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var drawn := false
	for i in range(1, points.size()):
		var a := points[i - 1] + Vector3.UP * ROUTE_HEIGHT
		var b := points[i] + Vector3.UP * ROUTE_HEIGHT
		var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if along.length() < 0.05:
			continue
		if not drawn:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drawn = true
		var side := Vector3(-along.z, 0.0, along.x).normalized() * ROUTE_WIDTH * 0.5
		for corner in [a - side, a + side, b + side, a - side, b + side, b - side]:
			mesh.surface_add_vertex(corner)
	if drawn:
		mesh.surface_end()
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 10
	line.material_override = material
	return line


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
