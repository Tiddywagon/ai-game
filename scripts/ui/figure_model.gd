class_name FigureModel
extends Node3D
## The placeholder 3D model of a collectible figure (DESIGN.md §6.6), built from the recipe in its
## item's "model" stat: {"base": "round" / "square" / "hex" (a low plinth, tinted by the figure's
## rarity), "body", "head" and "prop": each {"shape": one of SHAPES, "color": "rrggbb", "size": [x, y,
## z] (metres across, tall, deep), "at": [x, y, z] (optional: a prop's place from the middle of the
## base's top; for a body or head, a nudge from where it stands by itself)}}. The body stands on the
## base and the head on the body; a prop goes wherever "at" puts it. About half a metre tall at most,
## inside a 0.4 m footprint. A silhouette (the COLLECTION screen's missing figures) is the same shapes
## in one flat dark colour.

const SHAPES := ["box", "sphere", "cylinder", "capsule", "cone", "prism"]
const BASES := ["round", "square", "hex"]
const PARTS := ["body", "head", "prop"]
const PART_KEYS := ["shape", "color", "size", "at"]
## The plinth: this wide and this tall.
const BASE_WIDTH := 0.4
const BASE_HEIGHT := 0.04
## How far the head sinks into the body.
const NECK := 0.02
## The largest a part may be, and the farthest "at" may put one (metres).
const MAX_SIZE := 0.6
const MAX_OFFSET := 0.6
const SILHOUETTE := Color(0.06, 0.065, 0.075)

## The item this is a model of.
var data: ItemData
var silhouette := false


## A model of figure `item` (a dark silhouette of it with `as_silhouette`).
static func create(item: ItemData, as_silhouette := false) -> FigureModel:
	var model := FigureModel.new()
	model.data = item
	model.silhouette = as_silhouette
	model.name = "Figure_%s" % (item.id if item else "none")
	model._build()
	return model


## How tall the model built from `recipe` stands (metres, plinth included).
static func height(recipe: Variant) -> float:
	if not recipe is Dictionary:
		return BASE_HEIGHT
	var top := BASE_HEIGHT
	var body: Dictionary = recipe.get("body", {})
	var head: Dictionary = recipe.get("head", {})
	var body_top := BASE_HEIGHT + _size(body).y + _at(body).y
	top = maxf(top, body_top)
	top = maxf(top, body_top - NECK + _size(head).y + _at(head).y)
	var prop: Dictionary = recipe.get("prop", {})
	if not prop.is_empty():
		top = maxf(top, BASE_HEIGHT + _at(prop).y + _size(prop).y / 2.0)
	return top


func _build() -> void:
	var recipe: Dictionary = data.stats.get("model", {}) if data and data.stats.get("model") is Dictionary else {}
	var rarity_color := Palette.rarity_color(data.rarity) if data else Color.GRAY
	add_child(_base(str(recipe.get("base", "round")), rarity_color))
	var body: Dictionary = recipe.get("body", {})
	var body_size := _size(body)
	if not body.is_empty():
		_add_part("Body", body, Vector3(0, BASE_HEIGHT + body_size.y / 2.0, 0) + _at(body))
	var head: Dictionary = recipe.get("head", {})
	if not head.is_empty():
		_add_part("Head", head, Vector3(0, BASE_HEIGHT + body_size.y + _at(body).y - NECK + _size(head).y / 2.0, 0) + _at(head))
	var prop: Dictionary = recipe.get("prop", {})
	if not prop.is_empty():
		_add_part("Prop", prop, Vector3(0, BASE_HEIGHT, 0) + _at(prop))


