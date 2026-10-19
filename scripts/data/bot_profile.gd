class_name BotProfile
extends Resource
## How one type of AI behaves (DESIGN.md §4). One .tres per type in data/bots/.

@export var display_name: String
@export var side: Actor.Side
@export var body_color: Color
## Ammo item id from ItemDB.
@export var ammo_id: String
## Sight on its gun. A magnified one lets it spot targets farther away (DESIGN.md §13.6).
@export var optic: VisionConfig.Optic = VisionConfig.Optic.IRON_SIGHTS

@export_group("Movement")
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var walk_speed: float
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var sprint_speed: float

@export_group("Senses")
## Vision cone and range are in data/config/vision.tres (Scav and PMC values).
## Multiplies the radius of every noise this bot hears.
@export_range(0.0, 3.0, 0.05) var hearing: float
## Delay between first seeing someone and opening fire.
@export_range(0.0, 3.0, 0.05, "suffix:s") var reaction_time: float
## Without sight of the target for this long, the bot goes to search for it.
@export_range(0.5, 30.0, 0.5, "suffix:s") var give_up_time: float
## Hearing a gunshot (or an explosion) it runs to investigate and calls the Scavs of its zone within
## this distance to come too (0: it calls nobody). Footsteps it walks over to on its own.
@export_range(0.0, 60.0, 1.0, "suffix:m") var alert_radius := 0.0

@export_group("Shooting")
## Aim error: random spread added to the gun's own spread and recoil.
@export_range(0.0, 15.0, 0.1, "suffix:°") var spread_degrees: float
## Share of each recoil kick the bot fights off (0: none, 1: all of it).
@export_range(0.0, 1.0, 0.05) var recoil_control: float
## Fires for burst_time, then pauses for burst_pause.
@export_range(0.05, 3.0, 0.05, "suffix:s") var burst_time: float
@export_range(0.0, 3.0, 0.05, "suffix:s") var burst_pause: float

@export_group("Cover")
@export var uses_cover: bool
## How far the bot will go to reach cover.
@export_range(1.0, 50.0, 1.0, "suffix:m") var cover_search_radius: float
## Seconds spent peeking and ducked, picked at random between x and y.
@export var peek_time: Vector2
@export var duck_time: Vector2
## Peeks from the same spot before moving to new cover.
@export_range(1, 20) var peeks_before_move: int

@export_group("Advanced")
## Advanced AI can combat-roll.
@export var can_roll: bool
## Chance to roll out of the line of fire when shot at in the open.
@export_range(0.0, 1.0, 0.05) var dodge_chance: float
## Chance to roll into new cover when it's within a roll's reach.
@export_range(0.0, 1.0, 0.05) var roll_to_cover_chance: float

@export_group("Melee")
## A target this close (metres) gets the melee weapon instead of a bullet, if the bot carries one
## (DESIGN.md §13.4.2; a parry stance stops it). 0: never.
@export_range(0.0, 3.0, 0.1, "suffix:m") var melee_range := 0.0

@export_group("Behaviour")
## Below this share of its total HP (and not fled in the last minute or so) it breaks off a fight, runs
## for cover away from the threat and treats itself with what it carries. 0: never (bosses).
@export_range(0.0, 1.0, 0.05) var flee_health := 0.0
## Chance, each time it moves to new cover in a fight, that it picks a spot off to the threat's side
## (a flank) instead of the nearest one.
@export_range(0.0, 1.0, 0.05) var flank_chance := 0.0
## Out of a fight it picks up loose loot and loots ready event crates this close (0: never).
@export_range(0.0, 50.0, 1.0, "suffix:m") var loot_radius := 0.0
## Chance each patrol leg heads for a hot point of interest (a high tier, a fresh raid event) instead
## of its own zone (DESIGN.md §5.2).
@export_range(0.0, 1.0, 0.05) var hot_poi_chance := 0.0
## Its HP (every body part; the head a bit less) × this: bosses and their guards are tougher.
@export_range(0.5, 5.0, 0.05) var health_multiplier := 1.0
## A boss squad pushes as a group: moving to new cover means moving closer to the threat, one member
## at a time while the rest keep it pinned down.
@export var pushes := false
## A boss or guard keeps to its haunt (its BossSpawn): out of a fight it only goes after noises this
## close to it, so a fight farther off doesn't draw it away (DESIGN.md §4.3). 0: no limit. Only for a
## boss squad.
@export_range(0.0, 100.0, 1.0, "suffix:m") var haunt_radius := 0.0

@export_group("Loot")
## Extra loot rolled into the bot's pack and pockets (a boss's body: data/loot_tables/boss_body.tres
## holds valuables and stims). Empty: just its kit.
@export var extra_loot: LootTable
