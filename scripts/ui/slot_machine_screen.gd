class_name SlotMachineScreen
extends MenuScreen
## The Drip slot machine (DESIGN.md §6.7, §16.1), opened from the Slot Machine's panel in the hideout. Three
## reels behind a ring of lights; SPIN (100 Drip), SPIN ×10 (900) and FREE SPIN (the Oddities set's spin
## a day); the pity counter ("Epic or better within 23 spins"), the season in the machine and the time it
## has left, the Drip you have, and ODDS (every rarity's chance, the Drip a duplicate pays back, the wear
## bands). A spin is paid, rolled and saved first (Cosmetics.spin()); then the reels spin and stop one
## after another, ticking, with a thunk per reel and a sting by rarity (SlotSounds), the lights chasing and
## then flashing in the rarity's colour. On some results below Ultra Rare the reels tease: two land on a
## high symbol and the third slides just past it (looks only: the result was already decided). The
## result card shows the skin on a turning model, its rarity, what it fits, its wear and whether it was
## new or a duplicate (and the Drip paid back). Ten spins show the best on the reels and all ten as a row
## of cards. SKIP (or Esc / B while the reels turn) jumps to the end.

## Seconds until each reel stops, the extra a teasing third reel takes, and how long a reel slows down.
const STOP_AT := [1.1, 1.6, 2.1]
const TEASE_EXTRA := 1.1
const SLOW_DOWN := 0.55
const TEASE_SLOW_DOWN := 1.6
## Symbols on a reel's strip, and how far into it a reel stops (more for later reels).
const STRIP := 40
const STOP_INDEX := [22, 26, 30]
## The ten-spin row's cards appear this far apart.
const ROW_STEP := 0.12
const DIM := Color(0.6, 0.6, 0.58)

## The last spin's results, as Cosmetics.spin() gave them (or the saved ones when the screen opens).
var results: Array = []
## True while the reels turn (and the ten-spin row is still coming in).
var animating := false
var _time := 0.0
var _plans: Array[Dictionary] = []
var _stopped := 0
var _shown := 0
var _shown_rarity := 0
var _reels: Array[Control] = []
var _ring: Control
var _drip: Label
var _season: Label
var _pity: Label
var _status: Label
var _spin: Button
var _spin_ten: Button
var _free: Button
var _skip: Button
var _odds_button: Button
var _odds: PanelContainer
var _card: VBoxContainer
var _card_view: SubViewport
var _row: HBoxContainer
var _player: AudioStreamPlayer
var _ticker: AudioStreamPlayer
var _last_tick_ms := 0


static func create() -> SlotMachineScreen:
	return SlotMachineScreen.new()


func _ready() -> void:
	name = "SlotMachineScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.035, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	InputHub.pad_to_safe_area(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	layout.add_child(_header())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	columns.add_child(_machine())
	columns.add_child(_result_card())
	_player = AudioStreamPlayer.new()
	_player.bus = &"UI"
	add_child(_player)
	_ticker = AudioStreamPlayer.new()
	_ticker.bus = &"UI"
	_ticker.volume_db = -8.0
	add_child(_ticker)
	results = Cosmetics.state().get("last", []).duplicate(true)
	_set_reels_to(_best(results) if not results.is_empty() else {}, false)
	_show_results(false)
	refresh()
	_spin.grab_focus.call_deferred()


func _header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	var title := Label.new()
	title.text = "SLOT MACHINE"
	title.theme_type_variation = &"HeadingLabel"
	header.add_child(title)
	_season = Label.new()
	_season.name = "Season"
	_season.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4))
	header.add_child(_season)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_drip = Label.new()
	_drip.name = "Drip"
	_drip.add_theme_font_size_override("font_size", 22)
	_drip.add_theme_color_override("font_color", Player.TRICK_COLOR)
	header.add_child(_drip)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(150, 46)
	back.pressed.connect(close)
	header.add_child(back)
	return header


