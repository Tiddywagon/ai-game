@tool
class_name ExtractZone
extends Area3D
## An extract (DESIGN.md §2, §5): stand inside for RaidConfig.extract_seconds to leave the raid with
## what you carry. A ring and flare pillar mark it: green when you can use it, amber while a condition
## isn't met, red when it's closed. The RaidController counts down; walking out stops it.
##
## Kinds, which combine: always open (chance 1); random (open this raid with `chance`, rolled at raid
## start); paid (press F inside it to pay `price` roubles once); item (you must carry `required_item`,
## used up on extracting if `consumes_item`); power (the map's power must be on: PowerSwitch); and
## `sides` for PMC-only or Scav-only extracts.

const OPEN_COLOR := Color(0.35, 1.0, 0.45)
const CONDITION_COLOR := Color(0.95, 0.72, 0.25)
const CLOSED_COLOR := Color(0.9, 0.25, 0.2)

@export var extract_name := "Extract"
@export_range(0.5, 10.0, 0.1, "suffix:m") var radius := 2.5:
	set(value):
		radius = value
		_build()
## Chance the extract is open in a raid, rolled at raid start (1: always open).
@export_range(0.0, 1.0, 0.05) var chance := 1.0
## Roubles to pay (F, standing inside) before it works; 0 for free.
@export_range(0, 1000000, 500) var price := 0
## An item id you must carry to use it ("" for none), and whether extracting uses it up.
@export var required_item := ""
@export var consumes_item := false
## Works only once the map's power is on (a PowerSwitch).
@export var needs_power := false
@export_enum("Both", "PMC", "Scav") var sides := "Both"

## Open this raid (rolled by the RaidController from `chance`).
var open := true
## Paid this raid.
var paid := false

var _ring_material: StandardMaterial3D
var _pillar_material: StandardMaterial3D
var _shown_color := Color.TRANSPARENT


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("extract_zones")  # Before any _ready(), so the RaidController can roll it.


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("interactables")  # To pay.
	collision_layer = 0
	collision_mask = 2  # Actors.
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var raid := _raid()
	var color := OPEN_COLOR
	if not open or (raid and raid.player and not allows_side(raid.side())):
		color = CLOSED_COLOR
	elif raid and raid.player and block_reason(raid.player) != "":
		color = CONDITION_COLOR
	_set_color(color)


## Rolls whether it's open this raid.
func roll(rng: RandomNumberGenerator) -> void:
	open = chance >= 1.0 or rng.randf() < chance
	paid = false


func allows_side(raid_side: String) -> bool:
	return sides == "Both" or sides.to_lower() == raid_side


## Why `player` can't extract here right now ("" if they can): closed, the wrong side, no power, the
## item missing, or not paid yet.
func block_reason(player: Player) -> String:
	var raid := _raid()
	if not open:
		return "Closed this raid"
	if raid and not allows_side(raid.side()):
		return "%s only" % ("Scav" if sides == "Scav" else "PMC")
	if needs_power and raid and raid.power_state() != "on":
		return "Power coming on in %d s" % ceili(raid.power_left()) if raid.power_state() == "starting" else "No power: find the power switch"
	if required_item != "" and not carries_required(player):
		return "Needs %s" % _item_name()
	if price > 0 and not paid:
		return "Pay %s first (%s)" % [UiFormat.money(price), Settings.key_label("interact")]
	return ""


## True if `player` carries the required item (anywhere on them).
func carries_required(player: Player) -> bool:
	return player.inventory != null and player.inventory.all_items().any(func(item: ItemInstance) -> bool: return item.data.id == required_item)


## Its kind for the HUD's extract list: "open", "closed", "pay 7,000 ₽", "needs Paracord", "needs
## power", "Scav only"... as it stands for `player`.
func status_text(player: Player) -> String:
	var raid := _raid()
	if not open:
		return "closed this raid"
	if raid and not allows_side(raid.side()):
		return "%s only" % ("Scav" if sides == "Scav" else "PMC")
	var needs: Array[String] = []
	if needs_power and raid and raid.power_state() != "on":
		needs.append("power coming on" if raid.power_state() == "starting" else "needs power")
	if required_item != "" and (player == null or not carries_required(player)):
		needs.append("needs %s" % _item_name())
	if price > 0 and not paid:
		needs.append("pay %s" % UiFormat.money(price))
	return ", ".join(needs) if not needs.is_empty() else "open"


