@tool
class_name ExtractZone
extends Area3D
## An extract (DESIGN.md §2, §5): stand inside for RaidConfig.extract_seconds to leave the raid with
## what you carry. A glowing ring outlines it and a sign names it and says how it stands: green when
## you can use it, amber while a condition isn't met, red when it's closed, grey while you don't know
## yet (a random extract you haven't seen). The RaidController counts down; walking out or getting hit
## starts the count again.
##
## The rules come from data/config/extracts.json (ExtractTable) by `extract_id` and the map
## (configure()); tests can set them directly. Types: always open; random (open this raid with
## `chance`, rolled at raid start, "Unknown" until you get close enough to see it); conditional (any of:
## carry `required_item`, used up on extracting if `consumes_item`; pay `price` roubles here with F;
## the map's power on, PowerSwitch; fire a signal flare here with F; `no_gear` slots empty; and a
## `quest` that must be completed for the extract to exist at all). `sides` limits it to PMCs or Scavs.
## AI Scavs and PMCs use the same extracts, except paid, flare and quest ones (usable_by()).

const OPEN_COLOR := Color(0.35, 1.0, 0.45)
const CONDITION_COLOR := Color(0.95, 0.72, 0.25)
const CLOSED_COLOR := Color(0.9, 0.25, 0.2)
const UNKNOWN_COLOR := Color(0.78, 0.8, 0.82)
## Colours by status_state(): the ring, the sign and every extract list use these.
const STATE_COLORS := {"open": OPEN_COLOR, "condition": CONDITION_COLOR, "closed": CLOSED_COLOR, "unknown": UNKNOWN_COLOR}
const FLARE_ITEM := "signal_flare"
const SIGNAL_FLARE := preload("res://scripts/world/signal_flare.gd")

## The extract's id in data/config/extracts.json for this map ("" to set the rules by hand).
@export var extract_id := ""
@export var extract_name := "Extract"
@export_range(0.5, 10.0, 0.1, "suffix:m") var radius := 2.5:
	set(value):
		radius = value
		_build()

## "always", "random" or "conditional" (ExtractTable.TYPES).
var kind := "always"
## Random extracts: chance it's open in a raid, rolled at raid start.
var chance := 1.0
## Roubles to pay (F, standing inside) before it works; 0 for free.
var price := 0
## An item id you must carry to use it ("" for none, e.g. a key), and whether extracting uses it up.
var required_item := ""
var consumes_item := false
## Works only once the map's power is on (a PowerSwitch).
var needs_power := false
## Works only once a signal flare has been fired inside it (F).
var needs_flare := false
## Equipment slots that must be empty to use it ("backpack", "armor"...).
var no_gear := PackedStringArray()
## "Both", "PMC" or "Scav".
var sides := "Both"
## A quest id: the extract only exists once that quest is completed ("" for always there).
var quest := ""

## Exists for you this raid (its quest is done, if it has one; set at roll()).
var available := true
## Open this raid (rolled by the RaidController from `chance`).
var open := true
## Paid this raid, and a flare fired in it this raid.
var paid := false
var flare_fired := false
## You know whether it's open: always for known kinds, for a random one once you've been close enough
## to see it (RaidController) or stood in it.
var confirmed := true

var _ring_material: StandardMaterial3D
var _fill_material: StandardMaterial3D
var _sign: Label3D
var _shown_color := Color.TRANSPARENT
var _shown_text := ""


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("extract_zones")  # Before any _ready(), so the RaidController can configure it.


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("interactables")  # To pay or fire a flare.
	collision_layer = 0
	collision_mask = 2  # Actors.
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var raid := _raid()
	var player := raid.player if raid else null
	_set_look(STATE_COLORS[status_state(player)], "%s\n%s" % [extract_name.to_upper(), status_for(player).to_upper()])


# --- Rules -----------------------------------------------------------------------------------------

