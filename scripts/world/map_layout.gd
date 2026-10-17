class_name MapLayout
extends RefCounted
## The layout of a raid map for the map item (DESIGN.md §5, MapOverlay), read from a map scene: the
## live level in a raid, or an instance of the map's scene out of raid (nothing in it runs). Walls and
## obstacles (CoverBox footprints; low ones marked), raised floors (FloorSlab) and Stairs, Doors (and
## which are locked), MapLabels, high-value LootZones, points of interest (PointOfInterest), ScavZones and
## ExtractZones. Positions are on the ground plane (x, z).

## {"points": PackedVector2Array, "low": bool, "material": int}
var walls: Array = []
## PackedVector2Array footprints.
var floors: Array = []
var stairs: Array = []
## {"from": Vector2, "to": Vector2, "locked": bool, "name": String}
var doors: Array = []
## {"at": Vector2, "text": String, "landmark": bool}
var labels: Array = []
## High-value loot: {"points": PackedVector2Array, "name": String}
var loot_zones: Array = []
## Points of interest: {"points": PackedVector2Array, "id", "name", "tier", "hidden", "requirement"}.
var pois: Array = []
## {"at": Vector2, "radius": float, "name": String}
var scav_zones: Array = []
## {"at": Vector2, "radius": float, "name": String, "type": "always", "random" or "conditional",
## "kind": String (ExtractZone.kind_text()), "sides": "Both", "PMC" or "Scav", "zone": the ExtractZone
## in a live level (null when read from a scene)}. Quest extracts you haven't unlocked aren't listed.
var extracts: Array = []
var bounds := Rect2()

## The map read out of raid: extracts take their rules from data/config/extracts.json for it.
var _map_id := ""


## Reads the layout of the map under `root` (in the tree or not). Out of raid, `map_id` says which map
## it is, for its extracts' rules.
static func from_level(root: Node, map_id := "") -> MapLayout:
	var layout := MapLayout.new()
	layout._map_id = map_id
	layout._read(root, root)
	var first := true
	for wall: Dictionary in layout.walls:
		for point: Vector2 in wall.points:
			if first:
				layout.bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				layout.bounds = layout.bounds.expand(point)
	return layout


func _read(node: Node, root: Node) -> void:
	if node is CoverBox:
		walls.append({"points": BoxFootprint.corners(_xform(node, root), node.size), "low": node.size.y < 1.3,
			"material": node.cover_material})
	elif node is FloorSlab:
		floors.append(BoxFootprint.corners(_xform(node, root), node.size))
	elif node is Stairs:
		stairs.append(BoxFootprint.corners(_xform(node, root), node.size))
	elif node is Door:
		var xform := _xform(node, root)
		var half: Vector3 = xform.basis.x.normalized() * float(node.width) / 2.0
		doors.append({"from": _flat(xform.origin - half), "to": _flat(xform.origin + half), "locked": node.locked, "name": node.door_name})
	elif node is MapLabel:
		labels.append({"at": _flat(_xform(node, root).origin), "text": node.text, "landmark": node.landmark})
	elif node is LootZone:
		loot_zones.append({"points": BoxFootprint.corners(_xform(node, root), node.size), "name": node.zone_name})
	elif node is PointOfInterest:
		var entry: Dictionary = node.entry()
		pois.append({"points": BoxFootprint.corners(_xform(node, root), node.size), "id": node.poi_id, "name": node.poi_name(),
			"tier": node.tier(), "hidden": node.is_hidden(), "requirement": PoiTable.requirement_text(entry)})
		return  # Its event spots aren't on the map.
	elif node is ScavZone:
		var points := PackedVector2Array()
		for child in node.get_children():
			if child is Marker3D:
				points.append(_flat(_xform(child, root).origin))
		if not points.is_empty():
			var centre := Vector2.ZERO
			for point in points:
				centre += point
			centre /= points.size()
			var radius := 2.0
			for point in points:
				radius = maxf(radius, centre.distance_to(point) + 1.5)
			scav_zones.append({"at": centre, "radius": radius, "name": node.zone_name})
		return  # Not the Scavs spawned in it.
	elif node is ExtractZone:
		var live: bool = node.is_inside_tree()
		if not live and _map_id != "":
			node.configure_for_map(_map_id)
		if (node.available if live else node.quest == "" or GameState.quests.get(node.quest, {}).get("state", "") == "completed"):
			extracts.append({"at": _flat(_xform(node, root).origin), "radius": node.radius, "name": node.extract_name,
				"type": node.kind, "kind": node.kind_text(), "sides": node.sides, "zone": node if live else null})
	elif node is Actor or node is CanvasLayer:
		return
	for child in node.get_children():
		_read(child, root)


## `node`'s transform in the level: its global transform in the tree, else its local ones composed up
## to `root`.
static func _xform(node: Node, root: Node) -> Transform3D:
	if node is Node3D and node.is_inside_tree():
		return node.global_transform
	var xform := Transform3D.IDENTITY
	var current := node
	while current and current != root:
		if current is Node3D:
			xform = current.transform * xform
		current = current.get_parent()
	return xform


static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
