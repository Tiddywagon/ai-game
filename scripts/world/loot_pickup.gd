class_name LootPickup
extends Node3D
## An item lying loose on the ground in a raid (DESIGN.md §2, §6.2). F nearby picks it up into the
## pockets, rig or backpack (it's then loot: found in raid if you extract with it). Either a set item,
## or rolled at the start of the raid from a LootTable (normally loose_loot.tres, any item) with the
## map's multipliers; a spot only has something on it `spawn_chance` of the time. Hidden while out of
## sight, like enemies. A small box the size of the item, in its rarity colour, for now.

## A set item, or "" to roll one from `loot_table`.
@export var item_id := ""
@export var count := 1
@export var loot_table: LootTable = preload("res://data/loot_tables/loose_loot.tres")
## Chance (0-1) that a rolled spot has anything on it this raid.
@export_range(0.0, 1.0, 0.05) var spawn_chance := 1.0
## Rolls the same item every time when not 0 (for tests).
@export var loot_seed := 0

var item: ItemInstance

var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("vision_hideable")
	if item == null:
		item = _make_item()
	if item == null:
		queue_free()
		return
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(item.data.size.x * 0.22, 0.12, item.data.size.y * 0.22)
	_mesh.mesh = box
	_mesh.position.y = 0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = Palette.rarity_color(item.data.rarity)
	material.emission_enabled = true
	material.emission = Palette.rarity_color(item.data.rarity) * 0.25
	_mesh.material_override = material
	add_child(_mesh)


func _make_item() -> ItemInstance:
	if item_id != "":
		return ItemInstance.create(item_id, count)
	if loot_table == null:
		return null
	var rng := RandomNumberGenerator.new()
	if loot_seed != 0:
		rng.seed = loot_seed
	else:
		rng.randomize()
	if rng.randf() >= spawn_chance:
		return null
	var rolled := loot_table.roll_items(rng, MapInfo.find(GameState.raid.get("map", "")))
	return rolled[0] if not rolled.is_empty() else null


func set_seen(seen: bool) -> void:
	visible = seen


func interact_text() -> String:
	return "Pick up %s%s" % [item.data.display_name, " ×%d" % item.count if item.count > 1 else ""]


func can_interact(_player: Player) -> bool:
	return item != null and visible


func interact(player: Player) -> void:
	if player.pick_up(item):
		item = null
		queue_free()
