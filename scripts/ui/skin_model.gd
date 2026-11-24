class_name SkinModel
extends Node3D
## A placeholder 3D model of one kind of item, or the character, painted with its skins (DESIGN.md §6.7):
## the COSMETICS tab's rotating preview, the slot machine's result card and the skins collection. Built
## from boxes, cylinders and spheres about a metre across, centred on the origin. A gun, armor, a
## helmet or a backpack also has a sticker plate and, where the item takes one, a charm on a string.
## paint() puts a skin on a slot ("skin", "sticker", "charm"); "" puts the plain look back.

## The kind (SkinTable.KINDS) this model shows.
var kind := ""
## Slot -> the meshes that slot paints.
var _parts := {"skin": [], "sticker": [], "charm": []}


## A model of `kind`, unpainted. Stickers and charms on their own are shown big: a plate, a pendant.
static func create(model_kind: String) -> SkinModel:
	var model := SkinModel.new()
	model.name = "SkinModel"
	model.kind = model_kind
	model._build()
	return model


## A model of skin `id`'s kind wearing it at `wear` (`silhouette`: a dark shape, for one you don't own).
static func for_skin(id: String, wear: float, silhouette := false) -> SkinModel:
	var skin := SkinTable.find(id)
	var model := create(str(skin.get("kind", "weapon")))
	model.paint(SkinTable.slot_of(skin) if not skin.get("kind") in ["sticker", "charm"] else "skin", id, wear, silhouette)
	return model


## A model of `item` (its kind) with the skins it carries; `preview`: {slot: skin id} shown instead.
static func for_item(item: ItemInstance, preview := {}) -> SkinModel:
	var model := create(SkinTable.item_kind(item.data))
	for slot: String in SkinTable.SLOTS:
		var entry: Dictionary = item.cosmetics.get(slot, {})
		if preview.has(slot):
			model.paint(slot, str(preview[slot]), Cosmetics.wear_of(str(preview[slot])) if str(preview[slot]) != "" else 0.0)
		elif not entry.is_empty():
			model.paint(slot, str(entry.id), float(entry.get("wear", 0.0)))
	model.show_slot("charm", "charm" in SkinTable.item_slots(item.data) and (preview.get("charm", "") != "" or item.cosmetics.has("charm")))
	model.show_slot("sticker", "sticker" in SkinTable.item_slots(item.data) and (preview.get("sticker", "") != "" or item.cosmetics.has("sticker")))
	return model


## Paints `slot` with skin `id` at `wear` ("" or an unknown id: the plain look).
func paint(slot: String, id: String, wear: float, silhouette := false) -> void:
	var made: Material = SkinLook.material(id, wear, silhouette) if id != "" else null
	for mesh: MeshInstance3D in _parts.get(slot, []):
		mesh.material_override = made if made else SkinLook.plain(kind if slot == "skin" else slot)


## Shows or hides the sticker plate or the charm.
func show_slot(slot: String, on: bool) -> void:
	for mesh: MeshInstance3D in _parts.get(slot, []):
		mesh.visible = on


func _box(size: Vector3, at: Vector3, slot := "skin") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, at, slot)


func _cylinder(radius: float, height: float, at: Vector3, turn := Vector3.ZERO, slot := "skin") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var part := _add(mesh, at, slot)
	part.rotation_degrees = turn
	return part


