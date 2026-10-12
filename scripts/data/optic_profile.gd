class_name OpticProfile
extends Resource
## How looking through one kind of sight changes vision while aiming (DESIGN.md §13.6). Lives inside
## data/config/vision.tres, one per VisionConfig.Optic.

@export var display_name := ""
## Width of the vision cone while aimed in.
@export_range(1.0, 360.0, 1.0, "suffix:°") var cone_degrees := 110.0
## Multiplies the vision range while aimed in.
@export_range(0.1, 10.0, 0.05) var range_multiplier := 1.0
## Multiplies movement speed while aimed in (no sprinting through any optic).
@export_range(0.1, 1.0, 0.05) var move_multiplier := 1.0
## Camera distance multiplier while aimed in: pulls the camera out to fit the longer view.
@export_range(1.0, 4.0, 0.05) var camera_zoom := 1.0
## Share of the way toward the aim point the camera's focus moves while aimed in, and the most it moves.
@export_range(0.0, 0.9, 0.05) var camera_lead := 0.0
@export_range(0.0, 200.0, 1.0, "suffix:m") var camera_max_lead := 0.0
## False for binoculars: the gun is down while you hold them.
@export var can_shoot := true
