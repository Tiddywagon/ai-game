extends CanvasLayer
## In-raid HUD (DESIGN.md §13, §17): body silhouette with status effects, a red vignette while in
## pain, stamina bar, movement state, a shield icon in cover,
## short messages such as "Can't roll: overweight", the raid name, the ammo panel (rounds in the
## magazine, spare rounds, loaded ammo, reload progress), the aiming reticle and hit markers.
## Vision (DESIGN.md §13.6): direction markers for sounds you can't see, a white-out while blinded,
## time of day and weather next to the raid name, and the sight in use or the binoculars.
## Raid (DESIGN.md §2, §5): the time left under the raid name (amber in the last 5 minutes, red in the
## last minute); your extracts for a few seconds at raid start and whenever you press O (Show extracts),
## each marked Open, Unknown (a random one you haven't seen), Closed or with what it still needs ("Pay
## 7,000 ₽", "Needs Factory exit key", "No backpack"); an "F  Search ..." prompt when a container, body
## or item is in reach; and while extracting a countdown with a progress ring around you (or why the
## extract you're in won't take you yet).
## 360 trick shots (DESIGN.md §13.4): "TRICK SHOT READY" while the window is open, a gold hit marker
## and a sound sting for a trick-shot hit, and a kill banner with the bonus experience and Drip.
## Consumables (DESIGN.md §13.7): energy and hydration bars under stamina (amber when hungry or
## thirsty, red at 0) with a pulsing warning under them (HUNGRY, THIRSTY, EXHAUSTION, DEHYDRATION), the
## view blurring at 0, running effects beside the body (benefits green, drawbacks red, with the time
## left), what E would treat, and a progress bar with the item's name while one is being used.
## Stims (DESIGN.md §13.8): a row of icons over the body with countdown timers (StimIcons).
## Points of interest (DESIGN.md §5.2): walking into one for the first time in a raid shows its name for
## a few seconds near the top, with its tier and focus, and "NEW AREA" with the experience and how much of
## the map you've explored the first time ever ("HIDDEN AREA FOUND" for a hidden one). Raid events
## (airdrops, supply trucks, weapon caches) are announced in the same place (announce()).
## HUD scale, opacity, units and reticle come from Settings.

const NORMAL_COLOR := Color(0.85, 0.85, 0.75)
const EXHAUSTED_COLOR := Color(0.85, 0.3, 0.25)
## Shield colour while peeking, i.e. exposed.
const PEEK_COLOR := Color(0.95, 0.7, 0.3)
## Round count colours: a third of a magazine or less, and empty.
const LOW_AMMO_COLOR := Color(0.95, 0.7, 0.3)
const EMPTY_COLOR := Color(0.85, 0.3, 0.25)
const MESSAGE_TIME := 2.0
## Indexed by CoverBox.CoverMaterial.
const MATERIAL_NAMES := ["wood", "concrete", "metal"]
const EXTRACT_COLOR := Color(0.45, 0.95, 0.5)
const EXTRACT_BLOCKED_COLOR := Color(0.95, 0.72, 0.3)
const CLOSED_COLOR := Color(0.9, 0.35, 0.3)
## The extract progress ring around the player, in pixels.
const RING_RADIUS := 52.0
const RING_WIDTH := 7.0
## The raid clock turns amber, then red, with this many seconds left.
const CLOCK_WARNING := 300.0
const CLOCK_DANGER := 60.0
const TRICK_STING := preload("res://assets/audio/sfx/trick_sting.wav")
## How long the trick-shot kill banner stays up.
const BANNER_TIME := 2.6
const RAID_CONFIG: RaidConfig = preload("res://data/config/raid.tres")
const BUFF_COLOR := Color(0.55, 0.9, 0.55)
const DRAWBACK_COLOR := Color(0.95, 0.45, 0.4)
const ENERGY_COLOR := Color(0.9, 0.78, 0.4)
const HYDRATION_COLOR := Color(0.45, 0.7, 0.95)
## How often the E hint works out what it would use, in seconds.
const HINT_INTERVAL := 0.25
const BLUR_SHADER := preload("res://assets/shaders/depleted_blur.gdshader")

## The player whose status is shown.
@export var player: Player

