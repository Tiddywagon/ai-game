extends "res://tests/test_base.gd"
## Menus and raids (needs a display): every screen of the main menu opens and closes through its
## buttons (LOADOUT with AUTO-EQUIP and UNDO and its QUICK BUY tab buying a card, CHARACTER and its COLLECTION, HIDEOUT's plan and station panel (a build, fuel, handing over, a craft collected, a cosmetic), the Collectors Shelf's 3D SHELF (place, move and remove with the mouse, keys, touch and its buttons; zoom and pan) and COLLECTION, TRADERS with every
## trader's tabs, a purchase and a sale, FLEA MARKET locked before level 15, then browsing, filtering,
## buying, listing, a sale and COLLECT, and opened from TRADERS, ENTER RAID up to the loadout check, SETTINGS), then a seeded PMC
## raid on each map and a Scav run joined mid-raid, with the AI on. A Logger counts every error the
## engine reports (script errors included): there must be none.
## Each raid renders its first and last 0.1 s; in between only the render loop pauses (scripts,
## physics and the AI run as ever): the fog-of-war masks make every rendered frame slow under xvfb.

## Counts the errors and warnings the engine reports while it's added (OS.add_logger()).
class ErrorCounter extends Logger:
	var errors := 0
	var warnings := 0
	var first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
			return
		errors += 1
		if first == "":
			first = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Game seconds of a raid drawn at its start and its end.
const RENDERED := 0.1
const MAPS := [["test_yard", "res://maps/test_level.tscn"], ["factory", "res://maps/factory.tscn"]]

var counter := ErrorCounter.new()
var menu: Node
var started := 0


func run() -> void:
	started = Time.get_ticks_msec()
	OS.add_logger(counter)
	DisplayServer.window_set_size(Vector2i(640, 360))  # Rendering a smaller window keeps the raids quick.
	fresh_profile(0)
	gs.stash.add(item("ssh68_helmet"))  # Something for AUTO-EQUIP to put on.
	gs.stash.add(item("fuel_can"))  # What the generator needs.
	gs.quests["zoya_introduction"] = {"state": "completed", "progress": [1, 2, 150000]}  # The Broker trades.
	change_scene_to_file("res://ui/main_menu.tscn")
	await frames(5)
	menu = current_scene
	check(menu != null and menu.scene_file_path == "res://ui/main_menu.tscn" and _find(menu, "Menu").visible
		and not _find(menu, "FactionPicker").visible, "the main menu opens on the profile")
	await _loadout()
	await _character()
	await _hideout()
	await _shelf()
	await _traders()
	await _quests()
	await _flea()
	await _raid_setup()
	await _settings()
	check(counter.errors == 0, "no errors in the menus%s" % ("" if counter.errors == 0 else ": %d, first %s" % [counter.errors, counter.first]))
	for map: Array in MAPS:
		await _raid({"side": "pmc", "map": map[0], "loadout": gs.pmc_loadout(), "seed": 4, "boss": false}, map[1], 20.0)
	await _raid({"side": "scav", "map": "test_yard", "loadout": gs.scav_loadout(), "seed": 4, "boss": false, "offset": 400}, MAPS[0][1], 10.0)
	await _practice_raid()
	OS.remove_logger(counter)


func section(title: String) -> void:
	super("%s   (%.1f s)" % [title, (Time.get_ticks_msec() - started) / 1000.0])


func _find(from: Node, name: String) -> Node:
	return from.find_child(name, true, false)


## Presses `button_name` on the main menu and returns the screen it opened (null if none).
func _open(button_name: String) -> Node:
	(_find(menu, button_name) as Button).pressed.emit()
	await frames(3)
	var host := _find(menu, "ScreenHost")
	return host.get_child(0) if host.get_child_count() == 1 else null


## Presses `button_name` on `screen` and checks the menu is back.
func _close(screen: Node, button_name: String, what: String) -> void:
	(_find(screen, button_name) as Button).pressed.emit()
	await frames(3)
	check(not is_instance_valid(screen) and _find(menu, "ScreenHost").get_child_count() == 0 and _find(menu, "Menu").visible,
		"%s closes back to the menu" % what)


