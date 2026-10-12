class_name Palette
extends RefCounted
## Colours that depend on settings (DESIGN.md §6.2, §17): rarity colours switch to a distinct palette
## in each colorblind mode. Rarity names are shown next to colours too, so colour is never the only cue.

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Ultra Rare", "Epic", "Legendary"]
const RARITY_SHORT := ["C", "U", "R", "UR", "E", "L"]
## Indexed by ItemData.Rarity.
const RARITY_COLORS := {
	"none": [Color("9a9a96"), Color("5fae5a"), Color("4a8fd8"), Color("9b59d0"), Color("e08a2e"), Color("e8c23a")],
	# Red-green safe (Okabe-Ito): blue/orange/yellow and brightness carry the difference.
	"protanopia": [Color("9a9a96"), Color("56b4e9"), Color("0072b2"), Color("cc79a7"), Color("e69f00"), Color("f0e442")],
	"deuteranopia": [Color("9a9a96"), Color("56b4e9"), Color("0072b2"), Color("cc79a7"), Color("e69f00"), Color("f0e442")],
	# Blue-yellow safe: teal, red and pink stay apart.
	"tritanopia": [Color("9a9a96"), Color("00a99d"), Color("3f6fd8"), Color("d94f8a"), Color("e0532e"), Color("f4f4f4")],
}


static func rarity_color(rarity: int) -> Color:
	var mode: String = Settings.get_value("interface", "colorblind_mode")
	return RARITY_COLORS.get(mode, RARITY_COLORS.none)[clampi(rarity, 0, 5)]


## How well a round does against an armor class (0-1 chance to penetrate), from good to bad, in the
## current colorblind palette. Ammo charts also show the chance as how full each square is, so colour
## is never the only cue.
const EFFECTIVENESS_COLORS := {
	"none": [Color("4fb35a"), Color("a6c84a"), Color("e3b236"), Color("e07a2e"), Color("c8443a")],
	"protanopia": [Color("0072b2"), Color("56b4e9"), Color("f0e442"), Color("e69f00"), Color("d55e00")],
	"deuteranopia": [Color("0072b2"), Color("56b4e9"), Color("f0e442"), Color("e69f00"), Color("d55e00")],
	"tritanopia": [Color("00a99d"), Color("7fd4c8"), Color("f4f4f4"), Color("e88aa8"), Color("e0532e")],
}
## Chance thresholds for the colours above (at least 80%, 50%, 20%, above 0, none).
const EFFECTIVENESS_STEPS := [0.8, 0.5, 0.2, 0.0001]


static func effectiveness_color(chance: float) -> Color:
	var mode: String = Settings.get_value("interface", "colorblind_mode")
	var colors: Array = EFFECTIVENESS_COLORS.get(mode, EFFECTIVENESS_COLORS.none)
	for i in EFFECTIVENESS_STEPS.size():
		if chance >= EFFECTIVENESS_STEPS[i]:
			return colors[i]
	return colors[-1]