func _machine() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Machine"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	var frame := Control.new()
	frame.name = "Frame"
	frame.custom_minimum_size = Vector2(640, 430)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(frame)
	_ring = LightRing.new()
	_ring.name = "Lights"
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(_ring)
	var reels := HBoxContainer.new()
	reels.name = "Reels"
	reels.add_theme_constant_override("separation", 14)
	reels.alignment = BoxContainer.ALIGNMENT_CENTER
	reels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		reels.set("offset_" + side, 46.0 if side in ["left", "top"] else -46.0)
	frame.add_child(reels)
	for i in 3:
		var reel := ReelView.new()
		reel.name = "Reel%d" % (i + 1)
		reel.custom_minimum_size = Vector2(190, 0)
		reel.clip_contents = true
		reel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		reels.add_child(reel)
		_reels.append(reel)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_spin = _button("SpinButton", "SPIN  ·  %s" % UiFormat.drip(SkinTable.price(1)), func() -> void: spin(1))
	_spin_ten = _button("SpinTenButton", "SPIN ×10  ·  %s" % UiFormat.drip(SkinTable.price(10)), func() -> void: spin(10))
	_free = _button("FreeSpinButton", "FREE SPIN", func() -> void: spin(1, true))
	_skip = _button("SkipButton", "SKIP", skip)
	_odds_button = _button("OddsButton", "ODDS", func() -> void: _odds.visible = not _odds.visible)
	for button: Button in [_spin, _spin_ten, _free, _skip, _odds_button]:
		buttons.add_child(button)
	_pity = Label.new()
	_pity.name = "Pity"
	_pity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_pity)
	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", DIM)
	box.add_child(_status)
	_row = HBoxContainer.new()
	_row.name = "TenRow"
	_row.add_theme_constant_override("separation", 8)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_row)
	_odds = _odds_panel()
	_odds.visible = false
	box.add_child(_odds)
	return box


func _button(id: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size = Vector2(150, 52)
	button.pressed.connect(action)
	return button


## ODDS: every rarity's chance and duplicate Drip, the prices, the pity rule, the wear bands, the season.
func _odds_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "OddsPanel"
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	panel.add_child(grid)
	for text in ["RARITY", "CHANCE", "DUPLICATE PAYS"]:
		grid.add_child(_cell(text, DIM))
	var odds := SkinTable.odds()
	for index in 6:
		grid.add_child(_cell(Palette.RARITY_NAMES[index], Palette.rarity_color(index)))
		grid.add_child(_cell("%s%%" % String.num(odds[index] * 100.0, 1), Color.WHITE))
		grid.add_child(_cell(UiFormat.drip(SkinTable.duplicate_drip(index)), Color.WHITE))
	for band in SkinTable.wear_bands():
		grid.add_child(_cell(str(band.name), DIM))
		grid.add_child(_cell("%s%%" % String.num(float(band.chance) * 100.0, 0), Color.WHITE))
		grid.add_child(_cell("wear %.2f-%.2f" % [band.min, band.max], DIM))
	grid.add_child(_cell("Pity", DIM))
	grid.add_child(_cell("%d spins" % SkinTable.pity_spins(), Color.WHITE))
	grid.add_child(_cell("%s or better guaranteed" % Palette.RARITY_NAMES[SkinTable.pity_rarity()], DIM))
	return panel


func _cell(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label


func _result_card() -> VBoxContainer:
	_card = VBoxContainer.new()
	_card.name = "ResultCard"
	_card.custom_minimum_size = Vector2(380, 0)
	_card.add_theme_constant_override("separation", 6)
	var view := SubViewportContainer.new()
	view.name = "ResultView"
	view.stretch = true
	view.custom_minimum_size = Vector2(380, 300)
	_card.add_child(view)
	_card_view = SubViewport.new()
	_card_view.own_world_3d = true
	_card_view.size = Vector2i(380, 300)
	view.add_child(_card_view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.055, 0.07)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.58, 0.55)
	environment.environment.ambient_light_energy = 0.6
	_card_view.add_child(environment)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0, 0.25, 1.6)
	camera.fov = 40.0
	_card_view.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.3
	_card_view.add_child(light)
	for id in ["ResultName", "ResultRarity", "ResultFits", "ResultWear", "ResultState"]:
		var label := Label.new()
		label.name = id
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 380
		if id == "ResultName":
			label.add_theme_font_size_override("font_size", 26)
		_card.add_child(label)
	return _card


