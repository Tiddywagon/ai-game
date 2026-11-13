extends MenuScreen
## FLEA MARKET screen (DESIGN.md §10 Flea market, §16.2), opened from the main menu and the TRADERS
## screen from level 15 (FleaMarket). The header counts down to the next batch of listings. Tabs:
## BROWSE (every listing up: a search, category and rarity filters and a sort by price, time left or
## value for money; each row has the seller and rating, the time left, a worn item's durability and a
## gun's extra parts, the price with the trend arrow, the market price and the cheapest trader price
## beside it, and BUY), SELL (your found-in-raid stash items beside the listing form: the market price,
## what traders pay, the asking price, the fee and how fast it should sell, then LIST) and MY LISTINGS
## (each with its time left, COLLECT once it's sold or back, TAKE DOWN while it's up, COLLECT ALL). A
## clock ticks every second: new listings, a price that moved or a listing of yours that sold redraws
## what it changes. Every deal saves the game. Right-click an item (long-press on touch) to examine it.

## Item cells in rows: pixels per grid cell, and the most room one may take.
const CELL := 30.0
const MAX_CELL := Vector2(150, 64)
const SORTS: Array[String] = ["Price", "Time left", "Value for money"]
const TREND_ARROWS := {1: "▲", -1: "▼", 0: ""}

var _examine: ItemExaminePanel
var _browse: VBoxContainer
var _search: LineEdit
var _category: OptionButton
var _rarity: OptionButton
var _sort: OptionButton
var _stash_list: VBoxContainer
var _form: VBoxContainer
var _price: SpinBox
var _picked: ItemInstance
var _mine: VBoxContainer
var _mine_slots: Label
var _collect_all: Button
## What the BROWSE tab was drawn for: [refresh number, drift bucket]; a change redraws it.
var _shown := []


func _ready() -> void:
	%BackButton.pressed.connect(close)
	_examine = ItemExaminePanel.new()
	_examine.name = "ItemExaminePanel"
	_examine.can_set_hotkey = false
	add_child(_examine)
	var gestures := TouchGestures.new()
	gestures.name = "TouchGestures"
	add_child(gestures)
	var clock := Timer.new()
	clock.name = "MarketClock"
	clock.timeout.connect(_tick)
	clock.autostart = true
	add_child(clock)
	if not FleaMarket.is_unlocked():
		%Tabs.hide()
		%Status.text = FleaMarket.lock_reason()
		%BackButton.grab_focus.call_deferred()
		_update_header()
		return
	_build_browse()
	_build_sell()
	_build_mine()
	FleaMarket.update()
	_fill_all()
	(%Tabs as TabContainer).get_tab_bar().grab_focus.call_deferred()


func _on_cancel() -> void:
	if _examine.visible:
		_examine.close()
	else:
		close()


## Redraws every tab and the header.
func _fill_all() -> void:
	_fill_browse()
	_fill_stash()
	_fill_mine()
	_update_header()


func _update_header() -> void:
	%Money.text = "%s      %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")]
	%Clock.text = "New listings in %s" % TraderStock.clock(FleaMarket.seconds_to_refresh()) if FleaMarket.is_unlocked() else ""


## Every second: the countdowns, and whatever the clock changed (new listings or prices: BROWSE and the
## listing form; a listing of yours that sold or came back: MY LISTINGS, saved).
func _tick() -> void:
	_update_header()
	if not FleaMarket.is_unlocked():
		return
	var settled := FleaMarket.update()
	if not settled.is_empty():
		SaveManager.save_game()
		_fill_mine()
	if _shown != [FleaMarket.refresh_number(), FleaMarket.bucket()]:
		_fill_browse()
		_update_form()
	for row in _browse.get_children():
		if row.has_meta("listing"):
			(row.get_node("Info/TimeLeft") as Label).text = _time_left(row.get_meta("listing"))
	for row in _mine.get_children():
		if row.has_meta("listing") and row.get_meta("listing").state == FleaMarket.UP:
			(row.get_node("State") as Label).text = _state_text(row.get_meta("listing"))


# --- BROWSE -------------------------------------------------------------------------------------

