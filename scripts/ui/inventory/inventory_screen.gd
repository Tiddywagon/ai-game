class_name InventoryScreen
extends MenuScreen
## The inventory (DESIGN.md §7). Equipment slots on the left, what's on you in the middle (pockets and
## the grids of the equipped rig, backpack and secure container), and the stash on the right when out of
## raid. Drag to move; R turns the item while dragging; Shift-drag splits a stack (the mouse wheel
## changes how many); right-click examines; double-click opens a container in its own window. The header
## shows the weight you carry and what it does to you. Tab, Esc or CLOSE closes it. In a raid the game
## keeps running while it's open, and searching a container or body shows it on the right instead of
## the stash: its items turn up one by one while it's open (LootSearch), and the title counts them. Found-in-raid items carry a checkmark (faded until you extract); "FIR only" dims the rest
## of the stash. Guns can be unloaded from the examine panel: the rounds keep their status. Out of raid,
## MODIFY there opens the modding screen (WeaponModScreen), and dropping a weapon part on a gun fits it
## to a free slot. Meds, stims, food and drink have USE in the examine panel (DESIGN.md §13.7): in a
## raid the player uses it over its use time (the header shows progress; the game goes on); out of
## raid food and drink go straight to the profile's energy and hydration. The header shows both, and
## hovering a food or drink previews what one use would do under them ("Crackers: Energy 62 → 77 (+15)  ·  ...").
## Ctrl-click quick-moves an item to the stash (or the container or body being searched), or back onto
## you from there. Pressing 1-5 over a med, stim, food, drink, grenade or flare puts it on that hotkey.
## Every device works it (DESIGN.md §17.1): on touch, a finger is the mouse (tap, drag and drop),
## long-press examines, a second finger's tap turns the item being dragged and pinching zooms the
## stash (TouchGestures); with a controller, a cursor moves cell by cell and its buttons pick up, turn,
## quick-move and examine (GridCursor). The header's hint matches the device.

## Equipment slot layout: two columns of [slot, size in cells].
const SLOT_COLUMNS := [
	[["helmet", Vector2i(2, 2)], ["armor", Vector2i(2, 2)], ["rig", Vector2i(2, 2)], ["backpack", Vector2i(2, 2)], ["secure", Vector2i(2, 2)]],
	[["primary", Vector2i(5, 2)], ["secondary", Vector2i(5, 2)], ["pistol", Vector2i(3, 2)], ["melee", Vector2i(2, 2)]],
]
## Equipped items whose grids are shown under the pockets.
const CONTAINER_SLOTS := [["rig", "TACTICAL RIG"], ["backpack", "BACKPACK"], ["secure", "SECURE CONTAINER"]]
const HEAVY_COLOR := Color(0.95, 0.7, 0.3)
## Width of the energy / water status in the header.
const BODY_STATUS_WIDTH := 430.0
const OVERWEIGHT_COLOR := Color(0.9, 0.32, 0.25)
## The header's hint for each device (InputHub.Device order: keyboard and mouse, controller, touch).
const HINTS := [
	"Drag to move  ·  R: turn  ·  Shift-drag: split (wheel: how many)  ·  Right-click: examine  ·  Double-click: open  ·  Ctrl-click: quick move  ·  1-5 over a med: hotkey  ·  Checkmark: found in raid",
	"D-pad or left stick: move the cursor  ·  The buttons below pick up, turn, quick-move and examine  ·  Checkmark: found in raid",
	"Drag to move  ·  Second-finger tap while dragging: turn  ·  Long-press: examine  ·  Double-tap: open  ·  Pinch the stash: zoom  ·  Checkmark: found in raid",
]

## The character's equipment and pockets.
var inventory: Inventory
## The stash, beside the character out of raid; null in a raid.
var stash: InventoryGrid
## In a raid: what's being searched, a container's InventoryGrid or a body's Inventory (or null), and
## its title.
var loot: Variant
var loot_title := ""
## Searching `loot` (its unsearched items are revealed while this screen is open), or null.
var loot_search: LootSearch
## In a raid: the player whose inventory this is (items are used on them). Null out of raid.
var user: Player

