class_name StashFilterBar
extends VBoxContainer
## The stash's search, filters and sort (DESIGN.md §8), as one row that wraps when it's narrow: a name
## search box (live as you type), a category picker (All, then ItemData.CATEGORY_TITLES in
## ItemData.CATEGORY_ORDER), a rarity picker (All, then each rarity in its colour), FIR only, CLEAR (the
## filters), and a sort picker (Type, Rarity, Value, Name, Size) with SORT. Under it a line says how
## many items match, or what SORT did.
##
## Filtering dims what doesn't match, never hides it, so every item keeps its cell and drag and drop
## works as ever: the bar gives each view it's attach()ed to one filter, matches(), and redraws them when
## it changes. An item matches when it passes every filter set; a container also matches when anything
## inside it does (at any depth), so you can find the backpack holding it. SORT repacks `grid`
## (InventoryGrid.sort(); not while an item is being dragged) and saves the game when that's the stash.
##
## Controller and touch: the inventory's grid cursor lands on every control and works it (activate());
## menus reach them by focus, and A on the focused search box starts typing; tapping the search box
## brings up the on-screen keyboard (Godot does, on focus). When typing stops (Enter, or Esc where the box
## takes it) the bar says so (search_done) and the screen decides where the focus goes. A click or tap
## anywhere off the bar's focused control lets go of it; Esc or B leaves the bar first (the screen asks
## clear_focus()).
##
## Use: put one above the stash view, set `grid`, attach() the view (and the windows of containers in the
## stash; detach() them when they leave it).

## The filter changed (search, category, rarity or FIR only); the views are already redrawn.
signal filter_changed
## SORT ran: `ok` is false if it didn't (no room, or an item was being dragged); `text` says what
## happened (the bar's line shows it too).
signal sorted(ok: bool, text: String)
## Typing in the search box stopped while it still has the focus: `submitted` with Enter (or the on-screen
## keyboard's done key), else Esc. The screen decides where the focus goes.
signal search_done(submitted: bool)

## How long a SORT message stays before the match count comes back (seconds).
const MESSAGE_TIME := 4.0
## Height of every control (fingers too).
const CONTROL_HEIGHT := 40.0
## The rarity swatches in the rarity picker (pixels).
const SWATCH := 14

## The grid SORT repacks and the line counts (the stash).
var grid: InventoryGrid:
	set(value):
		if grid and grid.changed.is_connected(_update_status):
			grid.changed.disconnect(_update_status)
		grid = value
		if grid:
			grid.changed.connect(_update_status)
		_update_status()
## The search box's text: matched against item names (name_matches()).
var search := "":
	set(value):
		search = value
		_query = value.strip_edges().to_lower()
		_query_compact = _compact(_query)
		if _search_box and _search_box.text != value:
			_search_box.text = value
		_on_filter_changed()
## An ItemData.Category, or -1 for all.
var category := -1:
	set(value):
		category = value
		_select_by_metadata(_category_picker, value)
		_on_filter_changed()
## An ItemData.Rarity, or -1 for all.
var rarity := -1:
	set(value):
		rarity = value
		_select_by_metadata(_rarity_picker, value)
		_color_rarity_picker()
		_on_filter_changed()
## Only items found in raid.
var fir_only := false:
	set(value):
		fir_only = value
		if _fir_toggle:
			_fir_toggle.set_pressed_no_signal(value)
		_on_filter_changed()
## The order SORT uses (InventoryGrid.SortMode).
var sort_mode: int = InventoryGrid.SortMode.TYPE:
	set(value):
		sort_mode = value
		_select_by_metadata(_sort_picker, value)

## Item id -> its compact name and compact id: letters and digits only (name_matches()).
static var _compact_names := {}

