class_name GearUpgradeRow
extends HBoxContainer
## One gear upgrade on offer (DESIGN.md §12.2): the item, its level and what the next one changes, what
## `source` (a trader or the Workbench) charges in roubles and barter items, and UPGRADE (disabled, with
## the reason as its tooltip, when it can't be done). Used by the upgrade dialog from the examine panel,
## Ragman's UPGRADES tab and the Workbench in the hideout.

## Emitted after an upgrade (the game has been saved).
signal upgraded(item: ItemInstance)

const CELL_BOX := Vector2(110, 64)

var item: ItemInstance
var source := ""
## Show the item's icon (lists of several items do; the dialog for one item doesn't).
var show_icon := true


static func create(upgrade_item: ItemInstance, upgrade_source: String, with_icon := true) -> GearUpgradeRow:
	var row := GearUpgradeRow.new()
	row.item = upgrade_item
	row.source = upgrade_source
	row.show_icon = with_icon
	row.name = "Upgrade_%s_%s" % [upgrade_item.data.id, upgrade_source]
	return row


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	_build()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if show_icon:
		var cell := ItemCell.new()
		var fit := Vector2(item.data.size) * 30.0
		cell.box = fit * minf(1.0, minf(CELL_BOX.x / fit.x, CELL_BOX.y / fit.y))
		cell.item = item
		add_child(cell)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	add_child(info)
	var max_level := GearUpgrades.max_level(item.data)
	var title := Label.new()
	title.text = "%s%s" % [item.title(), "   →   +%d" % (item.upgrade_level + 1) if item.upgrade_level < max_level else "   ·   fully upgraded"]
	title.add_theme_color_override("font_color", Palette.rarity_color(item.data.rarity).lightened(0.25))
	info.add_child(title)
	var limit := GearUpgrades.source_max_level(source)
	var where := _dim("%s  ·  level +%d of +%d (%s)  ·  %s" % [GearUpgrades.source_name(source).to_upper(), item.upgrade_level, max_level,
		Palette.RARITY_NAMES[item.data.rarity], "upgrades to +%d here" % limit if limit > 0 else "can't upgrade yet"])
	info.add_child(where)
	var changes: Array = GearUpgrades.next_changes(item)
	if not changes.is_empty():
		info.add_child(_dim("  ·  ".join(changes.map(func(row: Array) -> String: return "%s %s → %s" % row))))
	if item.upgrade_level >= max_level:
		return
	var price := GearUpgrades.cost(item, source)
	var cost := VBoxContainer.new()
	cost.add_theme_constant_override("separation", 2)
	cost.custom_minimum_size.x = 300
	var money := Label.new()
	money.text = UiFormat.money(int(price.roubles))
	money.add_theme_color_override("font_color", RequirementRow.MET_COLOR if GameState.roubles >= int(price.roubles) else Color(0.95, 0.45, 0.4))
	cost.add_child(money)
	for wanted: Requirement in price.requirements:
		cost.add_child(RequirementRow.create(wanted))
	add_child(cost)
	var button := Button.new()
	button.name = "UpgradeButton"
	button.text = "UPGRADE"
	button.custom_minimum_size = Vector2(140, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var blocked := GearUpgrades.block_reason(item, source)
	button.disabled = blocked != ""
	button.tooltip_text = blocked
	button.pressed.connect(_on_upgrade)
	add_child(button)


func _on_upgrade() -> void:
	if GearUpgrades.upgrade(item, source) != "":
		return
	SaveManager.save_game()
	upgraded.emit(item)


func _dim(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 360
	return label