var _message_time := 0.0
var _raid: RaidController
var _raid_line := ""
var _prompt: Label
## The prompt's button icon (keycap, controller button), and the row holding both.
var _prompt_icon: PromptIcon
var _prompt_row: Control
var _extract: Label
var _extract_ring: Control
## Seconds the extract list stays up.
var _extract_list_left := 0.0
var _trick_ready: Label
var _sting: AudioStreamPlayer
var _banner: Control
var _banner_title: Label
var _banner_detail: Label
var _banner_tween: Tween
var _poi_box: VBoxContainer
var _poi_title: Label
var _poi_detail: Label
var _poi_tween: Tween
var _energy_bar: ProgressBar
var _energy_label: Label
var _hydration_bar: ProgressBar
var _hydration_label: Label
var _buffs: Label
var _drawbacks: Label
var _treat_hint: Label
var _use_label: Label
var _use_bar: ProgressBar
var _hint_time := 0.0
var _metabolism_warning: Label
var _blur: ColorRect
var _stim_icons: StimIcons

@onready var _root: Control = %HudRoot
@onready var _bottom_left: Control = %BottomLeft
@onready var _bar: ProgressBar = %StaminaBar
@onready var _fill: StyleBoxFlat = _bar.get_theme_stylebox("fill")
@onready var _state: Label = %MoveState
@onready var _message: Label = %Message
@onready var _cover_panel: Control = %CoverPanel
@onready var _cover_icon = %CoverIcon  # cover_icon.gd
@onready var _cover_label: Label = %CoverLabel
@onready var _reticle = %Reticle  # reticle.gd


func _ready() -> void:
	_reticle.player = player
	if player:
		%Silhouette.health = player.health
		player.action_blocked.connect(show_message)
		player.died.connect(show_message.bind("KILLED IN ACTION", 10.0))
		player.hit_landed.connect(func(target: Actor, _damage: float, _at: Vector3) -> void:
			if Settings.get_value("gameplay", "hit_markers"):
				_reticle.show_hit_marker(target.is_dead, player.weapon.firing_trick_shot, not player.last_hit.get("penetrated", true)))
		player.trick_shot_ready.connect(_on_trick_shot_ready)
		player.trick_shot_hit.connect(_on_trick_shot_hit)
	%SoundMarkers.player = player
	_build_prompt()
	_extract = _add_center_label(-470.0, 40, EXTRACT_COLOR)
	_trick_ready = _add_center_label(-330.0, 34, Player.TRICK_COLOR)  # Below the player, above the F prompt.
	_trick_ready.name = "TrickReady"
	_sting = AudioStreamPlayer.new()
	_sting.stream = TRICK_STING
	_sting.bus = &"Effects"
	add_child(_sting)
	_build_banner()
	_build_poi_label()
	_connect_raid.call_deferred()
	_build_consumables()
	_extract_ring = Control.new()
	_extract_ring.name = "ExtractRing"
	_extract_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_extract_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extract_ring.draw.connect(_draw_extract_ring)
	add_child(_extract_ring)
	_extract_list_left = RAID_CONFIG.extract_list_seconds
	VisionSystem.conditions_changed.connect(_update_raid_info)
	_update_raid_info()
	for panel: Control in [%TopRight, _bottom_left, %BottomRight]:
		InputHub.nudge_to_safe_area(panel)  # Clear of notches on phones.
	_connect_vision.call_deferred()
	Settings.applied.connect(_apply_settings)
	_apply_settings()


## Shows your extracts for RaidConfig.extract_list_seconds.
func show_extract_list() -> void:
	_extract_list_left = (_raid.config if _raid else RAID_CONFIG).extract_list_seconds


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("show_extracts") and player and not player.is_dead:
		show_extract_list()


## Shows `text` above the stamina panel for `duration` seconds.
## The POI name label, top centre (under the raid clock's height).
func _build_poi_label() -> void:
	_poi_box = VBoxContainer.new()
	_poi_box.name = "PoiLabel"
	_poi_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poi_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_poi_box.offset_left = -500.0
	_poi_box.offset_right = 500.0
	_poi_box.offset_top = 96.0
	_poi_box.add_theme_constant_override("separation", 2)
	_poi_box.modulate.a = 0.0
	_root.add_child(_poi_box)
	_poi_title = Label.new()
	_poi_title.name = "Title"
	_poi_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_poi_title.add_theme_font_size_override("font_size", 34)
	_poi_title.add_theme_constant_override("outline_size", 6)
	_poi_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_poi_box.add_child(_poi_title)
	_poi_detail = Label.new()
	_poi_detail.name = "Detail"
	_poi_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_poi_detail.add_theme_font_size_override("font_size", 18)
	_poi_detail.add_theme_constant_override("outline_size", 4)
	_poi_detail.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_poi_box.add_child(_poi_detail)