func _build_browse() -> void:
	var page := VBoxContainer.new()
	page.name = "BROWSE"
	page.add_theme_constant_override("separation", 12)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search by name"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _apply_filter())
	bar.add_child(_search)
	_category = _options("Category", ["All categories"] + Array(ItemData.CATEGORY_ORDER.map(func(category: int) -> String: return ItemData.CATEGORY_TITLES[category])))
	_category.item_selected.connect(func(_index: int) -> void: _apply_filter())
	bar.add_child(_category)
	_rarity = _options("Rarity", ["All rarities"] + Palette.RARITY_NAMES)
	_rarity.item_selected.connect(func(_index: int) -> void: _apply_filter())
	bar.add_child(_rarity)
	_sort = _options("Sort", SORTS.map(func(sort: String) -> String: return "Sort: " + sort))
	_sort.item_selected.connect(func(_index: int) -> void: _fill_browse())
	bar.add_child(_sort)
	page.add_child(bar)
	_browse = _scroll_rows(page, "Listings")
	%Tabs.add_child(page)


func _options(name: String, choices: Array) -> OptionButton:
	var options := OptionButton.new()
	options.name = name
	options.custom_minimum_size = Vector2(220, 44)
	for choice: String in choices:
		options.add_item(choice)
	return options


## A scroll list under `page`, its rows in a VBoxContainer named `name`.
func _scroll_rows(page: Control, name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.name = name
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	page.add_child(scroll)
	return rows


## Draws every listing up, in the chosen order, then filters them (_apply_filter()).
func _fill_browse() -> void:
	_shown = [FleaMarket.refresh_number(), FleaMarket.bucket()]
	_clear(_browse)
	var listings := FleaMarket.listings()
	var keys := {}
	for listing in listings:
		match _sort.selected:
			1:
				keys[listing.id] = FleaMarket.seconds_left(listing)
			2:
				keys[listing.id] = FleaMarket.value_ratio(listing)
			_:
				keys[listing.id] = float(FleaMarket.price(listing))
	listings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return keys[a.id] < keys[b.id] or (keys[a.id] == keys[b.id] and a.id < b.id))
	for listing in listings:
		_browse.add_child(_listing_row(listing))
	var nothing := _note("Nothing listed matches.")
	nothing.name = "NothingListed"
	_browse.add_child(nothing)
	_apply_filter()


func _listing_row(listing: Dictionary) -> Control:
	var piece: ItemInstance = listing.item
	var cost := FleaMarket.price(listing)
	var row := HBoxContainer.new()
	row.name = "Listing_" + str(listing.id)
	row.set_meta("listing", listing)
	row.add_theme_constant_override("separation", 14)
	row.add_child(_cell(piece))
	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := Label.new()
	title.text = "%s%s" % [piece.title(), "  ×%d" % piece.count if piece.count > 1 else ""]
	info.add_child(title)
	var details: Array[String] = ["%s  ★ %.1f" % [listing.seller, float(listing.rating)]]
	if piece.has_durability():
		details.append("durability %d / %d" % [roundi(piece.durability), roundi(piece.max_durability)])
	var extra := WeaponMods.installed(piece).size() - (piece.data.weapon.default_mods.size() if piece.is_gun() else 0)
	if extra > 0:
		details.append("+%d part%s" % [extra, "" if extra == 1 else "s"])
	var line := _note("   ·   ".join(details))
	info.add_child(line)
	var left := _note(_time_left(listing), false)
	left.name = "TimeLeft"
	info.add_child(left)
	row.add_child(info)
	var prices := VBoxContainer.new()
	prices.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var price := Label.new()
	price.name = "Price"
	price.theme_type_variation = &"AccentLabel"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var arrow: String = TREND_ARROWS[FleaMarket.trend(piece.data.id)]
	price.text = "%s%s" % [UiFormat.money(cost), "  " + arrow if arrow != "" else ""]
	if piece.count > 1:
		price.text += "\n%s each" % UiFormat.money(roundi(float(cost) / piece.count))
	prices.add_child(price)
	var compare := _note(_compare_text(piece), false)
	compare.name = "Compare"
	compare.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prices.add_child(compare)
	row.add_child(prices)
	row.add_child(_action_button("BUY", FleaMarket.buy_block_reason(listing, cost), func() -> String:
		var result := FleaMarket.buy(listing, cost)
		if result != "":
			return result
		SaveManager.save_game()
		return "Bought %s for %s. It's in your stash (not found in raid)." % [piece.title(), UiFormat.money(cost)]))
	return row


## "market ₽ 38,100  ·  Bulat ₽ 41,000 (LL2)" under a listing's price (the trader price for the same
## count; "no trader sells it" when none does).
func _compare_text(piece: ItemInstance) -> String:
	var parts: Array[String] = ["market %s" % UiFormat.money(FleaMarket.market_price(piece))]
	var trader := FleaMarket.trader_price(piece.data.id)
	if trader.is_empty():
		parts.append("no trader sells it")
	else:
		var level := int(trader.level)
		parts.append("%s %s%s" % [TraderTable.display_name(str(trader.trader)), UiFormat.money(roundi(float(trader.each) * piece.count)),
			" (LL%d)" % level if level > 1 else ""])
	return "   ·   ".join(parts)