var _config: InventoryConfig = preload("res://data/config/inventory.tres")
var _examine: ItemExaminePanel
var _shown_grids: Array[InventoryGrid] = []
var _loot_grids: Array[InventoryGrid] = []
var _loot_views: Array[InventoryGridView] = []
var _windows := {}
var _body_label: Label
var _use_label: Label
var _use_message := ""
var _use_message_time := 0.0
## The controller's cell cursor and the touch gestures.
var cursor: GridCursor
var gestures: TouchGestures


func _ready() -> void:
	%CloseButton.pressed.connect(close)
	_examine = ItemExaminePanel.new()
	_examine.unload_requested.connect(unload)
	_examine.modify_requested.connect(open_modding)
	_examine.upgrade_requested.connect(open_upgrade)
	_examine.part_removal_requested.connect(take_off_part)
	_examine.use_requested.connect(use_item)
	_examine.use_check = _use_reason
	_examine.can_modify = stash != null
	InventoryDrag.mods_allowed = stash != null
	%Overlay.add_child(_examine)
	_build_equipment()
	_build_containers()
	%StashPanel.visible = stash != null or loot != null
	%FirFilter.visible = loot == null
	%FirFilter.toggled.connect(func(on: bool) -> void: %StashView.fir_only = on)
	_hook_view(%StashView)
	%StashView.inventory = inventory
	if loot is InventoryGrid:
		%StashView.grid = loot
		%StashView.search = loot_search
		_loot_views = [%StashView]
	elif loot is Inventory:
		%StashView.hide()
		%LootBody.show()
		_build_loot_body()
		(loot as Inventory).changed.connect(_on_loot_changed)
	elif stash:
		%StashTitle.text = "STASH  ·  %d × %d" % [stash.size.x, stash.size.y]
		%StashView.grid = stash
	inventory.changed.connect(_on_inventory_changed)
	_build_body_status()
	Consumables.preview_health = user.health if user else null
	if user:
		user.item_use_ended.connect(_on_use_ended)
	elif stash:
		Consumables.recover_profile()
	_update_header()
	_update_loot_title()
	cursor = GridCursor.new()
	cursor.name = "GridCursor"
	cursor.screen = self
	add_child(cursor)
	gestures = TouchGestures.new()
	gestures.name = "TouchGestures"
	gestures.two_finger_tap.connect(_on_two_finger_tap)
	gestures.pinched.connect(_on_pinched)
	add_child(gestures)
	InputHub.device_changed.connect(_update_hint)
	_update_hint(InputHub.device)


func _update_hint(device: int) -> void:
	%Hint.text = HINTS[device] if device >= 0 and device < HINTS.size() else HINTS[0]
	%CloseButton.text = "CLOSE  (%s)" % Settings.key_label("toggle_inventory")


## A second finger tapped while the first drags an item: turn it.
func _on_two_finger_tap(_at: Vector2) -> void:
	if get_viewport().gui_is_dragging() and InventoryDrag.current:
		InventoryDrag.current.rotate()


## Two fingers pinching or spreading over the stash zoom it.
func _on_pinched(factor: float, centre: Vector2) -> void:
	var view: InventoryGridView = %StashView
	if view.is_visible_in_tree() and (%StashPanel as Control).get_global_rect().has_point(centre):
		view.zoom(factor)


## True when the controller cursor may work the screen (nothing open over the grids).
func cursor_allowed() -> bool:
	if _examine.visible or get_node_or_null("WeaponModScreen"):
		return false
	var upgrade_panel := %Overlay.get_node_or_null("GearUpgradePanel") as GearUpgradePanel
	return not (upgrade_panel and upgrade_panel.visible)


func examine(item: ItemInstance) -> void:
	_examine_item(item)


## Moves `item` straight across: from you to the stash (out of raid) or the container or body being
## searched, or from there back into your pockets, rig or backpack. What doesn't fit stays where it
## was. False if it didn't all move.
func quick_move(item: ItemInstance) -> bool:
	if item == null or item.hidden:
		return false
	var source := _source_of(item)
	if source.is_empty() or (not source.away and stash == null and loot == null):
		return false
	var from_grid: InventoryGrid = source.get("grid")
	var cell := item.cell
	var turned := item.rotated
	if from_grid:
		from_grid.remove(item)
	else:
		(source.owner as Inventory).unequip(source.slot)
	var moved := false
	if source.away:
		moved = inventory.add(item)
	elif stash:
		moved = stash.add(item)
	elif loot is InventoryGrid:
		moved = (loot as InventoryGrid).add(item)
	elif loot is Inventory:
		moved = (loot as Inventory).add(item)
	if not moved and item.count > 0:
		if from_grid:
			from_grid.place(item, cell, turned)
		else:
			(source.owner as Inventory).equip(source.slot, item)
	inventory.changed.emit()
	for other: Variant in [stash, loot]:
		if other:
			other.changed.emit()
	return moved