# --- State --------------------------------------------------------------------------------------

## Draws the labels and buttons again from the profile.
func refresh() -> void:
	_drip.text = UiFormat.drip(GameState.drip)
	var season := SkinTable.season_at(HideoutWork.now())
	var left := SkinTable.season_ends(HideoutWork.now()) - HideoutWork.now()
	_season.text = "Season: %s  ·  %d d %d h left" % [SkinTable.collection(season).get("name", "—"), int(left / 86400.0), int(fmod(left, 86400.0) / 3600.0)]
	_pity.text = "%s or better within %d spin%s" % [Palette.RARITY_NAMES[SkinTable.pity_rarity()], Cosmetics.pity_left(), "" if Cosmetics.pity_left() == 1 else "s"]
	var block := Cosmetics.spin_block_reason(1)
	_spin.disabled = animating or block != ""
	_spin.tooltip_text = block
	_spin_ten.disabled = animating or Cosmetics.spin_block_reason(10) != ""
	_spin_ten.tooltip_text = Cosmetics.spin_block_reason(10)
	_free.visible = Figures.free_spins_a_day() > 0
	_free.disabled = animating or Cosmetics.spin_block_reason(1, true) != ""
	_free.text = "FREE SPIN  ·  %d left today" % Figures.free_spins_left()
	_skip.visible = animating
	if not animating:
		_status.text = block if block != "" else "Skins only change how things look."


## Spins `count` times (`free`: today's free spin): paid, rolled and saved at once, then shown.
func spin(count: int, free := false) -> void:
	if animating:
		return
	var reason := Cosmetics.spin_block_reason(count, free)
	if reason != "":
		_status.text = reason
		return
	results = Cosmetics.spin(count, free)
	var best := _best(results)
	_plan(best)
	animating = true
	_time = 0.0
	_stopped = 0
	_shown = 0
	_clear_row()
	_clear_card()
	_status.text = "Spinning…"
	_play("pull")
	(_ring as LightRing).mode = LightRing.CHASE
	refresh()
	_skip.grab_focus.call_deferred()


## Jumps to the end of the spin.
func skip() -> void:
	if not animating:
		return
	_time = _end_time() + 10.0
	_process(0.0)


func _on_cancel() -> void:
	if animating:
		skip()
		return
	close()


## The best of `list` (the rarest, then the first): what the reels show for ten spins.
static func _best(list: Array) -> Dictionary:
	var best: Dictionary = {}
	for result: Dictionary in list:
		if best.is_empty() or int(result.rarity) > int(best.rarity):
			best = result
	return best


