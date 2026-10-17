class_name PoiConfig
extends Resource
## Tuning for points of interest (DESIGN.md §5.2): loot tiers, which spawn points are active, focus
## tags, exploration rewards, raid events and how much AI a POI draws. The values live in
## data/config/poi.tres; the POIs themselves in data/config/pois.json (PoiTable).

@export_group("Loot")
## Rarity multiplier for Rare and above, by tier (tier 1, 2, 3).
@export var tier_multipliers: PackedFloat32Array = [1.0, 1.5, 2.5]
## A POI behind a key: its loot rolls with these on top (indexed by ItemData.Rarity).
@export var locked_bonus: PackedFloat32Array = [1.0, 1.0, 1.2, 1.35, 1.5, 1.5]
## Share of a POI's spawn points active in a raid, by tier, unless the POI sets its own spawn_chance.
@export var spawn_chances: PackedFloat32Array = [0.55, 0.65, 0.75]
## Loose loot in a POI comes from its focus items this often (else from the loose loot table).
@export_range(0.0, 1.0, 0.05) var focus_share := 0.7
## In a container, items matching the POI's focus weigh this many times more.
@export_range(1.0, 10.0, 0.5) var focus_weight := 3.0

@export_group("Exploration")
## Raid experience for entering a POI for the first time (ever), a hidden one, and for having
## explored every POI on a map.
@export_range(0, 1000, 5) var xp_discover := 25
@export_range(0, 1000, 5) var xp_discover_hidden := 75
@export_range(0, 5000, 10) var xp_map_complete := 250
## Seconds the POI's name stays on screen when you walk in.
@export_range(0.5, 10.0, 0.5, "suffix:s") var label_seconds := 3.5

@export_group("Events")
## How many events a raid has (a random number from x to y), and when (shares of the raid time).
@export var event_count := Vector2i(1, 3)
@export var event_window := Vector2(0.15, 0.8)
## Seconds an airdrop crate takes to come down, and a supply truck to pull in.
@export_range(1.0, 60.0, 0.5, "suffix:s") var airdrop_fall_seconds := 9.0
@export_range(1.0, 60.0, 0.5, "suffix:s") var truck_arrive_seconds := 6.0
## Chance an AI not already fighting drops what it's doing and heads for an event: Scavs, PMCs.
@export_range(0.0, 1.0, 0.05) var rush_chance_scav := 0.5
@export_range(0.0, 1.0, 0.05) var rush_chance_pmc := 0.85
## How loud an event is (metres): AI within it may come.
@export_range(10.0, 500.0, 5.0, "suffix:m") var event_noise_radius := 120.0

@export_group("Heat")
## How strongly a POI draws Scav waves and roaming AI PMCs, by tier, and on top while it has a fresh
## event (for event_heat_seconds).
@export var tier_heat: PackedFloat32Array = [1.0, 2.0, 4.0]
@export_range(0.0, 50.0, 0.5) var event_heat := 8.0
@export_range(0.0, 1800.0, 10.0, "suffix:s") var event_heat_seconds := 300.0
