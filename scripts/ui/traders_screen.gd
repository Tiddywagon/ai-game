extends MenuScreen
## TRADERS screen (DESIGN.md §10, §16.2): every trader with your loyalty level, reputation and what
## the next level needs. Buying, selling and bartering come in a later update.

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

var _buttons: Array[Button] = []


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
	_buttons[TRADERS.find(trader)].set_pressed_no_signal(true)
	var loyalty: Dictionary = GameState.trader_loyalty[trader.id]
	%TraderName.text = trader.name.to_upper()
	%TraderInfo.text = "%s\nCurrency: %s\n%s" % [trader.specialty, trader.currency, trader.unique]
	if trader.get("locked", false):
		%Loyalty.text = "Locked. Complete his introduction quest to trade with Jaeger."
		return
	var lines := ["Loyalty level %d  ·  reputation %.2f  ·  spent %s" % [loyalty.level, loyalty.reputation, UiFormat.money(loyalty.spent)]]
	var next: int = loyalty.level + 1
	if LOYALTY.has(next):
		var need: Array = LOYALTY[next]
		lines.append("Next level (LL%d) needs: player level %d, reputation %.2f, %s spent with %s." % [
			next, need[0], need[1], UiFormat.money(need[2]), trader.name])
	else:
		lines.append("Highest loyalty level reached.")
	%Loyalty.text = "\n".join(lines)
