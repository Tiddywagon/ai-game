extends MenuScreen
## TRADERS screen (DESIGN.md §10, §11, §16.2): every trader (TraderTable) with your loyalty level, and
## for the one picked their role, personality, a greeting (one of three, picked each visit), loyalty,
## reputation, money spent and what the next level needs, when they restock (counting down; a restock
## while the screen is open redraws it, whatever noticed it first), and tabs to BUY (roubles or
## dollars: only what your loyalty level reaches, with a line saying how many more items each level
## above adds; limited offers say how many are left, SOLD OUT with the restock countdown at 0; at The
## Broker an EXCHANGE to buy and sell dollars; at Mole his worn gear), SELL (Selling: what this trader
## buys of your stash, pockets, rig and backpack, each with its price and SELL, checkboxes and SELL
## SELECTED, a name filter, the WANTED strip of the items they pay extra for this restock; insured gear
## says so; selling valuables or insured gear asks first if the setting says so), BARTER (items for an
## item), do their TASKS (accept, hand over, turn in), compare AMMO (every round of the gun in hand, or
## of any caliber: AmmoChart), at Stitch, UPGRADE gear (GearUpgradeRow) and, at the insurers (Bulat and
## Doc Vera: Insurance), INSURE the gear you'd take into a raid. A trader who isn't unlocked yet (The
## Broker, after Auntie Zoya's introduction) gives his locked line instead of a greeting, says how to
## unlock him and shows no tabs. Everything you get goes to the stash and is never found in raid.
## Requirements marked with the found-in-raid checkmark only take items that have it (Trading,
## QuestLog). Each deal saves the game and redraws the tabs, keeping the open tab and the keyboard or
## pad focus (or giving it to the tab bar); the SELL tab, which lists everything you own, is drawn only
## when shown, and a sale updates it in place and leaves the other tabs to be drawn when next shown.
## Right-click an item (long-press on touch: TouchGestures) to examine it.

## Item cells in offer rows: pixels per grid cell, and the most room one may take.
const OFFER_CELL := 30.0
const OFFER_MAX := Vector2(150, 64)

var _buttons: Array[Button] = []
var _traders: Array[Dictionary] = []
var _trader: Dictionary = {}
## The greeting each trader gave this visit, by id.
var _greetings := {}
## The caliber the AMMO tab compares ("" = the gun in hand's).
var _ammo_caliber := ""
## The SELL tab's ticked items (kept while you trade with one trader) and name filter, its item rows
## (each with the item as its "item" meta) and its SELL SELECTED button.
var _sell_picked: Array[ItemInstance] = []
var _sell_filter := ""
var _sell_rows: Array[Control] = []
var _sell_selected: Button
## Tabs to draw when they're next shown (_draw_stale()), by title.
var _stale: Array[String] = []
## True while _refresh() puts the tabs back (tab_changed draws nothing meanwhile).
var _refreshing := false
## The picked trader's restock number the tabs were drawn at (_tick() redraws when it moves on).
var _shown_restock := 0
## Dollars the EXCHANGE changes.
var _exchange_amount := 100
## Labels counting down to the restock: [Label, text with "{clock}" in it].
var _countdowns: Array = []
var _examine: ItemExaminePanel
## Asks before selling valuables and insured gear (Selling.needs_confirm()); runs `_on_confirm` when you
## say yes.
var _confirm: ConfirmationDialog
var _on_confirm := Callable()


func _ready() -> void:
	%BackButton.pressed.connect(close)
	_traders = TraderTable.all()
	var group := ButtonGroup.new()
	for trader: Dictionary in _traders:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 56
		button.name = "Trader_" + str(trader.id)
		Trading.update_loyalty(trader.id)
		button.text = _button_text(trader)
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
	_confirm = ConfirmationDialog.new()
	_confirm.name = "SellConfirm"
	_confirm.title = "Sell this?"
	_confirm.ok_button_text = "SELL"
	_confirm.dialog_autowrap = true
	_confirm.min_size = Vector2i(560, 0)
	_confirm.confirmed.connect(func() -> void:
		if _on_confirm.is_valid():
			_on_confirm.call())
	add_child(_confirm)
	var clock := Timer.new()
	clock.name = "RestockClock"
	clock.timeout.connect(_tick)
	clock.autostart = true
	add_child(clock)
	%Tabs.tab_changed.connect(func(_tab: int) -> void: _draw_stale())
	_show(_traders[0])