func _sphere(radius: float, at: Vector3, slot := "skin", hemisphere := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * (1.0 if hemisphere else 2.0)
	mesh.is_hemisphere = hemisphere
	return _add(mesh, at, slot)


func _add(mesh: Mesh, at: Vector3, slot: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = SkinLook.plain(kind if slot == "skin" else slot)
	add_child(part)
	(_parts[slot] as Array).append(part)
	return part


## A charm hanging from `at`: a string and a bead.
func _charm(at: Vector3) -> void:
	_cylinder(0.006, 0.12, at + Vector3(0, -0.06, 0), Vector3.ZERO, "charm")
	_sphere(0.045, at + Vector3(0, -0.15, 0), "charm")


func _build() -> void:
	match kind:
		"weapon":
			_box(Vector3(0.5, 0.13, 0.08), Vector3(0, 0, 0))
			_box(Vector3(0.28, 0.11, 0.06), Vector3(-0.38, -0.02, 0))
			_cylinder(0.022, 0.36, Vector3(0.43, 0.02, 0), Vector3(0, 0, 90))
			_box(Vector3(0.08, 0.2, 0.05), Vector3(0.08, -0.15, 0))
			_box(Vector3(0.06, 0.13, 0.05), Vector3(-0.12, -0.12, 0))
			_box(Vector3(0.12, 0.07, 0.005), Vector3(-0.02, 0.0, 0.043), "sticker")
			_charm(Vector3(-0.24, -0.06, 0.0))
		"armor":
			_box(Vector3(0.56, 0.62, 0.22), Vector3.ZERO)
			_box(Vector3(0.12, 0.16, 0.2), Vector3(-0.2, 0.36, 0))
			_box(Vector3(0.12, 0.16, 0.2), Vector3(0.2, 0.36, 0))
			_box(Vector3(0.44, 0.3, 0.05), Vector3(0, 0.04, 0.13))
			_box(Vector3(0.14, 0.1, 0.005), Vector3(0.12, 0.12, 0.158), "sticker")
		"helmet":
			_sphere(0.3, Vector3.ZERO, "skin", true)
			_cylinder(0.31, 0.04, Vector3(0, 0.0, 0))
			_box(Vector3(0.12, 0.08, 0.005), Vector3(0, 0.14, 0.27), "sticker")
		"rig":
			_box(Vector3(0.54, 0.46, 0.12), Vector3.ZERO)
			for x in [-0.17, 0.0, 0.17]:
				_box(Vector3(0.13, 0.17, 0.08), Vector3(x, -0.06, 0.09))
			_box(Vector3(0.08, 0.3, 0.1), Vector3(-0.2, 0.3, 0))
			_box(Vector3(0.08, 0.3, 0.1), Vector3(0.2, 0.3, 0))
		"backpack":
			_box(Vector3(0.46, 0.6, 0.26), Vector3.ZERO)
			_box(Vector3(0.46, 0.14, 0.28), Vector3(0, 0.3, 0.01))
			_box(Vector3(0.36, 0.22, 0.08), Vector3(0, -0.12, 0.16))
			_box(Vector3(0.14, 0.08, 0.005), Vector3(0, -0.06, 0.201), "sticker")
			_charm(Vector3(0.18, 0.36, 0.1))
		"knife":
			_box(Vector3(0.42, 0.07, 0.012), Vector3(0.12, 0, 0))
			var tip := PrismMesh.new()
			tip.size = Vector3(0.07, 0.08, 0.012)
			var point := _add(tip, Vector3(0.37, 0, 0), "skin")
			point.rotation_degrees = Vector3(0, 0, -90)
			_box(Vector3(0.03, 0.12, 0.04), Vector3(-0.11, 0, 0))
			_cylinder(0.028, 0.2, Vector3(-0.22, 0, 0), Vector3(0, 0, 90))
		"outfit":
			var body := CapsuleMesh.new()
			body.radius = 0.24
			body.height = 1.1
			_add(body, Vector3(0, -0.05, 0), "skin")
			var head := _sphere(0.15, Vector3(0, 0.62, 0))
			head.material_override = SkinLook.plain("knife")
			(_parts.skin as Array).erase(head)
		"sticker":
			_box(Vector3(0.6, 0.6, 0.03), Vector3.ZERO)
		"charm":
			_cylinder(0.01, 0.3, Vector3(0, 0.3, 0))
			_sphere(0.2, Vector3(0, -0.05, 0))
		_:
			_box(Vector3(0.4, 0.4, 0.4), Vector3.ZERO)