## What it takes, whatever the raid: "always open", "open some raids (50%)", "pay 7,000 ₽", "needs
## Factory exit key", "needs power", "Scav only" (the map item's legend).
func kind_text() -> String:
	var parts: Array[String] = []
	if sides != "Both":
		parts.append("%s only" % ("Scav" if sides == "Scav" else "PMC"))
	if chance < 1.0:
		parts.append("open some raids (%d%%)" % roundi(chance * 100.0))
	if price > 0:
		parts.append("pay %s" % UiFormat.money(price))
	if required_item != "":
		parts.append("needs %s%s" % [_item_name(), " (used up)" if consumes_item else ""])
	if needs_power:
		parts.append("needs power")
	return ", ".join(parts) if not parts.is_empty() else "always open"


## Uses up the required item on extracting (if it's used up): one piece of it.
func use_up_item(player: Player) -> void:
	if required_item == "" or not consumes_item:
		return
	for item in player.inventory.all_items():
		if item.data.id == required_item:
			if item.count > 1:
				item.count -= 1
			else:
				player.inventory.remove_item(item)
			return


# --- Paying (F inside the zone) ------------------------------------------------------------------

func interact_reach() -> float:
	return radius


func can_interact(player: Player) -> bool:
	var raid := _raid()
	return price > 0 and not paid and open and raid != null and raid.extract_zone == self and allows_side(raid.side()) and not player.is_dead


func interact_text() -> String:
	return "Pay %s to use the %s (you have %s)" % [UiFormat.money(price), extract_name.to_lower(), UiFormat.money(GameState.roubles)]


func interact(player: Player) -> void:
	if GameState.roubles < price:
		player.action_blocked.emit("Not enough roubles: %s needed" % UiFormat.money(price))
		return
	GameState.roubles -= price
	paid = true
	player.action_blocked.emit("Paid %s: %s" % [UiFormat.money(price), "hold still to extract" if block_reason(player) == "" else block_reason(player)])


func _item_name() -> String:
	var data := ItemDB.get_item(required_item) if ItemDB.has_item(required_item) else null
	return data.display_name if data else required_item


# --- Look ----------------------------------------------------------------------------------------

func _build() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("generated"):
			child.free()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	_add(shape)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.12
	torus.outer_radius = radius
	torus.rings = 48
	ring.mesh = torus
	ring.position.y = 0.03
	ring.scale.y = 0.15
	_ring_material = _glow(0.9)
	ring.material_override = _ring_material
	_add(ring)
	var pillar := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.15
	beam.bottom_radius = 0.15
	beam.height = 4.0
	pillar.mesh = beam
	pillar.position.y = 2.0
	_pillar_material = _glow(0.45)
	pillar.material_override = _pillar_material
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(pillar)
	_shown_color = Color.TRANSPARENT
	_set_color(OPEN_COLOR)


func _set_color(color: Color) -> void:
	if color == _shown_color or _ring_material == null:
		return
	_shown_color = color
	_ring_material.albedo_color = Color(color, 0.9)
	_ring_material.emission = color
	_pillar_material.albedo_color = Color(color, 0.45 if color == OPEN_COLOR else 0.2)
	_pillar_material.emission = color


func _add(node: Node) -> void:
	node.set_meta("generated", true)
	add_child(node)


func _glow(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(OPEN_COLOR, alpha)
	material.emission_enabled = true
	material.emission = OPEN_COLOR
	return material


func _raid() -> RaidController:
	return get_tree().get_first_node_in_group("raid_controller") as RaidController if is_inside_tree() else null


func _on_body_entered(body: Node3D) -> void:
	if body is Player and _raid():
		_raid().enter_extract(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player and _raid():
		_raid().leave_extract(self)
