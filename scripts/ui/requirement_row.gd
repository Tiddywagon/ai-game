class_name RequirementRow
extends HBoxContainer
## One required item in a quest, hideout upgrade, craft or barter (DESIGN.md §9–11): the item cell,
## its name with the found-in-raid checkmark when only found-in-raid items count, and how many you have
## of how many are needed (green when you have enough). `handed` shows quest progress instead.

const MET_COLOR := Color(0.55, 0.9, 0.55)
const MISSING_COLOR := Color(0.9, 0.45, 0.35)

var requirement: Requirement


## A row for `wanted`. With `handed` >= 0 (a quest objective) it shows handed / needed, and how many
## more you have to hand over.
static func create(wanted: Requirement, handed := -1) -> RequirementRow:
	var row := RequirementRow.new()
	row.requirement = wanted
	row.add_theme_constant_override("separation", 10)
	var cell := ItemCell.new()
	cell.box = Vector2(44, 44)
	cell.item = wanted.sample()
	row.add_child(cell)
	var name := Label.new()
	name.text = "%s  ×%d" % [wanted.item_data().display_name if wanted.item_data() else wanted.item_id, wanted.count]
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name)
	if wanted.fir:
		row.add_child(FirMark.new())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var have := wanted.have()
	var count := Label.new()
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if handed >= 0:
		count.text = "%d / %d handed over  ·  you have %d%s" % [handed, wanted.count, have, " found in raid" if wanted.fir else ""]
		count.add_theme_color_override("font_color", MET_COLOR if handed >= wanted.count or have > 0 else MISSING_COLOR)
	else:
		count.text = "%d / %d" % [have, wanted.count]
		count.add_theme_color_override("font_color", MET_COLOR if have >= wanted.count else MISSING_COLOR)
	count.tooltip_text = "Only items with the found-in-raid checkmark count" if wanted.fir else "Any of these count (items without the checkmark are used first)"
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(count)
	return row