func _connect_raid() -> void:
	if _raid == null:
		_raid = get_tree().get_first_node_in_group("raid_controller") as RaidController
	if _raid and not _raid.poi_entered.is_connected(_on_poi_entered):
		_raid.poi_entered.connect(_on_poi_entered)


func _on_poi_entered(poi: PointOfInterest, first_time: bool) -> void:
	var detail := PoiTable.summary(poi.entry())
	if first_time:
		var gained := PoiTable.CONFIG.xp_discover_hidden if poi.is_hidden() else PoiTable.CONFIG.xp_discover
		detail = "%s  ·  +%d XP  ·  %s %d%% explored" % ["HIDDEN AREA FOUND" if poi.is_hidden() else "NEW AREA", gained,
			_raid.map.display_name if _raid and _raid.map else "Map", roundi(GameState.exploration(poi.map_id) * 100.0)]
	var color: Color = MapOverlay.POI_COLORS[clampi(poi.tier(), 1, 3) - 1]
	announce(poi.poi_name().to_upper(), detail, Color(color, 1.0))


## Shows `title` and `detail` near the top for PoiConfig.label_seconds (a POI's name, a raid event).
func announce(title: String, detail: String, color := Color(0.92, 0.9, 0.8)) -> void:
	_poi_title.text = title
	_poi_title.add_theme_color_override("font_color", color)
	_poi_detail.text = detail
	if _poi_tween:
		_poi_tween.kill()
	_poi_tween = create_tween()
	_poi_tween.tween_property(_poi_box, "modulate:a", 1.0, 0.25)
	_poi_tween.tween_interval(PoiTable.CONFIG.label_seconds)
	_poi_tween.tween_property(_poi_box, "modulate:a", 0.0, 0.6)


## The text of the POI / event label now ("" when it's faded out).
func announcement() -> String:
	return "%s · %s" % [_poi_title.text, _poi_detail.text] if _poi_box.modulate.a > 0.01 else ""


func show_message(text: String, duration := MESSAGE_TIME) -> void:
	_message.text = text
	_message_time = duration


func _update_raid_info() -> void:
	var raid := GameState.raid
	if _raid == null:
		_raid = get_tree().get_first_node_in_group("raid_controller") as RaidController
	var map := _raid.map if _raid else MapInfo.find(raid.get("map", ""))
	_raid_line = "%s  ·  %s  ·  %s  ·  %s" % [map.display_name.to_upper() if map else "TEST YARD",
		Factions.side_name(str(raid.get("side", "pmc"))).to_upper(), VisionSystem.time_name(VisionSystem.time_of_day).to_upper(),
		VisionSystem.weather_name(VisionSystem.weather).to_upper()]
	if map and map.climate != "Temperate":
		_raid_line += "  ·  %s" % map.climate.to_upper()
	_update_raid_clock()


## The raid name line and the time left, and the extract list.
func _update_raid_clock() -> void:
	if _raid == null:
		_raid = get_tree().get_first_node_in_group("raid_controller") as RaidController
	var text := _raid_line
	var color := NORMAL_COLOR
	if _raid:
		var seconds := ceili(_raid.time_left)
		text += "\n%d:%02d LEFT" % [seconds / 60, seconds % 60]
		if _raid.time_left <= CLOCK_DANGER:
			color = CLOSED_COLOR
		elif _raid.time_left <= CLOCK_WARNING:
			color = EXTRACT_BLOCKED_COLOR
	if %RaidInfo.text != text:
		%RaidInfo.text = text
	%RaidInfo.add_theme_color_override("font_color", color)
	var list := extract_list_text()
	if %ExtractList.text != list:
		%ExtractList.text = list
	%ExtractList.visible = _extract_list_left > 0.0 and list != ""
	%ExtractList.modulate.a = clampf(_extract_list_left, 0.0, 1.0)  # Fades out over its last second.


