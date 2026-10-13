class_name ItemExaminePanel
extends PanelContainer
## Examining an item (DESIGN.md §7): its icon, name in its rarity colour, rarity and category, size,
## weight, value and stack, the stats that matter for its kind (a gun's fire rate and magazine, ammo
## damage and penetration, armor class, what meds treat, a container's grid and what's in it) and its
## description, and whether it's found in raid (with the checkmark). Guns show their stats with their
## parts fitted and their durability; weapon parts what they change and which guns they fit. Guns with
## rounds loaded can be unloaded from here, and out of raid MODIFY opens the modding screen. Guns and
## rounds also show an ammo chart beside the stats: every round of the caliber compared (AmmoChart).
## Armor shows its class, what it covers and its durability; helmets their face shield and headset
## (TAKE OFF out of raid); upgradable gear its level, and out of raid UPGRADE opens GearUpgradePanel.
## Meds, stims, food and drink (DESIGN.md §13.7) show what they treat, their HP pool or uses left, use
## time, energy and hydration and their effects and side effects; USE uses one (in a raid: on you,
## over its use time; out of raid: food and drink only). Disabled, its tooltip says why.
## Right-click any item in the inventory to open it; Esc or CLOSE hides it.

signal closed
## UNLOAD pressed for a gun.
signal unload_requested(item: ItemInstance)
## MODIFY pressed for a gun.
signal modify_requested(item: ItemInstance)
## UPGRADE pressed for upgradable gear.
signal upgrade_requested(item: ItemInstance)
## TAKE OFF pressed for the part in slot `path` of `item` (a helmet's face shield or headset).
signal part_removal_requested(item: ItemInstance, path: String)
## USE pressed for a med, stim, food or drink.
signal use_requested(item: ItemInstance)

const TREATMENTS := {"light_bleed": "light bleed", "heavy_bleed": "heavy bleed", "fracture": "fracture",
	"pain": "pain", "blacked": "blacked limb"}

var item: ItemInstance
## Guns can be modded from here (out of raid).
var can_modify := false
## Why an item can't be used right now ("" if it can): set by the inventory. Unset: no USE button.
var use_check: Callable

var _icon: TextureRect
var _name: Label
var _subtitle: Label
var _stats: GridContainer
var _description: Label
var _chart: AmmoChart
var _unload: Button
var _modify: Button
var _upgrade: Button
var _use: Button
var _parts: VBoxContainer


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
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 32)
	rows.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 28)
	_stats.add_theme_constant_override("v_separation", 4)
	left.add_child(_stats)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = 420
	_description.theme_type_variation = &"DimLabel"
	left.add_child(_description)
	_parts = VBoxContainer.new()
	_parts.name = "GearParts"
	left.add_child(_parts)
	_chart = AmmoChart.new()
	_chart.name = "AmmoChart"
	body.add_child(_chart)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	_use = Button.new()
	_use.name = "UseButton"
	_use.text = "USE"
	_use.custom_minimum_size = Vector2(120, 36)
	_use.pressed.connect(func() -> void: use_requested.emit(item))
	buttons.add_child(_use)
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
	_upgrade = Button.new()
	_upgrade.name = "UpgradeButton"
	_upgrade.text = "UPGRADE"
	_upgrade.custom_minimum_size = Vector2(120, 36)
	_upgrade.tooltip_text = "Raise its level at the Workbench or Ragman: more durability, room or hearing"
	_upgrade.pressed.connect(func() -> void: upgrade_requested.emit(item))
	buttons.add_child(_upgrade)
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
	_name.text = item.title()
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
	_upgrade.visible = can_modify and GearUpgrades.is_upgradable(data)
	_use.visible = use_check.is_valid() and Consumables.is_consumable(data)
	if _use.visible:
		var reason: String = use_check.call(item)
		_use.disabled = reason != ""
		_use.tooltip_text = reason if reason != "" else "Takes %.1f s" % Consumables.use_time(data)
	_build_parts()
	_description.text = data.description
	_description.visible = data.description != ""
	_chart.visible = data.weapon != null or data.category == ItemData.Category.AMMO
	if data.weapon:
		_chart.show_caliber(data.weapon.caliber, item.loaded_ammo, WeaponStats.build(item, GameState.skills))
	elif data.category == ItemData.Category.AMMO:
		_chart.show_caliber(str(data.stats.get("caliber", "")), data.id)
	show()
	_fit.call_deferred()