## The reels' moves for `result`: each strip of symbols (seeded by the result, so it's the same each
## time), where it stops, when, and how long it slows down. A tease puts a high symbol on the first two
## and just before the stop on the third, which crawls in.
func _plan(result: Dictionary) -> void:
	_plans.clear()
	var rarity := int(result.get("rarity", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = str(result.get("skin", "")).hash() + int(float(result.get("wear", 0.0)) * 10000.0)
	var tease := bool(result.get("near_miss", false))
	var high := 5 if rng.randf() < 0.35 else 4
	for i in 3:
		var strip: Array[int] = []
		for n in STRIP:
			var roll := rng.randf()
			strip.append(0 if roll < 0.4 else 1 if roll < 0.65 else 2 if roll < 0.82 else 3 if roll < 0.92 else 4 if roll < 0.97 else 5)
		var stop: int = STOP_INDEX[i]
		strip[stop] = high if tease and i < 2 else rarity
		if tease and i == 2:
			strip[stop - 1] = high
			strip[stop + 1] = high
		var at: float = STOP_AT[i] + (TEASE_EXTRA if tease and i == 2 else 0.0)
		var slow := TEASE_SLOW_DOWN if tease and i == 2 else SLOW_DOWN
		_plans.append({"strip": strip, "stop": float(stop), "at": at, "slow": slow, "speed": float(stop) / (at - slow / 2.0)})
		(_reels[i] as ReelView).strip = strip
	_shown_rarity = rarity


## The reels at rest on `result` (none: three blanks), without the animation.
func _set_reels_to(result: Dictionary, sound: bool) -> void:
	if result.is_empty():
		for reel: ReelView in _reels:
			reel.strip = [0, 1, 2]
			reel.reel_at = 1.0
			reel.queue_redraw()
		return
	_plan(result)
	for i in 3:
		(_reels[i] as ReelView).reel_at = float(_plans[i].stop)
		_reels[i].queue_redraw()
	(_ring as LightRing).flash(Palette.rarity_color(int(result.rarity)), int(result.rarity))
	if sound:
		_play("sting_%d" % int(result.rarity))


func _end_time() -> float:
	var last := 0.0
	for plan in _plans:
		last = maxf(last, float(plan.at))
	return last + (results.size() * ROW_STEP if results.size() > 1 else 0.0)


## Where reel `plan` is at `t` seconds: steady, then slowing evenly to a stop on its symbol.
static func reel_position(plan: Dictionary, t: float) -> float:
	var at := float(plan.at)
	var slow := float(plan.slow)
	var speed := float(plan.speed)
	if t >= at:
		return float(plan.stop)
	if t <= at - slow:
		return speed * t
	var into := t - (at - slow)
	return speed * (at - slow) + speed * into - speed * into * into / (2.0 * slow)


func _process(delta: float) -> void:
	if not animating:
		return
	_time += delta
	var ticked := false
	for i in 3:
		var reel := _reels[i] as ReelView
		var before := floori(reel.reel_at)
		reel.reel_at = reel_position(_plans[i], _time)
		reel.queue_redraw()
		if floori(reel.reel_at) != before:
			ticked = true
		if i == _stopped and _time >= float(_plans[i].at):
			_stopped += 1
			_play("stop")
			if i == 1 and bool(_best(results).get("near_miss", false)):
				_play("tease")
				(_ring as LightRing).flash(Palette.rarity_color(4), 1)
	if ticked and Time.get_ticks_msec() - _last_tick_ms > 35 and _stopped < 3:
		_last_tick_ms = Time.get_ticks_msec()
		_ticker.stream = SlotSounds.clip("tick")
		_ticker.play()
	if _stopped == 3:
		var reels_done := float(_plans[2].at)
		var due := 1 if results.size() == 1 else clampi(int((_time - reels_done) / ROW_STEP) + 1, 0, results.size())
		if _shown == 0:
			(_ring as LightRing).flash(Palette.rarity_color(_shown_rarity), _shown_rarity)
			_play("sting_%d" % _shown_rarity)
			_fill_card(_best(results))
		while _shown < due:
			if results.size() > 1:
				_row.add_child(_tile(results[_shown]))
			_shown += 1
		if _shown >= results.size():
			animating = false
			_status.text = _summary()
			refresh()
			_spin.grab_focus.call_deferred()


## The result card and the ten-spin row for `results`, at once (`animate` false: as the screen opens).
func _show_results(_animate: bool) -> void:
	_clear_row()
	if results.is_empty():
		_clear_card()
		return
	_fill_card(_best(results))
	if results.size() > 1:
		for result: Dictionary in results:
			_row.add_child(_tile(result))
	_status.text = _summary()


## "2 new, 8 duplicates (+180 Drip back)".
func _summary() -> String:
	var fresh := results.filter(func(result: Dictionary) -> bool: return not result.get("duplicate", false)).size()
	var back := 0
	for result: Dictionary in results:
		back += int(result.get("drip", 0))
	return "%d new%s" % [fresh, ", %d duplicate%s (+%s back)" % [results.size() - fresh, "" if results.size() - fresh == 1 else "s", UiFormat.drip(back)] if fresh < results.size() else ""]


func _clear_row() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()


func _clear_card() -> void:
	for child in _card_view.get_children():
		if child is SkinModel:
			_card_view.remove_child(child)
			child.queue_free()
	for id in ["ResultName", "ResultRarity", "ResultFits", "ResultWear", "ResultState"]:
		(_card.get_node(id) as Label).text = ""


## The card for `result`: the skin on its turning model, name, rarity, kind, what it fits, wear, new or
## duplicate.
func _fill_card(result: Dictionary) -> void:
	_clear_card()
	var skin := SkinTable.find(str(result.skin))
	var model := SkinModel.for_skin(str(result.skin), float(result.wear))
	_card_view.add_child(model)
	var camera := _card_view.get_node("Camera") as Camera3D
	var far := 2.7 if model.kind == "outfit" else 1.5
	camera.look_at_from_position(Vector3(0, far * 0.18, far), Vector3(0, 0.05, 0))
	var color := Palette.rarity_color(SkinTable.rarity(skin))
	var name_label := _card.get_node("ResultName") as Label
	name_label.text = str(skin.get("name", "?"))
	name_label.add_theme_color_override("font_color", color)
	var rarity := _card.get_node("ResultRarity") as Label
	rarity.text = "%s %s%s%s" % [SkinTable.rarity_name(skin), SkinTable.KIND_TITLES.get(skin.get("kind"), ""), "  ·  BOUND" if SkinTable.is_bound(skin) else "",
		"  ·  pity" if result.get("pity", false) else ""]
	rarity.add_theme_color_override("font_color", color)
	(_card.get_node("ResultFits") as Label).text = "Fits: %s  ·  %s" % [SkinTable.fits_text(skin), SkinTable.collection(str(skin.get("collection", ""))).get("name", "")]
	(_card.get_node("ResultWear") as Label).text = SkinTable.wear_text(float(result.wear))
	var state := _card.get_node("ResultState") as Label
	if result.get("duplicate", false):
		state.text = "DUPLICATE: +%s back%s" % [UiFormat.drip(int(result.get("drip", 0))), "  ·  better wear: yours took it" if result.get("better", false) else ""]
		state.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4))
	else:
		state.text = "NEW: in your collection"
		state.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))