## The extract list (BBCode): "EXTRACTS", then each of your extracts with its mark (Open, Unknown,
## Closed or what it still needs), green when you can use it, amber while a condition isn't met, red
## when it's closed, grey while unknown.
func extract_list_text() -> String:
	if _raid == null:
		return ""
	var zones := _raid.available_extracts()
	if zones.is_empty():
		return ""
	var lines := ["[right][b]EXTRACTS[/b]  (%s)" % Settings.key_label("show_extracts")]
	for zone in zones:
		var color: Color = ExtractZone.STATE_COLORS[zone.status_state(player)]
		lines.append("[color=#%s]%s  ·  %s[/color]" % [color.to_html(false), zone.extract_name, zone.status_for(player)])
	return "\n".join(lines) + "[/right]"


## The F prompt, the extract countdown and TRICK SHOT READY.
func _update_raid_prompts() -> void:
	_trick_ready.visible = player != null and player.trick_window_left > 0.0 and not player.is_dead
	if _trick_ready.visible:
		_trick_ready.text = "TRICK SHOT READY  %.1f" % player.trick_window_left
	var target := player.focused_interactable if player and not player.ui_open and not player.is_dead else null
	_prompt_row.visible = target != null and not InputHub.touch_controls_visible()  # On touch the Interact button says it.
	if target:
		_prompt.text = target.interact_text()
	var left := _raid.extract_remaining() if _raid else -1.0
	var blocked := _raid.extract_block() if _raid else ""
	_extract.visible = left >= 0.0 or blocked != ""
	_extract_ring.visible = left >= 0.0 and not player.is_dead
	if _extract_ring.visible:
		_extract_ring.queue_redraw()
	if left >= 0.0:
		_extract.text = "EXTRACTING  %.1f" % left
		_extract.add_theme_color_override("font_color", EXTRACT_COLOR)
	elif blocked != "":
		_extract.text = "CAN'T EXTRACT: %s" % blocked.to_upper()
		_extract.add_theme_color_override("font_color", EXTRACT_BLOCKED_COLOR)


## The extract countdown ring around the player: fills clockwise from the top (the seconds are in the
## EXTRACTING line).
func _draw_extract_ring() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or player == null or _raid == null:
		return
	var centre := camera.unproject_position(player.global_position + Vector3.UP * 0.9)
	var progress := _raid.extract_progress()
	_extract_ring.draw_arc(centre, RING_RADIUS, 0.0, TAU, 64, Color(0, 0, 0, 0.55), RING_WIDTH + 4.0, true)
	_extract_ring.draw_arc(centre, RING_RADIUS, 0.0, TAU, 64, Color(EXTRACT_COLOR, 0.25), RING_WIDTH, true)
	if progress > 0.0:
		_extract_ring.draw_arc(centre, RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * progress, 64, EXTRACT_COLOR, RING_WIDTH, true)


func _on_trick_shot_ready() -> void:
	_sting.pitch_scale = 0.6
	_sting.volume_db = -8.0
	_sting.play()


## A trick shot hit: the sting; a kill gets the banner too.
func _on_trick_shot_hit(target: Actor, _damage: float, _at: Vector3, killed: bool) -> void:
	_sting.pitch_scale = 1.0
	_sting.volume_db = 0.0
	_sting.play()
	if killed:
		var config := _raid.config if _raid else RAID_CONFIG
		show_trick_banner("%s DOWN  ·  +%d XP  ·  +%d DRIP" % [target.display_name().to_upper(), config.xp_trick_kill, config.drip_trick_kill])