## QUESTS (DESIGN.md §11): the tabs, a quest accepted and tracked through its buttons, the trader filter,
## the chain line, and the log opened from TRADERS too.
func _quests() -> void:
	section("QUESTS")
	var quests: GDScript = load("res://scripts/progression/quest_log.gd")
	var screen := await _open("QuestsButton")
	check(screen != null and screen.name == "QuestsScreen", "QUESTS opens the quest log")
	if screen == null:
		return
	(_find(screen, "AvailableTab") as Button).pressed.emit()
	await frames(2)
	var row := _find(screen, "Quest_scrap_run") as Button
	check(row != null, "AVAILABLE lists Scrap Run")
	if row:
		row.pressed.emit()
		await frames(2)
	check((_find(screen, "QuestTitle") as Label).text == "SCRAP RUN", "picking it shows it")
	(_find(screen, "AcceptButton") as Button).pressed.emit()
	await frames(2)
	check(quests.state(quests.find("scrap_run")) == "active" and screen.tab == 0 and screen.selected == "scrap_run", "ACCEPT: it's active, the log follows it to ACTIVE")
	(_find(screen, "TrackButton") as Button).pressed.emit()
	await frames(2)
	check(quests.is_tracked(quests.find("scrap_run")) and (_find(screen, "TrackButton") as Button).text == "UNTRACK", "TRACK tracks it")
	var filter := _find(screen, "TraderFilter") as OptionButton
	for i in filter.item_count:
		if str(filter.get_item_metadata(i)) == "vera":
			filter.select(i)
			filter.item_selected.emit(i)
	await frames(2)
	check(screen.quests_on(0).is_empty() and screen.quests_on(1).all(func(quest: Dictionary) -> bool: return quest.trader == "vera"), "the trader filter shows Doc Vera's quests only")
	filter.select(0)
	filter.item_selected.emit(0)
	(_find(screen, "AvailableTab") as Button).pressed.emit()
	await frames(2)
	var safekeeping := _find(screen, "Quest_safekeeping") as Button
	if safekeeping:
		safekeeping.pressed.emit()
		await frames(2)
	var chain := _find(screen, "Chain") as Label
	check(chain != null and "after Scrap Run ✗" in chain.text, "a locked quest shows its chain (%s)" % (chain.text if chain else "none"))
	(_find(screen, "CompletedTab") as Button).pressed.emit()
	await frames(2)
	check(_find(screen, "Quest_zoya_introduction") != null, "COMPLETED lists A Word in His Ear")
	await _close(screen, "BackButton", "QUESTS")
	var traders := await _open("TradersButton")
	(_find(traders, "QuestsButton") as Button).pressed.emit()
	await frames(3)
	var log := _find(traders, "QuestsScreen")
	check(log != null and log.trader_filter == "bulat", "TRADERS opens the quest log on the trader shown")
	if log:
		(_find(log, "BackButton") as Button).pressed.emit()
		await frames(3)
	check(_find(traders, "QuestsScreen") == null, "and closes back to TRADERS")
	await _close(traders, "BackButton", "TRADERS")
	gs.quests["scrap_run"] = {"state": "completed", "progress": [3, 2]}  # For the raid's tracker: a quest with raid objectives.
	quests.accept(quests.find("yard_sweep"))
	quests.set_tracked(quests.find("yard_sweep"), true)


## The inventory and stash as text, the stash in cell order.
func _gear_state() -> String:
	var stash: Array = gs.stash.to_array()
	stash.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a.y, a.x] < [b.y, b.x])
	return JSON.stringify([gs.inventory.to_dict(), stash], "", true, true)


func _loadout() -> void:
	section("LOADOUT")
	var screen := await _open("LoadoutButton")
	check(screen != null and screen.scene_file_path == "res://ui/loadout_screen.tscn" and not _find(menu, "Menu").visible, "LOADOUT opens over the menu")
	var slots: Array = load("res://scripts/inventory/inventory.gd").SLOTS
	check(slots.all(func(slot: Array) -> bool: return _find(screen, "Slot_" + slot[0]) != null), "it shows all 11 slots")
	var stats: Array = screen.find_children("Stat_*", "Label", true, false)
	check(stats.size() >= 5 and stats.all(func(label: Label) -> bool: return label.text != ""), "and the stats (%d)" % stats.size())
	var before := _gear_state()
	(_find(screen, "AutoEquipButton") as Button).pressed.emit()
	await frames(3)
	var summary: Control = _find(screen, "AutoEquipShade")
	check(summary != null and summary.visible and (_find(screen, "SummaryLines") as Control).get_child_count() > 0, "AUTO-EQUIP shows its summary")
	check(gs.inventory.equipment.helmet != null and gs.inventory.equipment.helmet.data.id == "ssh68_helmet" and gs.stash.count_of("ssh68_helmet") == 0,
		"the helmet from the stash is put on")
	(_find(screen, "SummaryUndo") as Button).pressed.emit()
	await frames(3)
	check(not summary.visible and gs.inventory.equipment.helmet == null and _gear_state() == before, "UNDO closes it and puts everything back")
	(_find(screen, "TabQuickBuy") as Button).pressed.emit()
	await frames(3)
	var tab: Control = _find(screen, "QuickBuyTab")
	check(tab.visible and not _find(screen, "Columns").visible and _find(tab, "Card_last_resort") != null
		and _find(tab, "QuickBuyCards").get_child_count() == 9, "the QUICK BUY tab shows the nine BEAR cards")
	(_find(_find(tab, "Card_last_resort"), "CardBuy") as Button).pressed.emit()
	await frames(3)
	check((_find(screen, "QuickBuyShade") as Control).visible and get_root().gui_get_focus_owner() == _find(screen, "DialogConfirm"),
		"BUY on Last Resort opens the confirm dialog, CONFIRM focused")
	var roubles: int = gs.roubles
	(_find(screen, "DialogConfirm") as Button).pressed.emit()
	await frames(3)
	check(not (_find(screen, "QuickBuyShade") as Control).visible and gs.inventory.equipment.pistol != null
		and gs.inventory.equipment.pistol.data.id == "pm_pistol" and gs.roubles < roubles, "CONFIRM buys it: the PM is on, the money paid")
	gs.roubles = roubles  # The screens below count on the money they started with.
	(_find(screen, "TabLoadout") as Button).pressed.emit()
	await frames(2)
	check(_find(screen, "Columns").visible and not tab.visible, "LOADOUT is back")
	await _close(screen, "CloseButton", "LOADOUT")