## One card of the ten-spin row: the skin's swatch, its name in the rarity's colour, NEW or the Drip back.
func _tile(result: Dictionary) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.name = "Tile%d" % _row.get_child_count()
	var skin := SkinTable.find(str(result.skin))
	tile.add_child(SkinSwatch.create(str(result.skin), float(result.wear), false, Vector2(118, 70)))
	var label := Label.new()
	label.text = "%s\n%s" % [skin.get("name", "?"), "NEW" if not result.get("duplicate", false) else "+%d Drip" % int(result.get("drip", 0))]
	label.custom_minimum_size.x = 118
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Palette.rarity_color(SkinTable.rarity(skin)))
	tile.add_child(label)
	return tile


func _play(clip: String) -> void:
	_player.stream = SlotSounds.clip(clip)
	_player.play()


func _physics_process(delta: float) -> void:
	for child in _card_view.get_children():
		if child is SkinModel:
			(child as Node3D).rotate_y(delta * 0.9)


## One reel: its strip of rarity symbols scrolling down past the line in the middle.
class ReelView extends Control:
	var strip: Array[int] = [0, 1, 2]
	## The symbol index on the line (fractional while turning).
	var reel_at := 1.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.92, 0.9, 0.84))
		var row := size.y / 3.0
		var centre := size.y / 2.0
		var font := get_theme_default_font()
		for offset in range(-2, 3):
			var index := floori(reel_at) + offset
			if index < 0 or index >= strip.size():
				continue
			var y := centre + (reel_at - index) * row
			var rarity := strip[index]
			var color := Palette.rarity_color(rarity)
			var at := Vector2(size.x / 2.0, y)
			var r := row * 0.34
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.9, -r * 0.2), at + Vector2(0, r), at + Vector2(-r * 0.9, -r * 0.2)]), color)
			draw_polyline(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.9, -r * 0.2), at + Vector2(0, r), at + Vector2(-r * 0.9, -r * 0.2), at + Vector2(0, -r)]),
				color.darkened(0.5), 2.0)
			draw_string(font, at + Vector2(-size.x / 2.0, r + 18.0), Palette.RARITY_SHORT[rarity], HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(0.15, 0.14, 0.13))
		draw_rect(Rect2(0, 0, size.x, row * 0.55), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(0, size.y - row * 0.55, size.x, row * 0.55), Color(0, 0, 0, 0.35))
		draw_line(Vector2(0, centre - row / 2.0), Vector2(size.x, centre - row / 2.0), Color(0.8, 0.15, 0.1, 0.6), 2.0)
		draw_line(Vector2(0, centre + row / 2.0), Vector2(size.x, centre + row / 2.0), Color(0.8, 0.15, 0.1, 0.6), 2.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.18, 0.16), false, 4.0)


