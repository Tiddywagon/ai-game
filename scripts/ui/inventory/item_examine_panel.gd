class_name ItemExaminePanel
extends PanelContainer
## Examining an item (DESIGN.md §7): its icon, name in its rarity colour, rarity and category, size,
## weight, value and stack, the stats that matter for its kind (a gun's fire rate and magazine, ammo
## damage and penetration, armor class, what meds treat, a container's grid and what's in it) and its
## description, and whether it's found in raid (with the checkmark). Guns show their stats with their
## parts fitted and their durability; weapon parts what they change and which guns they fit. Guns with
## rounds loaded can be unloaded from here, and out of raid MODIFY opens the modding screen.
## Right-click any item in the inventory to open it; Esc or CLOSE hides it.

signal closed
## UNLOAD pressed for a gun.
signal unload_requested(item: ItemInstance)
## MODIFY pressed for a gun.
signal modify_requested(item: ItemInstance)

const TREATMENTS := {"light_bleed": "light bleed", "heavy_bleed": "heavy bleed", "fracture": "fracture",
	"pain": "pain", "blacked": "blacked limb"}

var item: ItemInstance
## Guns can be modded from here (out of raid).
var can_modify := false

var _icon: TextureRect
var _name: Label
var _subtitle: Label
var _stats: GridContainer
var _description: Label
var _unload: Button
var _modify: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(460, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.065, 0.07, 0.97)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	add_child(rows)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	rows.add_child(header)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(150, 110)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(titles)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 24)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size.x = 260
	titles.add_child(_name)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"DimLabel"
	titles.add_child(_subtitle)
	rows.add_child(HSeparator.new())
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 28)
	_stats.add_theme_constant_override("v_separation", 4)
	rows.add_child(_stats)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = 420
	_description.theme_type_variation = &"DimLabel"
	rows.add_child(_description)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	_unload = Button.new()
	_unload.text = "UNLOAD"
	_unload.custom_minimum_size = Vector2(120, 36)
	_unload.tooltip_text = "Take the rounds out; each keeps its found-in-raid status"
	_unload.pressed.connect(func() -> void: unload_requested.emit(item))
	buttons.add_child(_unload)
	_modify = Button.new()
	_modify.name = "ModifyButton"
	_modify.text = "MODIFY"
	_modify.custom_minimum_size = Vector2(120, 36)
	_modify.tooltip_text = "Fit and swap parts, see the stats change, repair"
	_modify.pressed.connect(func() -> void: modify_requested.emit(item))
	buttons.add_child(_modify)
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(120, 36)
	close_button.pressed.connect(close)
	buttons.add_child(close_button)
	hide()


func show_item(examined: ItemInstance) -> void:
	item = examined
	var data := item.data
	_icon.texture = data.get_icon()
	_name.text = data.display_name
	_name.add_theme_color_override("font_color", Palette.rarity_color(data.rarity).lightened(0.15))
	_subtitle.text = "%s (%s)  ·  %s" % [Palette.RARITY_NAMES[data.rarity], Palette.RARITY_SHORT[data.rarity], data.category_name().capitalize()]
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for line in stat_lines(item):
		var label := Label.new()
		label.theme_type_variation = &"DimLabel"
		label.text = line[0]
		_stats.add_child(label)
		var value := Label.new()
		value.text = line[1]
		if line[0] == "Found in raid" and ItemDraw.has_fir_mark(item):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var mark := FirMark.new()
			mark.pending = item.fir_pending and not item.fir
			row.add_child(mark)
			row.add_child(value)
			_stats.add_child(row)
		else:
			_stats.add_child(value)
	_unload.visible = item.rounds_loaded() > 0
	_modify.visible = can_modify and item.is_gun()
	_description.text = data.description
	_description.visible = data.description != ""
	show()
	_fit.call_deferred()


## Shrinks to the new content once it's laid out, centred over the screen.
func _fit() -> void:
	reset_size()
	position = ((get_parent_area_size() - size) / 2.0).round()


func close() -> void:
	hide()
	closed.emit()


## Which guns weapon part `data` fits: their names, or any gun with a slot for it.
static func fits_text(data: ItemData) -> String:
	var platforms: Array = WeaponMods.info(data).get("fits", [])
	if platforms.is_empty():
		return "Any gun with a slot for it"
	var names: Array[String] = []
	for each in ItemDB.all_items():
		if each.weapon and each.weapon.platform in platforms:
			names.append(each.display_name)
	names.sort()
	return ", ".join(names) if not names.is_empty() else ", ".join(platforms)


