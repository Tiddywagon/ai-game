class_name CollectionScreen
extends MenuScreen
## The Collectors Shelf and the collection (DESIGN.md §6.6): two tabs. SHELF is a lit 3D shelf in a
## SubViewport with the figures on display as their models (FigureModel); pick a slot (click or tap it,
## or the d-pad / arrow keys with the shelf focused), then a figure from the stash list to put there,
## MOVE it to another slot, or REMOVE it back to the stash. Zoom with the wheel, a pinch or the
## triggers; pan with a right / middle drag, a one-finger drag or the right stick. COLLECTION lists every
## figure by set: owned ones as their model with how many you own and whether one is displayed, missing
## ones as dark silhouettes (named once you've owned one: Figures.is_seen()), each set's progress and
## its bonus with whether it's on. Opened from the Collectors Shelf's panel in the hideout (SHELF) and
## from CHARACTER (COLLECTION).

const SHELF := 0
const COLLECTION := 1
## Metres between slots on a board, between boards, and the board's depth.
const SLOT_GAP := 0.5
const BOARD_GAP := 0.75
const BOARD_DEPTH := 0.5
## How near and far the camera goes (metres from the shelf), and the zoom step of a wheel notch.
const ZOOM_RANGE := Vector2(1.2, 9.0)
const ZOOM_STEP := 0.88
const MARKER := Color(0.32, 0.3, 0.26)
const MARKER_SELECTED := Color(1.0, 0.82, 0.35)
const MARKER_MOVING := Color(0.45, 0.85, 1.0)
const ON := Color(0.55, 0.9, 0.55)
const OFF := Color(0.6, 0.6, 0.58)

var tab := SHELF
## The slot picked on the shelf, and the slot a MOVE started from (-1: none).
var selected := 0
var moving := -1
## The camera's distance from the shelf (-1: not set yet, the whole shelf in view) and where it looks.
var zoom := -1.0
var pan := Vector2.ZERO

var _margin: MarginContainer
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _bonus_line: Label
var _view: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _markers: Array[MeshInstance3D] = []
var _side: VBoxContainer
var _status: Label
var _stash_list: VBoxContainer
var _collection: VBoxContainer
var _touches := {}
var _pinch := 0.0
var _dragging := false


## A screen opened on `which` (SHELF or COLLECTION).
static func create(which := SHELF) -> CollectionScreen:
	var screen := CollectionScreen.new()
	screen.tab = which
	return screen


func _ready() -> void:
	name = "CollectionScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Figures.update_seen()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.02, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + side, 56)
	_margin.add_theme_constant_override("margin_top", 40)
	_margin.add_theme_constant_override("margin_bottom", 32)
	add_child(_margin)
	InputHub.pad_to_safe_area(_margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	_margin.add_child(layout)
	layout.add_child(_header())
	_bonus_line = Label.new()
	_bonus_line.name = "Bonuses"
	_bonus_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_bonus_line)
	var shelf_page := _shelf_page()
	var collection_page := _collection_page()
	for page: Control in [shelf_page, collection_page]:
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout.add_child(page)
		_pages.append(page)
	show_tab(tab)


func _header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "COLLECTORS SHELF"
	title.theme_type_variation = &"HeadingLabel"
	header.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	header.add_child(gap)
	for entry: Array in [["ShelfTab", "SHELF", SHELF], ["CollectionTab", "COLLECTION", COLLECTION]]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(190, 48)
		var which: int = entry[2]
		button.pressed.connect(func() -> void: show_tab(which))
		header.add_child(button)
		_tabs.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 48)
	back.pressed.connect(close)
	header.add_child(back)
	return header


## Shows tab `which` (SHELF or COLLECTION), drawn afresh.
func show_tab(which: int) -> void:
	tab = which
	for index in _pages.size():
		_pages[index].visible = index == which
		_tabs[index].button_pressed = index == which
	refresh()
	if which == SHELF:
		_view.grab_focus.call_deferred()
	else:
		_tabs[COLLECTION].grab_focus.call_deferred()


## Draws everything again from the profile: the bonuses, the shelf and its side panel, the collection.
func refresh() -> void:
	var lines := Figures.active_lines()
	_bonus_line.text = "Set bonuses on: " + "  ·  ".join(lines) if not lines.is_empty() else "No set complete on the shelf: display every figure of a set for its bonus."
	_bonus_line.add_theme_color_override("font_color", ON if not lines.is_empty() else OFF)
	if tab == SHELF:
		_build_shelf()
		_fill_side()
	else:
		_fill_collection()