## The kill banner: a dark band across the screen with "360 TRICK SHOT" sliding in, then fading.
func show_trick_banner(detail: String) -> void:
	_banner_detail.text = detail
	_banner.show()
	_banner.modulate.a = 1.0
	if _banner_tween:
		_banner_tween.kill()
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	_banner.scale = Vector2(1.0, 0.2 if not reduced else 1.0)
	_banner_title.position.x = -260.0 if not reduced else 0.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel()
	_banner_tween.tween_property(_banner, "scale:y", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(_banner_title, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.5).set_delay(BANNER_TIME - 0.5)
	_banner_tween.chain().tween_callback(_banner.hide)


func _build_banner() -> void:
	_banner = Control.new()
	_banner.name = "TrickBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.24
	_banner.anchor_bottom = 0.24
	_banner.offset_bottom = 120.0
	_banner.pivot_offset = Vector2(0, 60)
	_banner.hide()
	_root.add_child(_banner)
	var band := ColorRect.new()
	band.color = Color(0.06, 0.03, 0.08, 0.72)
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(band)
	for edge in [0.0, 1.0]:
		var line := ColorRect.new()
		line.color = Player.TRICK_COLOR
		line.anchor_right = 1.0
		line.anchor_top = edge
		line.anchor_bottom = edge
		line.offset_top = -2.0 if edge > 0.0 else 0.0
		line.offset_bottom = 0.0 if edge > 0.0 else 2.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(line)
	_banner_title = Label.new()
	_banner_title.name = "Title"
	_banner_title.text = "★  360 TRICK SHOT  ★"
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.anchor_right = 1.0
	_banner_title.offset_top = 10.0
	_banner_title.offset_bottom = 72.0
	_banner_title.add_theme_font_size_override("font_size", 48)
	_banner_title.add_theme_color_override("font_color", Player.TRICK_COLOR)
	_banner_title.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.25))
	_banner_title.add_theme_constant_override("outline_size", 10)
	_banner_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_banner_title.add_theme_constant_override("shadow_offset_x", 3)
	_banner_title.add_theme_constant_override("shadow_offset_y", 3)
	_banner.add_child(_banner_title)
	_banner_detail = Label.new()
	_banner_detail.name = "Detail"
	_banner_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_detail.anchor_right = 1.0
	_banner_detail.offset_top = 74.0
	_banner_detail.offset_bottom = 110.0
	_banner_detail.add_theme_font_size_override("font_size", 20)
	_banner_detail.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_banner.add_child(_banner_detail)


## Energy and hydration bars under stamina; effect lists and the E hint beside the body; the use
## progress bar above the player.
func _build_consumables() -> void:
	var rows: VBoxContainer = _bar.get_parent()
	var line := HBoxContainer.new()
	line.name = "Metabolism"
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(line)
	rows.move_child(line, _bar.get_index() + 1)
	var energy := _metabolism_bar(line, "ENERGY", ENERGY_COLOR)
	_energy_label = energy[0]
	_energy_bar = energy[1]
	var hydration := _metabolism_bar(line, "WATER", HYDRATION_COLOR)
	_hydration_label = hydration[0]
	_hydration_bar = hydration[1]
	_metabolism_warning = Label.new()
	_metabolism_warning.name = "MetabolismWarning"
	_metabolism_warning.add_theme_font_size_override("font_size", 14)
	_metabolism_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_metabolism_warning.hide()
	rows.add_child(_metabolism_warning)
	rows.move_child(_metabolism_warning, line.get_index() + 1)
	# Exhaustion and Dehydration blur the view: drawn first, under the rest of the HUD.
	_blur = ColorRect.new()
	_blur.name = "DepletedBlur"
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_material := ShaderMaterial.new()
	blur_material.shader = BLUR_SHADER
	_blur.material = blur_material
	_blur.hide()
	_root.add_child(_blur)
	_root.move_child(_blur, 0)
	# Long messages ("Propital ...: regeneration +1.0 HP/s, painkiller") wrap instead of widening the panel.
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = _bar.custom_minimum_size.x
	_stim_icons = StimIcons.new()
	_stim_icons.name = "StimIcons"
	_stim_icons.health = player.health if player else null
	_stim_icons.hide()
	var health_panel: Control = %Silhouette.get_parent().get_parent()
	_bottom_left.add_child(_stim_icons)
	_bottom_left.move_child(_stim_icons, health_panel.get_index())
	var info: VBoxContainer = %StatusList.get_parent()
	_buffs = _info_label(info, "Buffs", BUFF_COLOR)
	_drawbacks = _info_label(info, "Drawbacks", DRAWBACK_COLOR)
	_treat_hint = _info_label(info, "TreatHint", Color(NORMAL_COLOR, 0.75))
	_use_label = _add_center_label(-400.0, 24, NORMAL_COLOR)
	_use_label.name = "UseLabel"
	_use_bar = ProgressBar.new()
	_use_bar.name = "UseBar"
	_use_bar.show_percentage = false
	_use_bar.max_value = 1.0
	_use_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_bar.anchor_left = 0.5
	_use_bar.anchor_right = 0.5
	_use_bar.anchor_top = 1.0
	_use_bar.anchor_bottom = 1.0
	_use_bar.offset_left = -170.0
	_use_bar.offset_right = 170.0
	_use_bar.offset_top = -356.0
	_use_bar.offset_bottom = -346.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.55)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BUFF_COLOR
	_use_bar.add_theme_stylebox_override("background", background)
	_use_bar.add_theme_stylebox_override("fill", fill)
	_use_bar.hide()
	_root.add_child(_use_bar)