## Takes the rules from an ExtractTable entry.
func configure(entry: Dictionary) -> void:
	extract_name = str(entry.get("name", extract_name))
	kind = str(entry.get("type", "always"))
	chance = float(entry.get("chance", 1.0)) if kind == "random" else 1.0
	required_item = str(entry.get("item", ""))
	consumes_item = bool(entry.get("consumes", false))
	price = int(entry.get("price", 0))
	needs_power = bool(entry.get("power", false))
	needs_flare = bool(entry.get("flare", false))
	no_gear = PackedStringArray(entry.get("no_gear", []))
	sides = str(entry.get("sides", "Both"))
	quest = str(entry.get("quest", ""))


## Takes this extract's rules from the table for `map_id` (if it has an extract_id). False if the table
## has no such extract.
func configure_for_map(map_id: String) -> bool:
	if extract_id == "":
		return true
	var entry := ExtractTable.find(map_id, extract_id)
	if entry.is_empty():
		push_warning("ExtractZone %s: no extract \"%s\" for %s in %s" % [name, extract_id, map_id, ExtractTable.PATH])
		return false
	configure(entry)
	return true


## Rolls the raid: whether it exists for you (quest), whether it's open (random), nothing paid or fired.
func roll(rng: RandomNumberGenerator) -> void:
	available = quest == "" or GameState.quests.get(quest, {}).get("state", "") == "completed"
	open = kind != "random" or chance >= 1.0 or rng.randf() < chance
	confirmed = kind != "random"
	paid = false
	flare_fired = false
	visible = available
	monitoring = available


## The entry this zone would be in the table (for the map item out of raid and the debug overlay).
func kind_text() -> String:
	return ExtractTable.kind_text(_as_entry())


func allows_side(raid_side: String) -> bool:
	return sides == "Both" or sides.to_lower() == raid_side


## True if a point is inside the zone (on the ground, within its ring).
func contains(point: Vector3) -> bool:
	var at := global_position
	return Vector2(point.x - at.x, point.z - at.z).length() <= radius and absf(point.y - at.y) < 2.0


## Why `player` can't extract here right now ("" if they can): closed, the wrong side, no power, the
## item missing, gear to leave behind, no flare fired, not paid yet.
func block_reason(player: Actor) -> String:
	var raid := _raid()
	if not available:
		return "Not available"
	if not open:
		return "Closed this raid"
	if not allows_side(_side_of(player)):
		return "%s only" % ("Scav" if sides == "Scav" else "PMC")
	if needs_power and raid and raid.power_state() != "on":
		return "Power coming on in %d s" % ceili(raid.power_left()) if raid.power_state() == "starting" else "No power: find the power switch"
	if required_item != "" and not carries(player, required_item):
		return "Needs %s" % ExtractTable.item_name(required_item)
	var gear := gear_in_the_way(player)
	if not gear.is_empty():
		return "Take off your %s" % ", ".join(gear).to_lower()
	if needs_flare and not flare_fired:
		return "Fire a signal flare first (%s)" % Settings.key_label("interact")
	if price > 0 and not paid:
		return "Pay %s first (%s)" % [UiFormat.money(price), Settings.key_label("interact")]
	return ""


## The mark shown for `player` in the extract lists, on the map and on the sign: "Open", "Unknown" (a
## random extract you haven't seen yet), "Closed", or what's still needed ("Needs Factory exit key,
## needs power", "Pay 7,000 ₽", "Fire a flare", "No backpack").
func status_for(player: Actor) -> String:
	if not available:
		return "Locked"
	if player and not allows_side(_side_of(player)):
		return "%s only" % ("Scav" if sides == "Scav" else "PMC")
	if not confirmed:
		return "Unknown"
	if not open:
		return "Closed"
	var needs := PackedStringArray()
	var raid := _raid()
	if needs_power and (raid == null or raid.power_state() != "on"):
		needs.append("power on in %d s" % ceili(raid.power_left()) if raid and raid.power_state() == "starting" else "needs power")
	if required_item != "" and (player == null or not carries(player, required_item)):
		needs.append("needs %s" % ExtractTable.item_name(required_item))
	for slot in (gear_in_the_way(player) if player else PackedStringArray()):
		needs.append("no %s" % slot.to_lower())
	if needs_flare and not flare_fired:
		needs.append("fire a flare")
	if price > 0 and not paid:
		needs.append("pay %s" % UiFormat.money(price))
	if needs.is_empty():
		return "Open"
	var text := ", ".join(needs)
	return text[0].to_upper() + text.substr(1)