## Where `item` is: {"grid"} or {"owner", "slot"}, and "away" if that's the stash or what's being
## searched rather than you. {} if it's nowhere on screen.
func _source_of(item: ItemInstance) -> Dictionary:
	var slot := inventory.slot_of(item)
	if slot != "":
		return {"owner": inventory, "slot": slot, "away": false}
	var grid := inventory.holder_of(item)
	if grid:
		return {"grid": grid, "away": false}
	if loot is Inventory:
		var body: Inventory = loot
		slot = body.slot_of(item)
		if slot != "":
			return {"owner": body, "slot": slot, "away": true}
		grid = body.holder_of(item)
	elif loot is InventoryGrid:
		grid = (loot as InventoryGrid).find_holder(item)
	elif stash:
		grid = stash.find_holder(item)
	return {"grid": grid, "away": true} if grid else {}


func _process(delta: float) -> void:
	_update_body_status(delta)
	if loot_search == null or get_tree().paused:
		return
	var was_done := loot_search.is_done()
	var found := loot_search.step(delta)
	for view in _loot_views:
		if is_instance_valid(view):
			view.queue_redraw()
	if not found.is_empty() or was_done != loot_search.is_done():
		_update_loot_title()


## "DUFFLE BAG  ·  SEARCHING 2 / 5", then "·  SEARCHED".
func _update_loot_title() -> void:
	if loot == null:
		return
	if loot_search == null:
		%StashTitle.text = loot_title
		return
	var counts := loot_search.counts()
	if loot_search.is_done():
		%StashTitle.text = "%s  ·  SEARCHED" % loot_title if counts[1] > 0 else "%s  ·  EMPTY" % loot_title
	else:
		%StashTitle.text = "%s  ·  SEARCHING  %d / %d" % [loot_title, counts[0], counts[1]]