func _time_left(listing: Dictionary) -> String:
	return "%s left" % FleaMarket.duration_text(FleaMarket.seconds_left(listing))


## Shows the BROWSE rows matching the search, category and rarity.
func _apply_filter() -> void:
	var text := _search.text.strip_edges().to_lower()
	var category: int = ItemData.CATEGORY_ORDER[_category.selected - 1] if _category.selected > 0 else -1
	var shown := 0
	for row in _browse.get_children():
		if not row.has_meta("listing"):
			continue
		var data: ItemData = row.get_meta("listing").item.data
		row.visible = (text == "" or data.display_name.to_lower().contains(text)) and (category < 0 or data.category == category) \
			and (_rarity.selected <= 0 or data.rarity == _rarity.selected - 1)
		shown += 1 if row.visible else 0
	_browse.get_node("NothingListed").visible = shown == 0


# --- SELL ---------------------------------------------------------------------------------------

func _build_sell() -> void:
	var page := HBoxContainer.new()
	page.name = "SELL"
	page.add_theme_constant_override("separation", 24)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left.add_child(_note("Found-in-raid items in your stash. Keys and keycards, secure containers, boss uniques, quest items and the top armor-piercing rounds can't be listed."))
	_stash_list = _scroll_rows(left, "StashItems")
	page.add_child(left)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	_form = VBoxContainer.new()
	_form.name = "ListingForm"
	_form.add_theme_constant_override("separation", 12)
	panel.add_child(_form)
	page.add_child(panel)
	%Tabs.add_child(page)


## The SELL tab's list: every found-in-raid item in the stash (inside containers too) the market takes.
func _fill_stash() -> void:
	_clear(_stash_list)
	var group := ButtonGroup.new()
	var kept := false
	for entry: Dictionary in Selling.sellable_items():
		var piece: ItemInstance = entry.item
		if not piece.fir or GameState.stash.find_holder(piece) == null or FleaTable.is_banned(piece.data):
			continue
		var row := HBoxContainer.new()
		row.name = "Stash_%d" % _stash_list.get_child_count()
		row.set_meta("item", piece)
		row.add_theme_constant_override("separation", 14)
		row.add_child(_cell(piece))
		var label := Label.new()
		label.text = "%s%s\n%s   ·   market %s" % [piece.title(), "  ×%d" % piece.count if piece.count > 1 else "", entry.where, UiFormat.money(FleaMarket.market_price(piece))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		var pick := Button.new()
		pick.name = "Pick"
		pick.text = "PICK"
		pick.toggle_mode = true
		pick.button_group = group
		pick.custom_minimum_size = Vector2(120, 44)
		pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pick.pressed.connect(_pick.bind(piece))
		row.add_child(pick)
		_stash_list.add_child(row)
		if piece == _picked:
			pick.set_pressed_no_signal(true)
			kept = true
	if _stash_list.get_child_count() == 0:
		var nothing := _note("No found-in-raid items in your stash that the flea market takes. Bring some back from a raid.")
		nothing.name = "NothingToList"
		_stash_list.add_child(nothing)
	if not kept:
		_picked = null
	_build_form()


## Picks `piece` for the listing form, asking the market price.
func _pick(piece: ItemInstance) -> void:
	_picked = piece
	_build_form()


func _build_form() -> void:
	_clear(_form)
	var heading := Label.new()
	heading.theme_type_variation = &"HeadingLabel"
	heading.text = "NEW LISTING"
	_form.add_child(heading)
	var slots := _note("Listing slots: %d of %d in use (one more every 5 levels)" % [FleaMarket.slots_used(), FleaMarket.slots()])
	slots.name = "Slots"
	_form.add_child(slots)
	if _picked == null:
		_price = null
		_form.add_child(_note("Pick an item to list."))
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.add_child(_cell(_picked))
	var name := Label.new()
	name.text = _picked.title() + ("  ×%d" % _picked.count if _picked.count > 1 else "")
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name)
	_form.add_child(top)
	var market := _note("")
	market.name = "Market"
	_form.add_child(market)
	var traders := _note("")
	traders.name = "TradersPay"
	_form.add_child(traders)
	var asking := HBoxContainer.new()
	asking.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "Asking price"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	asking.add_child(label)
	var value := FleaMarket.market_price(_picked)
	_price = SpinBox.new()
	_price.name = "AskingPrice"
	_price.min_value = 1
	_price.max_value = 1_000_000_000
	_price.step = 1
	_price.custom_arrow_step = maxf(snappedf(value / 100.0, 10.0), 10.0)
	_price.prefix = UiFormat.currency_sign("RUB")
	_price.custom_minimum_size = Vector2(220, 44)
	_price.value = value
	_price.value_changed.connect(func(_value: float) -> void: _update_form())
	asking.add_child(_price)
	for share: float in [0.9, 1.0, 1.1]:
		var preset := Button.new()
		preset.text = "MARKET" if share == 1.0 else "%+d%%" % roundi((share - 1.0) * 100.0)
		preset.custom_minimum_size = Vector2(96, 44)
		preset.pressed.connect(func() -> void: _price.value = roundi(FleaMarket.market_price(_picked) * share))
		asking.add_child(preset)
	_form.add_child(asking)
	for key in ["Fairness", "Fee", "Estimate"]:
		var line := _note("")
		line.name = key
		_form.add_child(line)
	var list := Button.new()
	list.name = "ListButton"
	list.text = "LIST"
	list.custom_minimum_size = Vector2(200, 48)
	list.size_flags_horizontal = Control.SIZE_SHRINK_END
	list.pressed.connect(_list)
	_form.add_child(list)
	_update_form()