func _character() -> void:
	section("CHARACTER")
	var screen := await _open("CharacterButton")
	check(screen != null and screen.scene_file_path == "res://ui/character_screen.tscn", "CHARACTER opens")
	check(_find(screen, "XpBar") != null and _find(screen, "ScavKarma") != null and _find(screen, "StashCount") != null, "it shows experience, karma and the stash")
	(_find(screen, "CollectionButton") as Button).pressed.emit()
	await frames(3)
	var collection: Node = _find(screen, "CollectionScreen")
	check(collection != null and collection.tab == collection.COLLECTION and not _find(screen, "Margin").visible and _find(collection, "Set_raiders") != null,
		"COLLECTION opens the figure collection over CHARACTER")
	(_find(collection, "BackButton") as Button).pressed.emit()
	await frames(3)
	check(not is_instance_valid(collection) and _find(screen, "Margin").visible, "and BACK returns to CHARACTER")
	await _close(screen, "BackButton", "CHARACTER")


func _hideout() -> void:
	section("HIDEOUT")
	var hideout: GDScript = load("res://scripts/progression/hideout.gd")
	var work: GDScript = load("res://scripts/progression/hideout_work.gd")
	var screen := await _open("HideoutButton")
	var map: Node = _find(screen, "Map") if screen else null
	var rooms: Array = hideout.stations().filter(func(station: Dictionary) -> bool: return _find(map, "Room_" + station.id) is Button)
	check(screen != null and rooms.size() == 14, "HIDEOUT shows the plan with every station as a room")
	var room: Button = _find(map, "Room_generator")
	check("Can be built" in room.text and "Locked" in (_find(map, "Room_bitcoin_farm") as Button).text, "the generator's room says it can be built, the farm's that it's locked")
	room.pressed.emit()
	await frames(2)
	var details: Node = _find(screen, "Details")
	var build: Button = _find(details, "Build")
	check(build != null and not build.disabled and build.text == "BUILD" and _find(details, "Level_3") != null, "its panel shows the upgrade tree with BUILD")
	build.pressed.emit()
	await frames(3)
	check(gs.hideout_state.builds.has("generator") and gs.roubles == 450000 and gs.stash.count_of("fuel_can") == 0, "pressing it starts the generator's build")
	check((_find(screen, "Status") as Label).text == "Done." and _find(details, "BuildCountdown") != null and "Building" in room.text,
		"the panel counts the build down, the room says Building")
	work.now_override = Time.get_unix_time_from_system() + 4.0 * 60.0
	screen._tick()
	await frames(2)
	check(gs.hideout.get("generator", 0) == 1 and _find(details, "FuelGauge") != null and _find(details, "PowerSwitch") != null,
		"four minutes later it's built: the fuel gauge and the switch")
	gs.stash.add(item("fuel_can"))
	screen._refresh()
	await frames(2)
	(_find(details, "AddFuel") as Button).pressed.emit()
	await frames(3)
	check(gs.hideout_state.fuel.size() == 1 and work.has_power() and (_find(details, "FuelGauge") as ProgressBar).value > 0.4
		and (_find(screen, "Power") as Label).text.begins_with("POWER ON"), "ADD FUEL CAN fills a slot: power on, the gauge up")
	(_find(details, "PowerSwitch") as CheckButton).button_pressed = false
	await frames(3)
	check(not work.has_power() and (_find(screen, "Power") as Label).text.begins_with("NO POWER"), "the switch turns the generator off")
	(_find(details, "PowerSwitch") as CheckButton).button_pressed = true
	await frames(3)
	(_find(map, "Room_medstation") as Button).pressed.emit()
	await frames(2)
	var hand: Button = _find(details, "HandOver_bandage")
	check(hand != null and not hand.disabled, "the Medstation's bandages have HAND OVER")
	hand.pressed.emit()
	await frames(3)
	check(hideout.handed(hideout.find("medstation"), "bandage") == 2 and "2 / 2 in" in (_find(_find(details, "HandOver_bandage").get_parent(), "Count") as Label).text,
		"handing over shows 2 / 2")
	(_find(details, "Build") as Button).pressed.emit()
	await frames(3)
	work.now_override += 6.0 * 60.0
	screen._tick()
	await frames(2)
	gs.stash.add(item("duct_tape"))
	screen._refresh()
	await frames(2)
	(_find(details, "Craft_medkit") as Button).pressed.emit()
	await frames(3)
	check(work.queue(hideout.find("medstation")).size() == 1 and _find(details, "Queue_0") != null and "Crafting" in (_find(map, "Room_medstation") as Button).text,
		"CRAFT queues the medkit: the queue counts it down, the room says Crafting")
	var medkits: int = gs.stash.count_of("ai2_medkit")
	work.now_override += 6.0 * 60.0
	screen._tick()
	await frames(2)
	check("READY" in (_find(map, "Room_medstation") as Button).text and _find(details, "Collect") != null, "done: the room says it's ready, the panel has COLLECT")
	(_find(details, "Collect") as Button).pressed.emit()
	await frames(3)
	check(gs.stash.count_of("ai2_medkit") == medkits + 1, "COLLECT puts the medkit in the stash")
	(_find(screen, "DecorButton") as Button).pressed.emit()
	await frames(2)
	gs.stash.add(item("toilet_paper"))
	gs.stash.add(item("toilet_paper"))
	gs.stash.add(item("duct_tape"))
	screen._refresh()
	await frames(2)
	(_find(details, "Buy_poster_wall") as Button).pressed.emit()
	await frames(3)
	check(gs.hideout_state.cosmetics == ["poster_wall"], "DECOR buys the poster wall (%s)" % (_find(screen, "Status") as Label).text)
	work.now_override = -1.0
	await _close(screen, "BackButton", "HIDEOUT")


