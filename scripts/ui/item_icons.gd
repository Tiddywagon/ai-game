class_name ItemIcons
extends RefCounted
## Placeholder inventory icons (DESIGN.md §6.2, §7) until real art exists: a dark box tinted with the
## item's rarity colour, a border in that colour and a simple symbol for its category (a rifle, rounds,
## a cross for meds...). Sized to the item's grid footprint, PIXELS_PER_CELL per cell. Follows the
## colorblind palette; generated once per item and palette, then cached.

const PIXELS_PER_CELL := 64
const BORDER := 3

static var _cache := {}


static func placeholder(item: ItemData) -> Texture2D:
	var mode: String = Settings.get_value("interface", "colorblind_mode")
	var key := "%s|%s" % [item.id, mode]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_draw_icon(item, Palette.rarity_color(item.rarity)))
	return _cache[key]


static func _draw_icon(item: ItemData, color: Color) -> Image:
	var size := item.size * PIXELS_PER_CELL
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color.darkened(0.78))
	# Border.
	image.fill_rect(Rect2i(0, 0, size.x, BORDER), color)
	image.fill_rect(Rect2i(0, size.y - BORDER, size.x, BORDER), color)
	image.fill_rect(Rect2i(0, 0, BORDER, size.y), color)
	image.fill_rect(Rect2i(size.x - BORDER, 0, BORDER, size.y), color)
	var glyph := Glyph.new(image, Rect2(Vector2(size) * 0.14, Vector2(size) * 0.72), color.lightened(0.25))
	match item.category:
		ItemData.Category.WEAPON when str(item.stats.get("class", "")) == "pistol":
			glyph.box(0.1, 0.22, 0.92, 0.46)  # Slide.
			glyph.box(0.18, 0.46, 0.44, 0.92)  # Grip.
			glyph.box(0.44, 0.46, 0.6, 0.64)  # Trigger guard.
			glyph.clear(0.47, 0.46, 0.57, 0.58)
		ItemData.Category.WEAPON:
			glyph.box(0.18, 0.36, 0.78, 0.5)  # Receiver.
			glyph.box(0.78, 0.4, 1.0, 0.46)  # Barrel.
			glyph.box(0.0, 0.38, 0.2, 0.62)  # Stock.
			glyph.box(0.36, 0.5, 0.44, 0.78)  # Grip.
			glyph.box(0.54, 0.5, 0.64, 0.82)  # Magazine.
		ItemData.Category.AMMO:
			for x in [0.12, 0.42, 0.72]:
				glyph.box(x, 0.4, x + 0.16, 0.95)
				glyph.box(x + 0.03, 0.12, x + 0.13, 0.4)
		ItemData.Category.ATTACHMENT:
			_draw_part(glyph, WeaponMods.kind_of(item))
		ItemData.Category.ARMOR:
			glyph.box(0.2, 0.15, 0.8, 0.95)
			glyph.clear(0.38, 0.15, 0.62, 0.35)  # Neck.
			glyph.clear(0.2, 0.15, 0.3, 0.5)  # Arm holes.
			glyph.clear(0.7, 0.15, 0.8, 0.5)
		ItemData.Category.HELMET:
			glyph.disc(0.5, 0.62, 0.42, true)
			glyph.box(0.02, 0.6, 0.98, 0.72)  # Brim.
		ItemData.Category.RIG:
			glyph.box(0.15, 0.2, 0.85, 0.35)
			for x in [0.15, 0.39, 0.63]:
				glyph.box(x, 0.42, x + 0.21, 0.9)
		ItemData.Category.BACKPACK:
			glyph.box(0.2, 0.25, 0.8, 0.95)
			glyph.box(0.3, 0.1, 0.7, 0.3)  # Flap.
			glyph.clear(0.32, 0.55, 0.68, 0.6)  # Pocket seam.
		ItemData.Category.MEDS:
			glyph.box(0.38, 0.1, 0.62, 0.9)
			glyph.box(0.1, 0.38, 0.9, 0.62)
		ItemData.Category.FOOD:
			glyph.box(0.25, 0.2, 0.75, 0.9)
			glyph.clear(0.25, 0.32, 0.75, 0.37)  # Lid rim.
		ItemData.Category.VALUABLE:
			glyph.diamond(0.5, 0.5, 0.45)
		ItemData.Category.JUNK:
			glyph.box(0.3, 0.1, 0.7, 0.35)  # Bolt head.
			glyph.box(0.42, 0.35, 0.58, 0.95)  # Shaft.
		ItemData.Category.KEY:
			glyph.disc(0.25, 0.5, 0.22, false)  # Ring.
			glyph.disc(0.25, 0.5, 0.1, false, true)
			glyph.box(0.45, 0.44, 0.95, 0.56)  # Blade.
			glyph.box(0.75, 0.56, 0.82, 0.72)  # Teeth.
			glyph.box(0.87, 0.56, 0.94, 0.68)
		ItemData.Category.MELEE:
			glyph.box(0.44, 0.15, 0.56, 0.95)  # Handle.
			glyph.box(0.2, 0.12, 0.6, 0.38)  # Blade.
		_:
			glyph.box(0.1, 0.25, 0.9, 0.9)  # A case.
			glyph.clear(0.1, 0.42, 0.9, 0.46)
			glyph.box(0.4, 0.12, 0.6, 0.25)  # Handle.
	return image


