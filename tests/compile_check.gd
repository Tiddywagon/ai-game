extends SceneTree
## Loads every script and scene of the project and reports the ones that don't compile or load.
## Run: godot --headless --path . -s tests/compile_check.gd (after one `--headless --editor --quit`
## scan when class_name scripts were added or renamed). Exits 1 if anything is broken.

const SKIP_DIRS := ["res://.godot", "res://tests", "res://android", "res://build", "res://export"]


func _initialize() -> void:
	var broken := 0
	for path: String in _files("res://"):
		if path.get_file().begins_with("_"):
			continue  # Temporary test copies in the project root.
		var resource: Resource = load(path)
		var ok := resource != null
		if ok and resource is GDScript:
			ok = (resource as GDScript).can_instantiate() or (resource as GDScript).is_abstract()
		if not ok:
			broken += 1
			print("BROKEN: ", path)
	print("compile check: %d broken" % broken)
	quit(1 if broken > 0 else 0)


func _files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for name: String in dir.get_directories():
		var sub := dir_path.path_join(name)
		if not SKIP_DIRS.has(sub) and not name.begins_with("."):
			found.append_array(_files(sub))
	for name: String in dir.get_files():
		if name.ends_with(".gd") or name.ends_with(".tscn"):
			found.append(dir_path.path_join(name))
	return found