## The form's numbers for the asking price now: market, traders, fairness, fee, estimate and LIST.
func _update_form() -> void:
	if _picked == null or _price == null:
		return
	var asking := roundi(_price.value)
	var arrow: String = TREND_ARROWS[FleaMarket.trend(_picked.data.id)]
	(_form.get_node("Market") as Label).text = "Market price: %s%s   (worth %s)" % [UiFormat.money(FleaMarket.market_price(_picked)),
		"  " + arrow if arrow != "" else "", UiFormat.money(Selling.item_value(_picked))]
	var best := Selling.best_trader(_picked)
	(_form.get_node("TradersPay") as Label).text = "Traders pay: %s (%s)" % [UiFormat.money(Selling.price(best, _picked), Selling.currency(best)),
		TraderTable.display_name(best)] if best != "" else "No trader buys it"
	(_form.get_node("Fairness") as Label).text = "%.2f× the market price" % FleaMarket.fairness(_picked, asking)
	(_form.get_node("Fee") as Label).text = "Fee: %s (%d%%), paid now and not refunded" % [UiFormat.money(FleaMarket.listing_fee(_picked, asking)),
		roundi(FleaMarket.fee_share(_picked, asking) * 100.0)]
	(_form.get_node("Estimate") as Label).text = "%s; it comes back if it hasn't sold in %d hours" % [FleaMarket.estimate_text(_picked, asking),
		roundi(float(FleaTable.sale().get("hours", 12.0)))]
	var button := _form.get_node("ListButton") as Button
	var blocked := FleaMarket.list_block_reason(_picked, asking)
	button.disabled = blocked != ""
	button.tooltip_text = blocked


func _list() -> void:
	var asking := roundi(_price.value)
	var fee := FleaMarket.listing_fee(_picked, asking)
	var title := _picked.title()
	var result := FleaMarket.put_up(_picked, asking)
	if result == "":
		SaveManager.save_game()
		_picked = null
		%Status.text = "Listed %s for %s (fee %s)." % [title, UiFormat.money(asking), UiFormat.money(fee)]
		_fill_all()
		(%Tabs as TabContainer).get_tab_bar().grab_focus()
	else:
		%Status.text = result


# --- MY LISTINGS --------------------------------------------------------------------------------

func _build_mine() -> void:
	var page := VBoxContainer.new()
	page.name = "MY LISTINGS"
	page.add_theme_constant_override("separation", 12)
	var bar := HBoxContainer.new()
	_mine_slots = _note("")
	_mine_slots.name = "MineSlots"
	_mine_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mine_slots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_mine_slots)
	var all := Button.new()
	_collect_all = all
	all.name = "CollectAll"
	all.text = "COLLECT ALL"
	all.custom_minimum_size = Vector2(220, 44)
	all.pressed.connect(func() -> void:
		var got := FleaMarket.collect_all()
		SaveManager.save_game()
		var parts: Array[String] = []
		if int(got.roubles) > 0:
			parts.append(UiFormat.money(int(got.roubles)))
		if int(got.items) > 0:
			parts.append("%d item%s back in your stash" % [got.items, "" if int(got.items) == 1 else "s"])
		%Status.text = ("Collected " + " and ".join(parts) + "." if not parts.is_empty() else "Nothing collected.") \
			+ (" %d item%s waiting for room in the stash." % [got.left, "" if int(got.left) == 1 else "s"] if int(got.left) > 0 else "")
		_fill_all())
	bar.add_child(all)
	page.add_child(bar)
	_mine = _scroll_rows(page, "MyListings")
	%Tabs.add_child(page)