func _base(kind: String, rarity_color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Base"
	if kind == "square":
		var box := BoxMesh.new()
		box.size = Vector3(BASE_WIDTH * 0.9, BASE_HEIGHT, BASE_WIDTH * 0.9)
		node.mesh = box
	else:
		var disc := CylinderMesh.new()
		disc.top_radius = BASE_WIDTH / 2.0 * 0.92
		disc.bottom_radius = BASE_WIDTH / 2.0
		disc.height = BASE_HEIGHT
		disc.radial_segments = 6 if kind == "hex" else 24
		disc.rings = 1
		node.mesh = disc
	node.position.y = BASE_HEIGHT / 2.0
	node.material_override = _material(rarity_color.darkened(0.15), 0.35)
	return node


func _add_part(part_name: String, part: Dictionary, at: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.name = part_name
	var size := _size(part)
	node.mesh = _mesh(str(part.get("shape", "box")), size)
	node.position = at
	if str(part.get("shape", "box")) in ["sphere", "cylinder", "capsule", "cone"]:
		node.scale = Vector3(1.0, 1.0, size.z / maxf(size.x, 0.001))  # Round shapes are x across; z squashes them.
	node.material_override = _material(Color.from_string(str(part.get("color", "888888")), Color.GRAY), 0.7)
	add_child(node)


static func _mesh(shape: String, size: Vector3) -> Mesh:
	match shape:
		"sphere":
			var mesh := SphereMesh.new()
			mesh.radius = size.x / 2.0
			mesh.height = size.y
			mesh.radial_segments = 16
			mesh.rings = 8
			return mesh
		"cylinder", "cone":
			var mesh := CylinderMesh.new()
			mesh.bottom_radius = size.x / 2.0
			mesh.top_radius = 0.0 if shape == "cone" else size.x / 2.0
			mesh.height = size.y
			mesh.radial_segments = 16
			mesh.rings = 1
			return mesh
		"capsule":
			var mesh := CapsuleMesh.new()
			mesh.radius = minf(size.x / 2.0, size.y / 2.0)
			mesh.height = size.y
			mesh.radial_segments = 16
			mesh.rings = 4
			return mesh
		"prism":
			var mesh := PrismMesh.new()
			mesh.size = size
			return mesh
	var box := BoxMesh.new()
	box.size = size
	return box


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if silhouette:
		material.albedo_color = SILHOUETTE
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = 0.1
	return material


static func _size(part: Dictionary) -> Vector3:
	return _vector(part.get("size"), Vector3.ZERO)


static func _at(part: Dictionary) -> Vector3:
	return _vector(part.get("at"), Vector3.ZERO)


static func _vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


## What's wrong with a model recipe (empty if nothing): a known base, a body and a head (a prop is
## optional), each a known shape with a colour and a size within MAX_SIZE, placed within MAX_OFFSET.
static func problems(recipe: Variant) -> Array[String]:
	if not recipe is Dictionary:
		return ["no model recipe"]
	var found: Array[String] = []
	for key: String in recipe:
		if key != "base" and not key in PARTS:
			found.append("unknown key \"%s\"" % key)
	if not str(recipe.get("base", "")) in BASES:
		found.append("base \"%s\" isn't one of %s" % [recipe.get("base", ""), ", ".join(BASES)])
	for part_name: String in PARTS:
		var part: Variant = recipe.get(part_name)
		if part == null and part_name == "prop":
			continue
		if not part is Dictionary:
			found.append("no %s" % part_name)
			continue
		for key: String in part:
			if not key in PART_KEYS:
				found.append("%s: unknown key \"%s\"" % [part_name, key])
		if not str(part.get("shape", "")) in SHAPES:
			found.append("%s: shape \"%s\" isn't one of %s" % [part_name, part.get("shape", ""), ", ".join(SHAPES)])
		if not Color.html_is_valid(str(part.get("color", ""))):
			found.append("%s: colour \"%s\" isn't rrggbb" % [part_name, part.get("color", "")])
		var size: Variant = part.get("size")
		if not (size is Array and size.size() == 3 and size.all(func(side: Variant) -> bool:
				return (side is float or side is int) and float(side) > 0.0 and float(side) <= MAX_SIZE)):
			found.append("%s: size must be [x, y, z], each above 0 and at most %s" % [part_name, MAX_SIZE])
		var at: Variant = part.get("at")
		if part.has("at") and not (at is Array and at.size() == 3 and at.all(func(side: Variant) -> bool:
				return (side is float or side is int) and absf(float(side)) <= MAX_OFFSET)):
			found.append("%s: at must be [x, y, z], each within %s" % [part_name, MAX_OFFSET])
	return found
