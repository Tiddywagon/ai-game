class_name InventoryScreen
extends MenuScreen
## The inventory (DESIGN.md §7). Equipment slots on the left, what's on you in the middle (pockets and
## the grids of the equipped rig, backpack and secure container), and the stash on the right when out of
## raid. Drag to move; R turns the item while dragging; Shift-drag splits a stack (the mouse wheel
## changes how many); right-click examines; double-click opens a container in its own window. The header
## shows the weight you carry and what it does to you. Tab, Esc or CLOSE closes it. In a raid the game
## keeps running while it's open, and searching a container or body shows it on the right instead of
## the stash. Found-in-raid items carry a checkmark (faded until you extract); "FIR only" dims the rest
## of the stash. Guns can be unloaded from the examine panel: the rounds keep their status.

## Equipment slot layout: two columns of [slot, size in cells].
const SLOT_COLUMNS := [
	[["helmet", Vector2i(2, 2)], ["armor", Vector2i(2, 2)], ["rig", Vector2i(2, 2)], ["backpack", Vector2i(2, 2)], ["secure", Vector2i(2, 2)]],
	[["primary", Vector2i(5, 2)], ["secondary", Vector2i(5, 2)], ["pistol", Vector2i(3, 2)], ["melee", Vector2i(2, 2)]],
]
## Equipped items whose grids are shown under the pockets.
const CONTAINER_SLOTS := [["rig", "TACTICAL RIG"], ["backpack", "BACKPACK"], ["secure", "SECURE CONTAINER"]]
const HEAVY_COLOR := Color(0.95, 0.7, 0.3)
const OVERWEIGHT_COLOR := Color(0.9, 0.32, 0.25)

## The character's equipment and pockets.
var inventory: Inventory
## The stash, beside the character out of raid; null in a raid.
var stash: InventoryGrid
## In a raid: what's being searched, a container's InventoryGrid or a body's Inventory (or null), and
## its title.
var loot: Variant
var loot_title := ""

var _config: InventoryConfig = preload("res://data/config/inventory.tres")
var _examine: ItemExaminePanel
var _shown_grids: Array[InventoryGrid] = []
var _loot_grids: Array[InventoryGrid] = []
var _windows := {}


func _ready() -> void:
	%CloseButton.pressed.connect(close)
	_examine = ItemExaminePanel.new()
	_examine.unload_requested.connect(unload)
	%Overlay.add_child(_examine)
	_build_equipment()
	_build_containers()
	%StashPanel.visible = stash != null or loot != null
	%FirFilter.visible = loot == null
	%FirFilter.toggled.connect(func(on: bool) -> void: %StashView.fir_only = on)
	_hook_view(%StashView)
	%StashView.inventory = inventory
	if loot is InventoryGrid:
		%StashTitle.text = loot_title
		%StashView.grid = loot
	elif loot is Inventory:
		%StashTitle.text = loot_title
		%StashView.hide()
		%LootBody.show()
		_build_loot_body()
		(loot as Inventory).changed.connect(_on_loot_changed)
	elif stash:
		%StashTitle.text = "STASH  ·  %d × %d" % [stash.size.x, stash.size.y]
		%StashView.grid = stash
	inventory.changed.connect(_on_inventory_changed)
	_update_header()


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
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if get_viewport().gui_is_dragging():
			return
		if _examine.visible:
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


## A body being searched: its equipment slots, then its pockets, rig and backpack.
func _build_loot_body() -> void:
	var body: Inventory = loot
	for child in %LootBody.get_children():
		%LootBody.remove_child(child)
		child.queue_free()
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


func _hook_view(view: InventoryGridView) -> void:
	view.examine_requested.connect(_examine_item)
	view.open_requested.connect(_open_window)


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
