class_name WeaponMods
extends RefCounted
## The mod tree on a gun (DESIGN.md §12.1). A gun's WeaponData lists its slots; a mod (an attachment
## item with a "mod" stat) can bring slots of its own, e.g. a rail handguard adds a foregrip and a
## tactical slot. Installed mods live in ItemInstance.mods by slot id, each with its own `mods`, so
## taking a handguard off takes its foregrip with it.
##
## A mod's "mod" stat: {"kind": one of KINDS, "fits": [platforms] (leave out to fit any gun with a slot
## for its kind: rails, sights), "slots": [slot definitions], "modifiers": {...} (see WeaponStats),
## "capacity": rounds (magazines)}. Slot definitions: {"id", "name", "kinds": [...], "empty": {modifiers
## while nothing is in it}, "required": true if the gun can't fire without it}.
##
## A slot path names a slot in the tree: "handguard" on the gun, "handguard/foregrip" on the handguard.

const KINDS: Array[String] = ["muzzle", "barrel", "handguard", "foregrip", "stock", "pistol_grip", "receiver",
	"sight", "tactical", "magazine"]
const KIND_NAMES := {"muzzle": "Muzzle device", "barrel": "Barrel", "handguard": "Handguard", "foregrip": "Foregrip",
	"stock": "Stock", "pistol_grip": "Pistol grip", "receiver": "Receiver", "sight": "Sight",
	"tactical": "Tactical device", "magazine": "Magazine"}


## The "mod" stat of `data`, or {} if it isn't a weapon mod.
static func info(data: ItemData) -> Dictionary:
	if data == null:
		return {}
	var mod: Variant = data.stats.get("mod")
	return mod if mod is Dictionary else {}


static func is_mod(data: ItemData) -> bool:
	return not info(data).is_empty()


static func kind_of(data: ItemData) -> String:
	return str(info(data).get("kind", ""))


## Rounds a magazine mod holds (0 for anything else).
static func capacity_of(data: ItemData) -> int:
	return int(info(data).get("capacity", 0))


## The slot definitions on `item`: a gun's from its WeaponData, a mod's from its "mod" stat.
static func slots_of(item: ItemInstance) -> Array:
	if item.data.weapon:
		return item.data.weapon.slots
	return info(item.data).get("slots", [])


## True if mod item `mod` can go in `slot` on a gun of `platform`.
static func fits(platform: String, slot: Dictionary, mod: ItemData) -> bool:
	var mod_info := info(mod)
	if mod_info.is_empty() or str(mod_info.get("kind", "")) not in slot.get("kinds", []):
		return false
	var platforms: Array = mod_info.get("fits", [])
	return platforms.is_empty() or platform in platforms


static func platform_of(gun: ItemInstance) -> String:
	return gun.data.weapon.platform if gun.data.weapon else ""


## Every slot in `gun`'s tree, in order (each slot followed by the slots of what's in it): [{"path",
## "slot": its definition, "mod": the ItemInstance in it or null, "holder": the gun or mod it's on,
## "depth": 0 on the gun, 1 on a mod, ...}].
static func walk(gun: ItemInstance) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_walk(gun, "", 0, result)
	return result


static func _walk(holder: ItemInstance, prefix: String, depth: int, result: Array[Dictionary]) -> void:
	for slot: Dictionary in slots_of(holder):
		var path := prefix + str(slot.id)
		var mod: ItemInstance = holder.mods.get(str(slot.id))
		result.append({"path": path, "slot": slot, "mod": mod, "holder": holder, "depth": depth})
		if mod:
			_walk(mod, path + "/", depth + 1, result)


## Every mod on `gun`, at any depth.
static func installed(gun: ItemInstance) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for entry in walk(gun):
		if entry.mod:
			result.append(entry.mod)
	return result


## The gun or mod that has the slot at `path`, or null if there's no such slot right now.
static func holder_at(gun: ItemInstance, path: String) -> ItemInstance:
	var parts := path.split("/")
	var holder := gun
	for i in parts.size() - 1:
		holder = holder.mods.get(parts[i])
		if holder == null:
			return null
	return holder if not slot_on(holder, parts[-1]).is_empty() else null


