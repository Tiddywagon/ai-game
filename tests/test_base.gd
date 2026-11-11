extends SceneTree
## Base of every test suite (tests/<name>_test.gd: `extends "res://tests/test_base.gd"`, then override
## run()). It waits for the autoloads, runs run(), prints the final line ("PASS: 0 failure(s)" or
## "FAIL: n failure(s)") and exits 1 when a check failed. Helpers: section(), check(), wait(),
## frames(), item(), items(), fresh_profile().
## Suites load game scripts with load("res://...") (class names can be stale in -s scripts).

const ITEM := "res://scripts/inventory/item_instance.gd"

var fails := 0
var checks := 0
## The autoloads, set before run().
var gs: Node
var db: Node
var sm: Node


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	db = root.get_node("ItemDB")
	sm = root.get_node("SaveManager")
	await run()
	finish()


## The suite: override it. May await.
func run() -> void:
	pass


## Prints a section header.
func section(title: String) -> void:
	print(title)


## One assertion: prints "  ok   <what>" or "  FAIL <what>" and returns `condition`.
func check(condition: bool, what: String) -> bool:
	checks += 1
	if condition:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)
	return condition


## Prints the final line and quits (1 if a check failed).
func finish() -> void:
	print("PASS: 0 failure(s) (%d checks)" % checks if fails == 0 else "FAIL: %d failure(s) (%d checks)" % [fails, checks])
	quit(1 if fails > 0 else 0)


## Waits `seconds` of game time (physics frames at --fixed-fps 60).
func wait(seconds: float) -> void:
	var ticks := int(ceil(seconds * 60.0))
	for i in ticks:
		await physics_frame


## Waits `count` process frames.
func frames(count: int) -> void:
	for i in count:
		await process_frame


## A new item instance of `id` (a stack of `amount`).
func item(id: String, amount := 1) -> RefCounted:
	return load(ITEM).create(id, amount)


## `list` as the Array[ItemInstance] the game's functions want.
func items(list: Array) -> Array:
	return Array(list, TYPE_OBJECT, &"RefCounted", load(ITEM))


## A new profile (faction 0: BEAR, 1: USEC) with no save file on disk.
func fresh_profile(faction := 0) -> void:
	sm.delete_save()
	gs.new_profile(gs.Faction.USEC if faction == 1 else gs.Faction.BEAR)
