class_name Skills
extends RefCounted
## Skill levelling (DESIGN.md §12.3): skills live in GameState.skills as {"level", "progress" (0-1 of
## the way to the next level)}. Doing the thing a skill is about earns points; each level needs a
## little more than the last. Built so far: Metabolism (eating and drinking; Consumables).

const MAX_LEVEL := 50
## Points for level 0 → 1; every level after needs GROWTH more of them.
const BASE_POINTS := 100.0
const GROWTH := 0.1


static func level(id: String) -> int:
	return int(GameState.skills.get(id, {}).get("level", 0))


## Points from `skill_level` to the next level.
static func points_to_next(skill_level: int) -> float:
	return BASE_POINTS * (1.0 + GROWTH * skill_level)


## Adds `points` to skill `id`. Returns how many levels it gained (usually 0).
static func add_points(id: String, points: float) -> int:
	if not GameState.skills.has(id) or points <= 0.0:
		return 0
	var entry: Dictionary = GameState.skills[id]
	var gained := 0
	var current := int(entry.level)
	var progress := float(entry.progress) + points / points_to_next(current)
	while progress >= 1.0 and current < MAX_LEVEL:
		progress -= 1.0
		current += 1
		gained += 1
		progress *= points_to_next(current - 1) / points_to_next(current)  # Leftover points, in the next level's terms.
	entry.level = current
	entry.progress = progress if current < MAX_LEVEL else 0.0
	return gained


## "Metabolism" for "metabolism".
static func display_name(id: String) -> String:
	for skill in GameState.SKILLS:
		if skill[0] == id:
			return skill[1]
	return id.capitalize()
