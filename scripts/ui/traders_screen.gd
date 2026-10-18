extends MenuScreen
## TRADERS screen (DESIGN.md §10, §11, §16.2): every trader with your loyalty level, reputation and
## what the next level needs, and tabs to BUY (roubles or dollars), BARTER (items for an item), do
## their TASKS (accept, hand over, turn in), compare AMMO (every round of the gun in hand, or of any
## caliber: AmmoChart), at Ragman, UPGRADE gear (GearUpgradeRow) and, at the insurers (Prapor and
## Therapist: Insurance), INSURE the gear you'd take into a raid. Offers above your loyalty level with a trader show the level they need.
## Everything you get goes to the stash and is never found in raid. Requirements marked with the
## found-in-raid checkmark only take items that have it (Trading, QuestLog). Each deal saves the game.
## Right-click an item (long-press on touch: TouchGestures) to examine it.

const TRADERS := [
	{"id": "prapor", "name": "Prapor", "specialty": "Eastern weapons and ammo", "currency": "Roubles", "unique": "Insurance: cheap, slow"},
	{"id": "therapist", "name": "Therapist", "specialty": "Meds, food and valuables", "currency": "Roubles", "unique": "Insurance: dearer, faster · pays the most for valuables"},
	{"id": "skier", "name": "Skier", "specialty": "Black market and attachments", "currency": "Roubles and dollars", "unique": "Cheap barters"},
	{"id": "peacekeeper", "name": "Peacekeeper", "specialty": "Western weapons", "currency": "Dollars", "unique": "Pays well for weapons"},
	{"id": "mechanic", "name": "Mechanic", "specialty": "Attachments and weapon parts", "currency": "Roubles", "unique": "Gunsmith quests"},
	{"id": "ragman", "name": "Ragman", "specialty": "Clothing, rigs, backpacks and armor", "currency": "Roubles", "unique": "Cosmetics"},
	{"id": "jaeger", "name": "Jaeger", "specialty": "Survival gear and hunting rifles", "currency": "Roubles", "unique": "Unlocked by a quest", "locked": true},
]

## Item cells in offer rows: pixels per grid cell, and the most room one may take.
const OFFER_CELL := 30.0
const OFFER_MAX := Vector2(150, 64)

var _buttons: Array[Button] = []
var _trader: Dictionary = {}
## The caliber the AMMO tab compares ("" = the gun in hand's).
var _ammo_caliber := ""
var _examine: ItemExaminePanel


func _ready() -> void:
	%BackButton.pressed.connect(close)
	var group := ButtonGroup.new()
	for trader: Dictionary in TRADERS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 56
		Trading.update_loyalty(trader.id)
		var loyalty: Dictionary = GameState.trader_loyalty[trader.id]
		button.text = "%s   ·   %s" % [trader.name, "LOCKED" if trader.get("locked", false) else "LL%d" % loyalty.level]
		button.pressed.connect(_show.bind(trader))
		button.focus_entered.connect(_show.bind(trader))
		%TraderList.add_child(button)
		_buttons.append(button)
	_buttons[0].grab_focus.call_deferred()
	_examine = ItemExaminePanel.new()
	_examine.name = "ItemExaminePanel"
	_examine.can_set_hotkey = false
	add_child(_examine)
	var gestures := TouchGestures.new()
	gestures.name = "TouchGestures"
	add_child(gestures)
	_show(TRADERS[0])


func _on_cancel() -> void:
	if _examine.visible:
		_examine.close()
	else:
		close()


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
	Trading.update_loyalty(trader.id)
	_buttons[TRADERS.find(trader)].text = "%s   ·   LL%d" % [trader.name, loyalty.level]
	_build_buy(trader)
	_build_barters(trader)
	_build_tasks(trader)
	_build_ammo()
	if trader.id in GearUpgrades.sources():
		_build_upgrades(trader)
	if Insurance.insurers().any(func(each: Dictionary) -> bool: return each.id == trader.id):
		_build_insurance(trader)
	%Tabs.current_tab = clampi(tab, 0, %Tabs.get_tab_count() - 1)
	var lines := ["Loyalty level %d  ·  reputation %.2f  ·  spent %s" % [loyalty.level, loyalty.reputation, UiFormat.money(loyalty.spent)]]
	var next: int = loyalty.level + 1
	if Trading.LOYALTY.has(next):
		var need: Array = Trading.LOYALTY[next]
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
		var level := Trading.offer_level(offer)
		name.text = "%s%s\n%s%s" % [item.data.display_name, "  ×%d" % item.count if item.count > 1 else "",
			UiFormat.money(int(offer.price), str(offer.get("currency", "RUB"))), "   ·   LL%d" % level if level > 1 else ""]
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if Trading.loyalty_block_reason(trader.id, offer) != "":
			name.theme_type_variation = &"DimLabel"
		row.add_child(name)
		row.add_child(_action_button("BUY", Trading.buy_block_reason(offer, trader.id), func() -> String: return Trading.buy(trader.id, offer)))
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
		row.add_child(_action_button("TRADE", Trading.barter_block_reason(offer, trader.id), func() -> String: return Trading.barter(offer, trader.id)))
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
			if QuestLog.objective_type(quest, i) == "trick_kill":
				box.add_child(_trick_objective(quest, i, state))
				continue
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
		for unlock: Dictionary in ExtractTable.unlocked_by(quest.id):
			var map := MapInfo.find(unlock.map)
			var rules: Dictionary = unlock.entry.duplicate()
			rules.erase("quest")
			var needs := ", ".join(ExtractTable.condition_texts(rules))
			box.add_child(_note("Unlocks the %s extract on %s%s" % [unlock.entry.name, map.display_name if map else unlock.map,
				" (%s)" % needs if needs != "" else ""]))
		match state:
			"available":
				box.add_child(_action_button("ACCEPT", "", func() -> String: return "" if QuestLog.accept(quest) else "Can't accept"))
			"ready":
				box.add_child(_action_button("TURN IN", QuestLog.complete_block_reason(quest), func() -> String: return QuestLog.complete(quest)))
		rows.add_child(box)
		rows.add_child(HSeparator.new())
	if rows.get_child_count() == 0:
		rows.add_child(_note("No tasks yet."))


