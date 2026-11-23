class_name QuestRaid
extends RefCounted
## Quest progress during one raid (DESIGN.md §11), held by the RaidController: kills, visits and
## placements count toward active objectives the moment they happen and stay if you die; an objective
## with "survive": true keeps this raid's progress in `pending` until the raid settles, and only a
## SURVIVED raid (not a Run Through, not killed or missing) adds it. Extract and extract_with objectives
## count when you extract. Only PMC raids that go to the profile count (`counts`): Scav runs and Shooting
## Range practice count nothing. `progressed` is the HUD's toast. The open daily and weekly tasks
## (Operations) count the same way as the active quests (QuestLog.tracking()).

## An objective moved: `text` the toast ("Kill Scavs: 3 / 5", "Objective complete: ..."), `done` once
## it's complete.
signal progressed(text: String, done: bool)

## The map the raid is on (objectives for another map don't count), and whether anything counts.
var map_id := ""
var counts := true
## True for a count with no map (QuestLog.record_trick_kills()): every map's objectives count.
var any_map := false
## Survive-only progress waiting for the extract: {quest id: {objective index: amount}}.
var pending := {}
## Everything that moved this raid, pending or not: {quest id: {objective index: amount}} (the summary).
var made := {}
## Locations reached this raid ("map/poi" or "map/spot" keys).
var reached := {}


func _init(raid_map: String, counting: bool) -> void:
	map_id = raid_map
	counts = counting


## Objective `index`'s progress including this raid's pending part.
func progress(quest: Dictionary, index: int) -> int:
	return mini(QuestLog.progress(quest, index) + pending_of(quest, index), QuestLog.objective_count(quest, index))


func pending_of(quest: Dictionary, index: int) -> int:
	return int(pending.get(quest.id, {}).get(index, 0))


func _map_for(entry: Dictionary) -> String:
	return str(entry.get("map", map_id)) if any_map else map_id


## A kill by the player: {"side", "faction", "role", "boss", "weapon", "weapon_class", "part",
## "distance", "trick"} (QuestLog.kill_fits()). Counts for every active objective it fits.
func on_kill(kill: Dictionary) -> void:
	if not counts:
		return
	for quest in QuestLog.tracking():
		for i in quest.objectives.size():
			if QuestLog.kill_fits(quest.objectives[i], kill, _map_for(quest.objectives[i])):
				count(quest, i, 1)


## Adds `amount` to objective `index` of `quest` (pending if it's survive-only) and announces it.
## Returns how much it moved.
func count(quest: Dictionary, index: int, amount: int) -> int:
	amount = mini(amount, QuestLog.objective_count(quest, index) - progress(quest, index))
	if amount <= 0 or not counts:
		return 0
	if bool(quest.objectives[index].get("survive", false)):
		if not pending.has(quest.id):
			pending[quest.id] = {}
		pending[quest.id][index] = pending_of(quest, index) + amount
	else:
		QuestLog.add_progress(quest, index, amount)
	if not made.has(quest.id):
		made[quest.id] = {}
	made[quest.id][index] = int(made[quest.id].get(index, 0)) + amount
	var done := progress(quest, index) >= QuestLog.objective_count(quest, index)
	progressed.emit(toast_text(quest, index), done)
	return amount


## "Kill Scavs on Test Yard: 3 / 5", "Objective complete: Reach Signal hut", with " (extract to keep
## it)" on survive-only progress.
func toast_text(quest: Dictionary, index: int) -> String:
	var text := QuestLog.objective_text(quest, index)
	var count_text := QuestLog.objective_count(quest, index)
	var line := "Objective complete: %s" % text if progress(quest, index) >= count_text else "%s: %d / %d" % [text, progress(quest, index), count_text]
	if quest.has("operation"):
		line = "%s: %s" % [Operations.kind_name(str(quest.operation)), line]
	if pending_of(quest, index) > 0:
		line += " (extract to keep it)"
	return line


## The player searched a container to its last item (InventoryScreen): one toward every open search
## objective for this map or any.
func on_search() -> void:
	if not counts:
		return
	for quest in QuestLog.tracking():
		for i in quest.objectives.size():
			if QuestLog.objective_type(quest, i) == "search" and str(quest.objectives[i].get("map", map_id)) == _map_for(quest.objectives[i]):
				count(quest, i, 1)


## The world position and radius of a location objective's place on this map: {"position": Vector3,
## "radius"} ({} if it isn't on this map or can't be found in `tree`).
func place_of(quest: Dictionary, index: int, tree: SceneTree) -> Dictionary:
	var where := QuestLog.location(quest, index)
	if where.is_empty() or str(where.map) != map_id:
		return {}
	if where.has("spot"):
		var entry := QuestLog.spot(map_id, str(where.spot))
		var at: Array = entry.get("position", [0, 0, 0])
		return {"position": Vector3(float(at[0]), float(at[1]), float(at[2])), "radius": float(entry.get("radius", 2.0))}
	if tree:
		for node in tree.get_nodes_in_group("pois"):
			if node is PointOfInterest and node.poi_id == str(where.poi) and node.map_id == map_id:
				return {"position": node.global_position, "radius": maxf(node.size.x, node.size.z) * 0.5, "poi": node}
	return {}


