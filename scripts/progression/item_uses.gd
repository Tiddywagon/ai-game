class_name ItemUses
extends RefCounted
## What an item is needed for (DESIGN.md §6.5): the quests, hideout upgrades, trader barters
## (BarterTable: each named with everything it gives), hideout crafts and gear upgrades that take it.
## Examining an item shows a "Needed for" line with the full list as its tooltip, and the hover text in
## the inventory sums it up. Quests already completed and hideout levels already built drop out;
## barters, crafts and gear upgrades can be done again, so they stay. A barter you can't see or make yet
## says why: the loyalty level it needs while yours is lower ("Bulat LL4 → ..."), the quest it waits for
## ("(after Safekeeping)") and a trader who doesn't trade with you yet ("(locked)").

## Kinds of use, in the order they're listed, with their names (one, many).
const KINDS := {
	"quest": ["quest", "quests"],
	"upgrade": ["hideout upgrade", "hideout upgrades"],
	"barter": ["barter", "barters"],
	"craft": ["craft", "crafts"],
	"gear": ["gear upgrade", "gear upgrades"],
}
## marker(): nothing uses the item, only things that can be done again use it (crafts, barters, gear
## upgrades), or a hideout level or a quest still needs some.
enum Marker { NONE, USED, NEEDED }
## Gear upgrade groups (data/config/gear_upgrades.json) by what they upgrade.
const GEAR_GROUPS := {"armor": "Armor", "carry": "Rigs and backpacks", "electronics": "Headsets"}


