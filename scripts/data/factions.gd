class_name Factions
extends RefCounted
## The two PMC factions, BEAR and USEC (DESIGN.md §3), from data/config/factions.json (checked when it
## loads: problems()). One source for the player, AI PMCs, the faction picker and the docs: each
## faction's name and background, its look (body and accent colours, apply_look()), its voice (a WAV and
## 2-3 lines per event: Voice), a new character's kit and stash (starter_kit(), starter_stash()) and the
## BotKit its AI PMCs carry (ai_kit(): Eastern or Western gear). Also how AI PMC squads form
## (squad_config(), roll_squad_size()), how PMCs of one faction hold back from each other
## (same_faction()) and how far voice lines carry and how often (voice_config()).
## Faction ids are lower-case StringNames, &"bear" and &"usec" (GameState.Faction BEAR / USEC:
## of_profile()); &"" is no faction (a Scav, a boss or guard, the player as a Scav).

const PATH := "res://data/config/factions.json"
## Voice line events (DESIGN.md §3): spotting an enemy, being hit or shot at, reloading, throwing a
## grenade, a kill, a squad mate killed, a squad order (moving up, follow me), treating a wound,
## heading for an extract.
const EVENTS: Array[StringName] = [&"contact", &"hit", &"reload", &"grenade", &"enemy_down", &"mate_down", &"move", &"heal", &"extract"]
## A faction's placeholder voice sounds: assets/audio/voice/<voice id>_<event>.wav
## (tools/make_placeholder_audio.py).
const VOICE_DIR := "res://assets/audio/voice/"
const FIELDS := ["name", "member", "background", "look", "voice", "starter", "ai_kit", "gear_bias"]
## The accent (a band round the head) on the placeholder body: its height on the 1.8 m capsule and size.
const ACCENT_HEIGHT := 1.5
const ACCENT_RADII := Vector2(0.3, 0.42)

## The file data() loads (tests point it at a broken copy), and what was wrong with it when it last
## loaded (problems(); each one also an error).
static var path := PATH
static var load_problems: Array[String] = []
static var _data := {}
static var _loaded := false


## The whole file. Checked the first time it loads (each problem is an error, reported once). A file
## that's missing or isn't valid JSON gives {}: no factions (AI PMCs then have none, and a new character
## no kit), and it isn't read again until reload().
static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("factions") is Dictionary:
			_data = parsed
			load_problems = problems()
		else:
			load_problems = ["%s isn't valid JSON with a \"factions\" object" % path]
		for problem in load_problems:
			push_error("Factions: %s" % problem)
	return _data


## Forgets what was loaded (tests that point `path` elsewhere).
static func reload() -> void:
	_data = {}
	_loaded = false


## The factions' ids, in file order (BEAR first).
static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: String in data().get("factions", {}):
		result.append(StringName(id))
	return result


static func has(id: StringName) -> bool:
	return id != &"" and data().get("factions", {}).has(String(id))


## A faction's entry ({} for none).
static func entry(id: StringName) -> Dictionary:
	return data().get("factions", {}).get(String(id), {})


## The faction id of a GameState.Faction (BEAR -> &"bear"; NONE -> &"").
static func of_profile(faction: int) -> StringName:
	var key: Variant = GameState.Faction.find_key(faction)
	return StringName(str(key).to_lower()) if key != null and faction != GameState.Faction.NONE else &""


## "BEAR" / "USEC" ("" for none).
static func display_name(id: StringName) -> String:
	return str(entry(id).get("name", ""))


## What the side you play (GameState.raid "side") is called on screen: your profile's faction ("BEAR",
## "USEC") for "pmc" ("PMC" without one), "Scav" for "scav".
static func side_name(side: String) -> String:
	if side == "scav":
		return "Scav"
	var id := of_profile(GameState.faction)
	return display_name(id) if has(id) else "PMC"


## What one of them is called: "USEC operator" ("" for none).
static func member_name(id: StringName) -> String:
	return str(entry(id).get("member", display_name(id)))


static func background(id: StringName) -> String:
	return str(entry(id).get("background", ""))