## The Collectors Shelf: its panel in HIDEOUT opens the 3D shelf; a figure placed from the stash list,
## a slot picked with a click, a tap and the arrow keys, MOVE to a clicked slot, REMOVE, the wheel, a
## pinch and a drag zooming and panning; the COLLECTION tab with a model, a silhouette and set progress.
func _shelf() -> void:
	section("COLLECTORS SHELF")
	var figures: GDScript = load("res://scripts/progression/figures.gd")
	gs.hideout["collectors_shelf"] = 2
	var fox: RefCounted = item("figure_fox")
	gs.stash.add(fox)
	gs.stash.add(item("figure_rat"))
	var host := await _open("HideoutButton")
	(_find(_find(host, "Map"), "Room_collectors_shelf") as Button).pressed.emit()
	await frames(2)
	var open: Button = _find(host, "OpenShelf")
	check(open != null and not open.disabled and _find(host, "OpenCollection") != null, "the Collectors Shelf's panel has SHELF and COLLECTION")
	open.pressed.emit()
	await frames(4)
	var screen: Node = _find(host, "CollectionScreen")
	check(screen != null and screen.tab == screen.SHELF and _find(screen, "ShelfViewport") is SubViewport and _find(_find(screen, "ShelfWorld"), "Slot_27") != null
		and _find(_find(screen, "ShelfWorld"), "Slot_28") == null and _find(_find(screen, "ShelfWorld"), "Lamp_1") != null, "SHELF: a lit 3D shelf with 28 slots on two boards at level 2")
	(_find(screen, "Place_figure_fox") as Button).pressed.emit()
	await frames(2)
	check(figures.placed(0) == fox and gs.stash.count_of("figure_fox") == 0 and _find(_find(screen, "ShelfWorld"), "Figure_figure_fox") != null,
		"picking the fox from the stash list puts it in slot 1, where its model stands")
	var view: Control = _find(screen, "ShelfView")
	var click := func(slot: int, touch := false) -> void:
		var camera: Camera3D = _find(screen, "Camera")
		var scale := Vector2(_find(screen, "ShelfViewport").size) / view.size
		var at: Vector2 = camera.unproject_position(screen.slot_position(slot) + Vector3(0.0, 0.18, 0.0)) / scale
		if touch:
			var tap := InputEventScreenTouch.new()
			tap.position = at
			tap.pressed = true
			view.gui_input.emit(tap)
			tap = tap.duplicate()
			tap.pressed = false
			view.gui_input.emit(tap)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = at
		view.gui_input.emit(event)
	click.call(5)
	await frames(2)
	check(screen.selected == 5 and (_find(screen, "SlotTitle") as Label).text.begins_with("SLOT 6 OF 28"), "a click picks slot 6 (%s)" % (_find(screen, "SlotTitle") as Label).text)
	click.call(9, true)
	await frames(2)
	check(screen.selected == 9, "so does a tap (slot 10)")
	for action: String in ["ui_right", "ui_down", "ui_left"]:
		var key := InputEventAction.new()
		key.action = action
		key.pressed = true
		view.gui_input.emit(key)
	await frames(2)
	check(screen.selected == 9 + 14, "the arrow keys / d-pad step along a board and down to the next (%d)" % screen.selected)
	screen.pick_slot(0)
	await frames(2)
	(_find(screen, "Move") as Button).pressed.emit()
	await frames(2)
	check(screen.moving == 0 and (_find(screen, "Move") as Button).text == "CANCEL MOVE", "MOVE waits for the slot to move to")
	click.call(12)
	await frames(2)
	check(figures.placed(12) == fox and figures.placed(0) == null and screen.moving == -1 and screen.selected == 12, "a click on slot 13 moves the fox there")
	var zoom: float = screen.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	view.gui_input.emit(wheel)
	check(screen.zoom < zoom, "the wheel zooms in (%.2f from %.2f)" % [screen.zoom, zoom])
	zoom = screen.zoom
	for finger in 2:
		var touch := InputEventScreenTouch.new()
		touch.index = finger
		touch.pressed = true
		touch.position = Vector2(300 + finger * 100, 300)
		view.gui_input.emit(touch)
	var spread := InputEventScreenDrag.new()
	spread.index = 1
	spread.position = Vector2(600, 300)
	view.gui_input.emit(spread)
	check(screen.zoom < zoom, "two fingers spreading apart zoom in (%.2f from %.2f)" % [screen.zoom, zoom])
	for finger in 2:
		var lift := InputEventScreenTouch.new()
		lift.index = finger
		view.gui_input.emit(lift)
	var pan: Vector2 = screen.pan
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(-120, 40)
	view.gui_input.emit(drag)
	check(screen.pan != pan, "a one-finger drag pans (%s)" % str(screen.pan))
	(_find(screen, "Remove") as Button).pressed.emit()
	await frames(2)
	check(figures.placed(12) == null and gs.stash.count_of("figure_fox") == 1 and (_find(screen, "Status") as Label).text == "Back in the stash.", "REMOVE puts the fox back in the stash")
	(_find(screen, "Place_figure_rat") as Button).pressed.emit()
	await frames(2)
	(_find(screen, "CollectionTab") as Button).pressed.emit()
	await frames(4)
	var rat: Node = _find(screen, "Card_figure_rat")
	var leshy: Node = _find(screen, "Card_figure_leshy")
	check(rat != null and _find(rat, "Model") != null and (_find(rat, "Name") as Label).text == "The Rat" and "shown" in (_find(rat, "State") as Label).text,
		"COLLECTION: the rat in colour, owned and displayed")
	check(leshy != null and _find(leshy, "Silhouette") != null and (_find(leshy, "Name") as Label).text == "???" and (_find(leshy, "State") as Label).text == "Missing",
		"a figure never owned is a dark silhouette with its name hidden")
	check((_find(_find(screen, "Set_raiders"), "Progress") as Label).text == "Raiders  1 / 6  ·  1 displayed" and (_find(_find(screen, "Set_wildlife"), "Progress") as Label).text == "Wildlife  1 / 6  ·  0 displayed",
		"each set's progress (%s)" % (_find(_find(screen, "Set_raiders"), "Progress") as Label).text)
	check("on while all 6 are displayed" in (_find(_find(screen, "Set_raiders"), "Bonus") as Label).text, "and its bonus, off")
	(_find(screen, "BackButton") as Button).pressed.emit()
	await frames(3)
	check(not is_instance_valid(screen) and _find(host, "Margin").visible, "BACK returns to the hideout")
	await _close(host, "BackButton", "HIDEOUT")