func _on_cancel() -> void:
	if _examine.visible:
		_examine.close()
	else:
		close()


func _show(trader: Dictionary) -> void:
	if trader == _trader:
		return
	_trader = trader
	_sell_picked.clear()  # Prices differ from trader to trader.
	for button_index in _buttons.size():  # Focus moving (keys, a pad) picks a trader too, not just a click.
		_buttons[button_index].set_pressed_no_signal(button_index == _traders.find(trader))
	_refresh()


## "Bulat   ·   LL2", or "The Broker   ·   LOCKED".
func _button_text(trader: Dictionary) -> String:
	if not TraderTable.is_unlocked(trader.id):
		return "%s   ·   LOCKED" % trader.name
	return "%s   ·   LL%d" % [trader.name, int(GameState.trader_loyalty[trader.id].level)]


## Redraws the selected trader: info, greeting, loyalty, money and the tabs, keeping the open tab and
## the focus (_focus_trail()). SELL is drawn when it's shown (_draw_stale()): it lists everything you
## own, the slow part with a full stash.
func _refresh() -> void:
	var trail := _focus_trail()
	var trader := _trader
	var tab: int = %Tabs.current_tab
	_refreshing = true
	for child in %Tabs.get_children():
		%Tabs.remove_child(child)
		child.queue_free()
	_stale.clear()
	%TraderName.text = trader.name.to_upper()
	if not TraderTable.is_unlocked(trader.id):
		var line := TraderTable.locked_greeting(trader.id)  # Not a greeting: he doesn't know you yet.
		%Greeting.text = "“%s”" % line if line != "" else ""
	else:
		if not _greetings.has(trader.id):
			_greetings[trader.id] = TraderTable.greeting(trader.id)
		%Greeting.text = "“%s”" % _greetings[trader.id]
	%TraderInfo.text = "%s: %s\nCurrency: %s  ·  %s\n%s" % [trader.role, trader.specialty, TraderTable.currency_name(trader.id),
		trader.unique, trader.personality]
	_countdowns.clear()
	if not TraderTable.is_unlocked(trader.id):
		_refreshing = false
		_update_header()
		%Loyalty.text = "Locked. " + TraderTable.lock_text(trader.id)
		%Tabs.hide()
		%Restock.hide()
		return
	%Tabs.show()
	%Restock.show()
	Trading.update_loyalty(trader.id)
	_shown_restock = TraderStock.restock_number(trader.id)
	_countdowns.append([%Restock, "Restock in {clock}  ·  %s" % ("new worn gear, new wanted items" if trader.id == TraderStock.used_trader()
		else "limited stock refills, new wanted items")])
	_build_buy(trader)
	_add_tab("SELL")
	_stale.append("SELL")
	_build_barters(trader)
	_build_tasks(trader)
	_build_ammo()
	if trader.id in GearUpgrades.sources():
		_build_upgrades(trader)
	if Insurance.insurers().any(func(each: Dictionary) -> bool: return each.id == trader.id):
		_build_insurance(trader)
	%Tabs.current_tab = clampi(tab, 0, %Tabs.get_tab_count() - 1)
	_refreshing = false
	_update_header()
	_draw_stale()
	_update_countdowns()
	_restore_focus(trail)


## The money, every trader's button (their loyalty level) and the picked trader's loyalty lines.
func _update_header() -> void:
	%Money.text = "%s      %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")]
	for button_index in _buttons.size():
		_buttons[button_index].text = _button_text(_traders[button_index])
	if TraderTable.is_unlocked(_trader.id):
		%Loyalty.text = "\n".join(_loyalty_lines(_trader))


## Draws the open tab if it's waiting to be drawn when shown (SELL after a refresh, any tab after a sale).
func _draw_stale() -> void:
	if _refreshing or not %Tabs.visible or %Tabs.get_current_tab_control() == null:
		return
	var title := String(%Tabs.get_current_tab_control().name)
	if not title in _stale:
		return
	_stale.erase(title)
	match title:
		"BUY":
			_build_buy(_trader)
		"SELL":
			_build_sell(_trader)
		"BARTER":
			_build_barters(_trader)
		"TASKS":
			_build_tasks(_trader)
		"AMMO":
			_build_ammo()
		"UPGRADES":
			_build_upgrades(_trader)
		"INSURE":
			_build_insurance(_trader)
	_update_countdowns()