func _on_cancel() -> void:
	if moving >= 0:
		moving = -1
		_status.text = "Move cancelled."
		refresh()
		return
	close()


# --- The shelf ----------------------------------------------------------------------------------

func _shelf_page() -> HBoxContainer:
	var page := HBoxContainer.new()
	page.name = "ShelfPage"
	page.add_theme_constant_override("separation", 18)
	_view = SubViewportContainer.new()
	_view.name = "ShelfView"
	_view.stretch = true
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.focus_mode = Control.FOCUS_ALL
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	page.add_child(_view)
	_viewport = SubViewport.new()
	_viewport.name = "ShelfViewport"
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(1200, 800)
	_view.add_child(_viewport)
	_world = Node3D.new()
	_world.name = "ShelfWorld"
	_viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 40.0
	_viewport.add_child(_camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.05, 0.045)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.47, 0.42)
	environment.environment.ambient_light_energy = 0.45
	_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	_side = VBoxContainer.new()
	_side.name = "Side"
	_side.custom_minimum_size.x = 460
	_side.add_theme_constant_override("separation", 10)
	page.add_child(_side)
	return page


## How many slots a board holds at the shelf's level, and how many boards.
func _layout() -> Vector2i:
	var slots := Figures.slots()
	var columns := mini(FigureTable.columns(), maxi(slots, 1))
	return Vector2i(columns, maxi(ceili(float(slots) / columns), 1))


## Where slot `slot` stands (the middle of its place on the board's top), boards from the top down.
func slot_position(slot: int) -> Vector3:
	var shape := _layout()
	var column := slot % shape.x
	var board := slot / shape.x
	return Vector3((column - (shape.x - 1) / 2.0) * SLOT_GAP, ((shape.y - 1) / 2.0 - board) * BOARD_GAP, 0.0)