static func body_color(id: StringName) -> Color:
	return _color(entry(id).get("look", {}).get("body", []), Color(0.5, 0.5, 0.5))


static func accent_color(id: StringName) -> Color:
	return _color(entry(id).get("look", {}).get("accent", []), Color.WHITE)


## Dresses a placeholder body (an actor's $Body, with its Capsule) in faction `id`'s colours: the body
## colour and an accent band round the head. With no faction it takes the band off and, if
## `plain_color` is a Color (a Scav's, a boss's), paints the body that colour; else it leaves it as is.
static func apply_look(body: Node3D, id: StringName, plain_color: Variant = null) -> void:
	if body == null:
		return
	var capsule := body.get_node_or_null("Capsule") as MeshInstance3D
	var accent := body.get_node_or_null("Accent") as MeshInstance3D
	if not has(id):
		if accent:
			accent.queue_free()
			body.remove_child(accent)
		if capsule and plain_color is Color:
			capsule.material_override = _material(plain_color)
		return
	if capsule:
		capsule.material_override = _material(body_color(id))
	if accent == null:
		accent = MeshInstance3D.new()
		accent.name = "Accent"
		var band := TorusMesh.new()
		band.inner_radius = ACCENT_RADII.x
		band.outer_radius = ACCENT_RADII.y
		band.rings = 24
		band.ring_segments = 8
		accent.mesh = band
		accent.position = Vector3(0.0, ACCENT_HEIGHT, 0.0)
		accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(accent)
	accent.material_override = _material(accent_color(id), true)


## The voice lines of faction `id` for `event`: [{"text", "subtitle" (optional)}].
static func lines(id: StringName, event: StringName) -> Array:
	return entry(id).get("voice", {}).get("lines", {}).get(String(event), [])


## The placeholder sound of faction `id` for `event` (null if it's missing).
static func voice_stream(id: StringName, event: StringName) -> AudioStream:
	var file := voice_path(id, event)
	return load(file) as AudioStream if ResourceLoader.exists(file) else null


static func voice_path(id: StringName, event: StringName) -> String:
	return "%s%s_%s.wav" % [VOICE_DIR, entry(id).get("voice", {}).get("id", String(id)), event]


## Playback pitch of faction `id`'s voice (1: as recorded).
static func voice_pitch(id: StringName) -> float:
	return float(entry(id).get("voice", {}).get("pitch", 1.0))


## A new character's kit for faction `id` (&"": the first faction's): the gun loaded with its round,
## the armor, the secure container, and the pockets.
static func starter_kit(id: StringName) -> Inventory:
	var starter: Dictionary = entry(_or_first(id)).get("starter", {})
	var inventory := Inventory.new()
	var equipment: Dictionary = starter.get("equipment", {})
	for slot: String in equipment:
		var spec: Dictionary = equipment[slot]
		var item_id := str(spec.get("id", ""))
		if not ItemDB.has_item(item_id):
			continue
		var data := ItemDB.get_item(item_id)
		var item := Inventory.loaded_gun(item_id, str(spec.get("ammo", ""))) if data.weapon else ItemInstance.create(item_id)
		inventory.equip(slot, item)
	var pockets: Array = starter.get("pockets", [])
	for i in pockets.size():
		var item := ItemInstance.create(str(pockets[i].get("id", "")), int(pockets[i].get("count", 1)))
		if item and not inventory.pockets.place(item, Vector2i(i, 0), false):
			inventory.pockets.add(item)
	return inventory


## What a new character of faction `id` has in the stash (InventoryGrid.load_array() entries).
static func starter_stash(id: StringName) -> Array:
	return entry(_or_first(id)).get("starter", {}).get("stash", []).duplicate(true)


## The faction's starting gear in a few words, for the faction picker: "AK-74N, Module-3M body armor".
static func kit_summary(id: StringName) -> String:
	var names: Array[String] = []
	var equipment: Dictionary = entry(id).get("starter", {}).get("equipment", {})
	for slot in ["primary", "secondary", "pistol", "armor", "helmet"]:
		var item_id := str(equipment.get(slot, {}).get("id", ""))
		if ItemDB.has_item(item_id):
			names.append(ItemDB.get_item(item_id).display_name)
	return ", ".join(names)