var _views: Array[Control] = []
var _query := ""
var _query_compact := ""
var _search_box: LineEdit
var _category_picker: OptionButton
var _rarity_picker: OptionButton
var _fir_toggle: CheckButton
var _clear_button: Button
var _sort_picker: OptionButton
var _sort_button: Button
var _status: Label
var _message := ""
var _message_left := 0.0
## Enter ended the typing (search_done).
var _submitted := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var row := HFlowContainer.new()
	row.name = "Controls"
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	add_child(row)
	_search_box = LineEdit.new()
	_search_box.name = "Search"
	_search_box.placeholder_text = "Search by name"
	_search_box.tooltip_text = "Part of a name, any case (\"ak74\" finds the AK-74N)"
	_search_box.clear_button_enabled = true
	_search_box.custom_minimum_size = Vector2(170, CONTROL_HEIGHT)
	_search_box.text = search
	_search_box.text_changed.connect(func(text: String) -> void: search = text)
	_search_box.text_submitted.connect(func(_text: String) -> void: _submitted = true)
	_search_box.editing_toggled.connect(_on_editing_toggled)
	_search_box.gui_input.connect(_on_search_input)
	row.add_child(_search_box)
	_category_picker = _picker("Category", "Show one category; the rest are dimmed")
	_category_picker.add_item("All categories")
	_category_picker.set_item_metadata(0, -1)
	for each in ItemData.CATEGORY_ORDER:
		_category_picker.add_item(ItemData.CATEGORY_TITLES[each])
		_category_picker.set_item_metadata(_category_picker.item_count - 1, int(each))
	_category_picker.item_selected.connect(func(index: int) -> void: category = int(_category_picker.get_item_metadata(index)))
	row.add_child(_category_picker)
	_rarity_picker = _picker("Rarity", "Show one rarity; the rest are dimmed")
	_rarity_picker.add_item("All rarities")
	_rarity_picker.set_item_metadata(0, -1)
	for each in Palette.RARITY_NAMES.size():
		_rarity_picker.add_icon_item(_swatch(Palette.rarity_color(each)), Palette.RARITY_NAMES[each])
		_rarity_picker.set_item_metadata(_rarity_picker.item_count - 1, each)
	_rarity_picker.item_selected.connect(func(index: int) -> void: rarity = int(_rarity_picker.get_item_metadata(index)))
	row.add_child(_rarity_picker)
	_fir_toggle = CheckButton.new()
	_fir_toggle.name = "FirOnly"
	_fir_toggle.text = "FIR only"
	_fir_toggle.tooltip_text = "Show only items found in raid; the rest are dimmed"
	_fir_toggle.custom_minimum_size.y = CONTROL_HEIGHT
	_fir_toggle.toggled.connect(func(on: bool) -> void: fir_only = on)
	row.add_child(_fir_toggle)
	_clear_button = _button("Clear", "CLEAR", "Clear the search and filters", clear)
	row.add_child(_clear_button)
	_sort_picker = _picker("SortMode", "What SORT orders by")
	for each in InventoryGrid.SORT_NAMES.size():
		_sort_picker.add_item("By " + InventoryGrid.SORT_NAMES[each].to_lower())
		_sort_picker.set_item_metadata(each, each)
	_sort_picker.item_selected.connect(func(index: int) -> void: sort_mode = int(_sort_picker.get_item_metadata(index)))
	row.add_child(_sort_picker)
	_sort_button = _button("Sort", "SORT", "Repack the stash in this order (stacks of the same item merge)", sort_grid)
	row.add_child(_sort_button)
	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"DimLabel"
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_status)
	# What was set before the controls existed.
	_select_by_metadata(_category_picker, category)
	_select_by_metadata(_rarity_picker, rarity)
	_select_by_metadata(_sort_picker, sort_mode)
	_fir_toggle.set_pressed_no_signal(fir_only)
	_color_rarity_picker()
	_update_status()
	set_process(false)


## Dims what `view` (an InventoryGridView or StashGrid: anything with a `filter`) shows that doesn't
## match, from now on.
func attach(view: Control) -> void:
	_views.assign(_views.filter(func(each: Variant) -> bool: return is_instance_valid(each)))
	if not view in _views:
		_views.append(view)
	view.set("filter", matches)


## Stops dimming `view` (a container's window whose container left the stash).
func detach(view: Control) -> void:
	_views.erase(view)
	view.set("filter", Callable())


## True if any filter is set (otherwise everything matches).
func is_active() -> bool:
	return _query != "" or category >= 0 or rarity >= 0 or fir_only