func _traders() -> void:
	section("TRADERS")
	var traders: GDScript = load("res://scripts/data/trader_table.gd")
	var screen := await _open("TradersButton")
	check(screen != null and screen.scene_file_path == "res://ui/traders_screen.tscn", "TRADERS opens")
	var tabs: TabContainer = _find(screen, "Tabs")
	for trader: Dictionary in traders.all():
		(_find(screen, "Trader_" + trader.id) as Button).pressed.emit()  # Draws the trader at once.
		var built := 0
		for tab in tabs.get_tab_count():
			tabs.current_tab = tab  # Draws the tab at once, if it's waiting to be drawn.
			built += 1 if tabs.get_tab_control(tab).get_node("Rows").get_child_count() > 0 else 0
		check((_find(screen, "TraderName") as Label).text == str(trader.name).to_upper() and tabs.visible and tabs.get_tab_count() >= 5
			and built == tabs.get_tab_count(), "%s: all %d tabs build" % [trader.name, tabs.get_tab_count()])
	(_find(screen, "Trader_zoya") as Button).pressed.emit()
	tabs.current_tab = 0
	var row: Node = _find(tabs, "Offer_zoya_nails")
	var buy: Button = row.find_children("*", "Button", false, false)[0] if row else null
	check(buy != null and buy.text == "BUY" and not buy.disabled, "Zoya's nails have a BUY button")
	var before: int = gs.roubles  # What the hideout's builds left.
	buy.pressed.emit()
	await frames(3)
	check(gs.stash.count_of("nails") == 1 and gs.roubles == before - 7500 and (_find(screen, "Status") as Label).text == "Done.", "pressing it buys them")
	tabs.current_tab = tabs.get_node("SELL").get_index()
	var sell_rows: Array = tabs.get_node("SELL/Rows").get_children().filter(func(child: Node) -> bool:
		return child.has_meta("item") and (child.get_meta("item") as RefCounted).data.id == "nails")
	check(sell_rows.size() == 1, "the nails are on Zoya's SELL tab")
	var price: int = load("res://scripts/progression/selling.gd").price("zoya", sell_rows[0].get_meta("item"))
	(sell_rows[0].get_node("SellButton") as Button).pressed.emit()
	await frames(3)
	check(price > 0 and gs.stash.count_of("nails") == 0 and gs.roubles == before - 7500 + price
		and (_find(screen, "Status") as Label).text.begins_with("Sold 1 item to Auntie Zoya"), "its SELL button sells them back (for %d)" % price)
	await _close(screen, "BackButton", "TRADERS")


