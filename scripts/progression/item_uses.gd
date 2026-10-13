class_name ItemUses
extends RefCounted
## What an item is needed for (DESIGN.md §6.5): the quests, hideout upgrades, trader barters, hideout
## crafts and gear upgrades that take it. Examining an item shows a "Needed for" line with the full list
## as its tooltip, and the hover text in the inventory sums it up. Quests already completed and hideout
## levels already built drop out; barters, crafts and gear upgrades can be done again, so they stay.

## Kinds of use, in the order they're listed, with their names (one, many).
const KINDS := {
	"quest": ["quest", "quests"],
	"upgrade": ["hideout upgrade", "hideout upgrades"],
	"barter": ["barter", "barters"],
	"craft": ["craft", "crafts"],
	"gear": ["gear upgrade", "gear upgrades"],
}
## Gear upgrade groups (data/config/gear_upgrades.json) by what they upgrade.
const GEAR_GROUPS := {"armor": "Armor", "carry": "Rigs and backpacks", "electronics": "Headsets"}


## Every use of item `id`: [{"kind" (a KINDS key), "name" (what it's for), "count", "fir" (only
## found-in-raid items count)}], in KINDS order.
static func of(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest in QuestLog.all():
		if QuestLog.state(quest) == "completed":
			continue
		for objective: Dictionary in quest.get("objectives", []):
			if objective.get("type", "") == "hand_in" and objective.get("item", "") == id:
				result.append(_use("quest", "%s (%s)" % [quest.name, str(quest.get("trader", "")).capitalize()], objective))
	for station in Hideout.stations():
		for entry: Dictionary in station.levels:
			if int(entry.level) <= Hideout.level(station):
				continue
			for requirement: Dictionary in entry.get("requires", []):
				if requirement.get("item", "") == id:
					result.append(_use("upgrade", "%s level %d" % [station.name, int(entry.level)], requirement))
	for trader: String in GameState.TRADERS:
		for barter: Dictionary in Trading.offers(trader).get("barters", []):
			for give: Dictionary in barter.get("give", []):
				if give.get("item", "") == id:
					result.append(_use("barter", "%s → %s" % [trader.capitalize(), _output_text(barter.get("get", {}))], give))
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
## "Quests\n  Scrap Run (Prapor) — 3 needed, found in raid\nBarters\n  Therapist → CMS surgical kit — 1 needed".
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


static func _use(kind: String, name: String, requirement: Dictionary) -> Dictionary:
	return {"kind": kind, "name": name, "count": int(requirement.get("count", 1)), "fir": bool(requirement.get("fir", false))}


## "CMS surgical kit" or "Energy drink ×2" for {"item", "count"}.
static func _output_text(output: Dictionary) -> String:
	var data := ItemDB.get_item(str(output.get("item", ""))) if ItemDB.has_item(str(output.get("item", ""))) else null
	var name := data.display_name if data else str(output.get("item", "?"))
	var count := int(output.get("count", 1))
	return name + (" ×%d" % count if count > 1 else "")