## Every use of item `id`: [{"kind" (a KINDS key), "name" (what it's for), "count", "fir" (only
## found-in-raid items count)}], in KINDS order.
static func of(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest in QuestLog.shown():
		if QuestLog.state(quest) == "completed":
			continue
		for objective: Dictionary in quest.get("objectives", []):
			if objective.get("type", "") == "hand_in" and objective.get("item", "") == id:
				result.append(_use("quest", "%s (%s)" % [quest.name, TraderTable.display_name(str(quest.get("trader", "")))], objective))
	for station in Hideout.stations():
		for entry: Dictionary in station.levels:
			if int(entry.level) <= Hideout.level(station):
				continue
			for requirement: Dictionary in entry.get("requires", []):
				if requirement.get("item", "") == id:
					result.append(_use("upgrade", "%s level %d" % [station.name, int(entry.level)], requirement))
	for barter in BarterTable.all():
		if not BarterTable.visible(barter):
			continue
		for give: Variant in barter.get("requires", []):
			if give is Dictionary and give.get("item", "") == id:
				result.append(_use("barter", barter_text(barter), give))
	for station in Hideout.stations():
		for entry: Dictionary in station.levels:
			for recipe: Dictionary in entry.get("crafts", []):
				for input: Dictionary in recipe.get("inputs", []):
					if input.get("item", "") == id:
						result.append(_use("craft", "%s → %s" % [station.name, _output_text(recipe.get("output", {}))], input))
	var gear: Dictionary = GearUpgrades.config().get("items", {})
	for group: String in gear:
		var levels: Array = gear[group]
		var counts := []
		var fir := false
		for level in levels.size():
			for cost: Dictionary in levels[level]:
				if cost.get("item", "") == id:
					counts.append("+%d ×%d" % [level, int(cost.get("count", 1))])
					fir = fir or bool(cost.get("fir", false))
		if not counts.is_empty():
			result.append({"kind": "gear", "name": "%s: %s" % [GEAR_GROUPS.get(group, group.capitalize()), ", ".join(counts)], "count": 0, "fir": fir})
	for source: String in GearUpgrades.sources():
		for cost: Dictionary in GearUpgrades.config().sources[source].get("extra_items", []):
			if cost.get("item", "") == id:
				result.append(_use("gear", "Every upgrade at the %s" % GearUpgrades.source_name(source), cost))
	return result


## "Bulat LL4 → Anvil PK, 7.62x54R SNB ×40 (after Safekeeping)": the trader, the loyalty level while
## yours is below it, everything `barter` gives, the quest it waits for and "(locked)" for a trader who
## doesn't trade with you yet.
static func barter_text(barter: Dictionary) -> String:
	var trader := str(barter.get("trader", ""))
	var level := BarterTable.level(barter)
	var short := Trading.loyalty_block_reason(trader, barter) != ""
	var waits := "" if BarterTable.quest_done(barter) else " (after %s)" % str(QuestLog.find(BarterTable.quest(barter)).get("name", BarterTable.quest(barter)))
	return "%s%s → %s%s%s" % [TraderTable.display_name(trader), " LL%d" % level if short else "", BarterTable.reward_text(barter), waits,
		TraderTable.locked_suffix(trader)]


## "2 quests, 3 barters, 1 hideout upgrade", or "" if nothing needs it.
static func summary(id: String) -> String:
	var counts := {}
	for use in of(id):
		counts[use.kind] = int(counts.get(use.kind, 0)) + 1
	var parts := []
	for kind: String in KINDS:
		if counts.has(kind):
			parts.append("%d %s" % [counts[kind], KINDS[kind][0 if counts[kind] == 1 else 1]])
	return ", ".join(parts)


## Every use, one a line under a heading per kind, for the examine tooltip:
## "Quests\n  Scrap Run (Bulat) — 3 needed, found in raid\nBarters\n  Doc Vera → CMS surgical kit — 1 needed".
static func tooltip(id: String) -> String:
	var lines := []
	var kind := ""
	for use in of(id):
		if use.kind != kind:
			kind = use.kind
			var heading: String = KINDS[kind][1]
			lines.append(heading.left(1).to_upper() + heading.substr(1))
		var needs := []
		if use.count > 0:
			needs.append("%d needed" % use.count)
		if use.fir:
			needs.append("found in raid")
		lines.append("  " + use.name + (" — " + ", ".join(needs) if not needs.is_empty() else ""))
	return "\n".join(lines)


## What the hideout and quests still need of item `id`: [{"kind" ("upgrade" or "quest"), "name", "more"
## (how many still to hand over), "fir"}]: every hideout level not built yet (the next one less what's
## handed over to it; none for a level being built) and every quest not completed (less what's handed in).
static func still_needed(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for station in Hideout.stations():
		var next := int(Hideout.next_level(station).get("level", 0))
		for entry: Dictionary in station.levels:
			if int(entry.level) <= Hideout.level(station) or (int(entry.level) == next and Hideout.is_building(station)):
				continue
			for requirement: Dictionary in entry.get("requires", []):
				if requirement.get("item", "") != id:
					continue
				var more := int(requirement.get("count", 1)) - (Hideout.handed(station, id) if int(entry.level) == next else 0)
				if more > 0:
					result.append({"kind": "upgrade", "name": "%s level %d" % [station.name, int(entry.level)], "more": more,
						"fir": bool(requirement.get("fir", false))})
	for quest in QuestLog.shown():
		if QuestLog.state(quest) == "completed":
			continue
		var objectives: Array = quest.get("objectives", [])
		for index in objectives.size():
			var objective: Dictionary = objectives[index]
			if objective.get("type", "") == "hand_in" and objective.get("item", "") == id:
				var more := int(objective.get("count", 1)) - QuestLog.progress(quest, index)
				if more > 0:
					result.append({"kind": "quest", "name": "%s (%s)" % [quest.name, TraderTable.display_name(str(quest.get("trader", "")))],
						"more": more, "fir": bool(objective.get("fir", false))})
	return result


## "Needed: Generator level 2 — 1 more, found in raid; Scrap Run (Bulat) — 3 more" (one line a use),
## or "" if the hideout and quests need none: the hover text of the needed-for icon.
static func needed_text(id: String) -> String:
	var lines := []
	for use in still_needed(id):
		lines.append("%s: %s — %d more%s" % ["Hideout" if use.kind == "upgrade" else "Quest", use.name, use.more, ", found in raid" if use.fir else ""])
	return "\n".join(lines)


static var _markers := {}
static var _markers_frame := -1
static var _markers_key := 0


## The needed-for icon item `id` gets in every grid (ItemDraw): Marker.NEEDED while a hideout level or a
## quest still needs some (still_needed()), USED when only crafts, barters or gear upgrades take it,
## NONE otherwise. Worked out for every item in one pass, again only when the hideout's levels, what's
## handed over or the quests change (checked at most once a frame).
static func marker(id: String) -> Marker:
	var frame := Engine.get_process_frames()
	if frame != _markers_frame:
		_markers_frame = frame
		var key := hash([GameState.hideout, GameState.hideout_state.get("handed", {}), GameState.hideout_state.get("builds", {}).keys(), GameState.quests,
			GameState.faction])
		if key != _markers_key or _markers.is_empty():
			_markers_key = key
			_markers = _all_markers()
	return _markers.get(id, Marker.NONE)


static func _all_markers() -> Dictionary:
	var result := {"": Marker.NONE}
	var used := func(wanted: Variant) -> void:
		if wanted is Dictionary and wanted.has("item"):
			result[str(wanted.item)] = maxi(int(result.get(str(wanted.item), Marker.NONE)), Marker.USED)
	for barter in BarterTable.all():
		if not BarterTable.visible(barter):
			continue
		for give: Variant in barter.get("requires", []):
			used.call(give)
	for station in Hideout.stations():
		for entry: Dictionary in station.levels:
			for recipe: Dictionary in entry.get("crafts", []):
				for input: Variant in recipe.get("inputs", []):
					used.call(input)
	var gear: Dictionary = GearUpgrades.config().get("items", {})
	for group: String in gear:
		for level: Array in gear[group]:
			for cost: Variant in level:
				used.call(cost)
	for source: String in GearUpgrades.sources():
		for cost: Variant in GearUpgrades.config().sources[source].get("extra_items", []):
			used.call(cost)
	var named := {}
	for station in Hideout.stations():
		for entry: Dictionary in station.levels:
			for requirement: Dictionary in entry.get("requires", []):
				named[str(requirement.get("item", ""))] = true
	for quest in QuestLog.shown():
		for objective: Dictionary in quest.get("objectives", []):
			if objective.get("type", "") == "hand_in":
				named[str(objective.get("item", ""))] = true
	for id: String in named:
		if not still_needed(id).is_empty():
			result[id] = Marker.NEEDED
	return result


static func _use(kind: String, name: String, requirement: Dictionary) -> Dictionary:
	return {"kind": kind, "name": name, "count": int(requirement.get("count", 1)), "fir": bool(requirement.get("fir", false))}


## "CMS surgical kit" or "Energy drink ×2" for {"item", "count"}.
static func _output_text(output: Dictionary) -> String:
	var data := ItemDB.get_item(str(output.get("item", ""))) if ItemDB.has_item(str(output.get("item", ""))) else null
	var name := data.display_name if data else str(output.get("item", "?"))
	var count := int(output.get("count", 1))
	return name + (" ×%d" % count if count > 1 else "")
