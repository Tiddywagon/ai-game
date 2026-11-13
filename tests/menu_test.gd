extends "res://tests/test_base.gd"
## Menus and raids (needs a display): every screen of the main menu opens and closes through its
## buttons (LOADOUT with AUTO-EQUIP and UNDO and its QUICK BUY tab buying a card, CHARACTER, HIDEOUT's plan and station panel (a build, fuel, handing over, a craft collected, a cosmetic), TRADERS with every
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
	await _traders()
	await _flea()
	await _raid_setup()
	await _settings()
	check(counter.errors == 0, "no errors in the menus%s" % ("" if counter.errors == 0 else ": %d, first %s" % [counter.errors, counter.first]))
	for map: Array in MAPS:
		await _raid({"side": "pmc", "map": map[0], "loadout": gs.pmc_loadout(), "seed": 4, "boss": false}, map[1], 20.0)
	await _raid({"side": "scav", "map": "test_yard", "loadout": gs.scav_loadout(), "seed": 4, "boss": false, "offset": 400}, MAPS[0][1], 10.0)
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
	await _close(screen, "BackButton", "CHARACTER")


func _hideout() -> void:
	section("HIDEOUT")
	var hideout: GDScript = load("res://scripts/progression/hideout.gd")
	var work: GDScript = load("res://scripts/progression/hideout_work.gd")
	var screen := await _open("HideoutButton")
	var map: Node = _find(screen, "Map") if screen else null
	var rooms: Array = hideout.stations().filter(func(station: Dictionary) -> bool: return _find(map, "Room_" + station.id) is Button)
	check(screen != null and rooms.size() == 13, "HIDEOUT shows the plan with every station as a room")
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