## A helmet's face shield and headset slots: what's fitted, with TAKE OFF out of raid.
func _build_parts() -> void:
	for child in _parts.get_children():
		_parts.remove_child(child)
		child.queue_free()
	if item.is_gun() or not WeaponMods.has_slots(item):
		_parts.hide()
		return
	_parts.show()
	for entry in WeaponMods.walk(item):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.theme_type_variation = &"DimLabel"
		label.text = str(entry.slot.get("name", entry.path))
		label.custom_minimum_size.x = 110
		row.add_child(label)
		var value := Label.new()
		value.text = (entry.mod as ItemInstance).title() if entry.mod else "empty (drop one on the helmet)"
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value)
		if entry.mod and can_modify:
			var take_off := Button.new()
			take_off.name = "TakeOff_" + str(entry.path)
			take_off.text = "TAKE OFF"
			take_off.custom_minimum_size = Vector2(110, 30)
			var path := str(entry.path)
			take_off.pressed.connect(func() -> void: part_removal_requested.emit(item, path))
			row.add_child(take_off)
		_parts.add_child(row)


## Shrinks to the new content once it's laid out, centred over the screen.
func _fit() -> void:
	reset_size()
	position = ((get_parent_area_size() - size) / 2.0).round()


func close() -> void:
	hide()
	closed.emit()


## Which guns (or helmets, for a face shield) part `data` fits: their names, or any with a slot for it.
static func fits_text(data: ItemData) -> String:
	var platforms: Array = WeaponMods.info(data).get("fits", [])
	var gear := WeaponMods.is_gear_mod(data)
	if platforms.is_empty():
		return "Any helmet with a %s slot" % WeaponMods.KIND_NAMES.get(WeaponMods.kind_of(data), "").to_lower() if gear else "Any gun with a slot for it"
	var names: Array[String] = []
	for each in ItemDB.all_items():
		var platform := str(each.stats.get("platform", "")) if gear and each.category == ItemData.Category.HELMET else (each.weapon.platform if each.weapon else "")
		if platform != "" and platform in platforms:
			names.append(each.display_name)
	names.sort()
	return ", ".join(names) if not names.is_empty() else ", ".join(platforms)


## A round's own stats beyond damage and penetration: velocity, fragmentation, bleeds, recoil,
## accuracy, ricochet, pellets, tracer, noise and the guns that fire it.
static func round_lines(data: ItemData) -> Array:
	var stats := data.stats
	var lines := []
	if stats.has("velocity"):
		lines.append(["Velocity", "%d m/s" % int(stats.velocity)])
	if stats.has("fragmentation"):
		lines.append(["Fragmentation", "%d%% (more damage and a bleed)" % roundi(float(stats.fragmentation) * 100.0)])
	if stats.has("light_bleed"):
		lines.append(["Bleed chance", "%d%% light, %d%% heavy" % [roundi(float(stats.light_bleed) * 100.0), roundi(float(stats.get("heavy_bleed", 0.0)) * 100.0)]])
	if float(stats.get("recoil", 0.0)) != 0.0:
		lines.append(["Recoil", AmmoChart.signed_percent(float(stats.recoil))])
	if float(stats.get("accuracy", 0.0)) != 0.0:
		lines.append(["Accuracy", AmmoChart.signed_percent(float(stats.accuracy))])
	if stats.has("ricochet"):
		lines.append(["Ricochet chance", "%d%% off armor it doesn't get through" % roundi(float(stats.ricochet) * 100.0)])
	if stats.has("pellet_spread"):
		lines.append(["Pellet spread", "%s°" % str(stats.pellet_spread)])
	if str(stats.get("tracer", "")) != "":
		lines.append(["Tracer", "%s: gives your position away" % str(stats.tracer).capitalize()])
	if stats.has("noise"):
		lines.append(["Heard", "%d%% as far as other rounds" % roundi(float(stats.noise) * 100.0)])
	if stats.has("caliber"):
		lines.append(["Fits", guns_for_caliber(str(stats.caliber))])
	return lines


## The guns that fire `caliber`, by name.
static func guns_for_caliber(caliber: String) -> String:
	var names: Array[String] = []
	for each in ItemDB.all_items():
		if each.weapon and each.weapon.caliber == caliber:
			names.append(each.display_name)
	names.sort()
	return ", ".join(names) if not names.is_empty() else "No gun yet"


