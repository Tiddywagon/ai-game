class_name LootPickup
extends Node3D
## An item lying loose in a raid (DESIGN.md §2, §6.2). F nearby picks it up into the pockets, rig or
## backpack (it's then loot: found in raid if you extract with it). Either a set item, or rolled from a
## LootContainer (normally "Loose loot") at the start of the raid. Hidden while out of sight, like
## enemies. A small box in the item's rarity colour for now.

## A set item, or "" to roll one from `container`.
@export var item_id := ""
@export var count := 1
@export var container: LootContainer
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
	if container == null:
		return null
	var rng := RandomNumberGenerator.new()
	if loot_seed != 0:
		rng.seed = loot_seed
	else:
		rng.randomize()
	var table: LootTable = load("res://data/loot_tables/default.tres")
	var rolled := table.roll_container(rng, container, MapInfo.find(GameState.raid.get("map", "")))
	if rolled.is_empty():
		return null
	var made := ItemInstance.create(rolled[0].id, rolled[0].count)
	if made and made.data.weapon:
		made = Inventory.loaded_gun(made.data.id, LootBox._ammo_for(made.data.weapon.caliber))
	return made


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
