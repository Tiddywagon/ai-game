class_name RaidConfig
extends Resource
## Raid tuning (DESIGN.md §2, §5, §7): extraction, power, spawns, Run Through, raid experience,
## insurance, how long searching takes, the extract list and when AI leaves the raid. The values live
## in data/config/raid.tres.

## Seconds to stand in an extract zone before you're out.
@export_range(1.0, 60.0, 0.5, "suffix:s") var extract_seconds := 7.0
## Seconds between throwing a power switch and the power coming on (extracts that need power open).
@export_range(0.0, 120.0, 1.0, "suffix:s") var power_delay := 10.0
## A raid starts at a random spawn point at least this far from hostile AI, if there is one.
@export_range(0.0, 100.0, 1.0, "suffix:m") var spawn_safe_distance := 15.0

@export_group("Run Through")
## Extracting sooner than this AND with less raid experience than run_through_xp is a Run Through:
## you keep what you carry, but nothing becomes found in raid.
@export_range(0.0, 3600.0, 10.0, "suffix:s") var run_through_seconds := 420.0
@export_range(0, 10000, 10) var run_through_xp := 200

@export_group("Experience")
@export_range(0, 5000, 10) var xp_scav_kill := 100
@export_range(0, 5000, 10) var xp_pmc_kill := 300
## A boss and one of its guards (DESIGN.md §4.3), instead of the Scav kill's.
@export_range(0, 10000, 10) var xp_boss_kill := 1000
@export_range(0, 5000, 10) var xp_guard_kill := 250
## For each item that reaches your inventory as loot (the first time).
@export_range(0, 1000, 1) var xp_looted_item := 10
## For extracting (SURVIVED; a Run Through earns no experience at all).
@export_range(0, 5000, 10) var xp_survived := 300
## A 360 trick-shot kill (DESIGN.md §13.4): bonus experience on top of the kill's, and Drip (style
## points, kept in the profile).
@export_range(0, 5000, 10) var xp_trick_kill := 250
@export_range(0, 1000, 1) var drip_trick_kill := 25

@export_group("Insurance")
## Insuring an item costs its insurer's share of its value (data/config/insurers.json; this rate only
## if an insurer has none), with its parts, rounded up to 100 roubles, and at least
## insurance_min_price. Insured items lost when you die or go missing come back to the stash (Insurance).
@export_range(0.0, 1.0, 0.01) var insurance_rate := 0.1
@export_range(0, 100000, 100) var insurance_min_price := 1000

@export_group("Searching")
## Seconds to reveal one item when searching a container or body: this, plus search_seconds_per_cell
## for each cell it takes (a 1×1 bandage is quick, a 5×2 rifle slow), times the container's
## search_time.
@export_range(0.0, 5.0, 0.05, "suffix:s") var search_base_seconds := 0.35
@export_range(0.0, 5.0, 0.05, "suffix:s") var search_seconds_per_cell := 0.25

@export_group("Extracts")
## Seconds the list of your extracts stays on screen at raid start, and after pressing the Show
## extracts key (O).
@export_range(0.0, 60.0, 0.5, "suffix:s") var extract_list_seconds := 8.0
## A random extract becomes known (open or closed) once you're this close to it with a clear line of
## sight, or stand in it. Until then it's "Unknown".
@export_range(1.0, 100.0, 0.5, "suffix:m") var extract_confirm_distance := 12.0
## Seconds of the fade to black after extracting, before the raid summary.
@export_range(0.0, 10.0, 0.1, "suffix:s") var extract_fade_seconds := 1.5

@export_group("Scav waves")
## More Scavs turn up as the raid goes on (DESIGN.md §4): a wave of scav_wave_size Scavs every
## scav_wave_interval seconds (random between x and y), until scav_wave_until of the raid has passed
## and while fewer than scav_max_alive Scavs are alive. A wave spawns at a point of a Scav zone or of
## a point of interest (hot ones, PointOfInterest.heat(), are likelier), at least
## scav_wave_min_distance from the player and out of their sight, and roams from there.
@export var scav_wave_interval := Vector2(150.0, 240.0)
@export var scav_wave_size := Vector2i(2, 3)
@export_range(0, 40) var scav_max_alive := 10
@export_range(0.0, 200.0, 1.0, "suffix:m") var scav_wave_min_distance := 25.0
@export_range(0.0, 1.0, 0.05) var scav_wave_until := 0.85

@export_group("AI extraction")
## AI PMCs head for an extract they can use somewhere between these shares of the raid time (0.5:
## halfway through), and leave the raid there like the player does.
@export var ai_pmc_extract_window := Vector2(0.45, 0.85)
## The share of AI Scavs that leave at all, and when (the rest stay until the end).
@export_range(0.0, 1.0, 0.05) var ai_scav_extract_chance := 0.5
@export var ai_scav_extract_window := Vector2(0.6, 0.95)