## The BotKit AI PMCs of faction `id` carry (&"": the first faction's).
static func ai_kit(id: StringName) -> BotKit:
	var file := str(entry(_or_first(id)).get("ai_kit", ""))
	return load(file) as BotKit if ResourceLoader.exists(file) else null


## How AI PMC squads form and keep together: size_weights, spacing, wedge_degrees, tolerance, catch_up,
## spawn_spacing.
static func squad_config() -> Dictionary:
	return data().get("squads", {})


## A squad size (1-3) rolled by the size weights.
static func roll_squad_size(rng: RandomNumberGenerator) -> int:
	var sizes: Dictionary = squad_config().get("size_weights", {"1": 1.0})
	var keys := sizes.keys()
	var weights := PackedFloat32Array()
	for key in keys:
		weights.append(float(sizes[key]))
	var index := LootTable._pick(rng, weights)
	return int(keys[index]) if index >= 0 else 1


## How PMCs of one faction hold back from each other: reaction_multiplier, hold_fire_beyond,
## aimed_at_degrees.
static func same_faction() -> Dictionary:
	return data().get("same_faction", {})


## How voice lines are heard and how often: hearing_radius, noise_radius, speaker_cooldown,
## event_cooldowns, pitch_jitter, subtitle_seconds.
static func voice_config() -> Dictionary:
	return data().get("voice", {})


## What's wrong with factions.json: missing fields, colours that aren't colours, a body colour too
## close to another faction's or to a Scav's, boss's or guard's, an accent too close to its own body or to
## another faction's accent, an event without 2-3 lines or a sound, a starter kit with unknown items, a
## gun loaded with the wrong round or stash items that don't fit, an AI kit that isn't a BotKit, squad
## sizes outside 1-3, hesitation or voice values out of range. Empty if it's fine.
static func problems() -> Array[String]:
	var found: Array[String] = []
	var factions: Dictionary = data().get("factions", {})
	if factions.size() < 2:
		found.append("%s: fewer than two factions" % PATH)
	var others := {}
	for kind in ["Scav", "boss", "guard"]:
		others[kind] = (load("res://data/bots/%s.tres" % kind.to_lower()) as BotProfile).body_color
	var bodies: Array[Color] = []
	var accents: Array[Color] = []
	for key: String in factions:
		var id := StringName(key)
		var faction: Dictionary = factions[key]
		var where := "faction %s" % key
		for field in FIELDS:
			if not faction.has(field):
				found.append("%s: no %s" % [where, field])
		var look: Dictionary = faction.get("look", {})
		for part in ["body", "accent"]:
			if not _is_color(look.get(part)):
				found.append("%s: look.%s isn't [r, g, b]" % [where, part])
		if _is_color(look.get("body")):
			var body := body_color(id)
			for kind: String in others:
				if _distance(body, others[kind]) < 0.15:
					found.append("%s: its body colour is too close to a %s's" % [where, kind])
			for other in bodies:
				if _distance(body, other) < 0.15:
					found.append("%s: its body colour is too close to another faction's" % where)
			bodies.append(body)
		if _is_color(look.get("accent")):
			var accent := accent_color(id)
			if _is_color(look.get("body")) and _distance(accent, body_color(id)) < 0.3:
				found.append("%s: its accent is too close to its body colour" % where)
			for other in accents:
				if _distance(accent, other) < 0.3:
					found.append("%s: its accent is too close to another faction's" % where)
			accents.append(accent)
		var voice: Dictionary = faction.get("voice", {})
		for event in EVENTS:
			var options: Array = voice.get("lines", {}).get(String(event), [])
			if options.size() < 2 or options.size() > 3:
				found.append("%s: %d voice lines for %s (2-3)" % [where, options.size(), event])
			for line: Variant in options:
				if not line is Dictionary or str(line.get("text", "")) == "":
					found.append("%s: a %s line has no text" % [where, event])
			if not ResourceLoader.exists(voice_path(id, event)):
				found.append("%s: no sound %s" % [where, voice_path(id, event)])
		found.append_array(_starter_problems(where, faction.get("starter", {})))
		var kit_path := str(faction.get("ai_kit", ""))
		if not ResourceLoader.exists(kit_path) or not load(kit_path) is BotKit:
			found.append("%s: ai_kit %s isn't a BotKit" % [where, kit_path])
	var sizes: Dictionary = squad_config().get("size_weights", {})
	if sizes.is_empty():
		found.append("squads: no size_weights")
	for size: String in sizes:
		if int(size) < 1 or int(size) > 3 or float(sizes[size]) < 0.0:
			found.append("squads: size %s (weight %s) isn't 1-3 with a weight of 0 or more" % [size, sizes[size]])
	for key in ["spacing", "tolerance", "catch_up", "spawn_spacing"]:
		if float(squad_config().get(key, 0.0)) <= 0.0:
			found.append("squads: %s must be above 0" % key)
	var hold := same_faction()
	if float(hold.get("reaction_multiplier", 0.0)) < 1.0:
		found.append("same_faction: reaction_multiplier below 1")
	if float(hold.get("hold_fire_beyond", -1.0)) < 0.0 or float(hold.get("aimed_at_degrees", 0.0)) <= 0.0:
		found.append("same_faction: hold_fire_beyond or aimed_at_degrees missing")
	var voice_tuning := voice_config()
	for key in ["hearing_radius", "noise_radius", "speaker_cooldown", "subtitle_seconds"]:
		if float(voice_tuning.get(key, 0.0)) <= 0.0:
			found.append("voice: %s must be above 0" % key)
	for event in EVENTS:
		if float(voice_tuning.get("event_cooldowns", {}).get(String(event), 0.0)) <= 0.0:
			found.append("voice: no cooldown for %s" % event)
	return found


