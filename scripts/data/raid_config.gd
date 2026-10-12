class_name RaidConfig
extends Resource
## Raid tuning (DESIGN.md §2): extraction, Run Through and raid experience. The values live in
## data/config/raid.tres.

## Seconds to stand in an extract zone before you're out.
@export_range(1.0, 60.0, 0.5, "suffix:s") var extract_seconds := 7.0

@export_group("Run Through")
## Extracting sooner than this AND with less raid experience than run_through_xp is a Run Through:
## you keep what you carry, but nothing becomes found in raid.
@export_range(0.0, 3600.0, 10.0, "suffix:s") var run_through_seconds := 420.0
@export_range(0, 10000, 10) var run_through_xp := 200

@export_group("Experience")
@export_range(0, 5000, 10) var xp_scav_kill := 100
@export_range(0, 5000, 10) var xp_pmc_kill := 300
## For each item that reaches your inventory as loot (the first time).
@export_range(0, 1000, 1) var xp_looted_item := 10