## A med, stim, food or drink: what it treats (and what that costs a medkit), its HP pool or uses left,
## surgery, use time, energy and hydration, and each effect (side effects marked).
static func consumable_lines(examined: ItemInstance) -> Array:
	var data := examined.data
	var stats := data.stats
	var lines := []
	if stats.has("type"):
		lines.append(["Type", {"stim": "Stimulant", "medkit": "Medkit", "surgical": "Surgical kit", "hemostat": "Hemostatic"}.get(
			str(stats.type), str(stats.type).capitalize())])
	var treated: Array = Consumables.treats(data).map(func(what: String) -> String:
		var price := Consumables.cost(data, what)
		return TREATMENTS.get(what, what) + (" (%d HP)" % roundi(price) if price > 0.0 else ""))
	if not treated.is_empty():
		lines.append(["Treats", ", ".join(treated)])
	if Consumables.is_medkit(data):
		lines.append(["HP pool", "%d / %d: heals one body part a use" % [ceili(examined.charges), int(stats.hp)]])
	elif Consumables.max_charges(data) > 1.0:
		lines.append(["Uses", "%d / %d" % [roundi(examined.charges), int(stats.uses)]])
	if stats.has("restore"):
		lines.append(["Surgery", "back at %d%% HP; the part loses %d%% of its max HP for the raid" % [
			roundi(float(stats.restore) * 100.0), roundi(float(stats.get("max_hp_loss", 0.0)) * 100.0)]])
	lines.append(["Use time", "%.1f s, walking at %d%% speed" % [Consumables.use_time(data), roundi(Consumables.move_multiplier(data) * 100.0)]])
	for key in ["energy", "hydration"]:
		if stats.has(key) and not Stims.is_stim(data):
			lines.append([key.capitalize(), "%+d" % int(stats[key])])
	if Stims.is_stim(data):
		lines.append_array(stim_lines(data))
		return lines
	for effect: Dictionary in stats.get("effects", []):
		var side := bool(effect.get("side", false))
		var text := "%s for %s" % [BodyHealth.effect_label(str(effect.kind), float(effect.get("value", 0.0))),
			BodyHealth._clock(float(effect.get("duration", 0.0)))]
		if float(effect.get("delay", 0.0)) > 0.0:
			text += ", after %s" % BodyHealth._clock(float(effect.delay))
		lines.append(["Side effect" if side else "Effect", text])
	return lines


