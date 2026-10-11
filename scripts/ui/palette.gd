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
