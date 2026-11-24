class_name SkinSwatch
extends Control
## A skin drawn flat (DESIGN.md §6.7): the outline of its kind (a rifle, a vest, a helmet, a rig, a
## backpack, a knife, a figure for an outfit, a sticker, a charm) filled with the skin's pattern at its
## wear (SkinLook.swatch()), or a dark silhouette of that outline for a skin you don't own. The skins
## collection's cards, the slot machine's ten-spin row and the COSMETICS tab's skin list use it.

## Outlines in a unit square, by kind.
const SHAPES := {
	"weapon": [Vector2(0.02, 0.42), Vector2(0.62, 0.42), Vector2(0.62, 0.36), Vector2(0.98, 0.36), Vector2(0.98, 0.44), Vector2(0.66, 0.46),
		Vector2(0.66, 0.52), Vector2(0.5, 0.52), Vector2(0.48, 0.74), Vector2(0.41, 0.74), Vector2(0.41, 0.52), Vector2(0.3, 0.52),
		Vector2(0.26, 0.68), Vector2(0.18, 0.68), Vector2(0.2, 0.52), Vector2(0.02, 0.6)],
	"armor": [Vector2(0.25, 0.08), Vector2(0.4, 0.08), Vector2(0.45, 0.2), Vector2(0.55, 0.2), Vector2(0.6, 0.08), Vector2(0.75, 0.08),
		Vector2(0.84, 0.35), Vector2(0.84, 0.92), Vector2(0.16, 0.92), Vector2(0.16, 0.35)],
	"rig": [Vector2(0.25, 0.14), Vector2(0.37, 0.14), Vector2(0.42, 0.36), Vector2(0.58, 0.36), Vector2(0.63, 0.14), Vector2(0.75, 0.14),
		Vector2(0.82, 0.42), Vector2(0.82, 0.84), Vector2(0.18, 0.84), Vector2(0.18, 0.42)],
	"backpack": [Vector2(0.32, 0.1), Vector2(0.68, 0.1), Vector2(0.8, 0.24), Vector2(0.8, 0.9), Vector2(0.2, 0.9), Vector2(0.2, 0.24)],
	"knife": [Vector2(0.04, 0.46), Vector2(0.34, 0.46), Vector2(0.34, 0.42), Vector2(0.4, 0.42), Vector2(0.4, 0.45), Vector2(0.88, 0.45),
		Vector2(0.98, 0.5), Vector2(0.9, 0.57), Vector2(0.4, 0.57), Vector2(0.4, 0.6), Vector2(0.34, 0.6), Vector2(0.34, 0.56), Vector2(0.04, 0.56)],
	"outfit": [Vector2(0.36, 0.3), Vector2(0.64, 0.3), Vector2(0.82, 0.56), Vector2(0.72, 0.6), Vector2(0.64, 0.46), Vector2(0.64, 0.96),
		Vector2(0.36, 0.96), Vector2(0.36, 0.46), Vector2(0.28, 0.6), Vector2(0.18, 0.56)],
	"sticker": [Vector2(0.18, 0.18), Vector2(0.82, 0.18), Vector2(0.82, 0.66), Vector2(0.66, 0.82), Vector2(0.18, 0.82)],
}

var skin_id := ""
var wear := 0.0
var silhouette := false


## A swatch of skin `id` at `wear` (`dark`: its silhouette), `size` pixels.
static func create(id: String, skin_wear: float, dark := false, size := Vector2(150, 96)) -> SkinSwatch:
	var swatch := SkinSwatch.new()
	swatch.name = "Swatch"
	swatch.custom_minimum_size = size
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.show_skin(id, skin_wear, dark)
	return swatch


## Shows skin `id` at `wear` (`dark`: the silhouette).
func show_skin(id: String, skin_wear: float, dark := false) -> void:
	skin_id = id
	wear = skin_wear
	silhouette = dark
	material = SkinLook.swatch(id, skin_wear, dark) if SkinTable.has(id) else null
	queue_redraw()


func _draw() -> void:
	var kind := str(SkinTable.find(skin_id).get("kind", "weapon"))
	var side := minf(size.x, size.y * 1.4)
	var area := Rect2((size - Vector2(side, side / 1.4)) / 2.0, Vector2(side, side / 1.4))
	for outline in _outlines(kind):
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for corner: Vector2 in outline:
			points.append(area.position + corner * area.size)
			uvs.append(corner)
		draw_polygon(points, PackedColorArray([Color.WHITE]), uvs)


## The outlines drawn for `kind`: one, or several for the round ones (a helmet, a charm, an outfit's head).
static func _outlines(kind: String) -> Array:
	match kind:
		"helmet":
			var dome: Array = []
			for i in 17:
				var angle := PI + PI * i / 16.0
				dome.append(Vector2(0.5, 0.72) + Vector2(cos(angle) * 0.36, sin(angle) * 0.5))
			dome.append(Vector2(0.92, 0.72))
			dome.append(Vector2(0.92, 0.8))
			dome.append(Vector2(0.08, 0.8))
			dome.append(Vector2(0.08, 0.72))
			return [dome]
		"charm":
			return [_circle(Vector2(0.5, 0.62), 0.24), [Vector2(0.48, 0.08), Vector2(0.52, 0.08), Vector2(0.52, 0.4), Vector2(0.48, 0.4)]]
		"outfit":
			return [SHAPES.outfit, _circle(Vector2(0.5, 0.17), 0.11)]
	return [SHAPES.get(kind, SHAPES.sticker)]


static func _circle(centre: Vector2, radius: float) -> Array:
	var points: Array = []
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(centre + Vector2(cos(angle), sin(angle) * 1.4) * radius)
	return points