## "open", "unknown", "closed" or "condition" (colours).
func status_state(player: Actor) -> String:
	var status := status_for(player)
	match status:
		"Open":
			return "open"
		"Unknown":
			return "unknown"
		"Closed", "Locked", "PMC only", "Scav only":
			return "closed"
	return "condition"


## True if `actor` carries `item_id` anywhere on them.
static func carries(actor: Actor, item_id: String) -> bool:
	var inventory: Inventory = actor.get("inventory") if actor else null
	return inventory != null and inventory.all_items().any(func(item: ItemInstance) -> bool: return item.data.id == item_id)


## The names of the `no_gear` slots `actor` has something in ("Backpack"...).
func gear_in_the_way(actor: Actor) -> PackedStringArray:
	var names := PackedStringArray()
	var inventory: Inventory = actor.get("inventory") if actor else null
	if inventory == null:
		return names
	for slot in no_gear:
		if inventory.equipment.get(slot) != null:
			names.append(ExtractTable.slot_name(slot))
	return names


## Whether an AI Scav or PMC can leave through it now: AI uses the same extracts, but never pays,
## fires flares or knows quest extracts.
func usable_by(bot: Actor) -> bool:
	if price > 0 or needs_flare or quest != "":
		return false
	return block_reason(bot) == ""


## Uses up the required item on extracting (if it's used up): one piece of it.
func use_up_item(player: Actor) -> void:
	var inventory: Inventory = player.get("inventory")
	if required_item == "" or not consumes_item or inventory == null:
		return
	for item in inventory.all_items():
		if item.data.id == required_item:
			if item.count > 1:
				item.count -= 1
			else:
				inventory.remove_item(item)
			return


func confirm() -> void:
	confirmed = true


# --- F inside the zone: pay, or fire a flare ----------------------------------------------------

func interact_reach() -> float:
	return radius


func can_interact(player: Player) -> bool:
	var raid := _raid()
	if not available or not open or raid == null or raid.extract_zone != self or not allows_side(raid.side()) or player.is_dead:
		return false
	return (needs_flare and not flare_fired) or (price > 0 and not paid)


func interact_text() -> String:
	var raid := _raid()
	if needs_flare and not flare_fired:
		var flares: int = raid.player.inventory.count_of(FLARE_ITEM) if raid and raid.player else 0
		return "Fire a signal flare to call the %s (you have %d)" % [extract_name.to_lower(), flares]
	return "Pay %s to use the %s (you have %s)" % [UiFormat.money(price), extract_name.to_lower(), UiFormat.money(GameState.roubles)]


func interact(player: Player) -> void:
	if needs_flare and not flare_fired:
		fire_flare(player)
		return
	if GameState.roubles < price:
		player.action_blocked.emit("Not enough roubles: %s needed" % UiFormat.money(price))
		return
	GameState.roubles -= price
	paid = true
	player.action_blocked.emit("Paid %s: %s" % [UiFormat.money(price), "hold still to extract" if block_reason(player) == "" else block_reason(player)])