## True when `point` is inside objective `index`'s location.
func is_at(quest: Dictionary, index: int, point: Vector3, tree: SceneTree) -> bool:
	var place := place_of(quest, index, tree)
	if place.is_empty():
		return false
	if place.has("poi"):
		return (place.poi as PointOfInterest).contains(point)
	var offset: Vector3 = point - place.position
	return Vector2(offset.x, offset.z).length() <= float(place.radius)


## The player is at `point`: visit objectives whose location it's in count (once a raid).
func on_position(point: Vector3, tree: SceneTree) -> void:
	if not counts:
		return
	for quest in QuestLog.tracking():
		for i in quest.objectives.size():
			if QuestLog.objective_type(quest, i) != "visit" or progress(quest, i) >= 1:
				continue
			if is_at(quest, i, point, tree):
				count(quest, i, 1)


## The active place and mark objectives on this map still to do: [[quest, index], ...].
func placements() -> Array:
	var result := []
	for quest in QuestLog.tracking():
		for i in quest.objectives.size():
			if QuestLog.objective_type(quest, i) in ["place", "mark"] and str(quest.objectives[i].get("map", "")) == map_id \
					and progress(quest, i) < QuestLog.objective_count(quest, i):
				result.append([quest, i])
	return result


## Every active location objective on this map (the map overlay and the HUD tracker): [{"quest",
## "index", "type", "name", "position", "radius", "done"}].
func locations(tree: SceneTree) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest in QuestLog.tracking(true):
		for i in quest.objectives.size():
			var place := place_of(quest, i, tree)
			if place.is_empty():
				continue
			result.append({"quest": quest, "index": i, "type": QuestLog.objective_type(quest, i), "name": QuestLog.location(quest, i).name,
				"position": place.position, "radius": place.radius, "done": progress(quest, i) >= QuestLog.objective_count(quest, i)})
	return result


## Places one of objective `index`'s item from `inventory` (it leaves the inventory). "" on success, else
## why not.
func place(quest: Dictionary, index: int, inventory: Inventory) -> String:
	if not counts:
		return "Quests don't count in this raid"
	if progress(quest, index) >= QuestLog.objective_count(quest, index):
		return "Already done"
	var item_id := QuestLog.place_item(quest, index)
	if inventory == null or inventory.take(item_id, 1) < 1:
		return "You need %s" % ExtractTable.item_name(item_id)
	count(quest, index, 1)
	return ""


## The raid is over: when `survived` (SURVIVED, not a Run Through), the pending survive-only progress is
## added, and extract objectives (on this map, through `extract_id` if they name one) and extract_with
## objectives (the matching items in `inventory`) count. Otherwise the pending progress is lost.
func settle(survived: bool, extract_id: String, inventory: Inventory) -> void:
	if not counts:
		return
	var waiting := pending
	pending = {}
	if not survived:
		for quest_id: String in waiting:
			for index: int in waiting[quest_id]:
				made[quest_id][index] = int(made[quest_id][index]) - int(waiting[quest_id][index])
		return
	for quest_id: String in waiting:
		var quest := QuestLog.find(quest_id)
		if quest.is_empty():
			continue  # Gone (a task from a set that has since reset).
		for index: int in waiting[quest_id]:
			QuestLog.add_progress(quest, index, int(waiting[quest_id][index]))
	for quest in QuestLog.tracking():
		for i in quest.objectives.size():
			var entry: Dictionary = quest.objectives[i]
			if str(entry.get("map", map_id)) != map_id and not any_map:
				continue
			var type := QuestLog.objective_type(quest, i)
			if type == "extract" and str(entry.get("extract", extract_id)) == extract_id:
				count(quest, i, 1)
			elif type == "extract_with" and inventory:
				var carried := 0
				for item in inventory.all_items():
					if item.data.id == str(entry.get("item", "")) and (item.fir or not bool(entry.get("fir", false))):
						carried += item.count
				if carried > 0:
					count(quest, i, carried)


## The raid summary's quest lines: "Scav Sweep: Kill Scavs on Test Yard +2 (3 / 5)", one per objective
## that moved (survive-only progress lost by dying says so).
func summary_lines() -> Array[String]:
	var lines: Array[String] = []
	for quest_id: String in made:
		var quest := QuestLog.find(quest_id)
		if quest.is_empty():
			continue  # Gone (a task from a set that has since reset).
		for index: int in made[quest_id]:
			var amount := int(made[quest_id][index])
			var line := "%s: %s" % [QuestLog.title(quest), QuestLog.objective_text(quest, index)]
			if amount > 0:
				lines.append("%s +%d (%d / %d)" % [line, amount, QuestLog.progress(quest, index), QuestLog.objective_count(quest, index)])
			else:
				lines.append("%s: progress lost (needs an extract)" % line)
	return lines