## True if `item` passes every filter set, or holds something that does (at any depth). Everything
## matches when no filter is set.
func matches(item: ItemInstance) -> bool:
	if not is_active():
		return true
	if item_matches(item):
		return true
	if item.contents:
		for inner in item.contents.items:
			if matches(inner):
				return true
	return false


## True if `item` itself passes every filter set (not counting what's inside it).
func item_matches(item: ItemInstance) -> bool:
	return (category < 0 or int(item.data.category) == category) and (rarity < 0 or int(item.data.rarity) == rarity) \
		and (not fir_only or item.fir) and _name_matches(item.data)


## Clears the search and the filters (not the sort order).
func clear() -> void:
	search = ""
	category = -1
	rarity = -1
	fir_only = false


## How many of `grid`'s items match (containers by what's inside too).
func match_count() -> int:
	if grid == null:
		return 0
	return grid.items.filter(matches).size()


## True if `query` finds the item, any case: part of its name as written ("led" finds the LEDX), part of
## its compact name, the name with only letters and digits kept ("ak74" finds the AK-74N, "762x39" the
## 7.62x39 rounds), or its whole id ("ammo_545_ps", or "ammo545ps"). Parts of ids don't count, so "ammo"
## doesn't light every round (the Ammo category does that). An empty query matches everything.
static func name_matches(data: ItemData, query: String) -> bool:
	var wanted := query.strip_edges().to_lower()
	return wanted == "" or _matches_name(data, wanted, _compact(wanted))


## Sorts `grid` in `sort_mode` order (InventoryGrid.sort()), unless an item is being dragged; saves
## the game when it sorted the stash. The line under the bar says what happened. True if it sorted.
func sort_grid() -> bool:
	if grid == null:
		return false
	var ok := false
	var text := ""
	if is_inside_tree() and get_viewport().gui_is_dragging():
		text = "Can't sort while you're moving an item"
	elif grid.sort(sort_mode):
		ok = true
		text = "Sorted by %s" % InventoryGrid.SORT_NAMES[sort_mode].to_lower()
		if grid == GameState.stash:
			SaveManager.save_game()
	else:
		text = "Couldn't sort: not enough room"
	show_message(text)
	sorted.emit(ok, text)
	return ok


## Shows `text` on the bar's line for MESSAGE_TIME seconds, then the match count again.
func show_message(text: String) -> void:
	_message = text
	_message_left = MESSAGE_TIME
	set_process(true)
	_update_status()


## The controls the grid cursor can land on, left to right.
func focus_targets() -> Array[Control]:
	var result: Array[Control] = []
	for control: Control in [_search_box, _category_picker, _rarity_picker, _fir_toggle, _clear_button, _sort_picker, _sort_button]:
		if control and control.is_visible_in_tree():
			result.append(control)
	return result


## Works `control` (one of focus_targets()) for the grid cursor: the search box starts editing (the
## on-screen keyboard comes up where there is one), a picker opens its list, FIR only flips, a button
## presses.
func activate(control: Control) -> void:
	if control == _search_box:
		_search_box.grab_focus()
		_search_box.edit()
	elif control is OptionButton:
		(control as OptionButton).show_popup()
	elif control is BaseButton and (control as BaseButton).toggle_mode:
		(control as BaseButton).button_pressed = not (control as BaseButton).button_pressed
	elif control is BaseButton:
		(control as BaseButton).pressed.emit()


## True while the bar has the keys: typing in the search box, a picker's list open, or a control focused
## with the keyboard or a controller (the focus a mouse click leaves on a button doesn't count).
func has_focus_inside() -> bool:
	if _search_box == null or not is_inside_tree():
		return false
	if _search_box.has_focus():
		return true
	for picker in [_category_picker, _rarity_picker, _sort_picker]:
		if picker.get_popup().visible:
			return true
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and is_ancestor_of(focused) and focused.has_focus(true)


## Esc / B: lets go of the keys if the bar has them (has_focus_inside()). True if it did, so the screen
## knows not to close as well.
func clear_focus() -> bool:
	if not has_focus_inside():
		return false
	for picker in [_category_picker, _rarity_picker, _sort_picker]:
		picker.get_popup().hide()
	var focused := get_viewport().gui_get_focus_owner()
	if focused and is_ancestor_of(focused):
		focused.release_focus()
	return true