func _flea() -> void:
	section("FLEA MARKET")
	var flea: GDScript = load("res://scripts/progression/flea_market.gd")
	var stock: GDScript = load("res://scripts/progression/trader_stock.gd")
	var level: int = gs.level
	gs.level = 14
	menu._refresh_profile()
	var button: Button = _find(menu, "FleaButton")
	check(button.disabled and button.text.ends_with("Level 15"), "level 14: FLEA MARKET is locked (\"%s\")" % button.text)
	gs.level = 15
	menu._refresh_profile()
	check(not button.disabled and button.text == "FLEA MARKET", "level 15: it opens")
	stock.now_override = 2_000_000.0
	var screen := await _open("FleaButton")
	check(screen != null and screen.scene_file_path == "res://ui/flea_screen.tscn", "FLEA MARKET opens")
	var tabs: TabContainer = _find(screen, "Tabs")
	check(tabs.get_tab_count() == 3 and tabs.get_tab_title(0) == "BROWSE" and tabs.get_tab_title(1) == "SELL" and tabs.get_tab_title(2) == "MY LISTINGS",
		"tabs BROWSE, SELL and MY LISTINGS")
	var rows: Array = _find(screen, "Listings").get_children().filter(func(row: Node) -> bool: return row.has_meta("listing"))
	check(rows.size() == flea.listings().size() and rows.size() > 50, "BROWSE shows every listing up (%d)" % rows.size())
	var prices := rows.map(func(row: Node) -> int: return flea.price(row.get_meta("listing")))
	var sorted := prices.duplicate()
	sorted.sort()
	check(prices == sorted, "sorted by price, cheapest first")
	(_find(screen, "Sort") as OptionButton).select(1)
	(_find(screen, "Sort") as OptionButton).item_selected.emit(1)
	await frames(2)
	rows = _find(screen, "Listings").get_children().filter(func(row: Node) -> bool: return row.has_meta("listing"))
	var times := rows.map(func(row: Node) -> float: return flea.seconds_left(row.get_meta("listing")))
	var sorted_times := times.duplicate()
	sorted_times.sort()
	check(times == sorted_times, "sorted by time left")
	var target: Dictionary = rows[0].get_meta("listing")
	var search: LineEdit = _find(screen, "Search")
	search.text = target.item.data.display_name
	search.text_changed.emit(search.text)
	var visible := rows.filter(func(row: Node) -> bool: return row.visible)
	check(not visible.is_empty() and visible.all(func(row: Node) -> bool: return row.get_meta("listing").item.data.display_name.contains(target.item.data.display_name))
		and visible.size() < rows.size(), "the search shows only %s (%d rows)" % [target.item.data.display_name, visible.size()])
	search.text = ""
	search.text_changed.emit("")
	var rarity: OptionButton = _find(screen, "Rarity")
	rarity.select(1)
	rarity.item_selected.emit(1)
	check(rows.all(func(row: Node) -> bool: return row.visible == (row.get_meta("listing").item.data.rarity == 0)), "the rarity filter shows only Common listings")
	rarity.select(0)
	rarity.item_selected.emit(0)
	var cost: int = flea.price(target)
	var money: int = gs.roubles
	var buy: Button = rows[0].find_children("*", "Button", false, false)[0]
	check(buy.text == "BUY" and not buy.disabled, "the listing has a BUY button")
	buy.pressed.emit()
	await frames(3)
	check(gs.roubles == money - cost and (_find(screen, "Status") as Label).text.begins_with("Bought ") and flea.find(target.id).is_empty(),
		"BUY charges the price shown (%d) and the listing goes" % cost)
	var watch: RefCounted = item("roler")
	watch.fir = true
	gs.stash.add(watch)
	tabs.current_tab = 1
	screen._fill_all()
	await frames(2)
	var picks: Array = _find(screen, "StashItems").get_children().filter(func(row: Node) -> bool: return row.has_meta("item") and row.get_meta("item") == watch)
	check(picks.size() == 1, "SELL lists the found-in-raid Roler")
	(picks[0].get_node("Pick") as Button).pressed.emit()
	await frames(2)
	var price_box: SpinBox = _find(screen, "AskingPrice")
	check(price_box != null and roundi(price_box.value) == flea.market_price(watch) and (_find(screen, "Fee") as Label).text.begins_with("Fee: ")
		and (_find(screen, "Estimate") as Label).text.begins_with("Sells in"), "the form asks the market price and shows the fee and how fast it sells")
	var asking := roundi(price_box.value)
	var fee: int = flea.listing_fee(watch, asking)
	money = gs.roubles
	(_find(screen, "ListButton") as Button).pressed.emit()
	await frames(3)
	check(gs.roubles == money - fee, "LIST pays the fee (%d)" % fee)
	check(flea.own_listings().size() == 1 and gs.stash.find_holder(watch) == null, "and the Roler is listed")
	stock.now_override = 2_000_000.0 + 3600.0
	screen._tick()
	await frames(2)
	tabs.current_tab = 2
	var mine: Node = _find(screen, "Mine_own_1")
	var collect: Button = mine.find_children("*", "Button", false, false)[0] if mine else null
	check(collect != null and collect.text == "COLLECT" and tabs.get_tab_title(2) == "MY LISTINGS (1)", "an hour later it has sold: COLLECT")
	money = gs.roubles
	collect.pressed.emit()
	await frames(3)
	check(gs.roubles == money + asking and flea.own_listings().is_empty(), "COLLECT pays the asking price (%d)" % asking)
	await _close(screen, "BackButton", "FLEA MARKET")
	var traders := await _open("TradersButton")
	(_find(traders, "FleaButton") as Button).pressed.emit()
	await frames(3)
	var over: Node = _find(traders, "FleaScreen")
	check(over != null and not (_find(traders, "Margin") as Control).visible, "TRADERS opens the flea market over itself")
	(_find(over, "BackButton") as Button).pressed.emit()
	await frames(3)
	check(not is_instance_valid(over) and (_find(traders, "Margin") as Control).visible, "and comes back to TRADERS")
	await _close(traders, "BackButton", "TRADERS")
	stock.now_override = -1.0
	gs.level = level
	menu._refresh_profile()


