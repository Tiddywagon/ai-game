class_name AmmoChart
extends VBoxContainer
## Compares every round of one caliber (DESIGN.md §6.4): damage, penetration, armor damage and, as six
## squares, how likely it is to go through a new piece of armor of each class (the fuller the square,
## the likelier; the colour says the same; hover a row for the numbers). The examine panel shows a
## compact chart for a gun or a round; the trader screen's AMMO tab an extended one with velocity,
## fragmentation, bleeds, recoil, accuracy and where to get each round. Rarity colours the names; a
## coloured dot marks tracers.

const FONT_SIZE := 15
const SQUARE := 16.0
const SQUARE_GAP := 4.0

## The caliber shown, the round to point out (its row gets a ▶) and the gun its velocities are for.
var caliber := ""
var highlight := ""
var gun: WeaponData
## More columns: velocity, fragmentation, bleeds, recoil, accuracy and where to get it.
var extended := false

var _grid: GridContainer


## Shows `caliber_name`'s rounds, pointing out `round_id`, with velocities out of `gun_data` if given.
func show_caliber(caliber_name: String, round_id := "", gun_data: WeaponData = null) -> void:
	caliber = caliber_name
	highlight = round_id
	gun = gun_data
	_build()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 6)
	var rounds := ItemDB.ammo_of(caliber)
	var title := Label.new()
	title.theme_type_variation = &"AccentLabel"
	title.text = "AMMO  ·  %s  ·  %d round types" % [caliber, rounds.size()]
	add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.add_theme_font_size_override("font_size", 13)
	note.text = "Squares: chance to go through new armor of class 1–6 (full = always, empty = never)"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 360
	add_child(note)
	_grid = GridContainer.new()
	_grid.name = "AmmoGrid"
	var headers := ["Round", "Damage", "Pen", "Armor"]
	if extended:
		headers += ["Velocity", "Frag", "Bleed L / H", "Recoil", "Accuracy"]
	headers.append("vs armor class")
	if extended:
		headers.append("Where to get it")
	_grid.columns = headers.size()
	_grid.add_theme_constant_override("h_separation", 16 if extended else 12)
	_grid.add_theme_constant_override("v_separation", 5)
	add_child(_grid)
	for header: String in headers:
		if header == "vs armor class":
			var numbers := ClassSquares.new()
			numbers.labels = true
			_grid.add_child(numbers)
		else:
			_grid.add_child(_label(header, true))
	for ammo in rounds:
		_add_row(ammo)
	if rounds.is_empty():
		add_child(_label("No rounds of this caliber.", true))


func _add_row(ammo: ItemData) -> void:
	var stats := ammo.stats
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.name = "Row_" + ammo.id
	var name := _label(("▶ " if ammo.id == highlight else "") + short_name(ammo), false)
	name.add_theme_color_override("font_color", Palette.rarity_color(ammo.rarity).lightened(0.2))
	name.tooltip_text = "%s  ·  %s" % [ammo.display_name, Palette.RARITY_NAMES[ammo.rarity]]
	name.mouse_filter = Control.MOUSE_FILTER_PASS
	name_row.add_child(name)
	var tracer := str(stats.get("tracer", ""))
	if tracer != "":
		var dot := _label("●", false)
		dot.add_theme_color_override("font_color", Ballistics.TRACER_COLORS.get(tracer, Color.WHITE))
		dot.tooltip_text = "Tracer (%s): you see where it goes, and so do they" % tracer
		dot.mouse_filter = Control.MOUSE_FILTER_PASS
		name_row.add_child(dot)
	_grid.add_child(name_row)
	var pellets := Weapon.pellet_count(ammo)
	_grid.add_child(_label("%d × %d" % [int(stats.get("damage", 0)), pellets] if pellets > 1 else str(int(stats.get("damage", 0))), false))
	_grid.add_child(_label(str(int(stats.get("penetration", 0))), false))
	_grid.add_child(_label("%d%%" % int(stats.get("armor_damage", 0)), false))
	if extended:
		_grid.add_child(_label("%d m/s" % roundi(WeaponStats.shot_speed(gun, ammo) if gun else float(stats.get("velocity", 0))), false))
		_grid.add_child(_label("%d%%" % roundi(float(stats.get("fragmentation", 0.0)) * 100.0), false))
		_grid.add_child(_label("%d%% / %d%%" % [roundi(float(stats.get("light_bleed", 0.0)) * 100.0), roundi(float(stats.get("heavy_bleed", 0.0)) * 100.0)], false))
		_grid.add_child(_label(signed_percent(float(stats.get("recoil", 0.0))), false))
		_grid.add_child(_label(signed_percent(float(stats.get("accuracy", 0.0))), false))
	var squares := ClassSquares.new()
	squares.ammo = ammo
	_grid.add_child(squares)
	if extended:
		var where := _label(", ".join(sources(ammo.id)), false)
		where.custom_minimum_size.x = 220
		where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(where)