func _fill_mine() -> void:
	_clear(_mine)
	var own := FleaMarket.own_listings()
	var page := _mine.get_parent().get_parent()
	_mine_slots.text = "Listing slots: %d of %d in use" % [FleaMarket.slots_used(), FleaMarket.slots()]
	var waiting := FleaMarket.waiting()
	var to_collect := int(waiting.sold) + int(waiting.expired)
	_collect_all.disabled = to_collect == 0
	var tabs := %Tabs as TabContainer
	tabs.set_tab_title(page.get_index(), "MY LISTINGS" + (" (%d)" % to_collect if to_collect > 0 else ""))
	for listing: Dictionary in own:
		var piece := ItemInstance.from_dict(listing.item)
		if piece == null:
			continue
		var row := HBoxContainer.new()
		row.name = "Mine_" + str(listing.id)
		row.set_meta("listing", listing)
		row.add_theme_constant_override("separation", 14)
		row.add_child(_cell(piece))
		var info := Label.new()
		info.text = "%s%s\n%s asked (%.2f× the market price then)   ·   fee %s paid" % [piece.title(), "  ×%d" % piece.count if piece.count > 1 else "",
			UiFormat.money(int(listing.price)), float(listing.price) / maxf(float(listing.market), 1.0), UiFormat.money(int(listing.fee))]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(info)
		var state := Label.new()
		state.name = "State"
		state.theme_type_variation = &"AccentLabel" if listing.state == FleaMarket.SOLD else &"DimLabel"
		state.text = _state_text(listing)
		state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(state)
		if listing.state == FleaMarket.UP:
			row.add_child(_action_button("TAKE DOWN", "", func() -> String:
				var result := FleaMarket.take_down(listing)
				if result != "":
					return result
				SaveManager.save_game()
				return "Took %s down: it's back in your stash (the fee isn't refunded)." % piece.title()))
		else:
			row.add_child(_action_button("COLLECT", "", func() -> String:
				var sold: bool = listing.state == FleaMarket.SOLD
				var result := FleaMarket.collect(listing)
				if result != "":
					return result
				SaveManager.save_game()
				return "Collected %s for %s." % [UiFormat.money(int(listing.price)), piece.title()] if sold else "%s is back in your stash." % piece.title()))
		_mine.add_child(row)
	if own.is_empty():
		var nothing := _note("No listings. Put found-in-raid items up on the SELL tab.")
		nothing.name = "NoListings"
		_mine.add_child(nothing)


## "Up · 11 h 52 min left", "SOLD: ₽ 576,717 to collect" or "Back unsold: collect it".
func _state_text(listing: Dictionary) -> String:
	match str(listing.state):
		FleaMarket.SOLD:
			return "SOLD: %s to collect" % UiFormat.money(int(listing.price))
		FleaMarket.EXPIRED:
			return "Back unsold: collect it"
	return "Up   ·   %s left" % FleaMarket.duration_text(FleaMarket.time_left(listing))


# --- Helpers ------------------------------------------------------------------------------------

func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## An item cell for a row: the item's footprint at CELL pixels a cell, shrunk to fit MAX_CELL.
func _cell(item: ItemInstance) -> ItemCell:
	var cell := ItemCell.new()
	var fit := Vector2(item.data.size) * CELL
	cell.box = fit * minf(1.0, minf(MAX_CELL.x / fit.x, MAX_CELL.y / fit.y))
	cell.item = item
	cell.examine_requested.connect(_examine.show_item)
	return cell


## A button that runs `action` (it returns the status line and saves when it worked) and redraws.
## Disabled with the reason as its tooltip when `blocked` isn't "".
func _action_button(text: String, blocked: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = blocked != ""
	button.tooltip_text = blocked
	button.pressed.connect(func() -> void:
		%Status.text = action.call()
		_fill_all.call_deferred()
		(%Tabs as TabContainer).get_tab_bar().grab_focus.call_deferred())
	return button


## A dim line of text, wrapping at the width it's given unless `wrap` is false.
func _note(text: String, wrap := true) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return label
