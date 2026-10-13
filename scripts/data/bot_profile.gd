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

@export_group("Loot")
## Extra loot rolled into the bot's pack and pockets (a boss's body: data/loot_tables/boss_body.tres
## holds valuables and stims). Empty: just its kit.
@export var extra_loot: LootTable