## The AMMO tab: every round of a caliber side by side (AmmoChart, extended), the gun in hand's by
## default; pick another caliber from the list.
func _build_ammo() -> void:
	var rows := _add_tab("AMMO")
	var held := _held_gun()
	var calibers: Array[String] = []
	for data in ItemDB.all_items():
		if data.weapon and data.weapon.caliber not in calibers:
			calibers.append(data.weapon.caliber)
	calibers.sort()
	var caliber := _ammo_caliber
	if caliber == "" or caliber not in calibers:
		caliber = held.data.weapon.caliber if held else calibers[0]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Rounds for"
	top.add_child(label)
	var picker := OptionButton.new()
	picker.name = "CaliberPicker"
	for each in calibers:
		var text := each
		if held and held.data.weapon.caliber == each:
			text += "   ·   in hand: " + held.data.display_name
		picker.add_item(text)
	picker.selected = calibers.find(caliber)
	top.add_child(picker)
	rows.add_child(top)
	var chart := AmmoChart.new()
	chart.name = "AmmoChart"
	chart.extended = true
	rows.add_child(chart)
	var show := func(chosen: String) -> void:
		var in_hand := held != null and held.data.weapon.caliber == chosen
		chart.show_caliber(chosen, held.loaded_ammo if in_hand else "", WeaponStats.build(held, GameState.skills) if in_hand else null)
	show.call(caliber)
	picker.item_selected.connect(func(index: int) -> void:
		_ammo_caliber = calibers[index]
		show.call(_ammo_caliber))
	rows.add_child(_note("Velocity is out of the gun in hand (its barrel and parts) when it takes this caliber. Frag: chance to fragment in flesh (more damage, a bleed). Bleed: chance of a light / heavy bleed per hit. AP rounds go through armor but hurt less; soft rounds hurt the unarmored most. LL: the loyalty level a trader needs; the best AP rounds are only found in raid or made at the Workbench."))


## The UPGRADES tab (traders that upgrade gear): every piece of upgradable gear you own, with what the
## next level costs here (GearUpgradeRow).
func _build_upgrades(trader: Dictionary) -> void:
	var rows := _add_tab("UPGRADES")
	rows.add_child(_note("%s raises gear a level at a time, up to +%d at your loyalty level (rarer gear goes higher: Common +1 … Epic and Legendary +5). The Workbench in the hideout does it for less money." % [
		trader.name, GearUpgrades.source_max_level(trader.id)]))
	var owned := GearUpgrades.owned()
	for gear in owned:
		var row := GearUpgradeRow.create(gear, trader.id)
		row.upgraded.connect(func(_item: ItemInstance) -> void:
			%Status.text = "Upgraded."
			_refresh.call_deferred())
		rows.add_child(row)
		rows.add_child(HSeparator.new())
	if owned.is_empty():
		rows.add_child(_note("You have no gear to upgrade: armor, helmets, face shields, headsets, rigs and backpacks."))


