class_name SkinLook
extends RefCounted
## How a cosmetic skin is drawn (DESIGN.md §6.7): one shader with the skin's two colours, its pattern
## and its wear (assets/shaders/skin_pattern.gdshaderinc), as a 3D material (skin.gdshader: models in
## the world, previews, the machine's result) or a 2D one (skin_swatch.gdshader: collection cards). Item
## icons draw a quick swatch of the colours (draw_icon_mark()). Looks only.

const SHADER := preload("res://assets/shaders/skin.gdshader")
const SWATCH_SHADER := preload("res://assets/shaders/skin_swatch.gdshader")
## Each kind's plain colour, when nothing is applied.
const PLAIN := {"weapon": Color(0.12, 0.12, 0.12), "armor": Color(0.3, 0.34, 0.24), "helmet": Color(0.3, 0.33, 0.25),
	"rig": Color(0.33, 0.31, 0.22), "backpack": Color(0.36, 0.32, 0.22), "knife": Color(0.55, 0.56, 0.58), "outfit": Color(0.36, 0.42, 0.28),
	"sticker": Color(0.8, 0.8, 0.76), "charm": Color(0.7, 0.62, 0.3)}

static var _materials := {}


## The 3D material for skin `id` at `wear` (null for an id that isn't a skin). `silhouette`: flat black.
static func material(id: String, wear: float, silhouette := false) -> Material:
	var skin := SkinTable.find(id)
	if skin.is_empty():
		return null
	var key := "%s:%.2f:%s" % [id, wear, silhouette]
	if not _materials.has(key):
		var made := ShaderMaterial.new()
		made.shader = SHADER
		_fill(made, skin, wear, silhouette)
		_materials[key] = made
	return _materials[key]


## The 2D material for skin `id` at `wear` (a card's swatch; `silhouette`: a dark shape).
static func swatch(id: String, wear: float, silhouette := false) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = SWATCH_SHADER
	_fill(made, SkinTable.find(id), wear, silhouette)
	return made


static func _fill(made: ShaderMaterial, skin: Dictionary, wear: float, silhouette: bool) -> void:
	made.set_shader_parameter("base_color", SkinTable.base_color(skin))
	made.set_shader_parameter("accent_color", SkinTable.accent_color(skin))
	made.set_shader_parameter("pattern", SkinTable.pattern(skin))
	made.set_shader_parameter("pattern_scale", float(skin.get("look", {}).get("scale", 1.0)))
	made.set_shader_parameter("wear", clampf(wear, 0.0, 1.0))
	made.set_shader_parameter("silhouette", silhouette)


## A plain material of `kind`'s colour (an item with no skin).
static func plain(kind: String) -> StandardMaterial3D:
	var key := "plain:" + kind
	if not _materials.has(key):
		var made := StandardMaterial3D.new()
		made.albedo_color = PLAIN.get(kind, Color(0.3, 0.3, 0.3))
		made.roughness = 0.75
		_materials[key] = made
	return _materials[key]


## `item`'s skin as a corner swatch on its icon: its colours in a band across the cell's corner, with a
## rarity-coloured edge, and small marks for a sticker and a charm. Nothing for an item with none.
static func draw_icon_mark(canvas: CanvasItem, item: ItemInstance, rect: Rect2, alpha := 1.0) -> void:
	if item.cosmetics.is_empty():
		return
	var entry: Dictionary = item.cosmetics.get("skin", {})
	var skin := SkinTable.find(str(entry.get("id", "")))
	if not skin.is_empty():
		var fade := 1.0 - float(entry.get("wear", 0.0)) * 0.4
		var side := minf(rect.size.x, rect.size.y) * 0.55
		var corner := rect.position + Vector2(0, rect.size.y)
		canvas.draw_colored_polygon(PackedVector2Array([corner + Vector2(2, -2), corner + Vector2(2, -side), corner + Vector2(side, -2)]),
			Color(SkinTable.base_color(skin), 0.85 * alpha * fade))
		canvas.draw_colored_polygon(PackedVector2Array([corner + Vector2(2, -side * 0.55), corner + Vector2(2, -side * 0.75), corner + Vector2(side * 0.75, -2),
			corner + Vector2(side * 0.55, -2)]), Color(SkinTable.accent_color(skin), 0.9 * alpha * fade))
		canvas.draw_line(corner + Vector2(2, -side), corner + Vector2(side, -2), Color(Palette.rarity_color(SkinTable.rarity(skin)), alpha), 2.0)
	var x := rect.position.x + 4.0
	for slot in ["sticker", "charm"]:
		var mark := SkinTable.find(str(item.cosmetics.get(slot, {}).get("id", "")))
		if mark.is_empty():
			continue
		var at := Vector2(x + 4.0, rect.position.y + rect.size.y * 0.5)
		if slot == "sticker":
			canvas.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color(SkinTable.base_color(mark), alpha))
		else:
			canvas.draw_circle(at, 4.0, Color(SkinTable.base_color(mark), alpha))
		x += 11.0


## The tooltip lines for `item`'s skins: "Skin: Ash Camo (Common, Field-Tested 0.214)".
static func tooltip_lines(item: ItemInstance) -> Array[String]:
	var lines: Array[String] = []
	for slot in SkinTable.SLOTS:
		var entry: Dictionary = item.cosmetics.get(slot, {})
		var skin := SkinTable.find(str(entry.get("id", "")))
		if not skin.is_empty():
			lines.append("%s: %s (%s, %s%s)" % [slot.capitalize(), skin.name, SkinTable.rarity_name(skin), SkinTable.wear_text(float(entry.get("wear", 0.0))),
				", bound" if SkinTable.is_bound(skin) else ""])
	return lines
