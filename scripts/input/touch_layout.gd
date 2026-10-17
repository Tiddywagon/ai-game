class_name TouchLayout
extends RefCounted
## The on-screen touch controls (DESIGN.md §17.1): every widget's id, what it does, its default place,
## size and look. A saved layout (Settings, up to 3, edited in the touch layout editor) moves, resizes
## or fades any of them: {widget id: {"x", "y" (0-1 of the safe screen area), "scale", "opacity"}}.

## Kinds: "stick" (a virtual joystick), "button" (presses `action` while held), "context" (a button
## that only shows when it's needed), "wheel" (opens the hotkey radial wheel).
const WIDGETS := {
	"move_stick": {"label": "Move", "kind": "stick", "x": 0.24, "y": 0.6, "radius": 120.0, "opacity": 0.55},
	"aim_stick": {"label": "Aim / fire", "kind": "stick", "x": 0.85, "y": 0.68, "radius": 120.0, "opacity": 0.55},
	"fire": {"label": "Fire", "kind": "button", "action": "shoot", "x": 0.70, "y": 0.84, "radius": 64.0, "opacity": 0.7},
	"aim": {"label": "Aim", "kind": "button", "action": "aim", "x": 0.955, "y": 0.40, "radius": 48.0, "opacity": 0.6},
	"reload": {"label": "Reload", "kind": "button", "action": "reload", "x": 0.895, "y": 0.32, "radius": 44.0, "opacity": 0.6},
	"roll": {"label": "Roll", "kind": "button", "action": "roll", "x": 0.72, "y": 0.60, "radius": 48.0, "opacity": 0.6},
	"crouch": {"label": "Crouch", "kind": "button", "action": "crouch", "x": 0.96, "y": 0.62, "radius": 44.0, "opacity": 0.6},
	"melee": {"label": "Melee", "kind": "button", "action": "melee", "x": 0.78, "y": 0.42, "radius": 44.0, "opacity": 0.6},
	"quick_item": {"label": "Quick item", "kind": "button", "action": "use_item", "x": 0.045, "y": 0.42, "radius": 40.0, "opacity": 0.6},
	"hotkeys": {"label": "Hotkeys", "kind": "wheel", "action": "hotkey_wheel", "x": 0.11, "y": 0.42, "radius": 40.0, "opacity": 0.6},
	"inventory": {"label": "Inventory", "kind": "button", "action": "toggle_inventory", "x": 0.045, "y": 0.26, "radius": 40.0, "opacity": 0.6},
	"map": {"label": "Map", "kind": "button", "action": "map_view", "x": 0.11, "y": 0.26, "radius": 40.0, "opacity": 0.6},
	"pause": {"label": "Menu", "kind": "button", "action": "pause", "x": 0.03, "y": 0.07, "radius": 32.0, "opacity": 0.5},
	"interact": {"label": "Interact", "kind": "context", "action": "interact", "x": 0.64, "y": 0.68, "radius": 56.0, "opacity": 0.8},
	"extract": {"label": "Extract", "kind": "context", "action": "show_extracts", "x": 0.50, "y": 0.18, "radius": 52.0, "opacity": 0.8},
	"cover": {"label": "Cover", "kind": "context", "action": "take_cover", "x": 0.68, "y": 0.45, "radius": 40.0, "opacity": 0.7},
}
const SLOTS := 3
const MIN_SCALE := 0.5
const MAX_SCALE := 2.0
const MIN_OPACITY := 0.15
## Phones get bigger buttons.
const PHONE_SCALE := 1.15


## Every widget's place, scale and opacity for a saved `layout` (missing widgets and values take their
## defaults): {id: {"x", "y", "scale", "opacity"}}.
static func resolve(layout: Dictionary) -> Dictionary:
	var result := {}
	for id: String in WIDGETS:
		var widget: Dictionary = WIDGETS[id]
		var saved: Dictionary = layout.get(id, {}) if layout.get(id) is Dictionary else {}
		result[id] = {
			"x": clampf(float(saved.get("x", widget.x)), 0.0, 1.0),
			"y": clampf(float(saved.get("y", widget.y)), 0.0, 1.0),
			"scale": clampf(float(saved.get("scale", 1.0)), MIN_SCALE, MAX_SCALE),
			"opacity": clampf(float(saved.get("opacity", widget.opacity)), MIN_OPACITY, 1.0),
		}
	return result


## On-screen radius (pixels) of widget `id` at `scale`: bigger on phones, and the sticks follow the
## joystick size setting (`stick_size`).
static func radius_of(id: String, scale: float, stick_size: float) -> float:
	var widget: Dictionary = WIDGETS[id]
	var radius: float = widget.radius * scale * (PHONE_SCALE if InputHub.is_phone() else 1.0)
	return radius * stick_size if widget.kind == "stick" else radius


## A layout cleaned up for saving: only known widgets, numbers in range.
static func sanitize(layout: Variant) -> Dictionary:
	return resolve(layout if layout is Dictionary else {})