## Where the keyboard or pad focus is in the tabs (the tab bar too), as child indexes down from %Tabs
## ([] if it isn't there), so _restore_focus() finds the same place after the tabs are drawn again.
func _focus_trail() -> Array[int]:
	var trail: Array[int] = []
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not %Tabs.is_ancestor_of(focused):
		return trail
	var node: Node = focused
	while node != %Tabs:
		trail.push_front(node.get_index(true))
		node = node.get_parent()
	return trail


## Gives the focus back to the control at `trail` (_focus_trail()), or to the tab bar if it's gone.
func _restore_focus(trail: Array[int]) -> void:
	if trail.is_empty():
		return
	var node: Node = %Tabs
	for index in trail:
		node = node.get_child(index, true) if node and index < node.get_child_count(true) else null
	var control := node as Control
	if control and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
		control.grab_focus()
	else:
		(%Tabs as TabContainer).get_tab_bar().grab_focus()


## Every second: a restock redraws the trader (stock refilled, new wanted items), also one that came
## due while something else looked at the stock first (a hover, a tick box); otherwise the countdowns
## tick.
func _tick() -> void:
	if _trader.is_empty() or not TraderTable.is_unlocked(_trader.id):
		return
	if TraderStock.restock_number(_trader.id) != _shown_restock:
		%Status.text = "%s restocked." % _trader.name
		_refresh()
		return
	_update_countdowns()


func _update_countdowns() -> void:
	_countdowns = _countdowns.filter(func(entry: Array) -> bool: return is_instance_valid(entry[0]) and not (entry[0] as Node).is_queued_for_deletion())
	if _trader.is_empty() or not TraderTable.is_unlocked(_trader.id):
		return
	var clock := TraderStock.countdown_text(_trader.id)
	for entry: Array in _countdowns:
		(entry[0] as Label).text = str(entry[1]).replace("{clock}", clock)


## "Loyalty level 2  ·  reputation 0.27 (0.05 from barters)  ·  spent ₽ 812,000", then what the next
## level needs.
func _loyalty_lines(trader: Dictionary) -> Array[String]:
	var loyalty: Dictionary = GameState.trader_loyalty[trader.id]
	var bartered := Trading.barter_reputation(trader.id)
	var lines: Array[String] = ["Loyalty level %d  ·  reputation %.2f%s  ·  spent %s" % [loyalty.level, loyalty.reputation,
		" (%.2f from barters)" % bartered if bartered > 0.0 else "", UiFormat.money(loyalty.spent)]]
	var next: int = loyalty.level + 1
	var need := Progression.loyalty_needs(next)
	if TraderTable.max_loyalty(trader.id) <= 1:
		lines.append("%s's loyalty stays at level 1 for now." % trader.name)
	elif next > TraderTable.max_loyalty(trader.id) or need.is_empty():
		lines.append("Highest loyalty level reached.")
	else:
		lines.append("Next level (LL%d) needs: player level %d, reputation %.2f, %s spent with %s%s. Barters add %.2f reputation each, up to %.2f." % [
			next, need.player_level, need.reputation, UiFormat.money(need.spent), trader.name,
			" (a dollar counts as %s)" % UiFormat.money(roundi(Progression.dollar_rate())) if trader.currency == "USD" else "",
			Progression.barter_reputation(), Progression.barter_reputation_cap()])
	return lines