## A stim (DESIGN.md §13.8): when it kicks in, each buff with its number and duration, each side
## effect (during or after the buffs; shortened by your Stim resistance), and the overdose rule.
static func stim_lines(data: ItemData) -> Array:
	var lines := []
	var delay := Stims.buff_delay(data)
	lines.append(["Kicks in", "%d s after the injection" % roundi(delay) if delay > 0.0 else "at once"])
	var shorten := Stims.side_effect_multiplier()
	for effect: Dictionary in data.stats.get("effects", []):
		var side := bool(effect.get("side", false))
		var seconds := float(effect.get("duration", 0.0))
		var text := Stims.effect_label(str(effect.kind), float(effect.get("value", 0.0)))
		if not side:
			text += " for %s" % BodyHealth._clock(seconds)
			lines.append(["Buff", text])
			continue
		text += " for %s" % BodyHealth._clock(seconds * shorten)
		if shorten < 1.0:
			text += " (%s before Stim resistance)" % BodyHealth._clock(seconds)
		text += ", after the buffs" if str(effect.get("when", "")) == "after" else ", during the buffs"
		lines.append(["Side effect", text])
	for key in ["energy", "hydration"]:
		var amount := float(data.stats.get(key, 0.0))
		if amount != 0.0:
			lines.append(["Side effect" if amount < 0.0 else "Buff", "%s %+d at once" % [key.capitalize(), roundi(amount)]])
	lines.append(["Overdose", "%d or more stims within %d min: HP drain, tremor, blurred vision" % [Stims.overdose_threshold(),
		roundi(float(Stims.config().get("overdose", {}).get("window", 300.0)) / 60.0)]])
	return lines


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
		var gun := WeaponStats.build(examined, GameState.skills)
		lines.append(["Type", gun.class_title()])
		lines.append(["Caliber", "%s (%d round types)" % [gun.caliber, ItemDB.ammo_of(gun.caliber).size()]])
		lines.append(["Fire rate", "%d rpm, %s" % [gun.fire_rate, "automatic" if gun.automatic else "semi-automatic"]])
		lines.append(["Magazine", "%d rounds" % gun.magazine_size if gun.magazine_size > 0 else "none fitted"])
		lines.append(["Reload", "%.1f s (empty %.1f s)" % [gun.reload_time, gun.empty_reload_time]])
		lines.append(["Recoil", "%.2f° climb, ±%.2f° side a shot, recovers %.1f / s" % [gun.vertical_recoil, gun.horizontal_recoil, gun.recoil_recovery]])
		lines.append(["Spread", "%.2f° aimed, +%.2f° from the hip, +%.2f° a shot up to +%.1f°" % [gun.base_spread, gun.hip_spread,
			gun.bloom_per_shot, gun.max_bloom]])
		lines.append(["Handling", "ergonomics %d, sway %.2f°" % [gun.ergonomics, gun.sway]])
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
		var pellets := Weapon.pellet_count(data)
		lines.append(["Damage", "%d × %d pellets" % [int(stats.damage), pellets] if pellets > 1 else str(int(stats.damage))])
	if stats.has("penetration"):
		lines.append(["Penetration", str(int(stats.penetration))])
	if stats.has("armor_damage"):
		lines.append(["Armor damage", "%d%%" % int(stats.armor_damage)])
	if data.category == ItemData.Category.AMMO:
		lines.append_array(round_lines(data))
	if stats.has("class") and data.weapon == null:
		if examined.is_armor():
			lines.append(["Armor class", "%d (stops penetration below %d when new)" % [int(stats["class"]), roundi(ArmorRules.resistance(int(stats["class"])))]])
			lines.append(["Protects", ", ".join(stats.get("zones", []).map(func(zone: String) -> String: return zone.capitalize()))])
			if stats.has("material"):
				lines.append(["Material", str(stats.material).capitalize()])
			lines.append(["Blunt damage", "%d%% of a stopped round's" % roundi(GearUpgrades.blunt(examined) * 100.0)])
			if float(stats.get("ricochet", 0.0)) > 0.0:
				lines.append(["Ricochet", "×%.2f the round's chance" % GearUpgrades.ricochet(examined)])
		else:
			lines.append(["Type", str(stats["class"]).capitalize()])
	if examined.is_armor():
		var worn := examined.durability / maxf(examined.max_durability, 1.0)
		lines.append(["Durability", "%.1f / %.1f%s" % [examined.durability, examined.max_durability,
			", stops nothing" if examined.durability <= 0.0 else (", resists %d" % roundi(ArmorRules.resistance(int(stats["class"]), worn)) if worn < 1.0 else "")]])
	elif stats.has("durability"):
		lines.append(["Durability", str(int(stats.durability))])
	if Consumables.is_consumable(data):
		lines.append_array(consumable_lines(examined))
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
		if not WeaponStats.profile_of(data).is_empty():
			lines.append(["Rarity strength", "%d%% per bonus (%s)" % [roundi(WeaponStats.rarity_strength(data.rarity)), Palette.RARITY_NAMES[data.rarity]]])
		elif mod_info.get("standard", false):
			lines.append(["Standard part", "the gun's stats are measured with it"])
		var slots: Array = mod_info.get("slots", [])
		if not slots.is_empty():
			lines.append(["Adds slots", ", ".join(slots.map(func(slot: Dictionary) -> String: return str(slot.name)))])
		if not examined.mods.is_empty():
			lines.append(["Fitted", ", ".join(examined.mods.values().map(func(mod: ItemInstance) -> String: return mod.data.display_name))])
	if stats.has("hearing"):
		var hearing := GearUpgrades.hearing(examined)
		var text := "%+d%% (sounds heard %s)" % [roundi(hearing * 100.0), "further" if hearing > 0.0 else "less far"]
		if not examined.mods.is_empty():
			var total := hearing
			for part in WeaponMods.installed(examined):
				total += GearUpgrades.hearing(part)
			text = "%+d%% on its own, %+d%% with its face shield and headset" % [roundi(hearing * 100.0), roundi(total * 100.0)]
		if not is_zero_approx(hearing) or not examined.mods.is_empty():
			lines.append(["Hearing", text.replace("-", "−")])
	if GearUpgrades.is_upgradable(data):
		lines.append(["Upgrade", "+%d of +%d (%s)" % [examined.upgrade_level, GearUpgrades.max_level(data), Palette.RARITY_NAMES[data.rarity]]])
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
