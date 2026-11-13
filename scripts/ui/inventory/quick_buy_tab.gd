class_name QuickBuyTab
extends VBoxContainer
## The LOADOUT screen's QUICK BUY tab (DESIGN.md §16.6): a grid of quick-buy cards (QuickBuy.cards():
## your faction's and your custom ones), each with its name, faction or CUSTOM tag, description, the
## main pieces, the would-be loadout's stats (LoadoutStats: armor class per zone, weight, the gun's
## ergonomics and recoil, storage), the price after loyalty prices and the bundle discount with the full
## price struck through, the substitutions it needs, and BUY; a locked card shows a padlock and what is
## still missing. Above them: your money, and SAVE CURRENT GEAR AS QUICK-BUY with a name box.
##
## BUY opens a confirm dialog over the whole screen (modal: the keyboard and controller focus stay in it,
## container windows stay beneath its shade): every line with its trader and price, swaps and left-outs in
## amber, where the rounds and meds go, what goes to the stash, and every reason it can't be bought.
## CONFIRM buys the plan the dialog showed (QuickBuy.buy()); if prices or stock moved meanwhile it shows
## the card again instead. The cards are worked out again only when money, loyalty, tasks, stock or the
## custom cards change (refresh(), _state_key()); a restock is noticed within a second.

const CARD_WIDTH := 424.0
const COLUMNS := 4
const ICON_CELL := 22.0
const ICON_MAX := Vector2(118, 50)
const DIALOG_WIDTH := 900.0
const DIALOG_MAX_HEIGHT := 0.62
const AMBER := Color(0.95, 0.7, 0.3)
const RED := Color(0.9, 0.38, 0.3)
const DIM := Color(1, 1, 1, 0.55)
const GREEN := Color(0.55, 0.85, 0.5)
## The slots whose items a card shows as icons, in order.
const ICON_SLOTS: Array[String] = ["primary", "secondary", "pistol", "armor", "rig", "helmet", "backpack"]


## A padlock drawn in lines (fonts may lack the glyph).
class Padlock extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(18, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var colour := Color(0.95, 0.7, 0.3)
		draw_arc(Vector2(9, 9), 5.0, PI, TAU, 12, colour, 2.0)
		draw_line(Vector2(4, 9), Vector2(4, 11), colour, 2.0)
		draw_line(Vector2(14, 9), Vector2(14, 11), colour, 2.0)
		draw_rect(Rect2(2, 11, 14, 10), colour)


## The LOADOUT screen it's on (its inventory, stash and overlay).
var screen: LoadoutScreen
## The plan the confirm dialog shows ({} while it's closed).
var dialog_plan: Dictionary = {}
## The card each plan was worked out for, by card id, for the state they were worked out in.
var plans := {}

var _state := ""
var _grid: GridContainer
var _money: Label
var _status: Label
var name_box: LineEdit
var _save_button: Button
var _shade: ColorRect
var _dialog: PanelContainer
var _confirm: Button
var _cancel: Button
var _buying := false
var _restock_timer := 0.0


func _ready() -> void:
	name = "QuickBuyTab"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)
	_money = Label.new()
	_money.name = "QuickBuyMoney"
	_money.theme_type_variation = &"AccentLabel"
	_money.add_theme_font_size_override("font_size", 20)
	bar.add_child(_money)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	name_box = LineEdit.new()
	name_box.name = "QuickBuyName"
	name_box.placeholder_text = "Name for your gear"
	name_box.max_length = QuickBuyTable.name_length()
	name_box.custom_minimum_size = Vector2(300, 44)
	name_box.text_submitted.connect(func(_text: String) -> void: name_box.release_focus())
	bar.add_child(name_box)
	_save_button = Button.new()
	_save_button.name = "SaveQuickBuy"
	_save_button.text = "SAVE CURRENT GEAR AS QUICK-BUY"
	_save_button.custom_minimum_size = Vector2(0, 44)
	_save_button.tooltip_text = "Turn what you wear and carry into a custom card, priced from trader stock (up to %d)" % QuickBuyTable.max_custom()
	_save_button.pressed.connect(save_current)
	bar.add_child(_save_button)
	_status = Label.new()
	_status.name = "QuickBuyStatus"
	_status.theme_type_variation = &"DimLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.name = "QuickBuyScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "QuickBuyCards"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	_build_dialog()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_restock_timer -= delta
	if _restock_timer <= 0.0:
		_restock_timer = 1.0
		TraderStock.refresh_all()
		refresh()


