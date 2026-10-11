@tool
extends Control
## Small shield icon drawn in code, shown on the HUD while the player is in cover.

@export var color := Color(0.85, 0.85, 0.75):
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var outline := PackedVector2Array([
		Vector2(w * 0.5, 0.0), Vector2(w, h * 0.16), Vector2(w * 0.94, h * 0.58),
		Vector2(w * 0.5, h), Vector2(w * 0.06, h * 0.58), Vector2(0.0, h * 0.16),
	])
	draw_colored_polygon(outline, color)
	# A darker inner half gives the shield some shape.
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.5, h * 0.14), Vector2(w * 0.5, h * 0.86), Vector2(w * 0.2, h * 0.56), Vector2(w * 0.16, h * 0.24),
	]), color.darkened(0.35))
