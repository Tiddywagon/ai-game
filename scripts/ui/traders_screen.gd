extends MenuScreen
## TRADERS screen (DESIGN.md §10, §11, §16.2): every trader with your loyalty level, reputation and
## what the next level needs, and tabs to BUY (roubles or dollars), BARTER (items for an item) and do
## their TASKS (accept, hand over, turn in). Everything you get goes to the stash and is never found in
## raid. Requirements marked with the found-in-raid checkmark only take items that have it (Trading,
## QuestLog). Each deal saves the game.

const TRADERS := [
	{"id": "prapor", "name": "Prapor", "specialty": "Eastern weapons and ammo", "currency": "Roubles", "unique": "Insurance: cheap, slow"},
	{"id": "therapist", "name": "Therapist", "specialty": "Meds, food and valuables", "currency": "Roubles", "unique": "Pays the most for valuables"},
	{"id": "skier", "name": "Skier", "specialty": "Black market and attachments", "currency": "Roubles and dollars", "unique": "Cheap barters"},
	{"id": "peacekeeper", "name": "Peacekeeper", "specialty": "Western weapons", "currency": "Dollars", "unique": "Pays well for weapons"},
	{"id": "mechanic", "name": "Mechanic", "specialty": "Attachments and weapon parts", "currency": "Roubles", "unique": "Gunsmith quests"},
	{"id": "ragman", "name": "Ragman", "specialty": "Clothing, rigs, backpacks and armor", "currency": "Roubles", "unique": "Cosmetics"},
	{"id": "jaeger", "name": "Jaeger", "specialty": "Survival gear and hunting rifles", "currency": "Roubles", "unique": "Unlocked by a quest", "locked": true},
]
## What each loyalty level needs: player level, reputation, roubles spent (DESIGN.md §10).
const LOYALTY := {2: [15, 0.20, 750_000], 3: [25, 0.35, 1_500_000], 4: [35, 0.50, 2_500_000]}

## Item cells in offer rows: pixels per grid cell, and the most room one may take.
const OFFER_CELL := 30.0
const OFFER_MAX := Vector2(150, 64)

var _buttons: Array[Button] = []
var _trader: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(close)
	var group := ButtonGroup.new()
	for trader: Dictionary in TRADERS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 56
		var loyalty: Dictionary = GameState.trader_loyalty[trader.id]
		button.text = "%s   ·   %s" % [trader.name, "LOCKED" if trader.get("locked", false) else "LL%d" % loyalty.level]
		button.pressed.connect(_show.bind(trader))
		button.focus_entered.connect(_show.bind(trader))
		%TraderList.add_child(button)
		_buttons.append(button)
	_buttons[0].grab_focus.call_deferred()
	_show(TRADERS[0])


func _show(trader: Dictionary) -> void:
	if trader == _trader:
		return
	_trader = trader
	_buttons[TRADERS.find(trader)].set_pressed_no_signal(true)
	_refresh()


## Redraws the selected trader: info, loyalty, money and the three tabs (keeps the open tab).
func _refresh() -> void:
	var trader := _trader
	%Money.text = "%s      %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")]
	var tab: int = %Tabs.current_tab
	for child in %Tabs.get_children():
		%Tabs.remove_child(child)
		child.queue_free()
	var loyalty: Dictionary = GameState.trader_loyalty[trader.id]
	%TraderName.text = trader.name.to_upper()
	%TraderInfo.text = "%s\nCurrency: %s\n%s" % [trader.specialty, trader.currency, trader.unique]
	if trader.get("locked", false):
		%Loyalty.text = "Locked. Complete his introduction quest to trade with Jaeger."
		%Tabs.hide()
		return
	%Tabs.show()
	_build_buy(trader)
	_build_barters(trader)
	_build_tasks(trader)
	%Tabs.current_tab = clampi(tab, 0, %Tabs.get_tab_count() - 1)
	var lines := ["Loyalty level %d  ·  reputation %.2f  ·  spent %s" % [loyalty.level, loyalty.reputation, UiFormat.money(loyalty.spent)]]
	var next: int = loyalty.level + 1
	if LOYALTY.has(next):
		var need: Array = LOYALTY[next]
		lines.append("Next level (LL%d) needs: player level %d, reputation %.2f, %s spent with %s." % [
			next, need[0], need[1], UiFormat.money(need[2]), trader.name])
	else:
		lines.append("Highest loyalty level reached.")
	%Loyalty.text = "\n".join(lines)


func _build_buy(trader: Dictionary) -> void:
	var rows := _add_tab("BUY")
	for offer: Dictionary in Trading.offers(trader.id).get("buy", []):
		var item := ItemInstance.create(str(offer.item), int(offer.get("count", 1)))
		if item == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.add_child(_cell(item))
		var name := Label.new()
		name.text = "%s%s\n%s" % [item.data.display_name, "  ×%d" % item.count if item.count > 1 else "",
			UiFormat.money(int(offer.price), str(offer.get("currency", "RUB")))]
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name)
		row.add_child(_action_button("BUY", Trading.buy_block_reason(offer), func() -> String: return Trading.buy(trader.id, offer)))
		rows.add_child(row)
		rows.add_child(HSeparator.new())
	if rows.get_child_count() == 0:
		rows.add_child(_note("Nothing for sale."))