## A click or tap anywhere off the bar's focused control (the search box, or a control the keyboard or a
## controller moved to) takes the focus away from it, so keys (R to turn a dragged item, the hotkeys,
## Esc) go back to the screen. The mouse wheel doesn't count.
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or not is_inside_tree() \
			or not click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused and is_ancestor_of(focused) and not focused.get_global_rect().has_point(click.position):
		focused.release_focus()


## Typing started or stopped; once it has stopped (and the box kept the focus), search_done says how.
func _on_editing_toggled(editing: bool) -> void:
	if editing:
		_submitted = false
	else:
		_end_search.call_deferred()


func _end_search() -> void:
	if _search_box.has_focus() and not _search_box.is_editing():
		search_done.emit(_submitted)
	_submitted = false


## A on a controller (ui_accept) on the focused search box starts typing, as Enter does on a keyboard.
func _on_search_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.is_action_pressed("ui_accept") and not _search_box.is_editing():
		_search_box.edit()
		_search_box.accept_event()


func _process(delta: float) -> void:
	_message_left -= delta
	if _message_left <= 0.0:
		_message = ""
		set_process(false)
		_update_status()


func _on_filter_changed() -> void:
	for view in _views:
		if is_instance_valid(view):
			view.queue_redraw()
	_update_status()
	filter_changed.emit()


## "12 of 48 items match", "48 items", or the SORT message while it shows.
func _update_status() -> void:
	if _status == null:
		return
	if _message != "":
		_status.text = _message
	elif grid == null:
		_status.text = ""
	elif is_active():
		_status.text = "%d of %d items match" % [match_count(), grid.items.size()]
	else:
		_status.text = "%d item%s" % [grid.items.size(), "" if grid.items.size() == 1 else "s"]


func _name_matches(data: ItemData) -> bool:
	return _query == "" or _matches_name(data, _query, _query_compact)


static func _matches_name(data: ItemData, wanted: String, wanted_compact: String) -> bool:
	if wanted in data.display_name.to_lower():
		return true
	if wanted_compact == "":
		return false
	if not _compact_names.has(data.id):
		_compact_names[data.id] = [_compact(data.display_name), _compact(data.id)]
	var names: Array = _compact_names[data.id]
	return wanted_compact in names[0] or wanted_compact == names[1]


## `text` in lower case with only its letters and digits ("AK-74N" → "ak74n").
static func _compact(text: String) -> String:
	var result := ""
	for character in text.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			result += character
	return result


func _picker(node_name: String, tip: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name
	picker.tooltip_text = tip
	picker.custom_minimum_size.y = CONTROL_HEIGHT
	picker.fit_to_longest_item = true
	return picker


func _button(node_name: String, text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(76, CONTROL_HEIGHT)
	button.pressed.connect(action)
	return button


## Selects the item of `picker` whose metadata is `value`, without telling anyone.
static func _select_by_metadata(picker: OptionButton, value: int) -> void:
	if picker == null:
		return
	for index in picker.item_count:
		if int(picker.get_item_metadata(index)) == value:
			picker.select(index)
			return


## The rarity picker's text takes the chosen rarity's colour.
func _color_rarity_picker() -> void:
	if _rarity_picker == null:
		return
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		if rarity >= 0:
			_rarity_picker.add_theme_color_override(state, Palette.rarity_color(rarity).lightened(0.2))
		else:
			_rarity_picker.remove_theme_color_override(state)


## A small square in `color` (the rarity picker's icons).
static func _swatch(color: Color) -> Texture2D:
	var image := Image.create(SWATCH, SWATCH, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for i in SWATCH:  # A darker edge, so every colour reads against the list.
		for edge in [Vector2i(i, 0), Vector2i(i, SWATCH - 1), Vector2i(0, i), Vector2i(SWATCH - 1, i)]:
			image.set_pixelv(edge, color.darkened(0.5))
	return ImageTexture.create_from_image(image)