## The INSURE tab (insurers): what this trader charges and how long returns take, what's on its way
## back from them, and every piece of gear on your character that can be insured, each with INSURE
## (or who insures it), plus INSURE ALL and making them the insurer the loadout check's INSURE GEAR
## uses.
func _build_insurance(trader: Dictionary) -> void:
	var rows := _add_tab("INSURE")
	var insurer := Insurance.insurer(trader.id)
	var hours: Array = insurer.return_hours
	rows.add_child(_note("%s insures your gear for %d%% of its value, at least %s an item. If you die or go missing with it and nobody takes it off your body, it comes back to your stash %d-%d game hours later (%s-%s real time): guns with their parts, rigs and backpacks empty, no rounds. Ammo, meds, food, valuables and keys can't be insured; the secure container is never lost. Anything in your stash can be insured from its examine panel." % [
		trader.name, roundi(float(insurer.rate) * 100.0), UiFormat.money(Insurance.CONFIG.insurance_min_price), int(hours[0]), int(hours[1]),
		Insurance._clock(Insurance.real_seconds(float(hours[0]))), Insurance._clock(Insurance.real_seconds(float(hours[1])))]))
	var returning := Label.new()
	returning.name = "InsuranceReturning"
	returning.theme_type_variation = &"AccentLabel"
	rows.add_child(returning)
	var tick := func() -> void:
		returning.text = Insurance.pending_text(trader.id)
		returning.visible = returning.text != ""
	tick.call()
	var timer := Timer.new()
	timer.timeout.connect(tick)  # Counts down, and goes once it's arrived.
	returning.add_child(timer)
	timer.autostart = true
	var gear: Array[Dictionary] = []
	var uninsured: Array[ItemInstance] = []
	if GameState.inventory:
		gear = Insurance.gear(GameState.inventory)
		uninsured = Insurance.uninsured(GameState.inventory)
	var total := Insurance.total_price(uninsured, trader.id)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	var summary := Label.new()
	summary.text = "Your gear: %d of %d insured%s" % [gear.size() - uninsured.size(), gear.size(),
		"\nINSURE GEAR in the loadout check uses %s" % Insurance.insurer_name() if GameState.insurer != trader.id else "\n%s is your insurer in the loadout check" % trader.name]
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(summary)
	if GameState.insurer != trader.id:
		top.add_child(_action_button("USE %s" % trader.name.to_upper(), "", func() -> String:
			GameState.insurer = trader.id
			return ""))
	var all_reason := "All your gear is insured" if uninsured.is_empty() else ("Not enough roubles: %s needed" % UiFormat.money(total) if GameState.roubles < total else "")
	var insure_all := _action_button("INSURE ALL  ·  %s" % UiFormat.money(total) if not uninsured.is_empty() else "ALL INSURED", all_reason,
		func() -> String: return Insurance.insure(uninsured, trader.id))
	insure_all.name = "InsureAllButton"
	top.add_child(insure_all)
	rows.add_child(top)
	rows.add_child(HSeparator.new())
	for entry: Dictionary in gear:
		var item: ItemInstance = entry.item
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.add_child(_cell(item))
		var name := Label.new()
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if item.insured:
			name.text = "%s\n%s  ·  insured with %s" % [item.data.display_name, entry.where, Insurance.insurer_name(item.insurer)]
			name.theme_type_variation = &"DimLabel"
			row.add_child(name)
		else:
			var price := Insurance.price(item, trader.id)
			name.text = "%s\n%s  ·  %s" % [item.data.display_name, entry.where, UiFormat.money(price)]
			row.add_child(name)
			row.add_child(_action_button("INSURE", "Not enough roubles" if GameState.roubles < price else "",
				func() -> String: return Insurance.insure([item], trader.id)))
		rows.add_child(row)
	if gear.is_empty():
		rows.add_child(_note("You carry nothing that can be insured: guns, weapon parts, armor, helmets, rigs, backpacks and melee weapons."))


## The gun you'd raid with (in hand), or null.
func _held_gun() -> ItemInstance:
	var slot := GameState.inventory.weapon_slot() if GameState.inventory else ""
	var gun: ItemInstance = GameState.inventory.equipment[slot] if slot != "" else null
	return gun if gun and gun.is_gun() else null


## A trick-kill objective: what it asks for and how many so far.
func _trick_objective(quest: Dictionary, index: int, state: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var badge := Label.new()
	badge.text = "360"
	badge.add_theme_color_override("font_color", Player.TRICK_COLOR)
	badge.custom_minimum_size.x = 44
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(badge)
	var label := Label.new()
	label.text = "%s  ×%d" % [QuestLog.objective_text(quest, index), QuestLog.objective_count(quest, index)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	if state != "available":
		var done := QuestLog.progress(quest, index)
		var count := Label.new()
		count.text = "%d / %d in raids" % [done, QuestLog.objective_count(quest, index)]
		count.add_theme_color_override("font_color", RequirementRow.MET_COLOR if done >= QuestLog.objective_count(quest, index) else Color(1, 1, 1, 0.7))
		line.add_child(count)
	line.tooltip_text = "Counted at the end of each raid, whether you survive or not: spin a full 360° with a bolt-action rifle or DMR, then kill with the first shot"
	return line


func _rewards_text(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	if int(rewards.get("roubles", 0)) > 0:
		parts.append(UiFormat.money(int(rewards.roubles)))
	if int(rewards.get("xp", 0)) > 0:
		parts.append("%s XP" % UiFormat.thousands(int(rewards.xp)))
	if float(rewards.get("reputation", 0.0)) > 0.0:
		parts.append("+%.2f reputation" % float(rewards.reputation))
	if int(rewards.get("drip", 0)) > 0:
		parts.append("%d Drip" % int(rewards.drip))
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
	cell.examine_requested.connect(_examine.show_item)
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