## The BUY tab: what your loyalty level reaches (Trading.shown_offers(): the fence's worn gear too),
## with how many a limited offer has left or SOLD OUT and the restock countdown, then a line on what the
## levels above add; at The Broker the EXCHANGE first.
func _build_buy(trader: Dictionary) -> void:
	var rows := _add_tab("BUY")
	if trader.has("notice"):
		rows.add_child(_note(str(trader.notice)))
	if trader.id == Trading.exchange_trader():
		rows.add_child(_exchange_box())
		rows.add_child(HSeparator.new())
	var shown := Trading.shown_offers(trader.id)
	for offer: Dictionary in shown:
		var item := Trading.offer_item(offer)
		if item == null:
			continue
		var row := HBoxContainer.new()
		row.name = "Offer_" + str(offer.get("id", offer.item))
		row.add_theme_constant_override("separation", 14)
		row.add_child(_cell(item))
		var name := Label.new()
		name.name = "OfferText"
		var level := Trading.offer_level(offer)
		var details: Array[String] = [UiFormat.money(int(offer.price), str(offer.get("currency", "RUB")))]
		if level > 1:
			details.append("LL%d" % level)
		if item.has_durability() and offer.get("used", false):
			details.append("worn: durability %d / %d" % [roundi(item.durability), roundi(item.max_durability)])
		var left := TraderStock.left(trader.id, offer)
		if left > 0:
			details.append("%d left" % left)
		var heading := "%s%s" % [item.title(), "  ×%d" % item.count if item.count > 1 else ""]
		name.text = "%s\n%s" % [heading, "   ·   ".join(details)]
		if left == 0:
			details.append("SOLD OUT  ·  restock in {clock}")
			name.theme_type_variation = &"DimLabel"
			_countdowns.append([name, "%s\n%s" % [heading, "   ·   ".join(details)]])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name)
		row.add_child(_action_button("BUY", Trading.buy_block_reason(offer, trader.id), func() -> String: return Trading.buy(trader.id, offer)))
		rows.add_child(row)
		rows.add_child(HSeparator.new())
	var hidden := Trading.hidden_text(trader.id)
	if hidden != "":
		var more := _note(hidden + " (raise your loyalty level to see them)")
		more.name = "HiddenOffers"
		rows.add_child(more)
	elif shown.is_empty() and not trader.has("notice"):
		rows.add_child(_note("Nothing for sale."))


## The EXCHANGE (The Broker): buy dollars dearer than you sell them; an amount and a button each way.
func _exchange_box() -> Control:
	var box := VBoxContainer.new()
	box.name = "Exchange"
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.theme_type_variation = &"AccentLabel"
	title.text = "EXCHANGE  ·  a dollar costs %s, and fetches %s" % [UiFormat.money(Trading.exchange_roubles(1, true)), UiFormat.money(Trading.exchange_roubles(1, false))]
	box.add_child(title)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var amount := SpinBox.new()
	amount.name = "ExchangeAmount"
	amount.min_value = 1
	amount.max_value = 1000000
	amount.step = 1
	amount.prefix = "$"
	amount.value = _exchange_amount
	amount.custom_minimum_size.x = 170
	line.add_child(amount)
	var buy := Button.new()
	buy.name = "BuyDollars"
	var sell := Button.new()
	sell.name = "SellDollars"
	for button in [buy, sell]:
		button.custom_minimum_size = Vector2(240, 44)
		line.add_child(button)
	var update := func() -> void:
		buy.text = "BUY %s  ·  %s" % [UiFormat.money(_exchange_amount, "USD"), UiFormat.money(Trading.exchange_roubles(_exchange_amount, true))]
		sell.text = "SELL %s  ·  %s" % [UiFormat.money(_exchange_amount, "USD"), UiFormat.money(Trading.exchange_roubles(_exchange_amount, false))]
		buy.tooltip_text = Trading.exchange_block_reason(_exchange_amount, true)
		sell.tooltip_text = Trading.exchange_block_reason(_exchange_amount, false)
		buy.disabled = buy.tooltip_text != ""
		sell.disabled = sell.tooltip_text != ""
	update.call()
	amount.value_changed.connect(func(value: float) -> void:
		_exchange_amount = roundi(value)
		update.call())
	for pair in [[buy, true], [sell, false]]:
		var buying: bool = pair[1]
		(pair[0] as Button).pressed.connect(func() -> void:
			var result := Trading.buy_dollars(_exchange_amount) if buying else Trading.sell_dollars(_exchange_amount)
			if result == "":
				SaveManager.save_game()
			%Status.text = result if result != "" else ("Bought %s." if buying else "Sold %s.") % UiFormat.money(_exchange_amount, "USD")
			_refresh.call_deferred())
	box.add_child(line)
	box.add_child(_note("Changing money doesn't count toward the money spent with %s; the dollars count when you spend them with him." % TraderTable.display_name(Trading.exchange_trader())))
	return box