## [label, value] pairs describing `examined`.
static func stat_lines(examined: ItemInstance) -> Array:
	var data := examined.data
	var stats := data.stats
	var lines := []
	lines.append(["Size", "%d × %d cells" % [data.size.x, data.size.y]])
	if examined.count > 1:
		lines.append(["Weight", "%s each, %s in all" % [Settings.format_weight(data.weight_kg), Settings.format_weight(examined.weight())]])
		lines.append(["Value", "%s each, %s in all" % [UiFormat.money(data.base_value), UiFormat.money(examined.value())]])
	else:
		lines.append(["Weight", Settings.format_weight(examined.weight())])
		lines.append(["Value", UiFormat.money(examined.value())])
	if data.max_stack > 1:
		lines.append(["Stack", "%d / %d" % [examined.count, data.max_stack]])
	if data.weapon:
		var gun := WeaponStats.build(examined)
		lines.append(["Caliber", gun.caliber])
		lines.append(["Fire rate", "%d rpm, %s" % [gun.fire_rate, "automatic" if gun.automatic else "semi-automatic"]])
		lines.append(["Magazine", "%d rounds" % gun.magazine_size if gun.magazine_size > 0 else "none fitted"])
		lines.append(["Reload", "%.1f s (empty %.1f s)" % [gun.reload_time, gun.empty_reload_time]])
		var recoil := 100.0 * gun.recoil_per_shot / data.weapon.recoil_per_shot if data.weapon.recoil_per_shot > 0.0 else 100.0
		lines.append(["Handling", "ergonomics %d, recoil %d%%, spread %.2f°" % [gun.ergonomics, roundi(recoil), gun.base_spread]])
		lines.append(["Muzzle velocity", "%d m/s" % gun.muzzle_velocity])
		lines.append(["Parts", "%d fitted" % WeaponMods.installed(examined).size()])
		if gun.missing_part != "":
			lines.append(["Can't fire", "no %s" % gun.missing_part.to_lower()])
		var jam := gun.malfunction_chance(examined.durability) * 100.0
		lines.append(["Durability", "%.1f / %.1f%s" % [examined.durability, examined.max_durability,
			", jams %.2f%% of shots" % jam if jam > 0.0 else ""]])
		var rounds := examined.rounds_loaded()
		if rounds > 0:
			var text := "%d × %s" % [rounds, examined.magazine.back().data.display_name]
			var found := examined.rounds_with_status(true)
			var pending := examined.rounds_with_status(false, true)
			if found > 0:
				text += ", %d found in raid" % found
			if pending > 0:
				text += ", %d looted this raid" % pending
			lines.append(["Loaded", text])
		else:
			lines.append(["Loaded", "empty"])
	if stats.has("caliber") and data.weapon == null:
		lines.append(["Caliber", str(stats.caliber)])
	if stats.has("damage"):
		lines.append(["Damage", str(int(stats.damage))])
	if stats.has("penetration"):
		lines.append(["Penetration", str(int(stats.penetration))])
	if stats.has("class"):
		if data.category in [ItemData.Category.ARMOR, ItemData.Category.HELMET]:
			lines.append(["Armor class", str(int(stats["class"]))])
		else:
			lines.append(["Type", str(stats["class"]).capitalize()])
	if stats.has("durability"):
		lines.append(["Durability", str(int(stats.durability))])
	if stats.has("treats"):
		var treated: Array = stats.treats.map(func(what: String) -> String: return TREATMENTS.get(what, what))
		lines.append(["Treats", ", ".join(treated)])
	if stats.has("heals"):
		lines.append(["Heals", "%d HP" % int(stats.heals)])
	if stats.has("uses"):
		lines.append(["Uses", str(int(stats.uses))])
	if stats.has("energy"):
		lines.append(["Energy", "+%d" % int(stats.energy)])
	if stats.has("hydration"):
		lines.append(["Hydration", "+%d" % int(stats.hydration)])
	if stats.has("optic"):
		var optic := VisionSystem.config.optic(int(stats.optic))
		if optic:
			lines.append(["Sight", "%s: %d° cone, ×%s range" % [optic.display_name, roundi(optic.cone_degrees), str(optic.range_multiplier)]])
	var mod_info := WeaponMods.info(data)
	if not mod_info.is_empty():
		lines.append(["Part", WeaponMods.KIND_NAMES.get(WeaponMods.kind_of(data), "Part")])
		lines.append(["Fits", fits_text(data)])
		if WeaponMods.capacity_of(data) > 0:
			lines.append(["Holds", "%d rounds" % WeaponMods.capacity_of(data)])
		for line in WeaponStats.modifier_lines(data):
			lines.append([line[0], line[1]])
		if data.rarity > 0 and not WeaponStats.modifier_lines(data).is_empty():
			lines.append(["Rarity", "bonuses ×%s" % str(WeaponStats.RARITY_SCALE[data.rarity])])
		var slots: Array = mod_info.get("slots", [])
		if not slots.is_empty():
			lines.append(["Adds slots", ", ".join(slots.map(func(slot: Dictionary) -> String: return str(slot.name)))])
		if not examined.mods.is_empty():
			lines.append(["Fitted", ", ".join(examined.mods.values().map(func(mod: ItemInstance) -> String: return mod.data.display_name))])
	if examined.contents:
		var inside := examined.contents
		lines.append(["Holds", "%d × %d grid" % [inside.size.x, inside.size.y]])
		lines.append(["Inside", "nothing" if inside.items.is_empty() else "%d items, %s" % [inside.items.size(), Settings.format_weight(inside.weight())]])
		if stats.get("secure", false):
			lines.append(["Secure", "Kept when you die. No rigs, backpacks or other containers"])
	if examined.fir:
		lines.append(["Found in raid", "Yes"])
	elif examined.fir_pending:
		lines.append(["Found in raid", "Once you extract with it"])
	else:
		lines.append(["Found in raid", "No"])
	return lines
