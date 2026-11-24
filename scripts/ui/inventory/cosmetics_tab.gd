class_name CosmeticsTab
extends HBoxContainer
## The LOADOUT screen's COSMETICS tab (DESIGN.md §6.7, §16.6). Left: what can wear a skin: your
## character (the outfit for your faction), then every worn item and every item in the stash that takes
## one, each with the skins it carries. Middle: the picked one on a turning 3D model (SkinModel): drag to
## turn it (mouse or touch), the wheel or a pinch to zoom; it turns slowly on its own otherwise. Right:
## its cosmetic slots (SKIN, and STICKER and CHARM where the item has them; OUTFIT for the character),
## and the skins in your collection that fit that slot, with rarity, wear and BOUND (a bound skin lost with
## an item is back here, ready to put on again). PREVIEW shows the picked skin on the model without
## applying it, APPLY puts it on (what was there goes back to the collection), REMOVE takes the slot's
## skin off; COLLECTION opens the skins collection (SkinsScreen). Every change saves.

const CHARACTER := "character"
const OFF := Color(0.6, 0.6, 0.58)
const ON := Color(0.55, 0.9, 0.55)
const ZOOM_RANGE := Vector2(0.9, 4.0)

## The LOADOUT screen this tab is on (to redraw its grids after a change).
var screen: Control
## What's picked: an ItemInstance, or CHARACTER for the outfit (null: nothing).
var target: Variant = null
## The slot picked ("skin", "sticker", "charm"; "skin" for the outfit), the skin picked in the list, and
## the skin shown on the model as a preview ("" for none).
var slot := "skin"
var picked := ""
var previewing := ""
var zoom := 1.9
var yaw := 0.0
var pitch := -0.2
var _dragging := false

var _targets: VBoxContainer
var _view: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _model: SkinModel
var _title: Label
var _worn: Label
var _slots: HBoxContainer
var _skins: VBoxContainer
var _status: Label
var _drip: Label
var _preview: Button
var _apply: Button
var _remove: Button


func _ready() -> void:
	name = "CosmeticsTab"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 380
	add_child(left)
	left.add_child(_label("WHAT TO DRESS", OFF))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_targets = VBoxContainer.new()
	_targets.name = "Targets"
	_targets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_targets)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(middle)
	_title = _label("", Color.WHITE)
	_title.name = "TargetTitle"
	_title.theme_type_variation = &"HeadingLabel"
	middle.add_child(_title)
	_view = SubViewportContainer.new()
	_view.name = "Preview3D"
	_view.stretch = true
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.focus_mode = Control.FOCUS_NONE
	_view.tooltip_text = "Drag to turn  ·  Wheel or pinch: zoom"
	_view.gui_input.connect(_on_view_input)
	middle.add_child(_view)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_view.add_child(_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.07, 0.075, 0.08)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.58)
	environment.environment.ambient_light_energy = 0.55
	_viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.3
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_viewport.add_child(_camera)
	_worn = _label("", OFF)
	_worn.name = "WornSkins"
	_worn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	middle.add_child(_worn)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 440
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	_drip = _label("", Player.TRICK_COLOR)
	_drip.name = "CosmeticsDrip"
	_drip.add_theme_font_size_override("font_size", 20)
	right.add_child(_drip)
	_slots = HBoxContainer.new()
	_slots.name = "Slots"
	right.add_child(_slots)
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(list_scroll)
	_skins = VBoxContainer.new()
	_skins.name = "SkinList"
	_skins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_skins)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)
	_preview = _button("PreviewButton", "PREVIEW", preview)
	_apply = _button("ApplyButton", "APPLY", apply)
	_remove = _button("RemoveButton", "REMOVE", remove)
	for button: Button in [_preview, _apply, _remove]:
		buttons.add_child(button)
	right.add_child(_button("SkinsButton", "COLLECTION", open_collection))
	_status = _label("", OFF)
	_status.name = "CosmeticsStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label