## The SELL tab: a note on what this trader pays, the WANTED strip, a name filter and SELL SELECTED,
## then everything of yours they buy (Selling.sellable_items(): the stash, pockets, rig and backpack),
## each with a tick box, where it is, its price and SELL. _update_sell() fills in the prices and states,
## then and after each sale.
func _build_sell(trader: Dictionary) -> void:
	var rows := _add_tab("SELL")
	var note := _note("")
	note.name = "SellNote"
	rows.add_child(note)
	var wanted := VBoxContainer.new()
	wanted.name = "Wanted"
	wanted.add_theme_constant_override("separation", 10)
	rows.add_child(wanted)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var filter := LineEdit.new()
	filter.name = "SellFilter"
	filter.placeholder_text = "Filter by name"
	filter.text = _sell_filter
	filter.clear_button_enabled = true
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.text_changed.connect(func(text: String) -> void:
		_sell_filter = text
		_apply_sell_filter())
	top.add_child(filter)
	_sell_selected = Button.new()
	_sell_selected.name = "SellSelected"
	_sell_selected.custom_minimum_size = Vector2(300, 44)
	_sell_selected.pressed.connect(func() -> void: _sell(trader, _sell_picked.duplicate()))
	top.add_child(_sell_selected)
	rows.add_child(top)
	_sell_rows.clear()
	for entry: Dictionary in Selling.sellable_items():
		var item: ItemInstance = entry.item
		if not Selling.buys(trader.id, item.data):
			continue
		var row := HBoxContainer.new()
		row.name = "Sell_%d" % _sell_rows.size()
		row.add_theme_constant_override("separation", 14)
		row.set_meta("item", item)
		row.set_meta("where", entry.where)
		var pick := CheckBox.new()
		pick.name = "Pick"
		pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pick.toggled.connect(func(on: bool) -> void:
			if on and not item in _sell_picked:
				_sell_picked.append(item)
			elif not on:
				_sell_picked.erase(item)
			_update_picked(trader))
		row.add_child(pick)
		row.add_child(_cell(item))
		var label := Label.new()
		label.name = "SellText"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		var sell_one := Button.new()
		sell_one.name = "SellButton"
		sell_one.text = "SELL"
		sell_one.custom_minimum_size = Vector2(150, 44)
		sell_one.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sell_one.pressed.connect(func() -> void: _sell(trader, [item]))
		row.add_child(sell_one)
		rows.add_child(row)
		_sell_rows.append(row)
	var nothing := _note("You have nothing %s buys in your stash, pockets, rig or backpack." % trader.name)
	nothing.name = "NothingToSell"
	rows.add_child(nothing)
	_update_sell(trader)