## The ring of lights round the reels: idle, chasing while they spin, flashing in a rarity's colour.
class LightRing extends Control:
	const IDLE := 0
	const CHASE := 1
	const FLASH := 2
	const BULBS := 30
	var mode := IDLE
	var color := Color(0.95, 0.75, 0.4)
	var flashes := 0
	var _time := 0.0

	## Flashes in `with` (more for a higher `rarity`), then glows in it.
	func flash(with: Color, rarity: int) -> void:
		color = with
		flashes = 2 + rarity * 2
		mode = FLASH
		_time = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.1, 0.14), true)
		draw_rect(Rect2(Vector2(8, 8), size - Vector2(16, 16)), Color(0.45, 0.3, 0.12), false, 3.0)
		for i in BULBS:
			var at := _along(float(i) / BULBS)
			var on := 0.35 + 0.15 * sin(_time * 2.0 + i * 0.4)
			var lit := Color(1.0, 0.85, 0.5)
			if mode == CHASE:
				var head := fmod(_time * 22.0, BULBS)
				var behind := fposmod(head - i, BULBS)
				on = 1.0 if behind < 1.0 else maxf(0.25, 1.0 - behind * 0.18)
			elif mode == FLASH:
				lit = color
				var blink := int(_time * 8.0)
				on = 1.0 if blink >= flashes * 2 or blink % 2 == 0 else 0.15
			draw_circle(at, 8.0, Color(lit.darkened(0.7), 1.0))
			if on > 0.8:
				draw_circle(at, 14.0, Color(lit, 0.22))
			draw_circle(at, 6.0, Color(lit.lightened(0.25 if on > 0.8 else 0.0), on))

	## A point `share` (0-1) of the way round the frame, inset from its edge.
	func _along(share: float) -> Vector2:
		var inset := 22.0
		var w := size.x - inset * 2.0
		var h := size.y - inset * 2.0
		var d := share * (w + h) * 2.0
		if d < w:
			return Vector2(inset + d, inset)
		d -= w
		if d < h:
			return Vector2(inset + w, inset + d)
		d -= h
		if d < w:
			return Vector2(inset + w - d, inset + h)
		return Vector2(inset, inset + h - (d - w))