func _button(id: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size = Vector2(140, 46)
	button.pressed.connect(action)
	return button


## Everything that can wear a skin: CHARACTER, then worn items (by slot), then the stash's.
static func targets() -> Array:
	var result: Array = [CHARACTER]
	for entry: Array in Inventory.SLOTS:
		var item: ItemInstance = GameState.inventory.equipment.get(entry[0])
		if item and not SkinTable.item_slots(item.data).is_empty():
			result.append(item)
	for item in GameState.stash.all_items():
		if not SkinTable.item_slots(item.data).is_empty():
			result.append(item)
	return result


## Draws the tab again from the profile (`keep`: stay on the target picked if it's still there).
func refresh(keep := true) -> void:
	var list := targets()
	if not keep or not (target is String or list.has(target)):
		target = list[0]
	_drip.text = UiFormat.drip(GameState.drip)
	_fill_targets(list)
	_fill_slots()
	_fill_skins()
	_rebuild_model()


## Puts the keyboard and controller focus on the first entry of the list.
func focus_first() -> void:
	var first := _targets.get_child(0) as Button if _targets.get_child_count() > 0 else null
	if first:
		first.grab_focus()


## Picks `what` (an item or CHARACTER): its slots and fitting skins, on the model.
func pick_target(what: Variant) -> void:
	target = what
	slot = "skin"
	picked = ""
	previewing = ""
	refresh()


## Picks slot `which` of the target.
func pick_slot(which: String) -> void:
	slot = which
	picked = ""
	previewing = ""
	_fill_slots()
	_fill_skins()
	_rebuild_model()


## Picks skin `id` in the list.
func pick_skin(id: String) -> void:
	picked = id
	_fill_skins()
	_update_buttons()


## PREVIEW: the picked skin on the model, not applied.
func preview() -> void:
	if picked == "":
		return
	previewing = picked
	_status.text = "Previewing %s. APPLY to keep it." % SkinTable.find(picked).get("name", "")
	_rebuild_model()


## APPLY: the picked skin onto the target's slot (an outfit: worn as your faction).
func apply() -> void:
	var reason := Cosmetics.wear_outfit(picked) if target is String else Cosmetics.apply(picked, target)
	if reason != "":
		_status.text = reason
		return
	_status.text = "%s applied." % SkinTable.find(picked).get("name", "")
	_changed()


## REMOVE: the target's slot back to plain (the skin back to the collection).
func remove() -> void:
	var reason := Cosmetics.wear_outfit("") if target is String else Cosmetics.remove(target, slot)
	if reason != "":
		_status.text = reason
		return
	_status.text = "Back in your collection."
	_changed()


func open_collection() -> void:
	var skins := SkinsScreen.create()
	var layer := screen.call("overlay") as Control if screen and screen.has_method("overlay") else self
	layer.add_child(skins)
	skins.closed.connect(func() -> void:
		refresh()
		focus_first.call_deferred())


func _changed() -> void:
	picked = ""
	previewing = ""
	SaveManager.save_game()
	refresh()
	if screen and screen.has_method("gear_changed"):
		screen.call("gear_changed")


## The skin on the target's picked slot ("" for none).
func current() -> String:
	if target is String:
		return Cosmetics.outfit()
	return str(Cosmetics.on_item(target, slot).get("id", "")) if target else ""


## The collection's skins that fit the target's picked slot, best rarity first.
func fitting() -> Array[String]:
	var result: Array[String] = []
	for id: String in Cosmetics.state().owned:
		var skin := SkinTable.find(id)
		if target is String:
			if skin.get("kind") == "outfit" and str(skin.get("faction", "")) == ("usec" if GameState.faction == GameState.Faction.USEC else "bear"):
				result.append(id)
		elif target and SkinTable.slot_of(skin) == slot and SkinTable.fits(skin, target.data):
			result.append(id)
	result.sort_custom(func(a: String, b: String) -> bool:
		var ra := SkinTable.rarity(SkinTable.find(a))
		var rb := SkinTable.rarity(SkinTable.find(b))
		return ra > rb if ra != rb else a < b)
	return result


func _fill_targets(list: Array) -> void:
	for child in _targets.get_children():
		_targets.remove_child(child)
		child.queue_free()
	var group := ButtonGroup.new()
	for index in list.size():
		var what: Variant = list[index]
		var button := Button.new()
		button.name = "Target%d" % index
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size = Vector2(360, 40)
		button.text = _target_text(what)
		button.button_pressed = (what is String and target is String) or (not what is String and not target is String and what == target)
		button.pressed.connect(pick_target.bind(what))
		_targets.add_child(button)


func _target_text(what: Variant) -> String:
	if what is String:
		var outfit := Cosmetics.outfit()
		return "Character  ·  %s" % (SkinTable.find(outfit).get("name", "") if outfit != "" else "plain uniform")
	var item: ItemInstance = what
	var where := "worn" if GameState.inventory.holder_of(item) or GameState.inventory.equipment.values().has(item) else "stash"
	var skin := str(item.cosmetics.get("skin", {}).get("id", ""))
	return "%s  ·  %s%s" % [item.data.display_name, where, "  ·  " + str(SkinTable.find(skin).get("name", "")) if skin != "" else ""]


func _fill_slots() -> void:
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	var names: Array = ["skin"] if target is String else SkinTable.item_slots(target.data) if target else []
	var group := ButtonGroup.new()
	for name_id: String in names:
		var button := Button.new()
		button.name = "Slot_" + name_id
		button.text = "OUTFIT" if target is String else name_id.to_upper()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(120, 40)
		button.button_pressed = name_id == slot
		button.pressed.connect(pick_slot.bind(name_id))
		_slots.add_child(button)


func _fill_skins() -> void:
	for child in _skins.get_children():
		_skins.remove_child(child)
		child.queue_free()
	var now := current()
	if now != "":
		_skins.add_child(_skin_row(now, true))
	var list := fitting()
	if list.is_empty() and now == "":
		_skins.add_child(_label("No skin in your collection fits this. Spin the Slot Machine in the hideout.", OFF))
	for id in list:
		if id != now:  # An outfit worn stays in the collection: listed once, as ON.
			_skins.add_child(_skin_row(id, false))
	_update_buttons()


## One row: the swatch, name (rarity colour), rarity, wear and BOUND; ON for the one on the slot now.
func _skin_row(id: String, on: bool) -> Button:
	var skin := SkinTable.find(id)
	var row := Button.new()
	row.name = "Skin_" + id
	row.toggle_mode = true
	row.button_pressed = id == picked
	row.custom_minimum_size = Vector2(420, 64)
	row.pressed.connect(pick_skin.bind(id))
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	var wear := Cosmetics.wear_of(id)
	box.add_child(SkinSwatch.create(id, wear, false, Vector2(84, 60)))
	var text := Label.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.text = "%s%s\n%s  ·  %s%s" % [skin.get("name", ""), "  (ON)" if on else "", SkinTable.rarity_name(skin), SkinTable.wear_text(wear), "  ·  BOUND" if SkinTable.is_bound(skin) else ""]
	text.add_theme_color_override("font_color", Palette.rarity_color(SkinTable.rarity(skin)))
	text.add_theme_font_size_override("font_size", 15)
	box.add_child(text)
	return row


func _update_buttons() -> void:
	var on := current()
	_preview.disabled = picked == "" or picked == on
	var block := "Pick a skin from the list" if picked == "" else ("" if target is String else Cosmetics.apply_block_reason(picked, target))
	if target is String and picked != "":
		block = Cosmetics.outfit_block_reason(picked)
	if picked == on and picked != "":
		block = "It's on already"
	_apply.disabled = block != ""
	_apply.tooltip_text = block
	_remove.disabled = on == ""
	if target is String:
		_title.text = "CHARACTER (%s)" % ("USEC" if GameState.faction == GameState.Faction.USEC else "BEAR")
		_worn.text = "Outfit: %s. Outfits are never lost." % (SkinTable.find(on).get("name", "") if on != "" else "plain uniform")
	elif target:
		_title.text = (target as ItemInstance).data.display_name.to_upper()
		var lines := SkinLook.tooltip_lines(target)
		_worn.text = "  ·  ".join(lines) if not lines.is_empty() else "No skins on it."


func _rebuild_model() -> void:
	if _model:
		_viewport.remove_child(_model)
		_model.queue_free()
		_model = null
	if target == null:
		return
	if target is String:
		_model = SkinModel.create("outfit")
		var shown := previewing if previewing != "" else Cosmetics.outfit()
		_model.paint("skin", shown, Cosmetics.wear_of(shown))
	else:
		_model = SkinModel.for_item(target, {slot: previewing} if previewing != "" else {})
	_viewport.add_child(_model)
	zoom = 2.8 if target is String else 1.9
	_place_camera()
	_update_buttons()


func _place_camera() -> void:
	var offset := Vector3(0, 0, zoom).rotated(Vector3.RIGHT, pitch)
	_camera.look_at_from_position(offset, Vector3.ZERO)


func _process(delta: float) -> void:
	if _model and visible and not _dragging:
		yaw += delta * 0.5
	if _model:
		_model.rotation = Vector3(0, yaw, 0)


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(-1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
	elif event is InputEventMouseMotion and _dragging:
		turn_by((event as InputEventMouseMotion).relative)
	elif event is InputEventScreenDrag:
		_dragging = true
		turn_by((event as InputEventScreenDrag).relative)
	elif event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		_dragging = false
	elif event is InputEventMagnifyGesture:
		zoom_by((1.0 - (event as InputEventMagnifyGesture).factor) * 4.0)


## Turns the model by a drag of `by` pixels.
func turn_by(by: Vector2) -> void:
	yaw += by.x * 0.01
	pitch = clampf(pitch - by.y * 0.006, -1.2, 0.8)
	_place_camera()


## Zooms by `steps` wheel notches (out when positive).
func zoom_by(steps: float) -> void:
	zoom = clampf(zoom * pow(1.12, steps), ZOOM_RANGE.x, ZOOM_RANGE.y)
	_place_camera()
