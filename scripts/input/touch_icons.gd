class_name TouchIcons
extends RefCounted
## Simple vector pictograms for the touch buttons and touch prompts (DESIGN.md §17.1), drawn into any
## CanvasItem: no textures, so they stay sharp at any size and in any colour.


## Draws the icon for touch widget `id` centred on `at`, `size` across, in `color`.
static func draw(canvas: CanvasItem, id: String, at: Vector2, size: float, color: Color) -> void:
	var r := size * 0.5
	var w := maxf(size * 0.08, 2.0)
	match id:
		"fire", "aim_stick":
			canvas.draw_arc(at, r * 0.62, 0.0, TAU, 32, color, w, true)
			for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				canvas.draw_line(at + dir * r * 0.3, at + dir * r * 0.95, color, w, true)
			canvas.draw_circle(at, w * 0.8, color)
		"aim":
			canvas.draw_arc(at, r * 0.75, 0.0, TAU, 32, color, w, true)
			canvas.draw_arc(at, r * 0.35, 0.0, TAU, 24, color, w * 0.8, true)
			canvas.draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), color, w * 0.6, true)
			canvas.draw_line(at + Vector2(0, -r), at + Vector2(0, r), color, w * 0.6, true)
		"reload":
			canvas.draw_arc(at, r * 0.6, -PI * 0.15, PI * 1.45, 32, color, w, true)
			var tip := at + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * r * 0.6
			canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.32, -r * 0.08), tip + Vector2(r * 0.12, r * 0.3), tip + Vector2(r * 0.18, -r * 0.3)]), color)
		"roll":
			canvas.draw_arc(at + Vector2(0, r * 0.1), r * 0.55, PI, TAU + PI * 0.15, 28, color, w, true)
			var end := at + Vector2(0, r * 0.1) + Vector2(cos(PI * 0.15), sin(PI * 0.15)) * r * 0.55
			canvas.draw_colored_polygon(PackedVector2Array([end + Vector2(-r * 0.3, 0), end + Vector2(r * 0.18, -r * 0.05), end + Vector2(-r * 0.05, r * 0.32)]), color)
		"crouch":
			_chevron(canvas, at + Vector2(0, -r * 0.2), r * 0.55, color, w)
			_chevron(canvas, at + Vector2(0, r * 0.25), r * 0.55, color, w)
		"melee":
			canvas.draw_line(at + Vector2(-r * 0.55, r * 0.55), at + Vector2(r * 0.45, -r * 0.45), color, w * 1.6, true)
			canvas.draw_line(at + Vector2(-r * 0.6, r * 0.2), at + Vector2(-r * 0.2, r * 0.6), color, w * 1.2, true)
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(r * 0.15, -r * 0.65), at + Vector2(r * 0.7, -r * 0.65), at + Vector2(r * 0.7, -r * 0.1)]), color)
		"quick_item":
			canvas.draw_rect(Rect2(at - Vector2(r * 0.18, r * 0.6), Vector2(r * 0.36, r * 1.2)), color)
			canvas.draw_rect(Rect2(at - Vector2(r * 0.6, r * 0.18), Vector2(r * 1.2, r * 0.36)), color)
		"hotkeys":
			for i in 6:
				var angle := TAU * i / 6.0 - PI / 2.0
				canvas.draw_circle(at + Vector2(cos(angle), sin(angle)) * r * 0.55, r * 0.14, color)
			canvas.draw_circle(at, r * 0.12, color)
		"inventory":
			canvas.draw_rect(Rect2(at + Vector2(-r * 0.55, -r * 0.3), Vector2(r * 1.1, r * 0.9)), color, false, w)
			canvas.draw_arc(at + Vector2(0, -r * 0.3), r * 0.28, PI, TAU, 12, color, w, true)
			canvas.draw_line(at + Vector2(-r * 0.55, r * 0.05), at + Vector2(r * 0.55, r * 0.05), color, w * 0.7)
		"map":
			var points := PackedVector2Array([at + Vector2(-r * 0.7, -r * 0.45), at + Vector2(-r * 0.25, -r * 0.6), at + Vector2(r * 0.25, -r * 0.45),
				at + Vector2(r * 0.7, -r * 0.6), at + Vector2(r * 0.7, r * 0.45), at + Vector2(r * 0.25, r * 0.6), at + Vector2(-r * 0.25, r * 0.45),
				at + Vector2(-r * 0.7, r * 0.6), at + Vector2(-r * 0.7, -r * 0.45)])
			canvas.draw_polyline(points, color, w, true)
			canvas.draw_line(at + Vector2(-r * 0.25, -r * 0.6), at + Vector2(-r * 0.25, r * 0.45), color, w * 0.6)
			canvas.draw_line(at + Vector2(r * 0.25, -r * 0.45), at + Vector2(r * 0.25, r * 0.6), color, w * 0.6)
		"pause":
			for y in [-0.35, 0.0, 0.35]:
				canvas.draw_line(at + Vector2(-r * 0.55, r * y), at + Vector2(r * 0.55, r * y), color, w * 1.1, true)
		"interact":
			canvas.draw_arc(at, r * 0.65, 0.0, TAU, 28, color, w, true)
			canvas.draw_line(at + Vector2(0, -r * 0.35), at + Vector2(0, r * 0.12), color, w * 1.3, true)
			canvas.draw_circle(at + Vector2(0, r * 0.35), w * 0.9, color)
		"extract":
			canvas.draw_rect(Rect2(at + Vector2(-r * 0.6, -r * 0.6), Vector2(r * 0.7, r * 1.2)), color, false, w)
			canvas.draw_line(at + Vector2(-r * 0.1, 0), at + Vector2(r * 0.7, 0), color, w * 1.2, true)
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(r * 0.75, 0), at + Vector2(r * 0.4, -r * 0.3), at + Vector2(r * 0.4, r * 0.3)]), color)
		"cover":
			canvas.draw_rect(Rect2(at + Vector2(-r * 0.7, -r * 0.1), Vector2(r * 1.4, r * 0.6)), color, false, w)
			canvas.draw_circle(at + Vector2(0, -r * 0.4), r * 0.22, color)
		"move_stick":
			for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				var tip := at + dir * r * 0.75
				var side := Vector2(-dir.y, dir.x) * r * 0.22
				canvas.draw_colored_polygon(PackedVector2Array([tip, tip - dir * r * 0.3 + side, tip - dir * r * 0.3 - side]), color)
		_:
			canvas.draw_circle(at, r * 0.25, color)


static func _chevron(canvas: CanvasItem, at: Vector2, half: float, color: Color, width: float) -> void:
	canvas.draw_polyline(PackedVector2Array([at + Vector2(-half, -half * 0.45), at + Vector2(0, half * 0.35), at + Vector2(half, -half * 0.45)]), color, width, true)