## Works the cards out again and redraws them if anything they depend on changed (or `force`).
func refresh(force := false) -> void:
	var key := _state_key()
	if not force and key == _state:
		return
	_state = key
	_money.text = "%s  ·  %s" % [UiFormat.money(GameState.roubles), UiFormat.money(GameState.dollars, "USD")]
	plans.clear()
	# Built cards are kept while what they show is the same (_view_key()): only changed ones are rebuilt.
	var old := {}
	for child in _grid.get_children():
		old[child.name] = child
	var index := 0
	for card in QuickBuy.cards():
		var plan := QuickBuy.plan(card, screen.inventory if screen else null)
		plans[str(card.id)] = plan
		var view: Control = old.get(StringName("Card_" + str(card.id)))
		old.erase(StringName("Card_" + str(card.id)))
		if view == null or view.get_meta("view_key", "") != _view_key(plan):
			if view:
				_grid.remove_child(view)
				view.queue_free()
			view = _card_view(plan)
			_grid.add_child(view)
		_grid.move_child(view, index)
		index += 1
	for view: Node in old.values():
		_grid.remove_child(view)
		view.queue_free()
	_save_button.disabled = GameState.quick_buys.size() >= QuickBuyTable.max_custom()


## What a card's view shows, as text: its price, swaps, what it still needs and what it's made of.
func _view_key(plan: Dictionary) -> String:
	return str([plan.signature, plan.roubles, plan.dollars, plan.full_roubles, plan.full_dollars, plan.missing, plan.card.get("name", ""),
		plan.card.get("left_out", []), plan.kit.inventory.total_weight()])


## What the cards depend on: money, loyalty levels, tasks done, each trader's restock and stock bought,
## the custom cards and what you wear (the secure container's weight counts in the totals).
func _state_key() -> String:
	var parts: Array = [GameState.roubles, GameState.dollars, QuickBuy.tasks_completed(), GameState.quick_buys.size(), GameState.faction]
	for trader_id in TraderTable.ids():
		parts.append([GameState.trader_loyalty.get(trader_id, {}).get("level", 1), TraderTable.is_unlocked(trader_id)])
	parts.append(str(GameState.trader_stock).hash())
	for card: Dictionary in GameState.quick_buys:
		parts.append(card.get("name", ""))
	var secure: ItemInstance = screen.inventory.equipment.get("secure") if screen else null
	parts.append(secure.data.id if secure else "")
	return str(parts)


# --- Cards ----------------------------------------------------------------------------------------