## Fires one of `player`'s signal flares here: the extract works from now on. Everyone nearby sees and
## hears it. False if they have none.
func fire_flare(player: Player) -> bool:
	if player.inventory.count_of(FLARE_ITEM) == 0:
		player.action_blocked.emit("You need a %s" % ExtractTable.item_name(FLARE_ITEM))
		return false
	player.inventory.take(FLARE_ITEM, 1)
	flare_fired = true
	var flare: Node3D = SIGNAL_FLARE.new()
	get_tree().current_scene.add_child(flare)
	flare.global_position = player.global_position + Vector3.UP * 1.5
	NoiseSystem.emit_noise(player.global_position, SIGNAL_FLARE.NOISE_RADIUS, player, &"flare")
	player.action_blocked.emit("Flare fired: %s" % ("hold still to extract" if block_reason(player) == "" else block_reason(player)))
	return true


func _as_entry() -> Dictionary:
	var entry := {"name": extract_name, "type": kind, "sides": sides}
	if kind == "random":
		entry.chance = chance
	for pair in [["item", required_item], ["quest", quest]]:
		if pair[1] != "":
			entry[pair[0]] = pair[1]
	if consumes_item:
		entry.consumes = true
	if price > 0:
		entry.price = price
	if needs_power:
		entry.power = true
	if needs_flare:
		entry.flare = true
	if not no_gear.is_empty():
		entry.no_gear = Array(no_gear)
	return entry


static func _side_of(actor: Actor) -> String:
	if actor == null:
		return "pmc"
	return "scav" if actor.side == Actor.Side.SCAV else "pmc"


# --- Look ----------------------------------------------------------------------------------------

## A glowing ring around the zone with a faint fill, and a sign at its far (north) edge.
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
	_ring_material = _glow(0.95)
	ring.material_override = _ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(ring)
	var fill := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius - 0.1
	disc.bottom_radius = radius - 0.1
	disc.height = 0.01
	fill.mesh = disc
	fill.position.y = 0.02
	_fill_material = _glow(0.12)
	fill.material_override = _fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(fill)
	# The sign: a post at the north edge with a board, and the name and state above it.
	var post := MeshInstance3D.new()
	var pole := BoxMesh.new()
	pole.size = Vector3(0.08, 1.6, 0.08)
	post.mesh = pole
	post.position = Vector3(0, 0.8, -radius)
	post.material_override = _plain(Color(0.25, 0.25, 0.27))
	_add(post)
	var board := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(1.1, 0.5, 0.05)
	board.mesh = plate
	board.position = Vector3(0, 1.55, -radius)
	board.material_override = _plain(Color(0.12, 0.35, 0.18))
	_add(board)
	_sign = Label3D.new()
	_sign.name = "Sign"
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.font_size = 56
	_sign.outline_size = 14
	_sign.pixel_size = 0.008
	_sign.modulate = OPEN_COLOR
	_sign.outline_modulate = Color(0, 0, 0, 0.9)
	_sign.position = Vector3(0, 2.4, -radius)
	# Cut, not blended: the text writes depth, so the fog of war judges it by where the sign is, not by
	# whatever is behind each letter.
	_sign.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	_sign.text = extract_name.to_upper()
	_add(_sign)
	_shown_color = Color.TRANSPARENT
	_shown_text = ""
	_set_look(OPEN_COLOR, extract_name.to_upper())


func _set_look(color: Color, text: String) -> void:
	if _ring_material == null:
		return
	if color != _shown_color:
		_shown_color = color
		_ring_material.albedo_color = Color(color, 0.95)
		_ring_material.emission = color
		_fill_material.albedo_color = Color(color, 0.12)
		_fill_material.emission = color
		_sign.modulate = color
	if text != _shown_text:
		_shown_text = text
		_sign.text = text


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


func _plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _raid() -> RaidController:
	return get_tree().get_first_node_in_group("raid_controller") as RaidController if is_inside_tree() else null


func _on_body_entered(body: Node3D) -> void:
	if body is Player and _raid() and available:
		confirm()
		_raid().enter_extract(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player and _raid():
		_raid().leave_extract(self)