## Builds the boards, the lights over them, a marker on every slot and the figures on display.
func _build_shelf() -> void:
	for child in _world.get_children():
		_world.remove_child(child)
		child.queue_free()
	_markers.clear()
	var shape := _layout()
	var width := shape.x * SLOT_GAP + 0.3
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.25, 0.16)
	wood.roughness = 0.8
	var back := MeshInstance3D.new()
	back.name = "Back"
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(width + 0.1, shape.y * BOARD_GAP + 0.2, 0.04)
	back.mesh = back_mesh
	back.position = Vector3(0.0, BOARD_GAP / 2.0 - 0.1, -BOARD_DEPTH / 2.0 - 0.02)
	var back_material := wood.duplicate()
	back_material.albedo_color = Color(0.22, 0.16, 0.11)
	back.material_override = back_material
	_world.add_child(back)
	for board in shape.y:
		var y := slot_position(board * shape.x).y
		var plank := MeshInstance3D.new()
		plank.name = "Board_%d" % board
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, 0.05, BOARD_DEPTH)
		plank.mesh = mesh
		plank.material_override = wood
		plank.position = Vector3(0.0, y - 0.025, 0.0)
		_world.add_child(plank)
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp_%d" % board
		lamp.light_color = Color(1.0, 0.88, 0.7)
		lamp.light_energy = 1.6
		lamp.omni_range = width * 0.75
		lamp.position = Vector3(0.0, y + BOARD_GAP * 0.8, 0.9)
		_world.add_child(lamp)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.17
	disc.bottom_radius = 0.17
	disc.height = 0.006
	for slot in Figures.slots():
		var marker := MeshInstance3D.new()
		marker.name = "Slot_%d" % slot
		marker.mesh = disc
		marker.position = slot_position(slot) + Vector3(0.0, 0.003, 0.0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = material
		_world.add_child(marker)
		_markers.append(marker)
		var figure := Figures.placed(slot)
		if figure:
			var model := FigureModel.create(figure.data)
			model.position = slot_position(slot) + Vector3(0.0, 0.006, 0.0)
			_world.add_child(model)
	if zoom < 0.0:
		zoom = fit_zoom()
	_paint_markers()
	_place_camera()


## The distance that shows every board at once.
func fit_zoom() -> float:
	var shape := _layout()
	var aspect := float(_viewport.size.x) / maxf(float(_viewport.size.y), 1.0)
	var half_v := tan(deg_to_rad(_camera.fov / 2.0))
	var wide := (shape.x * SLOT_GAP / 2.0 + 0.4) / (half_v * aspect)
	var tall := (shape.y * BOARD_GAP / 2.0 + 0.5) / half_v
	return clampf(maxf(wide, tall), ZOOM_RANGE.x, ZOOM_RANGE.y)


func _paint_markers() -> void:
	for slot in _markers.size():
		var color := MARKER_MOVING if slot == moving else MARKER_SELECTED if slot == selected else MARKER
		(_markers[slot].material_override as StandardMaterial3D).albedo_color = color
		# The picked slot (and a move's start) shows as a bigger glowing ring around the figure's base.
		_markers[slot].scale = Vector3(1.4, 1.0, 1.4) if slot == selected or slot == moving else Vector3.ONE


func _place_camera() -> void:
	var shape := _layout()
	var half := Vector2(shape.x * SLOT_GAP / 2.0, shape.y * BOARD_GAP / 2.0)
	pan = pan.clamp(-half, half)
	zoom = clampf(zoom, ZOOM_RANGE.x, ZOOM_RANGE.y)
	_camera.position = Vector3(pan.x, pan.y + 0.35 + zoom * 0.12, zoom)
	_camera.look_at(Vector3(pan.x, pan.y + 0.2, 0.0))


## Zooms in (`steps` > 0) or out by wheel notches.
func zoom_by(steps: float) -> void:
	zoom *= pow(ZOOM_STEP, steps)
	_place_camera()


## Pans by `by` metres (x right, y up).
func pan_by(by: Vector2) -> void:
	pan += by
	_place_camera()


## The slot nearest `at` (a point in the shelf view, in its own pixels), or -1 if none is close.
func slot_at(at: Vector2) -> int:
	var scale := Vector2(_viewport.size) / _view.size if _view.size.x > 0.0 and _view.size.y > 0.0 else Vector2.ONE
	var point := at * scale
	var best := -1
	var best_distance := INF
	for slot in Figures.slots():
		var middle := slot_position(slot) + Vector3(0.0, 0.18, 0.0)
		if _camera.is_position_behind(middle):
			continue
		var distance := _camera.unproject_position(middle).distance_to(point)
		if distance < best_distance:
			best = slot
			best_distance = distance
	var reach := _camera.unproject_position(Vector3.ZERO).distance_to(_camera.unproject_position(Vector3(SLOT_GAP * 0.6, 0.0, 0.0)))
	return best if best_distance <= maxf(reach, 24.0) else -1


## Picks slot `slot`: during a MOVE it's where the figure goes, else the slot the panel is about.
func pick_slot(slot: int) -> void:
	if slot < 0 or slot >= Figures.slots():
		return
	var message := ""
	if moving >= 0:
		var from := moving
		moving = -1
		var reason := Figures.move(from, slot)
		SaveManager.save_game()
		message = reason if reason != "" else "Moved to slot %d." % (slot + 1)
	selected = slot
	refresh()
	if message != "":
		_status.text = message


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.0)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(-1.0)
		elif button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT and _touches.size() < 2:
			_view.grab_focus()
			pick_slot(slot_at(button.position))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		pan_by(Vector2(-motion.relative.x, motion.relative.y) * zoom * 0.0012)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch = _touch_spread()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			var spread := _touch_spread()
			if _pinch > 0.0 and spread > 0.0:
				zoom *= _pinch / spread
				_place_camera()
			_pinch = spread
		else:
			pan_by(Vector2(-drag.relative.x, drag.relative.y) * zoom * 0.0012)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom /= (event as InputEventMagnifyGesture).factor
		_place_camera()
	elif event is InputEventPanGesture:
		pan_by((event as InputEventPanGesture).delta * Vector2(1, -1) * 0.02)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		_step_selection(event)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		if moving >= 0:
			pick_slot(selected)
		else:
			_focus_side()
		accept_event()


## How far apart the first two fingers on the shelf are (0 with fewer).
func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])


## The d-pad or arrow keys step the picked slot along a board or to the board above or below.
func _step_selection(event: InputEvent) -> void:
	var columns := _layout().x
	var step := -1 if event.is_action_pressed("ui_left") else 1 if event.is_action_pressed("ui_right") else -columns if event.is_action_pressed("ui_up") else columns
	selected = clampi(selected + step, 0, maxi(Figures.slots() - 1, 0))
	var at := slot_position(selected)
	pan = Vector2(at.x, at.y) if zoom < 3.0 else pan
	_paint_markers()
	_place_camera()
	_fill_side()