## One card: header, description, icons, stats, price, swaps, lock, buttons.
func _card_view(plan: Dictionary) -> Control:
	var card: Dictionary = plan.card
	var panel := PanelContainer.new()
	panel.name = "Card_" + str(card.id)
	panel.set_meta("view_key", _view_key(plan))
	panel.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.075, 0.08, 0.96)
	style.border_color = Color(1, 1, 1, 0.12) if plan.missing.is_empty() else Color(0.95, 0.7, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	var head := HBoxContainer.new()
	rows.add_child(head)
	if not plan.missing.is_empty():
		head.add_child(Padlock.new())
	var title := Label.new()
	title.name = "CardName"
	title.text = str(card.get("name", "")).to_upper()
	title.theme_type_variation = &"AccentLabel"
	title.add_theme_font_size_override("font_size", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var tag := _tag(card)
	if tag != "":
		var label := _label(tag, 13, GREEN if card.get("custom", false) else AMBER)
		label.name = "CardTag"
		head.add_child(label)
	var about := _label(str(card.get("description", "")), 14, DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = CARD_WIDTH - 28.0
	rows.add_child(about)
	rows.add_child(_icons(plan))
	var stats := _label("\n".join(stat_lines(plan)), 14, Color(1, 1, 1, 0.85))
	stats.name = "CardStats"
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.custom_minimum_size.x = CARD_WIDTH - 28.0
	rows.add_child(stats)
	rows.add_child(HSeparator.new())
	var price := RichTextLabel.new()
	price.name = "CardPrice"
	price.bbcode_enabled = true
	price.fit_content = true
	price.scroll_active = false
	price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price.custom_minimum_size.x = CARD_WIDTH - 28.0
	price.add_theme_font_size_override("normal_font_size", 17)
	price.text = price_bbcode(plan)
	rows.add_child(price)
	var changes := changes_text(plan)
	if changes != "":
		var label := _label(changes, 14, AMBER)
		label.name = "CardChanges"
		rows.add_child(label)
	if not card.get("left_out", []).is_empty():
		var left := _label("Not for sale, left out: %s" % ", ".join(card.left_out), 13, AMBER)
		left.name = "CardLeftOut"
		left.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.custom_minimum_size.x = CARD_WIDTH - 28.0
		rows.add_child(left)
	if not plan.missing.is_empty():
		var lock := _label("Needs " + "  ·  ".join(plan.missing), 14, AMBER)
		lock.name = "CardLock"
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock.custom_minimum_size.x = CARD_WIDTH - 28.0
		rows.add_child(lock)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	buttons.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(buttons)
	if card.get("custom", false):
		var delete := Button.new()
		delete.name = "CardDelete"
		delete.text = "DELETE"
		delete.custom_minimum_size = Vector2(120, 42)
		delete.size_flags_vertical = Control.SIZE_SHRINK_END
		delete.pressed.connect(delete_custom.bind(str(card.id)))
		buttons.add_child(delete)
	var buy := Button.new()
	buy.name = "CardBuy"
	buy.text = "BUY"
	buy.custom_minimum_size = Vector2(150, 42)
	buy.size_flags_vertical = Control.SIZE_SHRINK_END
	buy.disabled = not plan.missing.is_empty()
	buy.tooltip_text = "Locked" if buy.disabled else "See every line, then confirm"
	buy.pressed.connect(open_dialog.bind(str(card.id)))
	buttons.add_child(buy)
	return panel


func _tag(card: Dictionary) -> String:
	if card.get("custom", false):
		return "CUSTOM"
	return str(card.get("faction", "")).to_upper()


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


## The main pieces of the kit as small icons.
func _icons(plan: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "CardIcons"
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = ICON_MAX.y
	var kit: Inventory = plan.kit.inventory
	var shown := 0
	for slot in ICON_SLOTS:
		var piece: ItemInstance = kit.equipment.get(slot)
		if piece == null or shown >= 5:
			continue
		var cell := ItemCell.new()
		var fit := Vector2(piece.data.size) * ICON_CELL
		cell.box = fit * minf(1.0, minf(ICON_MAX.x / fit.x, ICON_MAX.y / fit.y))
		cell.item = piece
		cell.tooltip_text = piece.data.display_name
		row.add_child(cell)
		shown += 1
	return row


## The would-be loadout's stats, compact: "Armor class  head 4 · thorax 4 · stomach 4  ·  bare: face, arms, legs",
## "Weight 14.2 kg · 22 of 34 cells", "AK-74N · ergonomics 52 · recoil 0.42° / ±0.31°".
func stat_lines(plan: Dictionary) -> Array[String]:
	var kit: Inventory = plan.kit.inventory
	var armor: Array[String] = []
	var bare: Array[String] = []
	for row in LoadoutStats.armor_rows(kit):
		var piece: ItemInstance = row.piece
		if piece and row.tone == "":
			armor.append("%s %d" % [str(row.name).to_lower(), int(piece.data.stats.get("class", 0))])
		else:
			bare.append(str(row.name).to_lower())
	var room := LoadoutStats.storage(kit)
	var lines: Array[String] = ["Armor class  %s%s" % [" · ".join(armor) if not armor.is_empty() else "none",
		"  ·  bare: %s" % ", ".join(bare) if not bare.is_empty() and not armor.is_empty() else ""],
		"Weight %s  ·  storage %d cells" % [Settings.format_weight(kit.total_weight()), room.y]]
	var slot := kit.weapon_slot()
	var gun: ItemInstance = kit.equipment.get(slot) if slot != "" else null
	if gun and gun.is_gun():
		var data := WeaponStats.build(gun, GameState.skills)
		lines.append("%s  ·  ergonomics %d  ·  recoil %.2f° / ±%.2f°" % [gun.data.display_name, data.ergonomics, data.vertical_recoil, data.horizontal_recoil])
	else:
		lines.append("No gun")
	return lines


## "₽ 361,599  ₽ 401,774 (struck through)  −10%", then "+ $ 1,782 (₽ 258,390 at the exchange)" when
## dollars are involved.
func price_bbcode(plan: Dictionary) -> String:
	var text := "[b]%s[/b]" % UiFormat.money(int(plan.roubles))
	var full := int(plan.full_roubles) + int(plan.full_dollars) * Trading.exchange_roubles(1, true)
	var paid := int(plan.roubles) + int(plan.dollars) * Trading.exchange_roubles(1, true)
	if full > paid:
		text += "   [color=#ffffff80][s]%s[/s][/color]   [color=#8cd97f]−%d%%[/color]" % [UiFormat.money(int(plan.full_roubles)), roundi((full - paid) * 100.0 / full)]
	if int(plan.dollars) > 0:
		text += "\n+ [b]%s[/b]%s  (%s at the exchange)" % [UiFormat.money(int(plan.dollars), "USD"),
			"   [color=#ffffff80][s]%s[/s][/color]" % UiFormat.money(int(plan.full_dollars), "USD") if int(plan.full_dollars) > int(plan.dollars) else "",
			UiFormat.money(Trading.exchange_roubles(int(plan.dollars), true))]
	return text


## "2 substitutions · 1 left out" ("" when the card needs neither).
static func changes_text(plan: Dictionary) -> String:
	var parts: Array[String] = []
	if int(plan.swaps) > 0:
		parts.append("%d substitution%s" % [plan.swaps, "" if int(plan.swaps) == 1 else "s"])
	if int(plan.left_out) > 0:
		parts.append("%d left out" % plan.left_out)
	return " · ".join(parts)


## The card view for card `id` (tests).
func card_view(id: String) -> Control:
	return _grid.get_node_or_null("Card_" + id)


## The first BUY button that can be pressed (a controller lands there when the tab opens), else any.
func first_button() -> Button:
	var fallback: Button = null
	for view in _grid.get_children():
		var buy := view.find_child("CardBuy", true, false) as Button
		if buy and not buy.disabled:
			return buy
		if fallback == null and buy:
			fallback = buy
	return fallback if fallback else _save_button


# --- Custom cards ---------------------------------------------------------------------------------

## SAVE CURRENT GEAR AS QUICK-BUY: a custom card from what you wear and carry, named from the box.
func save_current() -> Dictionary:
	var result := QuickBuy.save_custom(name_box.text, screen.inventory)
	if result.ok:
		name_box.text = ""
		SaveManager.save_game()
	_say(str(result.message), not result.ok or not result.card.get("left_out", []).is_empty())
	refresh(true)
	return result


## DELETE on custom card `id`.
func delete_custom(id: String) -> void:
	for i in GameState.quick_buys.size():
		if str(GameState.quick_buys[i].get("id", "")) == id:
			var name := str(GameState.quick_buys[i].get("name", ""))
			QuickBuy.remove_custom(i)
			SaveManager.save_game()
			_say("Deleted %s." % name, false)
			break
	refresh(true)


func _say(text: String, warning: bool) -> void:
	_status.text = text
	if warning:
		_status.add_theme_color_override("font_color", AMBER)
	else:
		_status.remove_theme_color_override("font_color")


# --- The confirm dialog ---------------------------------------------------------------------------

func _build_dialog() -> void:
	_shade = ColorRect.new()
	_shade.name = "QuickBuyShade"
	_shade.color = Color(0, 0, 0, 0.66)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.hide()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.add_child(center)
	_dialog = PanelContainer.new()
	_dialog.name = "QuickBuyDialog"
	_dialog.custom_minimum_size.x = DIALOG_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.06, 1.0)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	_dialog.add_theme_stylebox_override("panel", style)
	center.add_child(_dialog)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_dialog.add_child(rows)
	var title := Label.new()
	title.name = "DialogTitle"
	title.theme_type_variation = &"AccentLabel"
	title.add_theme_font_size_override("font_size", 24)
	rows.add_child(title)
	rows.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.name = "DialogScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	var lines := VBoxContainer.new()
	lines.name = "DialogLines"
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 4)
	scroll.add_child(lines)
	rows.add_child(HSeparator.new())
	var total := RichTextLabel.new()
	total.name = "DialogTotal"
	total.bbcode_enabled = true
	total.fit_content = true
	total.scroll_active = false
	total.custom_minimum_size.x = DIALOG_WIDTH - 48.0
	total.add_theme_font_size_override("normal_font_size", 19)
	rows.add_child(total)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	_cancel = Button.new()
	_cancel.name = "DialogCancel"
	_cancel.text = "CANCEL"
	_cancel.custom_minimum_size = Vector2(170, 46)
	_cancel.pressed.connect(close_dialog)
	buttons.add_child(_cancel)
	_confirm = Button.new()
	_confirm.name = "DialogConfirm"
	_confirm.text = "CONFIRM"
	_confirm.custom_minimum_size = Vector2(170, 46)
	_confirm.pressed.connect(confirm)
	buttons.add_child(_confirm)


func dialog_open() -> bool:
	return _shade != null and _shade.is_inside_tree() and _shade.visible


## BUY on card `id`: works it out against the stash and opens the dialog. Returns the plan.
func open_dialog(id: String) -> Dictionary:
	var card := {}
	for each in QuickBuy.cards():
		if str(each.id) == id:
			card = each
	if card.is_empty() or screen == null:
		return {}
	_show(QuickBuy.plan(card, screen.inventory, screen.stash), "")
	return dialog_plan


## Fills the dialog with `plan` (`note` on top, amber) and shows it over everything.
func _show(plan: Dictionary, note: String) -> void:
	dialog_plan = plan
	_buying = false
	if _shade.get_parent() == null:
		screen.overlay().add_child(_shade)
	screen.overlay().move_child(_shade, -1)  # Over any container window.
	(_dialog.find_child("DialogTitle", true, false) as Label).text = "BUY %s" % str(plan.card.get("name", "")).to_upper()
	var lines := _dialog.find_child("DialogLines", true, false) as VBoxContainer
	for child in lines.get_children():
		lines.remove_child(child)
		child.queue_free()
	if note != "":
		lines.add_child(_dialog_line(note, AMBER))
	for line: Dictionary in plan.lines:
		lines.add_child(_dialog_line(line_text(line), AMBER if line.swap or line.left_out else Color(1, 1, 1, 0.92)))
	lines.add_child(_dialog_line("", DIM))
	for text: String in plan.kit.placed:
		lines.add_child(_dialog_line(text, DIM.lightened(0.2)))
	var going := QuickBuy.names(plan.to_stash)
	if not going.is_empty():
		lines.add_child(_dialog_line("To the stash: %s" % ", ".join(going), DIM.lightened(0.2)))
	if screen.inventory.equipment.get("secure"):
		lines.add_child(_dialog_line("Your %s stays on, with what's in it" % screen.inventory.equipment.secure.data.display_name, DIM.lightened(0.2)))
	for reason: String in plan.reasons:
		lines.add_child(_dialog_line(reason, RED))
	(_dialog.find_child("DialogTotal", true, false) as RichTextLabel).text = "Total  " + price_bbcode(plan)
	_confirm.disabled = not plan.reasons.is_empty()
	_shade.show()
	screen.trap_focus(true, _shade)
	_fit.call_deferred()
	(_cancel if _confirm.disabled else _confirm).grab_focus.call_deferred()


## "AK-74N  ·  Bulat  ·  ₽ 36,900"; a swap "Tundra 47 instead of AK-74N (sold out at Bulat)  ·  Bulat  ·  ₽ 46,800";
## a left-out line "Left out: Red dot sight (needs Tinker LL2, and nothing like it is for sale)".
static func line_text(line: Dictionary) -> String:
	var wanted := ItemDB.get_item(str(line.wanted)) if ItemDB.has_item(str(line.wanted)) else null
	var wanted_name := wanted.display_name if wanted else str(line.wanted)
	if line.left_out:
		return "Left out: %s (%s)" % [wanted_name, line.why]
	var data := ItemDB.get_item(str(line.item))
	var name := ("%d × %s" % [int(line.count), data.display_name]) if int(line.count) > 1 else data.display_name
	if line.swap:
		name += " instead of %s (%s)" % [wanted_name, line.why] if str(line.item) != str(line.wanted) else " from %s (%s)" % [TraderTable.display_name(str(line.trader)), line.why]
	return "%s  ·  %s  ·  %s" % [name, TraderTable.display_name(str(line.trader)), UiFormat.money(int(line.price), str(line.currency))]


func _dialog_line(text: String, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = DIALOG_WIDTH - 72.0
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", colour)
	return label


func _fit() -> void:
	var scroll := _dialog.find_child("DialogScroll", true, false) as ScrollContainer
	var lines := _dialog.find_child("DialogLines", true, false) as Control
	scroll.custom_minimum_size.y = minf(lines.get_combined_minimum_size().y, screen.size.y * DIALOG_MAX_HEIGHT)
	_dialog.reset_size()


## The dialog's lines as text, in order (tests and tools).
func dialog_lines() -> Array[String]:
	var result: Array[String] = []
	for child in _dialog.find_child("DialogLines", true, false).get_children():
		if not child.is_queued_for_deletion():
			result.append((child as Label).text)
	return result


## CANCEL (or Esc / B): closes the dialog, nothing bought.
func close_dialog() -> void:
	dialog_plan = {}
	_shade.hide()
	screen.trap_focus(false, _shade)
	focus_first.call_deferred()


## Puts the focus on the first BUY that can be pressed (when the tab shows: a controller lands there).
func focus_first() -> void:
	var first := first_button()
	if first and first.is_inside_tree() and is_visible_in_tree():
		first.grab_focus()


## CONFIRM: buys the plan the dialog shows (once: a second press does nothing). Prices or stock that
## moved since it opened show the card again; any other reason stays in the dialog. Saves after.
func confirm() -> Dictionary:
	if _buying or dialog_plan.is_empty():
		return {"ok": false, "changed": false, "message": "", "reasons": []}
	_buying = true
	_confirm.disabled = true
	var result := QuickBuy.buy(dialog_plan, screen.inventory, screen.stash)
	if result.ok:
		SaveManager.save_game()
		screen.gear_changed()
		refresh()
		close_dialog()
		_say(str(result.message), false)
	elif result.changed:
		_show(result.plan, "Prices or stock changed since you opened it: check the card again")
	else:
		_show(QuickBuy.plan(dialog_plan.card, screen.inventory, screen.stash), "")
	return result