static func _starter_problems(where: String, starter: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var equipment: Dictionary = starter.get("equipment", {})
	if not equipment.has("primary") or not equipment.has("armor"):
		found.append("%s: the starter kit needs a primary weapon and armor" % where)
	var probe := Inventory.new()
	for slot: String in equipment:
		var item_id := str(equipment[slot].get("id", ""))
		if not ItemDB.has_item(item_id):
			found.append("%s: starter %s: no item %s" % [where, slot, item_id])
			continue
		var data := ItemDB.get_item(item_id)
		if not probe.equip(slot, ItemInstance.create(item_id)):
			found.append("%s: starter %s can't take %s" % [where, slot, item_id])
		if data.weapon:
			var ammo := str(equipment[slot].get("ammo", ""))
			if not ItemDB.has_item(ammo) or str(ItemDB.get_item(ammo).stats.get("caliber", "")) != data.weapon.caliber:
				found.append("%s: starter %s doesn't fire %s" % [where, item_id, ammo])
	for entry_list in [starter.get("pockets", []), starter.get("stash", [])]:
		for item: Variant in entry_list:
			if not item is Dictionary or not ItemDB.has_item(str(item.get("id", ""))):
				found.append("%s: starter item %s doesn't exist" % [where, item])
	var stash := InventoryGrid.new((load("res://data/config/inventory.tres") as InventoryConfig).stash_size, &"stash")
	for item: Variant in starter.get("stash", []):
		if item is Dictionary and ItemDB.has_item(str(item.get("id", ""))):
			var instance := ItemInstance.from_dict(item)
			if instance and not stash.place(instance, instance.cell, instance.rotated):
				found.append("%s: starter stash item %s doesn't fit at %d, %d" % [where, item.id, instance.cell.x, instance.cell.y])
	return found


static func _or_first(id: StringName) -> StringName:
	if has(id):
		return id
	var all := ids()
	return all[0] if not all.is_empty() else &""


static func _is_color(value: Variant) -> bool:
	return value is Array and value.size() >= 3 and value.all(func(part: Variant) -> bool: return (part is float or part is int) and float(part) >= 0.0 and float(part) <= 1.0)


static func _color(value: Variant, fallback: Color) -> Color:
	return Color(float(value[0]), float(value[1]), float(value[2])) if _is_color(value) else fallback


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


static func _material(color: Color, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if glow:
		# The accent stays readable in the dusk and the dark: it lights itself a little.
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.35
	return material