## The triggers zoom and the right stick pans while the shelf has the focus.
func _process(delta: float) -> void:
	if tab != SHELF or not _view.has_focus():
		return
	var zoom_axis := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(zoom_axis) > 0.1:
		zoom_by(zoom_axis * delta * 6.0)
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.2:
		pan_by(stick * delta * zoom * 0.5)


func _focus_side() -> void:
	for child in _side.find_children("*", "Button", true, false):
		if not (child as Button).disabled:
			(child as Button).grab_focus()
			return


## The side panel: the slot picked, what can be done with it, and the figures in the stash.
func _fill_side() -> void:
	for child in _side.get_children():
		_side.remove_child(child)
		child.queue_free()
	if Figures.slots() == 0:
		_side_label("Build the Collectors Shelf in the hideout first: 12 display slots at level 1, 28 at level 2, %d at level 3." % FigureTable.figures().size())
		_status = _side_label("")
		return
	var figure := Figures.placed(selected)
	_side_label("SLOT %d OF %d  ·  %d ON DISPLAY" % [selected + 1, Figures.slots(), Figures.displayed_count()]).name = "SlotTitle"
	var about := _side_label("Empty: pick a figure below to put it here." if figure == null else "%s  ·  %s  ·  %s set%s" % [figure.data.display_name,
		Palette.RARITY_NAMES[clampi(figure.data.rarity, 0, 5)], FigureTable.set_title(FigureTable.set_of(figure.data)), "  ·  found in raid" if figure.fir else ""])
	about.name = "SlotInfo"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_side.add_child(row)
	row.add_child(_side_button("Move", "MOVE" if moving < 0 else "CANCEL MOVE", "" if figure != null or moving >= 0 else "No figure in this slot", func() -> String:
		if moving >= 0:
			moving = -1
			return "Move cancelled."
		moving = selected
		_view.grab_focus.call_deferred()
		return "Pick the slot to move %s to." % figure.data.display_name))
	row.add_child(_side_button("Remove", "REMOVE", Figures.remove_block_reason(selected) if figure != null else "No figure in this slot", func() -> String:
		var reason := Figures.remove(selected)
		return reason if reason != "" else "Back in the stash."))
	_status = _side_label("Pick the slot to move it to (Esc / B cancels)." if moving >= 0 else "")
	_status.name = "Status"
	_side.add_child(HSeparator.new())
	_side_label("FIGURES IN YOUR STASH").theme_type_variation = &"HeadingLabel"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.add_child(scroll)
	_stash_list = VBoxContainer.new()
	_stash_list.name = "StashFigures"
	_stash_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stash_list)
	var shown := {}
	for item in Figures.in_stash():
		if shown.has(item.data.id):
			continue
		shown[item.data.id] = true
		var target := selected if figure == null else Figures.free_slot()
		var blocked := Figures.place_block_reason(item, target) if target >= 0 else "The shelf is full"
		var count := GameState.stash.all_items().filter(func(each: ItemInstance) -> bool: return each.data.id == item.data.id).size()
		var button := _side_button("Place_" + item.data.id, "%s%s  (%s)" % [item.data.display_name, "  ×%d" % count if count > 1 else "",
			Palette.RARITY_NAMES[clampi(item.data.rarity, 0, 5)]], blocked, func() -> String:
				var reason := Figures.place(item, target)
				if reason == "":
					selected = target
				return reason if reason != "" else "%s is on the shelf." % item.data.display_name)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_color_override("font_color", Palette.rarity_color(item.data.rarity))
		_stash_list.add_child(button)
	if not shown.is_empty() and figure != null and Figures.free_slot() < 0:
		var full := _side_label("The shelf is full: remove a figure first, or build the next level for more slots.")
		full.name = "FullNote"
		_side.move_child(full, _side.get_child_count() - 2)
	if shown.is_empty():
		_stash_list.add_child(_side_label("No figures in the stash. They turn up on bodies, in containers, on bosses and at points of interest."))
	_side_label("Click or tap a slot (arrows / d-pad with the shelf picked). Wheel, pinch or triggers zoom; right drag, a finger or the right stick pans.").add_theme_color_override("font_color", OFF)