## The definition of slot `id` on `holder`, or {}.
static func slot_on(holder: ItemInstance, id: String) -> Dictionary:
	for slot: Dictionary in slots_of(holder):
		if str(slot.id) == id:
			return slot
	return {}


static func slot_at(gun: ItemInstance, path: String) -> Dictionary:
	var holder := holder_at(gun, path)
	return slot_on(holder, path.get_file()) if holder else {}


## The mod in the slot at `path`, or null.
static func mod_at(gun: ItemInstance, path: String) -> ItemInstance:
	var holder := holder_at(gun, path)
	return holder.mods.get(path.get_file()) if holder else null


## Why `mod` can't go in the slot at `path` on `gun`, or "" if it can (replacing what's there).
static func install_block_reason(gun: ItemInstance, path: String, mod: ItemInstance) -> String:
	if mod == null or not is_mod(mod.data):
		return "Not a weapon part"
	if mod == gun or mod in installed(gun):
		return "Already on the gun"
	var slot := slot_at(gun, path)
	if slot.is_empty():
		return "No such slot"
	if not fits(platform_of(gun), slot, mod.data):
		return "Doesn't fit the %s slot" % str(slot.get("name", path)).to_lower()
	return ""


## Puts `mod` in the slot at `path` (the caller has taken it out of wherever it was). Returns the mod
## it replaced, or null. Does nothing (returns null) if it doesn't fit: check install_block_reason().
static func install(gun: ItemInstance, path: String, mod: ItemInstance) -> ItemInstance:
	if install_block_reason(gun, path, mod) != "":
		return null
	var holder := holder_at(gun, path)
	var replaced: ItemInstance = holder.mods.get(path.get_file())
	holder.mods[path.get_file()] = mod
	return replaced


## Takes the mod (with whatever is on it) out of the slot at `path`. Returns it, or null if empty.
static func uninstall(gun: ItemInstance, path: String) -> ItemInstance:
	var holder := holder_at(gun, path)
	if holder == null:
		return null
	var mod: ItemInstance = holder.mods.get(path.get_file())
	holder.mods.erase(path.get_file())
	return mod


## The path of the first empty slot on `gun` that `mod` fits, else (unless `empty_only`) the first
## full one, else "".
static func slot_for(gun: ItemInstance, mod: ItemInstance, empty_only := false) -> String:
	var occupied := ""
	for entry in walk(gun):
		if install_block_reason(gun, entry.path, mod) != "":
			continue
		if entry.mod == null:
			return entry.path
		if occupied == "":
			occupied = entry.path
	return "" if empty_only else occupied


## Every path on `gun` that `mod` could go in.
static func compatible_paths(gun: ItemInstance, mod: ItemInstance) -> Array[String]:
	var result: Array[String] = []
	for entry in walk(gun):
		if install_block_reason(gun, entry.path, mod) == "":
			result.append(entry.path)
	return result


## Fits the parts `gun` comes with (WeaponData.default_mods), parents before children.
static func install_defaults(gun: ItemInstance) -> void:
	if gun.data.weapon == null:
		return
	var paths: Array = gun.data.weapon.default_mods.keys()
	paths.sort_custom(func(a: String, b: String) -> bool: return a.count("/") < b.count("/"))
	for path: String in paths:
		var mod := ItemInstance.create(str(gun.data.weapon.default_mods[path]))
		if mod == null:
			continue
		if install_block_reason(gun, path, mod) == "":
			install(gun, path, mod)
		else:
			push_warning("WeaponMods: %s's default %s doesn't fit slot %s" % [gun.data.id, mod.data.id, path])


## Rounds `gun` holds with its magazine (0 with its magazine slot empty).
static func capacity(gun: ItemInstance) -> int:
	if gun.data.weapon == null:
		return 0
	if slot_on(gun, "magazine").is_empty():
		return gun.data.weapon.magazine_size
	var magazine := mod_at(gun, "magazine")
	return capacity_of(magazine.data) if magazine else 0


## The name of a required slot that's empty, or "" if the gun has everything it needs to fire.
static func missing_part(gun: ItemInstance) -> String:
	for entry in walk(gun):
		if entry.mod == null and entry.slot.get("required", false):
			return str(entry.slot.get("name", entry.path))
	return ""
