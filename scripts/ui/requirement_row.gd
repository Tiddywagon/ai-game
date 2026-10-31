class_name RequirementRow
extends HBoxContainer
## One required item in a quest, hideout upgrade, craft or barter (DESIGN.md §9–11): the item cell,
## its name with the found-in-raid checkmark when only found-in-raid items count, and how many you have
## of how many are needed (green when you have enough). `handed` shows quest progress instead. Barters
## count the stash only, and only whole food, drink and meds (`stash_only`), and end the row with a green
## check or a red cross (MetMark).

const MET_COLOR := Color(0.55, 0.9, 0.55)
const MISSING_COLOR := Color(0.9, 0.45, 0.35)

var requirement: Requirement


## A row for `wanted`. With `handed` >= 0 (a quest objective) it shows handed / needed, and how many
## more you have to hand over. With `stash_only` (a barter) it counts what's in the stash and adds the
## check or cross.
static func create(wanted: Requirement, handed := -1, stash_only := false) -> RequirementRow:
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
	var have := wanted.have_in_stash() if stash_only else wanted.have()
	var count := Label.new()
	count.name = "Count"
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if handed >= 0:
		count.text = "%d / %d handed over  ·  you have %d%s" % [handed, wanted.count, have, " found in raid" if wanted.fir else ""]
		count.add_theme_color_override("font_color", MET_COLOR if handed >= wanted.count or have > 0 else MISSING_COLOR)
	else:
		count.text = "%d / %d" % [have, wanted.count]
		count.add_theme_color_override("font_color", MET_COLOR if have >= wanted.count else MISSING_COLOR)
	count.tooltip_text = "Only items with the found-in-raid checkmark count" if wanted.fir else "Any of these count (items without the checkmark are used first)"
	if stash_only:
		var data := wanted.item_data()
		var partial := data != null and (Consumables.is_consumable(data) or Keys.is_key(data))
		count.tooltip_text = "In your stash%s. %s" % [", whole ones only (part-used ones don't count)" if partial else "", count.tooltip_text]
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(count)
	if stash_only:
		var mark := MetMark.new()
		mark.name = "MetMark"
		mark.met = have >= wanted.count
		row.add_child(mark)
	return row
