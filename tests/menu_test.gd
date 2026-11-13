extends "res://tests/test_base.gd"
## Menus and raids (needs a display): every screen of the main menu opens and closes through its
## buttons (LOADOUT with AUTO-EQUIP and UNDO and its QUICK BUY tab buying a card, CHARACTER, HIDEOUT with an upgrade, TRADERS with every
## trader's tabs, a purchase and a sale, ENTER RAID up to the loadout check, SETTINGS), then a seeded PMC
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
	var screen := await _open("HideoutButton")
	var list: Node = _find(screen, "StationList") if screen else null
	check(screen != null and list.get_child_count() == hideout.stations().size() and hideout.stations().size() >= 7, "HIDEOUT lists every station")
	var index: int = hideout.stations().find(hideout.find("generator"))
	(list.get_child(index) as Button).pressed.emit()
	await frames(2)
	var build: Array = _find(screen, "Details").find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "BUILD")
	check(build.size() == 1 and not build[0].disabled, "the generator has a BUILD button")
	build[0].pressed.emit()
	await frames(3)
	check(gs.hideout.get("generator", 0) == 1 and gs.roubles == 450000 and gs.stash.count_of("fuel_can") == 0, "pressing it builds the generator")
	check((_find(screen, "Status") as Label).text == "Done." and (list.get_child(index) as Button).text.ends_with("level 1 / 3"), "the screen says so")
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
	buy.pressed.emit()
	await frames(3)
	check(gs.stash.count_of("nails") == 1 and gs.roubles == 450000 - 7500 and (_find(screen, "Status") as Label).text == "Done.", "pressing it buys them")
	tabs.current_tab = tabs.get_node("SELL").get_index()
	var sell_rows: Array = tabs.get_node("SELL/Rows").get_children().filter(func(child: Node) -> bool:
		return child.has_meta("item") and (child.get_meta("item") as RefCounted).data.id == "nails")
	check(sell_rows.size() == 1, "the nails are on Zoya's SELL tab")
	var price: int = load("res://scripts/progression/selling.gd").price("zoya", sell_rows[0].get_meta("item"))
	(sell_rows[0].get_node("SellButton") as Button).pressed.emit()
	await frames(3)
	check(price > 0 and gs.stash.count_of("nails") == 0 and gs.roubles == 450000 - 7500 + price
		and (_find(screen, "Status") as Label).text.begins_with("Sold 1 item to Auntie Zoya"), "its SELL button sells them back (for %d)" % price)
	await _close(screen, "BackButton", "TRADERS")


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