func _raid_setup() -> void:
	section("ENTER RAID")
	var maps: Array = load("res://scripts/data/map_info.gd").load_all()
	var screen := await _open("EnterRaidButton")
	check(screen != null and _find(screen, "MapStep").visible, "ENTER RAID opens on the map list")
	var index := maps.find(maps.filter(func(map: Resource) -> bool: return map.id == "test_yard")[0])
	(_find(screen, "MapList").get_child(index) as Button).pressed.emit()
	(_find(screen, "NextButton") as Button).pressed.emit()
	await frames(2)
	check(_find(screen, "SideStep").visible and not _find(screen, "MapStep").visible, "NEXT goes on to PMC or Scav")
	(_find(screen, "PmcButton") as Button).pressed.emit()
	await frames(2)
	check(_find(screen, "LoadoutStep").visible and _find(screen, "GearGrid").get_child_count() > 0 and screen.find_children("Checks", "Label", true, false)[0].text != "",
		"PMC goes on to the loadout check")
	check((_find(screen, "RaidSummary") as Label).text.begins_with(maps[index].display_name), "which names the map")
	(_find(screen, "BackButton") as Button).pressed.emit()
	await frames(1)
	(_find(screen, "BackButton") as Button).pressed.emit()
	await frames(1)
	check(_find(screen, "MapStep").visible, "BACK steps back to the map list")
	await _close(screen, "BackButton", "ENTER RAID")


func _settings() -> void:
	section("SETTINGS")
	var screen := await _open("SettingsButton")
	check(screen != null and screen.scene_file_path == "res://ui/settings_menu.tscn" and _find(screen, "ApplyButton") != null, "SETTINGS opens")
	await _close(screen, "BackButton", "SETTINGS")


