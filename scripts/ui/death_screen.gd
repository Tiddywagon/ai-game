extends CanvasLayer
## Death screen (DESIGN.md §16.5): says what killed you (who, with what, where it hit, from how far,
## or what you bled out from), shows your body as it was, and a few raid stats. BACK TO MENU leaves.

const MAIN_MENU := "res://ui/main_menu.tscn"
const FADE_TIME := 0.6


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%MenuButton.pressed.connect(_to_menu)
	%Root.modulate.a = 0.0
	create_tween().tween_property(%Root, "modulate:a", 1.0, FADE_TIME)


func show_death(player: Player, raid_seconds: float) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var lines := describe(player.health.death_cause)
	%Cause.text = lines[0]
	%Detail.text = lines[1]
	%Detail.visible = lines[1] != ""
	%Silhouette.health = player.health
	var statuses := player.health.status_lines()
	%Statuses.text = "\n".join(statuses) if not statuses.is_empty() else "No status effects"
	var map := MapInfo.find(GameState.raid.get("map", ""))
	_stat("Map", map.display_name if map else "Test Yard")
	_stat("Side", "Scav" if GameState.raid.get("side") == "scav" else "PMC")
	_stat("Time in raid", "%d:%02d" % [int(raid_seconds) / 60, int(raid_seconds) % 60])
	_stat("Kills", str(player.kills))
	%MenuButton.grab_focus()


## Headline and detail line for a BodyHealth death cause, e.g.
## ["Shot in the head by a Scav", "AK-74N  ·  5.45x39 PS  ·  50 damage  ·  23 m"].
static func describe(cause: Dictionary) -> Array[String]:
	var fatal := _part_name(cause.get("fatal_part", -1))
	match cause.get("kind", ""):
		"shot":
			var part := _part_name(cause.part)
			var headline := "Shot in the %s by a %s" % [part, cause.get("attacker", "unknown attacker")]
			var details: Array[String] = []
			for key in ["weapon", "ammo"]:
				if cause.get(key, "") != "":
					details.append(cause[key])
			details.append("%d damage" % roundi(cause.damage))
			if cause.has("distance"):
				details.append(Settings.format_distance(cause.distance))
			var detail := "  ·  ".join(details)
			if part != fatal:
				detail += "\nThe %s was already gone: the damage spread to your %s." % [part, fatal]
			return [headline, detail]
		"bleed":
			var kind := "Heavy bleed" if cause.bleed == BodyHealth.Bleed.HEAVY else "Light bleed"
			var detail := "%s from the %s" % [kind, _part_name(cause.part)]
			var source: Dictionary = cause.get("source", {})
			if source.has("attacker"):
				detail += ", from a wound by a %s" % source.attacker
				if source.get("weapon", "") != "":
					detail += " (%s)" % source.weapon
			return ["Bled out", detail + "."]
	return ["Killed in action", ""]


static func _part_name(part: int) -> String:
	return BodyHealth.PART_NAMES[part].to_lower() if part >= 0 else "body"


func _stat(name: String, value: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.text = name
	var value_label := Label.new()
	value_label.text = value
	%Stats.add_child(label)
	%Stats.add_child(value_label)


func _to_menu() -> void:
	get_tree().paused = false
	GameState.raid = {}
	get_tree().change_scene_to_file(MAIN_MENU)