func _label(text: String, header: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13 if header else FONT_SIZE)
	if header:
		label.theme_type_variation = &"DimLabel"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## The round's name without its caliber ("5.45x39 BS" → "BS").
static func short_name(ammo: ItemData) -> String:
	var caliber_name := str(ammo.stats.get("caliber", ""))
	var name := ammo.display_name
	if caliber_name != "" and name.begins_with(caliber_name + " "):
		return name.substr(caliber_name.length() + 1)
	return name


## "+5%", "−15%" or "—".
static func signed_percent(value: float) -> String:
	if is_zero_approx(value):
		return "—"
	return ("%+d%%" % roundi(value)).replace("-", "−")


## Where round `id` comes from: the traders that sell or barter it (with the loyalty level needed;
## "(locked)" after one who doesn't trade with you yet), the hideout crafts that make it (with the
## station level), else loot only.
static func sources(id: String) -> Array[String]:
	var result: Array[String] = []
	for trader: String in TraderTable.ids():
		var offers := Trading.offers(trader)
		var levels: Array[int] = []
		for offer: Dictionary in offers.get("buy", []):
			if str(offer.item) == id:
				levels.append(Trading.offer_level(offer))
		for offer: Dictionary in offers.get("barters", []):
			if str(Trading.barter_reward(offer).item) == id:
				levels.append(Trading.offer_level(offer))
		if not levels.is_empty():
			result.append("%s LL%d%s" % [TraderTable.display_name(trader), levels.min(), TraderTable.locked_suffix(trader)])
	for station in Hideout.stations():
		for entry in Hideout.all_crafts(station):
			if str(entry[1].output.item) == id:
				result.append("%s %d" % [station.name, entry[0]])
	if result.is_empty():
		result.append("Found in raid")
	return result


## Six squares, one per armor class: filled to the round's chance to go through new armor of that
## class, coloured by it. With `labels`, the class numbers instead (the header).
class ClassSquares:
	extends Control

	var ammo: ItemData
	var labels := false

	func _init() -> void:
		custom_minimum_size = Vector2(6.0 * AmmoChart.SQUARE + 5.0 * AmmoChart.SQUARE_GAP, AmmoChart.SQUARE)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _ready() -> void:
		if ammo:
			var lines: Array[String] = []
			for armor_class in range(1, 7):
				lines.append("Class %d: %d%% to penetrate" % [armor_class, roundi(ArmorRules.effectiveness(ammo, armor_class) * 100.0)])
			tooltip_text = "%s vs new armor\n%s" % [ammo.display_name, "\n".join(lines)]

	func chance(armor_class: int) -> float:
		return ArmorRules.effectiveness(ammo, armor_class) if ammo else 0.0

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for i in 6:
			var rect := Rect2(Vector2(i * (AmmoChart.SQUARE + AmmoChart.SQUARE_GAP), 0.0), Vector2(AmmoChart.SQUARE, AmmoChart.SQUARE))
			if labels:
				draw_string(font, Vector2(rect.position.x + 4.0, AmmoChart.SQUARE - 3.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
				continue
			var value := chance(i + 1)
			var color := Palette.effectiveness_color(value)
			draw_rect(rect, Color(color, 0.14))
			if value > 0.0:
				var filled := rect.size.y * value
				draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - filled), Vector2(rect.size.x, filled)), color)
			draw_rect(rect, Color(color, 0.85), false, 1.0)