## A weapon part's symbol, by its kind (a sight for anything that isn't a part).
static func _draw_part(glyph: Glyph, kind: String) -> void:
	match kind:
		"muzzle":
			glyph.box(0.05, 0.36, 0.95, 0.64)  # Body.
			for x in [0.3, 0.5, 0.7]:
				glyph.clear(x, 0.36, x + 0.08, 0.48)  # Ports.
		"barrel":
			glyph.box(0.0, 0.42, 1.0, 0.58)
			glyph.box(0.0, 0.34, 0.16, 0.66)  # Chamber end.
			glyph.box(0.62, 0.3, 0.7, 0.42)  # Front sight base.
		"handguard":
			glyph.box(0.05, 0.3, 0.95, 0.7)
			for x in [0.12, 0.3, 0.48, 0.66, 0.84]:
				glyph.clear(x, 0.3, x + 0.06, 0.38)  # Rail slots or vents.
		"foregrip":
			glyph.box(0.2, 0.08, 0.8, 0.22)  # Rail clamp.
			glyph.box(0.36, 0.22, 0.64, 0.95)
		"stock":
			glyph.box(0.0, 0.3, 0.55, 0.45)  # Comb.
			glyph.box(0.5, 0.2, 0.95, 0.85)  # Butt.
			glyph.box(0.0, 0.45, 0.25, 0.6)
		"pistol_grip":
			glyph.box(0.2, 0.05, 0.75, 0.25)
			glyph.box(0.3, 0.25, 0.62, 0.95)
			glyph.clear(0.3, 0.25, 0.4, 0.45)  # The rake.
		"receiver":
			glyph.box(0.02, 0.35, 0.98, 0.62)
			glyph.box(0.02, 0.28, 0.98, 0.35)  # Rib.
			glyph.clear(0.75, 0.42, 0.95, 0.55)  # Ejection port.
		"tactical":
			glyph.box(0.15, 0.3, 0.85, 0.7)
			glyph.disc(0.78, 0.5, 0.18, false)  # Lens.
			glyph.box(0.35, 0.15, 0.65, 0.3)  # Mount.
		"magazine":
			glyph.box(0.25, 0.0, 0.7, 0.35)
			glyph.box(0.3, 0.35, 0.78, 0.7)  # The curve.
			glyph.box(0.38, 0.7, 0.88, 1.0)
		_:
			glyph.box(0.1, 0.42, 0.9, 0.58)  # Tube.
			glyph.box(0.05, 0.3, 0.25, 0.7)  # Lenses.
			glyph.box(0.75, 0.25, 0.95, 0.75)
			glyph.box(0.4, 0.58, 0.6, 0.78)  # Mount.


## Draws simple shapes into part of an image, in coordinates from 0 to 1 across that part.
class Glyph:
	var image: Image
	var area: Rect2
	var color: Color
	var background: Color

	func _init(target: Image, region: Rect2, ink: Color) -> void:
		image = target
		area = region
		color = ink
		background = target.get_pixel(int(region.get_center().x), int(region.get_center().y))

	func box(x0: float, y0: float, x1: float, y1: float, ink := Color.TRANSPARENT) -> void:
		var from := area.position + area.size * Vector2(x0, y0)
		var to := area.position + area.size * Vector2(x1, y1)
		image.fill_rect(Rect2i(Vector2i(from), Vector2i(to - from).max(Vector2i.ONE)), color if ink.a == 0.0 else ink)

	func clear(x0: float, y0: float, x1: float, y1: float) -> void:
		box(x0, y0, x1, y1, background)

	## A disc (or its upper half, a dome), measured on the shorter side of the area.
	func disc(cx: float, cy: float, radius: float, dome: bool, erase := false) -> void:
		var side := minf(area.size.x, area.size.y)
		var center := area.position + area.size * Vector2(cx, cy)
		var r := radius * side
		for y in range(int(center.y - r), int(center.y + r) + 1):
			if dome and y > center.y:
				break
			for x in range(int(center.x - r), int(center.x + r) + 1):
				if Vector2(x, y).distance_to(center) <= r and x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					image.set_pixel(x, y, background if erase else color)

	func diamond(cx: float, cy: float, radius: float) -> void:
		var side := minf(area.size.x, area.size.y)
		var center := area.position + area.size * Vector2(cx, cy)
		var r := radius * side
		for y in range(int(center.y - r), int(center.y + r) + 1):
			for x in range(int(center.x - r), int(center.x + r) + 1):
				if absf(x - center.x) + absf(y - center.y) <= r:
					image.set_pixel(x, y, color)
