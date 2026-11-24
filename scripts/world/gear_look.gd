class_name GearLook
extends RefCounted
## The player's gear on the placeholder body (DESIGN.md §6.7): the helmet as a cap, body armor and the
## rig as bands round the torso, the backpack on the back and the knife at the hip, each in its skin
## (or the kind's plain colour), the gun in hand in its skin, and the body in the outfit worn as the
## player's faction. Looks only: the meshes have no collision. dress() is cheap to call on every
## inventory change: it rebuilds only when what's worn or its skins changed.

## Where each worn piece sits on the 1.8 m capsule (the body's local space; forward is -Z).
const PIECES := {
	"helmet": {"mesh": "helmet", "at": Vector3(0, 1.58, 0)},
	"armor": {"mesh": "band", "at": Vector3(0, 1.18, 0), "size": Vector3(0.4, 0.46, 0)},
	"rig": {"mesh": "band", "at": Vector3(0, 0.98, 0), "size": Vector3(0.415, 0.26, 0)},
	"backpack": {"mesh": "box", "at": Vector3(0, 1.15, 0.42), "size": Vector3(0.48, 0.58, 0.24)},
	"melee": {"mesh": "box", "at": Vector3(-0.37, 0.82, 0.05), "size": Vector3(0.04, 0.32, 0.07)},
}
const NODE := "GearLook"


## Dresses `body` (an actor's $Body, holding "Capsule" and the "Gun" Weapon) in what `inventory` wears,
## the gun in hand being `gun` (or null), and the outfit `outfit` (a skin id, "" for the plain uniform).
static func dress(body: Node3D, inventory: Inventory, gun: ItemInstance, outfit := "") -> void:
	if body == null or inventory == null:
		return
	var signature := _signature(inventory, gun, outfit)
	if body.get_meta("gear_look", "") == signature:
		return
	body.set_meta("gear_look", signature)
	var holder := body.get_node_or_null(NODE) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = NODE
		body.add_child(holder)
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	for slot: String in PIECES:
		var piece: ItemInstance = inventory.equipment.get(slot)
		if piece:
			holder.add_child(_piece(slot, piece))
	var capsule := body.get_node_or_null("Capsule") as MeshInstance3D
	if capsule:
		capsule.material_override = SkinLook.material(outfit, Cosmetics.wear_of(outfit)) if outfit != "" else null
	var model := body.get_node_or_null("Gun/Model") as MeshInstance3D
	if model:
		var entry: Dictionary = gun.cosmetics.get("skin", {}) if gun else {}
		model.material_override = SkinLook.material(str(entry.id), float(entry.get("wear", 0.0))) if not entry.is_empty() else null


static func _signature(inventory: Inventory, gun: ItemInstance, outfit: String) -> String:
	var parts: Array[String] = [outfit, str(Cosmetics.wear_of(outfit)) if outfit != "" else ""]
	for slot: String in PIECES:
		var piece: ItemInstance = inventory.equipment.get(slot)
		parts.append("%s:%s" % [piece.data.id, str(piece.cosmetics)] if piece else "-")
	parts.append(str(gun.cosmetics) if gun else "-")
	return "|".join(parts)


static func _piece(slot: String, piece: ItemInstance) -> MeshInstance3D:
	var spec: Dictionary = PIECES[slot]
	var part := MeshInstance3D.new()
	part.name = slot.capitalize()
	part.position = spec.at
	match str(spec.mesh):
		"helmet":
			var cap := SphereMesh.new()
			cap.radius = 0.27
			cap.height = 0.27
			cap.is_hemisphere = true
			part.mesh = cap
		"band":
			var band := CylinderMesh.new()
			band.top_radius = spec.size.x
			band.bottom_radius = spec.size.x
			band.height = spec.size.y
			part.mesh = band
		_:
			var box := BoxMesh.new()
			box.size = spec.size
			part.mesh = box
	var entry: Dictionary = piece.cosmetics.get("skin", {})
	part.material_override = SkinLook.material(str(entry.id), float(entry.get("wear", 0.0))) if not entry.is_empty() else SkinLook.plain(SkinTable.item_kind(piece.data))
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part
