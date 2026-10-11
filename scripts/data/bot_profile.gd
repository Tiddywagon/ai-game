class_name BotProfile
extends Resource
## How one type of AI behaves (DESIGN.md §4). One .tres per type in data/bots/.

@export var display_name: String
@export var side: Actor.Side
@export var body_color: Color
@export var max_health: float
## Ammo item id from ItemDB.
@export var ammo_id: String

@export_group("Movement")
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var walk_speed: float
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var sprint_speed: float

@export_group("Senses")
@export_range(1.0, 200.0, 1.0, "suffix:m") var vision_range: float
## Width of the vision cone. Anyone within 3 m is noticed whatever the angle.
@export_range(10.0, 360.0, 1.0, "suffix:°") var vision_angle: float
## Multiplies the radius of every noise this bot hears.
@export_range(0.0, 3.0, 0.05) var hearing: float
## Delay between first seeing someone and opening fire.
@export_range(0.0, 3.0, 0.05, "suffix:s") var reaction_time: float
## Without sight of the target for this long, the bot goes to search for it.
@export_range(0.5, 30.0, 0.5, "suffix:s") var give_up_time: float

@export_group("Shooting")
## Random spread of each shot.
@export_range(0.0, 15.0, 0.1, "suffix:°") var spread_degrees: float
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