## A small "ENERGY 74" label and bar in `parent`: returns [label, bar].
func _metabolism_bar(parent: Control, title: String, color: Color) -> Array:
	var box := VBoxContainer.new()
	box.name = title.capitalize()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(NORMAL_COLOR, 0.85))
	label.text = title
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	return [label, bar]


func _info_label(parent: Control, node_name: String, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 240.0
	label.hide()
	parent.add_child(label)
	return label


## The F prompt: the interact button's icon for the device in use, then what it would do.
func _build_prompt() -> void:
	var centre := CenterContainer.new()
	centre.name = "Prompt"
	centre.anchor_left = 0.0
	centre.anchor_right = 1.0
	centre.anchor_top = 1.0
	centre.anchor_bottom = 1.0
	centre.offset_top = -214.0
	centre.offset_bottom = -174.0
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.hide()
	_root.add_child(centre)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(row)
	_prompt_icon = PromptIcon.new()
	_prompt_icon.action = "interact"
	_prompt_icon.icon_size = 30.0
	_prompt_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prompt_icon)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", NORMAL_COLOR)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_prompt)
	_prompt_row = centre


func _add_center_label(from_bottom: float, size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = from_bottom
	label.offset_bottom = from_bottom + size * 1.6
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.hide()
	_root.add_child(label)
	return label


func _connect_vision() -> void:
	var vision := get_tree().get_first_node_in_group("player_vision")
	if vision:
		vision.sound_heard.connect(%SoundMarkers.add_marker)


func _apply_settings() -> void:
	_root.modulate.a = Settings.get_value("interface", "hud_opacity")
	var hud_scale: float = Settings.get_value("interface", "hud_scale")
	for control: Control in [_bottom_left, %TopRight, %BottomRight]:
		control.scale = Vector2.ONE * hud_scale


func _process(delta: float) -> void:
	# Scale the panels from the corner they're anchored to.
	_bottom_left.pivot_offset = Vector2(0.0, _bottom_left.size.y)
	%TopRight.pivot_offset = Vector2(%TopRight.size.x, 0.0)
	%BottomRight.pivot_offset = %BottomRight.size
	_message_time -= delta
	_message.visible = _message_time > 0.0
	_extract_list_left = maxf(_extract_list_left - delta, 0.0)
	_update_raid_clock()
	if player == null:
		return
	_update_raid_prompts()
	_bar.max_value = player.stamina_cap()
	_bar.value = player.stamina
	_fill.bg_color = EXHAUSTED_COLOR if player.is_exhausted else NORMAL_COLOR
	var text := "%s  ·  noise %s" % [_move_text(), Settings.format_distance(player.noise_radius)]
	if player.is_exhausted:
		text += "  ·  exhausted"
	if player.is_overweight():
		text += "  ·  overweight %s" % Settings.format_weight(player.carried_weight_kg)
	elif player.is_encumbered():
		text += "  ·  heavy %s" % Settings.format_weight(player.carried_weight_kg)
	_state.text = text
	_update_health(delta)
	_update_consumables(delta)
	_update_ammo()
	_update_blind()

	var cover := player.cover
	_cover_panel.visible = cover != null
	if cover:
		var cover_text := "%s cover · %s" % ["Low" if cover.is_low else "High", MATERIAL_NAMES[cover.material]]
		if player.is_peeking:
			cover_text += " · peeking"
		elif not cover.can_peek:
			cover_text += " · no peek here"
		_cover_label.text = cover_text
		_cover_icon.color = PEEK_COLOR if player.is_peeking else NORMAL_COLOR


func _update_health(delta: float) -> void:
	var health := player.health
	%HealthTotal.text = "HP %d / %d" % [ceili(health.total()), roundi(health.max_total())]
	var lines := health.status_lines()
	%StatusList.text = "\n".join(lines)
	%StatusList.visible = not lines.is_empty()
	# Pain: dark red edges, slowly pulsing (steady with "reduce flashing").
	var target := 0.0
	if health.has_pain() and not player.is_dead:
		target = 1.0 if Settings.get_value("accessibility", "reduce_flashing") else 0.8 + 0.2 * sin(Time.get_ticks_msec() / 400.0)
	%PainVignette.modulate.a = move_toward(%PainVignette.modulate.a, target, delta * 2.0)


func _update_consumables(delta: float) -> void:
	var health := player.health
	var tuning := Consumables.CONFIG
	_set_metabolism(_energy_bar, _energy_label, "ENERGY", health.energy, tuning.max_energy, ENERGY_COLOR, tuning.low_threshold)
	_set_metabolism(_hydration_bar, _hydration_label, "WATER", health.hydration, tuning.max_hydration, HYDRATION_COLOR, tuning.low_threshold)
	_update_metabolism_warning(health)
	var buffs := health.effect_lines(false)
	_buffs.text = "\n".join(buffs)
	_buffs.visible = not buffs.is_empty()
	var drawbacks := health.effect_lines(true)
	_drawbacks.text = "\n".join(drawbacks)
	_drawbacks.visible = not drawbacks.is_empty()
	_hint_time -= delta
	if _hint_time <= 0.0:
		_hint_time = HINT_INTERVAL
		_treat_hint.text = treat_hint_text()
	_treat_hint.visible = _treat_hint.text != "" and player.using_item == null and not player.is_dead
	var item := player.using_item
	_use_label.visible = item != null and not player.is_dead
	_use_bar.visible = _use_label.visible
	if item:
		_use_label.text = "USING  %s  %.1f" % [item.data.display_name.to_upper(), maxf(player.use_time_left, 0.0)]
		_use_bar.value = player.use_progress()


## Under the bars: HUNGRY / THIRSTY (amber) below the low threshold, EXHAUSTION / DEHYDRATION (red) at
## 0, pulsing (steady with "reduce flashing"); and the blur over the view at 0.
func _update_metabolism_warning(health: BodyHealth) -> void:
	var words: Array[String] = []
	if health.has_dehydration():
		words.append("DEHYDRATION")
	elif health.is_thirsty():
		words.append("THIRSTY")
	if health.has_exhaustion():
		words.append("EXHAUSTION")
	elif health.is_hungry():
		words.append("HUNGRY")
	var depleted := health.has_dehydration() or health.has_exhaustion()
	_metabolism_warning.visible = not words.is_empty() and not player.is_dead
	if _metabolism_warning.visible:
		var hint := "losing HP: eat or drink now" if depleted else "stamina recovers slower"
		_metabolism_warning.text = "%s  ·  %s" % ["  ·  ".join(words), hint]
		var pulse := 1.0 if Settings.get_value("accessibility", "reduce_flashing") else 0.65 + 0.35 * absf(sin(Time.get_ticks_msec() / 350.0))
		_metabolism_warning.add_theme_color_override("font_color", Color(EXHAUSTED_COLOR if depleted else LOW_AMMO_COLOR, pulse))
	var amount := health.blur_amount() if not player.is_dead else 0.0
	_blur.visible = amount > 0.0
	if _blur.visible:
		if not Settings.get_value("accessibility", "reduce_flashing"):
			amount *= 0.85 + 0.15 * sin(Time.get_ticks_msec() / 900.0)  # Swimming in and out.
		(_blur.material as ShaderMaterial).set_shader_parameter("amount", amount)


## "E  Bandage: light bleed": what the use_item key would do now, or "" if nothing needs treating.
func treat_hint_text() -> String:
	if player == null or player.is_dead:
		return ""
	var pick := Consumables.quick_pick(player.inventory, player.health)
	if pick.has("item"):
		var where := " (%s)" % BodyHealth.PART_NAMES[pick.part].to_lower() if int(pick.part) >= 0 else ""
		return "%s  %s: %s%s" % [Settings.key_label("use_item"), (pick.item as ItemInstance).data.display_name,
			Consumables.problem_name(pick.problem), where]
	var reason := str(pick.get("reason", ""))
	return reason if reason.begins_with("Nothing in") else ""


func _set_metabolism(bar: ProgressBar, label: Label, title: String, value: float, maximum: float, color: Color, low: float) -> void:
	bar.max_value = maximum
	bar.value = value
	var shown := color
	if value <= 0.0:
		shown = EXHAUSTED_COLOR
	elif value <= low:
		shown = LOW_AMMO_COLOR
	(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = shown
	label.text = "%s  %d" % [title, ceili(snappedf(value, 0.1))]
	label.add_theme_color_override("font_color", shown if value <= low else Color(NORMAL_COLOR, 0.85))


func _update_blind() -> void:
	var amount := clampf(player.blind_fraction() * 1.5, 0.0, 1.0) if player.is_blind() else 0.0
	%BlindOverlay.visible = amount > 0.0
	# "Reduce flashing effects": fade to dark instead of a white flash.
	var reduced: bool = Settings.get_value("accessibility", "reduce_flashing")
	%BlindOverlay.color = Color(0.03, 0.03, 0.03, amount * 0.92) if reduced else Color(1.0, 1.0, 0.97, amount)


func _update_ammo() -> void:
	var weapon := player.weapon
	%BottomRight.visible = weapon.has_gun() or player.using_binoculars
	var gear: Array[String] = []
	if player.using_binoculars:
		gear.append("Binoculars in hand: can't shoot")
	else:
		var optic := VisionSystem.config.optic(weapon.optic)
		gear.append(optic.display_name if optic else "Iron sights")
	if player.flashlight_on:
		gear.append("flashlight on")
	%GearLine.text = "  ·  ".join(gear)
	if not weapon.has_gun():
		return
	var magazine := weapon.data.magazine_size
	%WeaponName.text = weapon.display_name().to_upper()
	%Rounds.text = str(weapon.rounds)
	var color := NORMAL_COLOR
	if weapon.rounds == 0:
		color = EMPTY_COLOR
	elif weapon.rounds * 3 <= magazine:
		color = LOW_AMMO_COLOR
	%Rounds.add_theme_color_override("font_color", color if not weapon.is_reloading else Color(color, 0.45))
	%MagSize.text = "/ %d" % magazine
	%Spare.text = "+%d" % weapon.spare_rounds if weapon.spare_rounds >= 0 else ""
	%Spare.add_theme_color_override("font_color", EMPTY_COLOR if weapon.spare_rounds == 0 else Color(NORMAL_COLOR, 0.8))
	%AmmoType.text = _weapon_state_text()
	%AmmoType.add_theme_color_override("font_color", EMPTY_COLOR if weapon.is_jammed or weapon.data.missing_part != "" \
		else Color(NORMAL_COLOR, 0.8))
	%ReloadBar.visible = weapon.is_reloading or weapon.is_clearing
	%ReloadBar.value = weapon.reload_progress()


## Under the round count: reloading, a jam, a missing part, or the loaded ammo and fire mode.
func _weapon_state_text() -> String:
	var weapon := player.weapon
	if weapon.is_clearing:
		return "CLEARING JAM"
	if weapon.is_jammed:
		return "JAMMED  ·  %s to clear" % Settings.key_label("reload")
	if weapon.data.missing_part != "":
		return "NO %s" % weapon.data.missing_part.to_upper()
	if weapon.is_reloading:
		return "RELOADING"
	return "%s  ·  %s" % [player.ammo_label(), "auto" if weapon.data.automatic else "semi"]


func _move_text() -> String:
	if player.is_dead:
		return "Dead"
	match player.move_state:
		Actor.Move.ROLL:
			return "Rolling"
		Actor.Move.COVER:
			return "Peeking" if player.is_peeking else "In cover"
	if player.is_crouching:
		return "Crouching"
	match player.move_state:
		Actor.Move.WALK:
			return "Walking"
		Actor.Move.SPRINT:
			return "Sprinting"
	return "Standing"