func _input(event: InputEvent) -> void:
	if get_viewport().gui_is_dragging() and InventoryDrag.current:
		var key := event as InputEventKey
		if key and key.pressed and not key.echo and (key.physical_keycode == KEY_R or event.is_action_pressed("reload")):
			InventoryDrag.current.rotate()
			get_viewport().set_input_as_handled()
			return
		var wheel := event as InputEventMouseButton
		if wheel and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			InventoryDrag.current.change_amount(1 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and not get_viewport().gui_is_dragging():
		for i in GameState.HOTKEY_COUNT:
			if event.is_action_pressed("hotkey_%d" % (i + 1)):
				assign_hotkey(hovered_item(), i)
				get_viewport().set_input_as_handled()
				return
	if user and user.using_item and event.is_action_pressed("use_item"):
		user.cancel_use("Stopped using %s" % user.using_item.data.display_name)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if get_viewport().gui_is_dragging():
			return
		var upgrade_panel := %Overlay.get_node_or_null("GearUpgradePanel") as GearUpgradePanel
		if upgrade_panel and upgrade_panel.visible:
			upgrade_panel.close()
		elif _examine.visible:
			_examine.close()
		elif not _windows.is_empty():
			_close_window(_windows.keys().back())
		else:
			close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		InventoryDrag.current = null


func _on_inventory_changed() -> void:
	_update_header()
	if inventory.grids() != _shown_grids:
		_build_containers()


func _update_header() -> void:
	var weight := inventory.total_weight()
	%WeightLabel.text = "WEIGHT  %s  /  %s" % [Settings.format_weight(weight), Settings.format_weight(_config.overweight_kg)]
	%WeightBar.max_value = _config.max_weight_kg
	%WeightBar.value = weight
	var color := MenuEntryButton.TEXT
	var state := "Carrying %s more slows you down" % Settings.format_weight(maxf(_config.encumbered_kg - weight, 0.0))
	if weight >= _config.overweight_kg:
		color = OVERWEIGHT_COLOR
		state = "Overweight: %d%% speed, no sprinting or rolling" % roundi(_config.speed_multiplier(weight) * 100.0)
	elif weight > _config.encumbered_kg:
		color = HEAVY_COLOR
		state = "Heavy: %d%% speed, sprinting tires you faster" % roundi(_config.speed_multiplier(weight) * 100.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	%WeightBar.add_theme_stylebox_override("fill", fill)
	%WeightLabel.add_theme_color_override("font_color", color)
	%WeightState.text = state
	%ValueLabel.text = "Carried value  %s" % UiFormat.money(inventory.total_value())


func _build_equipment() -> void:
	for column in SLOT_COLUMNS:
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		%Equipment.add_child(rows)
		for entry in column:
			var slot: String = entry[0]
			var label := Label.new()
			label.theme_type_variation = &"DimLabel"
			label.text = _slot_name(slot)
			rows.add_child(label)
			var view := EquipmentSlotView.new()
			view.name = "Slot_" + slot
			view.setup(inventory, slot, _slot_name(slot), entry[1])
			view.examine_requested.connect(_examine_item)
			view.open_requested.connect(_open_window)
			view.quick_move_requested.connect(quick_move)
			rows.add_child(view)


func _build_containers() -> void:
	for child in %Containers.get_children():
		%Containers.remove_child(child)  # Now, so the new views get their names.
		child.queue_free()
	_shown_grids = inventory.grids()
	_add_section("POCKETS", inventory.pockets)
	var any := false
	for entry in CONTAINER_SLOTS:
		var item: ItemInstance = inventory.equipment[entry[0]]
		if item and item.contents:
			_add_section("%s  ·  %s" % [entry[1], item.data.display_name], item.contents)
			any = true
	if not (inventory.equipment.rig or inventory.equipment.backpack):
		var note := Label.new()
		note.theme_type_variation = &"DimLabel"
		note.text = "Equip a rig or backpack for more room."
		%Containers.add_child(note)


func _add_section(title: String, grid: InventoryGrid, parent: Control = null, owner_inventory: Inventory = null, prefix := "Grid_") -> void:
	parent = parent if parent else %Containers
	var label := Label.new()
	label.theme_type_variation = &"AccentLabel"
	label.text = title
	parent.add_child(label)
	var view := InventoryGridView.new()
	view.name = prefix + str(grid.kind)
	_hook_view(view)
	view.inventory = owner_inventory if owner_inventory else inventory
	view.grid = grid
	view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(view)
	if owner_inventory and owner_inventory == loot:
		view.search = loot_search
		_loot_views.append(view)


## A body being searched: its equipment slots, then its pockets, rig and backpack.
func _build_loot_body() -> void:
	var body: Inventory = loot
	for child in %LootBody.get_children():
		%LootBody.remove_child(child)
		child.queue_free()
	_loot_views.clear()
	_loot_grids = body.grids()
	var slots := HFlowContainer.new()
	slots.add_theme_constant_override("h_separation", 12)
	slots.add_theme_constant_override("v_separation", 6)
	%LootBody.add_child(slots)
	for column in SLOT_COLUMNS:
		for entry in column:
			var slot: String = entry[0]
			if slot == "secure":
				continue  # A body's secure container can't be searched.
			var box := VBoxContainer.new()
			var label := Label.new()
			label.theme_type_variation = &"DimLabel"
			label.text = _slot_name(slot)
			box.add_child(label)
			var view := EquipmentSlotView.new()
			view.name = "LootSlot_" + slot
			view.setup(body, slot, _slot_name(slot), entry[1])
			view.examine_requested.connect(_examine_item)
			view.open_requested.connect(_open_window)
			view.quick_move_requested.connect(quick_move)
			box.add_child(view)
			slots.add_child(box)
	_add_section("POCKETS", body.pockets, %LootBody, body, "LootGrid_")
	for entry in CONTAINER_SLOTS:
		var item: ItemInstance = body.equipment[entry[0]]
		if item and item.contents and entry[0] != "secure":
			_add_section("%s  ·  %s" % [entry[1], item.data.display_name], item.contents, %LootBody, body, "LootGrid_")


func _on_loot_changed() -> void:
	if (loot as Inventory).grids() != _loot_grids:
		_build_loot_body()


## Empties the magazine of `gun`: the rounds go to your pockets, rig or backpack (or the stash), each
## keeping its found-in-raid status. Rounds with nowhere to go stay loaded.
func unload(gun: ItemInstance) -> void:
	for rounds in gun.unload():
		if inventory.add(rounds) or (stash and stash.add(rounds)):
			continue
		gun.load_rounds(rounds)
	inventory.changed.emit()
	if stash:
		stash.changed.emit()
	if _examine.visible and _examine.item == gun:
		_examine.show_item(gun)


## Uses a med, stim, food or drink: in a raid, the player starts using it (the examine panel closes);
## out of raid, food and drink feed the profile at once (and the game is saved).
func use_item(item: ItemInstance) -> void:
	if user:
		if user.start_use(item):
			_examine.close()
		return
	var holder := inventory.holder_of(item)
	if holder == null and stash:
		holder = stash.find_holder(item)
	var result := Consumables.use_in_profile(item, holder)
	_show_use_message(str(result.get("text", result.get("reason", ""))))
	if not result.ok:
		return
	_examine.close()
	inventory.changed.emit()
	if holder:
		holder.changed.emit()
	SaveManager.save_game()


## Puts `item` on hotkey `index` (0-4) if it can go on one, and says so. False if it can't.
func assign_hotkey(item: ItemInstance, index: int) -> bool:
	if item == null:
		return false
	if not Player.hotkey_usable(item.data):
		_show_use_message("%s can't go on a hotkey" % item.data.display_name)
		return false
	GameState.set_hotkey(index, item.data.id)
	_show_use_message("Hotkey %d: %s" % [index + 1, item.data.display_name])
	if stash:
		SaveManager.save_game()
	return true


func _use_reason(item: ItemInstance) -> String:
	if user:
		return user.use_block_reason(item)
	return Consumables.profile_block_reason(item) if stash else "Can't be used here"


func _on_use_ended(_item: ItemInstance, _finished: bool, text: String) -> void:
	if text != "":
		_show_use_message(text)


func _show_use_message(text: String) -> void:
	_use_message = text
	_use_message_time = 3.0


## Energy and hydration (the player's in a raid, the profile's out of raid), and what's being used.
func _build_body_status() -> void:
	var box := VBoxContainer.new()
	box.name = "BodyStatus"
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.custom_minimum_size.x = BODY_STATUS_WIDTH  # Fixed: long previews are cut, never widen the header.
	box.add_theme_constant_override("separation", 2)
	%ValueLabel.add_sibling(box)
	_body_label = Label.new()
	_body_label.name = "Metabolism"
	box.add_child(_body_label)
	_use_label = Label.new()
	_use_label.name = "UseStatus"
	_use_label.theme_type_variation = &"DimLabel"
	box.add_child(_use_label)
	for label in [_body_label, _use_label]:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = BODY_STATUS_WIDTH


## The item under the mouse in one of the grids or slots, or null.
func hovered_item() -> ItemInstance:
	var control := get_viewport().gui_get_hovered_control()
	if control is InventoryGridView:
		return (control as InventoryGridView).item_at_position(control.get_local_mouse_position())
	if control is EquipmentSlotView:
		return (control as EquipmentSlotView).item()
	return null


func _exit_tree() -> void:
	if user and Consumables.preview_health == user.health:
		Consumables.preview_health = null


func _update_body_status(delta: float) -> void:
	if _body_label == null:
		return
	var tuning := Consumables.CONFIG
	var energy := user.health.energy if user else GameState.energy
	var hydration := user.health.hydration if user else GameState.hydration
	_body_label.text = "ENERGY  %d / %d    WATER  %d / %d" % [ceili(snappedf(energy, 0.1)), roundi(tuning.max_energy), ceili(snappedf(hydration, 0.1)),
		roundi(tuning.max_hydration)]
	var hovered := hovered_item()
	var preview := Consumables.preview_text(hovered.data) if hovered and Consumables.is_consumable(hovered.data) else ""
	var low := energy <= tuning.low_threshold or hydration <= tuning.low_threshold
	_body_label.add_theme_color_override("font_color", HEAVY_COLOR if low else MenuEntryButton.TEXT)
	_use_message_time -= delta
	_use_label.remove_theme_color_override("font_color")
	if user and user.using_item:
		_use_label.text = "Using %s  ·  %.1f s  ·  %s to stop" % [user.using_item.data.display_name, maxf(user.use_time_left, 0.0),
			Settings.key_label("use_item")]
	elif preview != "":
		_use_label.text = "%s: %s" % [hovered.data.display_name, preview.replace("Hydration", "Water")]
		_use_label.add_theme_color_override("font_color", HEAVY_COLOR)
	elif _use_message_time > 0.0:
		_use_label.text = _use_message
	else:
		_use_label.text = ""


## Opens the upgrade dialog for `item` over the inventory (out of raid only).
func open_upgrade(item: ItemInstance) -> GearUpgradePanel:
	if stash == null or item == null or not GearUpgrades.is_upgradable(item.data):
		return null
	_examine.close()
	var panel := GearUpgradePanel.new()
	%Overlay.add_child(panel)
	panel.upgraded.connect(func(_upgraded: ItemInstance) -> void: _on_gear_upgraded())
	panel.closed.connect(panel.queue_free)
	panel.show_item(item)
	return panel


func _on_gear_upgraded() -> void:
	for grid in inventory.grids():
		grid.changed.emit()
	stash.changed.emit()
	inventory.changed.emit()
	_build_containers()  # A bigger rig or backpack.


## Takes the part in slot `path` off `item` (a helmet's face shield or headset) into the stash, else
## your pockets, rig or backpack.
func take_off_part(item: ItemInstance, path: String) -> void:
	var part := WeaponMods.mod_at(item, path)
	if part == null:
		return
	WeaponMods.uninstall(item, path)
	if not ((stash and stash.add(part)) or inventory.add(part)):
		WeaponMods.install(item, path, part)  # Nowhere to put it.
	inventory.changed.emit()
	if stash:
		stash.changed.emit()
	_examine.show_item(item)


## Opens the modding screen for `gun` over the inventory (out of raid only).
func open_modding(gun: ItemInstance) -> WeaponModScreen:
	if stash == null or gun == null or not gun.is_gun():
		return null
	_examine.close()
	var screen := WeaponModScreen.new()
	screen.name = "WeaponModScreen"
	screen.gun = gun
	screen.inventory = inventory
	screen.stash = stash
	screen.closed.connect(_on_modding_closed)
	add_child(screen)
	return screen


func _on_modding_closed() -> void:
	for grid in inventory.grids():
		grid.changed.emit()
	stash.changed.emit()
	inventory.changed.emit()


func _hook_view(view: InventoryGridView) -> void:
	view.examine_requested.connect(_examine_item)
	view.open_requested.connect(_open_window)
	view.quick_move_requested.connect(quick_move)


func _examine_item(item: ItemInstance) -> void:
	_examine.show_item(item)


## A floating window with the grid of `item` (a rig, backpack or container), e.g. one in the stash.
func _open_window(item: ItemInstance) -> void:
	if _windows.has(item):
		%Overlay.move_child(_windows[item], -1)
		return
	var window := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.065, 0.07, 0.97)
	style.border_color = Palette.rarity_color(item.data.rarity)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	window.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	window.add_child(rows)
	var bar := HBoxContainer.new()
	rows.add_child(bar)
	var title := Label.new()
	title.text = item.data.display_name.to_upper()
	title.theme_type_variation = &"AccentLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(32, 28)
	close_button.pressed.connect(_close_window.bind(item))
	bar.add_child(close_button)
	var view := InventoryGridView.new()
	_hook_view(view)
	view.inventory = inventory
	view.grid = item.contents
	rows.add_child(view)
	%Overlay.add_child(window)
	window.reset_size()
	window.position = (%Overlay.size - window.size) / 2.0 + Vector2(40, 40) * _windows.size()
	_windows[item] = window


func _close_window(item: ItemInstance) -> void:
	if _windows.has(item):
		_windows[item].queue_free()
		_windows.erase(item)


func _slot_name(slot: String) -> String:
	for entry in Inventory.SLOTS:
		if entry[0] == slot:
			return entry[1]
	return slot
