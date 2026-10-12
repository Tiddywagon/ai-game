class_name RaidConfig
extends Resource
## Raid tuning (DESIGN.md §2, §7): extraction, Run Through, raid experience and how long searching
## takes. The values live in data/config/raid.tres.

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
## A 360 trick-shot kill (DESIGN.md §13.4): bonus experience on top of the kill's, and Drip (style
## points, kept in the profile).
@export_range(0, 5000, 10) var xp_trick_kill := 250
@export_range(0, 1000, 1) var drip_trick_kill := 25

@export_group("Searching")
## Seconds to reveal one item when searching a container or body: this, plus search_seconds_per_cell
## for each cell it takes (a 1×1 bandage is quick, a 5×2 rifle slow), times the container's
## search_time.
@export_range(0.0, 5.0, 0.05, "suffix:s") var search_base_seconds := 0.35
@export_range(0.0, 5.0, 0.05, "suffix:s") var search_seconds_per_cell := 0.25