func _side_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(label)
	return label


## A button named `id` that runs `action` (returns a message, or why it failed: a reason the shelf
## gave), saves and draws the screen again. Disabled with the reason as its tooltip when `blocked`
## isn't "".
func _side_button(id: String, text: String, blocked: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size = Vector2(150, 44)
	button.disabled = blocked != ""
	button.tooltip_text = blocked
	button.pressed.connect(func() -> void:
		var message: String = action.call()
		SaveManager.save_game()
		refresh()
		_status.text = message
		if moving < 0:
			_view.grab_focus.call_deferred())
	return button


# --- The collection -----------------------------------------------------------------------------

func _collection_page() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "CollectionPage"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_collection = VBoxContainer.new()
	_collection.name = "Sets"
	_collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collection.add_theme_constant_override("separation", 10)
	scroll.add_child(_collection)
	return scroll


## "Raiders 4 / 6 · 3 displayed" for set `id`.
static func progress_text(id: String) -> String:
	return "%s  %d / %d  ·  %d displayed" % [FigureTable.set_title(id), Figures.owned_in(id), FigureTable.in_set(id).size(), Figures.displayed_in(id)]


func _fill_collection() -> void:
	for child in _collection.get_children():
		_collection.remove_child(child)
		child.queue_free()
	var counts := Figures.owned_counts()
	for entry in FigureTable.sets():
		var id := str(entry.id)
		var box := VBoxContainer.new()
		box.name = "Set_" + id
		_collection.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var title := Label.new()
		title.name = "Progress"
		title.text = progress_text(id)
		title.theme_type_variation = &"HeadingLabel"
		head.add_child(title)
		var bonus := Label.new()
		bonus.name = "Bonus"
		var on := Figures.set_complete(id)
		bonus.text = "    %s  ·  %s" % [FigureTable.bonus_text(entry), "ON" if on else "on while all %d are displayed" % FigureTable.in_set(id).size()]
		bonus.add_theme_color_override("font_color", ON if on else OFF)
		head.add_child(bonus)
		var about := Label.new()
		about.text = "%s  %s." % [entry.get("about", ""), entry.get("found", "")]
		about.add_theme_color_override("font_color", OFF)
		box.add_child(about)
		var cards := HFlowContainer.new()
		cards.add_theme_constant_override("h_separation", 10)
		cards.add_theme_constant_override("v_separation", 10)
		box.add_child(cards)
		for data in FigureTable.in_set(id):
			cards.add_child(_card(data, int(counts.get(data.id, 0))))
		_collection.add_child(HSeparator.new())


## A figure's card: its model lit in a small view (a dark silhouette if you own none), its name (hidden
## until you've owned one) and how many you own, and whether one is displayed.
func _card(data: ItemData, owned: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Card_" + data.id
	card.custom_minimum_size = Vector2(176, 0)
	var rows := VBoxContainer.new()
	card.add_child(rows)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(176, 150)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(view)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(176, 150)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.1, 0.105, 0.115) if owned == 0 else Color(0.05, 0.045, 0.04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.52, 0.48)
	environment.environment.ambient_light_energy = 0.5
	viewport.add_child(environment)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	view.add_child(viewport)
	var model := FigureModel.create(data, owned == 0)
	model.name = "Silhouette" if owned == 0 else "Model"
	model.rotation_degrees.y = -20.0
	viewport.add_child(model)
	var camera := Camera3D.new()
	var tall := FigureModel.height(data.stats.get("model"))
	camera.position = Vector3(0.0, tall * 0.62, 0.95)
	camera.fov = 32.0
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0.0, tall * 0.45, 0.0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30.0, -30.0, 0.0)
	light.light_energy = 1.2 if owned > 0 else 0.0
	viewport.add_child(light)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.custom_minimum_size.x = 176
	name_label.text = data.display_name if Figures.is_seen(data.id) else "???"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Palette.rarity_color(data.rarity) if owned > 0 else OFF)
	rows.add_child(name_label)
	var state := Label.new()
	state.name = "State"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.custom_minimum_size.x = 176
	state.text = "Missing" if owned == 0 else "Owned ×%d%s" % [owned, " · shown" if Figures.is_displayed(data.id) else ""]
	state.add_theme_color_override("font_color", OFF if owned == 0 else ON if Figures.is_displayed(data.id) else Color.WHITE)
	rows.add_child(state)
	return card
