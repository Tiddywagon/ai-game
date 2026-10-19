class_name BossSpawn
extends Node3D
## Where a map's boss (DESIGN.md §4.3, data/config/bosses.json: BossTable) may turn up. At raid start
## it rolls the boss's chance (35%; seeded by the raid; GameState.raid "boss": true or false forces it)
## and if it comes up, the boss stands here with 2-4 guards at its Marker3D children (its haunt, which
## the boss then wanders, the guards staying with it). Boss and guards are a squad: they share targets
## and push as a group (Bot), and raid events don't pull them away from here, nor a fight they hear
## farther than their profile's haunt_radius from here (Bot.near_haunt()). The boss is tougher
## (data/bots/boss.tres; guards: guard.tres), wears class 5-6 armor (guards 4-5) and always carries its
## unique and Epic or Legendary loot (BossTable.add_boss_loot()). Place it before the RaidController,
## so the player's spawn keeps away from the squad.

const BOT_SCENE := preload("res://scenes/actors/bot.tscn")
const BOSS_PROFILE := preload("res://data/bots/boss.tres")
const GUARD_PROFILE := preload("res://data/bots/guard.tres")

## The map whose boss this is ("": the raid's map).
@export var map_id := ""

## This raid's boss and guards (null and empty if the boss didn't show), its entry, and the guaranteed
## loot it carries (its unique first).
var boss: Bot
var guards: Array[Bot] = []
var entry := {}
var boss_loot: Array[ItemInstance] = []


func _enter_tree() -> void:
	add_to_group("boss_spawns")


func _ready() -> void:
	entry = BossTable.for_map(boss_map())
	if entry.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	if GameState.raid.has("seed"):
		rng.seed = hash([int(GameState.raid.seed), "boss", boss_map()])
	else:
		rng.randomize()
	var roll := rng.randf()
	var forced: Variant = GameState.raid.get("boss")
	if (forced == null and roll < float(entry.chance)) or (forced != null and bool(forced)):
		spawn(rng)


func boss_map() -> String:
	if map_id != "":
		return map_id
	return str(GameState.raid.get("map", "test_yard"))


## Puts the boss here and its guards at the haunt points (in turn). Returns the squad, boss first.
func spawn(rng: RandomNumberGenerator) -> Array[Bot]:
	var squad: Array[Bot] = []
	boss = _make(BOSS_PROFILE, str(entry.name), BossTable.kit(entry.boss, rng), Vector3.ZERO)
	boss_loot = BossTable.add_boss_loot(boss.inventory, entry, rng)
	boss.wander_points = haunt()
	squad.append(boss)
	var spots := haunt().slice(1)
	var count := rng.randi_range(int(entry.guards[0]), int(entry.guards[1]))
	for i in count:
		var at: Vector3 = to_local(spots[i % spots.size()]) if not spots.is_empty() else Vector3(cos(TAU * i / count), 0, sin(TAU * i / count)) * 2.0
		at += Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
		var guard := _make(GUARD_PROFILE, str(entry.guard_name), BossTable.kit(entry.guard, rng), at)
		guard.name = "Guard%d" % (i + 1)
		guard.leader = boss
		guards.append(guard)
		squad.append(guard)
	for bot in squad:
		bot.squad = squad
	return squad


## Where the boss roams: its Marker3D children (world positions), and here.
func haunt() -> PackedVector3Array:
	var points := PackedVector3Array([global_position])
	for child in get_children():
		if child is Marker3D:
			points.append(child.global_position)
	return points


func _make(profile: BotProfile, title: String, kit: Inventory, at: Vector3) -> Bot:
	var bot: Bot = BOT_SCENE.instantiate()
	bot.name = "Boss"
	bot.profile = profile
	bot.title = title
	bot.inventory = kit
	bot.boss_spawn = self
	bot.position = at
	add_child(bot)
	return bot