## Brings the SELL tab up to date without drawing it again (the end of _build_sell(), and after each
## sale, which with a full stash would take a moment): rows of what's gone are dropped, the rest get
## their price, Wanted bonus, "insured" and whether they can be sold now (a container just emptied
## can); the note, the WANTED strip and SELL SELECTED follow. If the focus was on a row that went, the
## next row takes it.
func _update_sell(trader: Dictionary) -> void:
	var rows := %Tabs.get_node_or_null("SELL/Rows") as VBoxContainer
	if rows == null:
		return
	var currency := Selling.currency(trader.id)
	var bonus := roundi((TraderStock.wanted_multiplier() - 1.0) * 100.0)
	(rows.get_node("SellNote") as Label).text = "%s pays %d%% of what an item is worth at your loyalty level%s, in %s; sales count toward the money spent with %s." % [
		trader.name, roundi(Selling.rate(trader.id) * 100.0), " (more for some kinds of item)" if _has_multipliers(trader.id) else "",
		TraderTable.currency_name(trader.id).to_lower(), trader.name]
	_fill_wanted(rows.get_node("Wanted"), trader)
	var focused := get_viewport().gui_get_focus_owner()
	var refocus := -1
	var kept: Array[Control] = []
	var reasons := {}
	for row in _sell_rows:
		var item: ItemInstance = row.get_meta("item")
		if Selling.locate(item).is_empty():  # Sold.
			if focused and row.is_ancestor_of(focused):
				refocus = kept.size()
			rows.remove_child(row)
			row.queue_free()
			continue
		kept.append(row)
		var reason := Selling.sell_block_reason(trader.id, item)
		reasons[item] = reason
		var notes: Array[String] = [str(row.get_meta("where")), UiFormat.money(Selling.price(trader.id, item), currency)]
		var wanted_units := mini(item.count, TraderStock.wanted_left(trader.id, item.data.id))
		if wanted_units > 0:
			notes.append("WANTED +%d%%%s" % [bonus, " on %d" % wanted_units if wanted_units < item.count else ""])
		if item.insured:
			notes.append("insured: the insurance goes with it")
		var label := row.get_node("SellText") as Label
		label.text = "%s%s\n%s" % [item.title(), "  ×%d" % item.count if item.count > 1 else "", "   ·   ".join(notes)]
		label.theme_type_variation = &"DimLabel" if reason != "" else &""
		var sell_one := row.get_node("SellButton") as Button
		sell_one.disabled = reason != ""
		sell_one.tooltip_text = reason
	_sell_rows = kept
	_sell_picked = _sell_picked.filter(func(item: ItemInstance) -> bool: return reasons.get(item, "x") == "")
	for row in kept:
		var pick := row.get_node("Pick") as CheckBox
		var item: ItemInstance = row.get_meta("item")
		pick.disabled = reasons[item] != ""
		pick.tooltip_text = reasons[item]
		pick.set_pressed_no_signal(item in _sell_picked)
	(rows.get_node("NothingToSell") as Control).visible = kept.is_empty()
	_update_picked(trader)
	_apply_sell_filter()
	if refocus >= 0:
		var next := kept[mini(refocus, kept.size() - 1)] if not kept.is_empty() else null
		if next:
			var button := next.get_node("SellButton") as Button
			(next.get_node("Pick") as Control if button.disabled else button).grab_focus()
		else:
			(%Tabs as TabContainer).get_tab_bar().grab_focus()


## The WANTED strip in `box`: what `trader` pays extra for until the restock, each with its price and
## how many more they take (hidden if they want nothing).
func _fill_wanted(box: Control, trader: Dictionary) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var wanted := TraderStock.wanted(trader.id)
	box.visible = not wanted.is_empty()
	if wanted.is_empty():
		return
	var title := Label.new()
	title.theme_type_variation = &"AccentLabel"
	title.text = "WANTED until the restock: +%d%%, up to %d of each" % [roundi((TraderStock.wanted_multiplier() - 1.0) * 100.0),
		int(TraderStock.wanted_rules().get("per_item", 0))]
	box.add_child(title)
	var strip := HFlowContainer.new()
	strip.name = "WantedStrip"
	strip.add_theme_constant_override("h_separation", 28)
	strip.add_theme_constant_override("v_separation", 8)
	for id in wanted:
		var sample := ItemInstance.create(id)
		if sample == null:
			continue
		var cell := HBoxContainer.new()
		cell.name = "Wanted_" + id
		cell.add_theme_constant_override("separation", 10)
		cell.add_child(_cell(sample))
		var label := Label.new()
		var more := TraderStock.wanted_left(trader.id, id)
		label.text = "%s\n%s  ·  %s" % [sample.data.display_name, UiFormat.money(Selling.price(trader.id, sample), Selling.currency(trader.id)),
			"%d more" % more if more > 0 else "no more this restock"]
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(label)
		strip.add_child(cell)
	box.add_child(strip)
	box.add_child(HSeparator.new())


## SELL SELECTED's text and state for what's ticked.
func _update_picked(trader: Dictionary) -> void:
	if not is_instance_valid(_sell_selected):
		return
	_sell_selected.text = "SELL SELECTED (%d)  ·  %s" % [_sell_picked.size(), UiFormat.money(Selling.total(trader.id, _sell_picked), Selling.currency(trader.id))]
	_sell_selected.disabled = _sell_picked.is_empty()
	_sell_selected.tooltip_text = "Tick items below to sell them together" if _sell_picked.is_empty() else ""


## Shows only the SELL rows whose item's name has the filter text in it.
func _apply_sell_filter() -> void:
	var wanted_text := _sell_filter.strip_edges().to_lower()
	for row in _sell_rows:
		row.visible = wanted_text == "" or wanted_text in (row.get_meta("item") as ItemInstance).data.display_name.to_lower()