## The Shooting Range's practice raid played through: loot picked up, a Scav killed, a point of interest
## walked into, out through an extract. Nothing reaches the profile: stash, gear, experience, money,
## explored points, quests (one with kill and extract objectives active), insurance, karma, trick shots.
func _practice_raid() -> void:
	section("Shooting Range practice raid")
	var errors := counter.errors
	var quests: GDScript = load("res://scripts/progression/quest_log.gd")
	gs.hideout["shooting_range"] = 1
	gs.level = maxi(gs.level, 5)
	var line: Array = quests.shown().filter(func(quest: Dictionary) -> bool: return quests.faction_of(quest) != &"")
	for quest: Dictionary in line.slice(0, 2):
		gs.quests[quest.id] = {"state": "active", "progress": quest.objectives.map(func(_objective: Dictionary) -> int: return 0)}
	gs.insurance_pending = [{"due": 1e12, "items": [], "insurer": gs.insurer}]
	var before: Dictionary = gs.to_dict()
	var raid: Dictionary = load("res://scripts/progression/hideout.gd").practice_raid()
	raid.seed = 4
	gs.raid = raid
	change_scene_to_file(MAPS[0][1])
	await frames(3)
	var controller: Node = root.get_tree().get_first_node_in_group("raid_controller")
	var player: Node = controller.player if controller else null
	check(controller != null and controller.is_practice() and player != null, "the practice raid starts on the Test Yard")
	var pickups: Array = root.get_tree().get_nodes_in_group("interactables").filter(func(node: Node) -> bool:
		return node.get_script() == load("res://scripts/world/loot_pickup.gd") and node.item != null)
	# Loose loot is rolled unseeded: pick up the first piece the copied gear has room for. Counted by its
	# id, since a stack of rounds can merge into one already carried.
	var fits: Array = pickups.filter(func(node: Node) -> bool:
		return player.inventory.grids().any(func(grid: RefCounted) -> bool: return grid.has_room_for(node.item)))
	var picked: RefCounted = fits[0].item if not fits.is_empty() else null
	var held := func(id: String) -> int:
		return player.inventory.grids().reduce(func(total: int, grid: RefCounted) -> int: return total + grid.count_of(id), 0)
	var carried: int = held.call(picked.data.id) if picked else 0
	var amount: int = picked.count if picked else 0
	if picked:
		fits[0].interact(player)
	check(picked != null and held.call(picked.data.id) == carried + amount, "loot is picked up (%s)" % (picked.data.display_name if picked else "none on the map that fits"))
	var scav_side: int = load("res://scripts/actors/actor.gd").Side.SCAV
	var scavs: Array = root.get_tree().get_nodes_in_group("bots").filter(func(bot: Node) -> bool: return not bot.is_dead and bot.side == scav_side)
	for bot: Node in root.get_tree().get_nodes_in_group("bots"):
		bot.ai_enabled = false  # Nobody shoots back while the test walks to the extract.
	if not scavs.is_empty():
		var hit: Dictionary = scavs[0].take_blow(10000.0, player, "melee", "Test", scavs[0].chest_point())
		player.on_hit_landed(scavs[0], 10000.0, scavs[0].chest_point(), hit)
	check(not scavs.is_empty() and scavs[0].is_dead and controller.kill_list.size() == 1 and controller.xp > 0,
		"a Scav is killed: on the kill list, experience counted in the raid (%d)" % (controller.xp if controller else 0))
	var poi: Node = root.get_tree().get_nodes_in_group("pois").filter(func(node: Node) -> bool: return not node.entry().is_empty())[0]
	player.global_position = poi.global_position
	await wait(0.6)
	check(poi.poi_id in controller.visited_pois, "a point of interest is walked into (%s)" % poi.poi_id)
	var zones: Array = root.get_tree().get_nodes_in_group("extract_zones").filter(func(zone: Node) -> bool: return zone.block_reason(player) == "")
	check(not zones.is_empty(), "an extract is open")
	if not zones.is_empty():
		player.global_position = zones[0].global_position
	var waited := 0.0
	while controller.outcome == null and waited < 12.0:
		await wait(0.5)
		waited += 0.5
	var outcome: RefCounted = controller.outcome
	check(outcome != null and outcome.survived() and outcome.xp == 0, "out through %s: survived, no experience" % (outcome.extract_name if outcome else "nothing"))
	var after: Dictionary = gs.to_dict()
	for key: String in ["level", "xp", "roubles", "dollars", "drip", "trick_shots", "trader_loyalty", "inventory", "skills", "quests", "explored",
			"insurance_pending", "scav"]:
		check(str(after.profile[key]) == str(before.profile[key]), "the profile's %s is untouched" % key)
	# The metabolism clock moves on in real time (out-of-raid recovery); energy and water don't change.
	check(after.profile.metabolism.energy == before.profile.metabolism.energy and after.profile.metabolism.hydration == before.profile.metabolism.hydration,
		"energy and water are untouched")
	check(str(after.stash) == str(before.stash), "the stash is untouched")
	check(counter.errors == errors, "no errors in the practice raid%s" % ("" if counter.errors == errors else ": %d, first %s" % [counter.errors - errors, counter.first]))
	gs.raid = {}


## Runs `raid` on `scene` for `seconds` of game time.
func _raid(raid: Dictionary, scene: String, seconds: float) -> void:
	var what := "%s raid on %s" % [raid.side.to_upper(), raid.map]
	section(what)
	var errors := counter.errors
	gs.raid = raid
	change_scene_to_file(scene)
	await frames(3)
	var bots: Array = root.get_tree().get_nodes_in_group("actors").filter(func(actor: Node) -> bool: return "ai_enabled" in actor)
	check(current_scene != null and current_scene.scene_file_path == scene, "%s starts" % what)
	check(not bots.is_empty() and bots.all(func(bot: Node) -> bool: return bot.ai_enabled), "with %d AI bots, their AI on" % bots.size())
	await wait(RENDERED)
	RenderingServer.render_loop_enabled = false
	await wait(seconds - RENDERED * 2.0)
	RenderingServer.render_loop_enabled = true
	await wait(RENDERED)
	check(current_scene != null and current_scene.scene_file_path == scene, "it is still running after %d s" % seconds)
	check(counter.errors == errors, "no errors in %d s of %s%s" % [seconds, what, "" if counter.errors == errors else ": %d, first %s" % [counter.errors - errors, counter.first]])
	if raid.side == "pmc" and raid.map == "test_yard":
		await _raid_quest_log()


## In a raid: the HUD tracker lists the tracked quest, and the pause menu's QUESTS opens the log
## read-only (no ACCEPT or TURN IN), live progress shown.
func _raid_quest_log() -> void:
	var hud := _find(current_scene, "QuestTracker") as VBoxContainer
	await wait(0.6)
	check(hud != null and hud.visible and hud.get_children().any(func(label: Node) -> bool: return label.text == "YARD SWEEP"),
		"the HUD tracker shows the tracked Yard Sweep's raid objectives")
	var pause := _find(current_scene, "PauseMenu")
	pause.open()
	(_find(pause, "QuestsButton") as Button).pressed.emit()
	await frames(3)
	var log := _find(pause, "QuestsScreen")
	check(log != null and log.raid != null and _find(log, "AcceptButton") == null and _find(log, "TurnInButton") == null,
		"the pause menu's QUESTS opens the log, read-only in a raid")
	if log:
		(_find(log, "BackButton") as Button).pressed.emit()
		await frames(3)
	pause.close()