func _build_barters(trader: Dictionary) -> void:
	var rows := _add_tab("BARTER")
	for offer: Dictionary in Trading.offers(trader.id).get("barters", []):
		var reward := Trading.barter_reward(offer)
		var item := ItemInstance.create(str(reward.item), int(reward.get("count", 1)))
		if item == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var give := VBoxContainer.new()
		give.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for wanted in Trading.barter_requirements(offer):
			give.add_child(RequirementRow.create(wanted))
		row.add_child(give)
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 28)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(arrow)
		var reward_box := VBoxContainer.new()
		reward_box.custom_minimum_size.x = 170
		reward_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reward_box.add_child(_cell(item))
		var name := Label.new()
		name.text = item.data.display_name + ("  ×%d" % item.count if item.count > 1 else "")
		reward_box.add_child(name)
		row.add_child(reward_box)
		row.add_child(_action_button("TRADE", Trading.barter_block_reason(offer), func() -> String: return Trading.barter(offer)))
		rows.add_child(row)
		rows.add_child(HSeparator.new())
	if rows.get_child_count() == 0:
		rows.add_child(_note("No barters."))


func _build_tasks(trader: Dictionary) -> void:
	var rows := _add_tab("TASKS")
	for quest in QuestLog.for_trader(trader.id):
		var state := QuestLog.state(quest)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var title := Label.new()
		title.theme_type_variation = &"AccentLabel"
		title.text = "%s  ·  %s" % [quest.name.to_upper(), {"locked": "LOCKED", "available": "AVAILABLE", "active": "ACTIVE",
			"ready": "READY TO TURN IN", "completed": "COMPLETED"}[state]]
		box.add_child(title)
		if state == "locked":
			box.add_child(_note("Finish %s first." % ", ".join(quest.get("requires", []).map(func(id: String) -> String:
				return QuestLog.find(id).get("name", id)))))
			rows.add_child(box)
			rows.add_child(HSeparator.new())
			continue
		box.add_child(_note(quest.get("description", "")))
		for i in quest.objectives.size():
			var wanted := QuestLog.objective(quest, i)
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 12)
			var requirement := RequirementRow.create(wanted, QuestLog.progress(quest, i) if state != "available" else -1)
			requirement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(requirement)
			if state == "active" and QuestLog.progress(quest, i) < wanted.count:
				var reason := "" if wanted.have() > 0 else ("No found-in-raid %s" % wanted.item_data().display_name if wanted.fir else "None in your stash")
				line.add_child(_action_button("HAND OVER", reason, func() -> String:
					return "" if QuestLog.hand_in(quest, i) > 0 else "Nothing to hand over"))
			box.add_child(line)
		box.add_child(_note("Rewards: " + _rewards_text(quest.get("rewards", {}))))
		match state:
			"available":
				box.add_child(_action_button("ACCEPT", "", func() -> String: return "" if QuestLog.accept(quest) else "Can't accept"))
			"ready":
				box.add_child(_action_button("TURN IN", QuestLog.complete_block_reason(quest), func() -> String: return QuestLog.complete(quest)))
		rows.add_child(box)
		rows.add_child(HSeparator.new())
	if rows.get_child_count() == 0:
		rows.add_child(_note("No tasks yet."))


func _rewards_text(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	if int(rewards.get("roubles", 0)) > 0:
		parts.append(UiFormat.money(int(rewards.roubles)))
	if int(rewards.get("xp", 0)) > 0:
		parts.append("%s XP" % UiFormat.thousands(int(rewards.xp)))
	if float(rewards.get("reputation", 0.0)) > 0.0:
		parts.append("+%.2f reputation" % float(rewards.reputation))
	for reward in rewards.get("items", []):
		var data := ItemDB.get_item(str(reward.item))
		if data:
			parts.append(("%d × " % int(reward.count) if int(reward.get("count", 1)) > 1 else "") + data.display_name)
	return "  ·  ".join(parts) + "  (not found in raid)"


## A tab of `title` with a scrolling list; returns the list.
func _add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	%Tabs.add_child(scroll)
	return rows


func _cell(item: ItemInstance) -> ItemCell:
	var cell := ItemCell.new()
	var fit := Vector2(item.data.size) * OFFER_CELL
	cell.box = fit * minf(1.0, minf(OFFER_MAX.x / fit.x, OFFER_MAX.y / fit.y))
	cell.item = item
	return cell


## A button that runs `action` (returns "" or why it failed), saves and refreshes. Disabled with the
## reason as its tooltip when `blocked` isn't "".
func _action_button(text: String, blocked: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.disabled = blocked != ""
	button.tooltip_text = blocked
	button.pressed.connect(func() -> void:
		var result: String = action.call()
		if result == "":
			SaveManager.save_game()
		%Status.text = result if result != "" else "Done."
		_refresh.call_deferred())
	return button


func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