## True if `trader_id` pays more or less than their rate for some items.
func _has_multipliers(trader_id: String) -> bool:
	return Selling.rules(trader_id).get("buys", []).any(func(entry: Dictionary) -> bool: return not is_equal_approx(float(entry.get("multiplier", 1.0)), 1.0))


## Sells `items` to `trader`, asking first when they include valuables or insured gear and the setting
## says so.
func _sell(trader: Dictionary, items: Array) -> void:
	if items.is_empty():
		return
	var go := func() -> void:
		var paid := Selling.total(trader.id, items)
		var result := Selling.sell(trader.id, items)
		if result == "":
			SaveManager.save_game()
			_sell_picked.clear()
		%Status.text = result if result != "" else "Sold %d item%s to %s for %s." % [items.size(), "" if items.size() == 1 else "s", trader.name,
			UiFormat.money(paid, Selling.currency(trader.id))]
		_after_sale.call_deferred(trader)
	if Selling.needs_confirm(items):
		_on_confirm = go
		_confirm.dialog_text = Selling.confirm_text(trader.id, items)
		_confirm.popup_centered()
	else:
		go.call()


## After a sale: the money, loyalty and SELL tab brought up to date in place (_update_sell()); the other
## tabs are drawn again when next shown (what you can afford now, a new loyalty level's offers).
func _after_sale(trader: Dictionary) -> void:
	if trader != _trader or not TraderTable.is_unlocked(trader.id):
		return
	_update_header()
	if not "SELL" in _stale:
		_update_sell(trader)
	for index in %Tabs.get_tab_count():
		var title := String(%Tabs.get_tab_control(index).name)
		if title != "SELL" and not title in _stale:
			_stale.append(title)


func _build_barters(trader: Dictionary) -> void:
	var rows := _add_tab("BARTER")
	if trader.has("notice"):
		rows.add_child(_note(str(trader.notice)))
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
	if Trading.offers(trader.id).get("barters", []).is_empty() and not trader.has("notice"):
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
			box.add_child(_note(QuestLog.lock_reason(quest) + "."))
			rows.add_child(box)
			rows.add_child(HSeparator.new())
			continue
		box.add_child(_note(quest.get("description", "")))
		for i in quest.objectives.size():
			if QuestLog.objective_type(quest, i) == "trick_kill":
				box.add_child(_trick_objective(quest, i, state))
				continue
			if QuestLog.objective_type(quest, i) == "roubles":
				box.add_child(_money_objective(quest, i, state))
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
		for unlocked: Dictionary in _traders.filter(func(each: Dictionary) -> bool: return TraderTable.unlock_quest(each.id) == quest.id):
			box.add_child(_note("Unlocks %s: %s" % [unlocked.name, str(unlocked.specialty).to_lower()]))
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


## A roubles objective: how much, how much is handed over so far, and HAND OVER (pays what you can).
func _money_objective(quest: Dictionary, index: int, state: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var label := Label.new()
	var count := QuestLog.objective_count(quest, index)
	var paid := QuestLog.progress(quest, index)
	label.text = "Roubles   %s" % (UiFormat.money(count) if state == "available" else "%s / %s" % [UiFormat.money(paid), UiFormat.money(count)])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if state != "available":
		label.add_theme_color_override("font_color", RequirementRow.MET_COLOR if paid >= count else RequirementRow.MISSING_COLOR)
	line.add_child(label)
	if state == "active" and paid < count:
		line.add_child(_action_button("HAND OVER", "No roubles" if GameState.roubles <= 0 else "", func() -> String:
			return "" if QuestLog.hand_in(quest, index) > 0 else "Nothing to hand over"))
	return line


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
	if int(rewards.get("dollars", 0)) > 0:
		parts.append(UiFormat.money(int(rewards.dollars), "USD"))
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


## A tab of `title` with a scrolling list; returns the list. If the tab is there already (one tab drawn
## again: _draw_stale()), its list, emptied.
func _add_tab(title: String) -> VBoxContainer:
	var scroll := %Tabs.get_node_or_null(title) as ScrollContainer
	if scroll:
		var list := scroll.get_node("Rows") as VBoxContainer
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		return list
	scroll = ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.name = "Rows"
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
