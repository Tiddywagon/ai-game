class_name VisionConfig
extends Resource
## All vision tuning in one place (DESIGN.md §13.6): cone angles, ranges, light, weather, status
## effects, optics and the AI. The values live in data/config/vision.tres.

## Sights, by index into `optics`. Saved as numbers: only add new values at the end.
enum Optic { IRON_SIGHTS, RED_DOT, HOLO, SCOPE_2_4, SCOPE_6_8, BINOCULARS }
## Time of day and weather of a raid. Same rule.
enum TimeOfDay { DAY, DUSK, NIGHT }
enum Weather { CLEAR, FOG, RAIN }

@export_group("Player")
## Vision cone, pointed where you aim.
@export_range(10.0, 360.0, 1.0, "suffix:°") var player_cone_degrees := 110.0
## How far the cone reaches in full daylight and clear weather.
@export_range(1.0, 200.0, 1.0, "suffix:m") var player_range := 30.0
## You always sense things this close, in every direction (walls still block).
@export_range(0.0, 10.0, 0.1, "suffix:m") var awareness_radius := 2.0

@export_group("AI")
@export_range(10.0, 360.0, 1.0, "suffix:°") var scav_cone_degrees := 120.0
@export_range(1.0, 200.0, 1.0, "suffix:m") var scav_range := 25.0
@export_range(10.0, 360.0, 1.0, "suffix:°") var pmc_cone_degrees := 140.0
@export_range(1.0, 200.0, 1.0, "suffix:m") var pmc_range := 35.0
@export_range(0.0, 10.0, 0.1, "suffix:m") var ai_awareness_radius := 3.0

@export_group("Occlusion")
## Sight lines are traced at eye height: standing above low cover, crouched below it, so low cover
## only blocks a crouched viewer (or hides a crouched target). Keep standing above the low cover limit
## in combat.tres (1.3 m) and crouched below the lowest low cover.
@export_range(0.1, 2.0, 0.05, "suffix:m") var standing_eye_height := 1.45
@export_range(0.1, 2.0, 0.05, "suffix:m") var crouched_eye_height := 0.5

@export_group("Light")
## Light level (0 = pitch dark, 1 = full daylight) for each TimeOfDay.
@export var time_light: PackedFloat32Array = [1.0, 0.6, 0.15]
## Light level inside DarkZones (dark rooms), unless the zone sets its own.
@export_range(0.0, 1.0, 0.05) var dark_room_light := 0.1
## Range multiplier in pitch darkness; it scales up linearly to 1 in full light.
@export_range(0.0, 1.0, 0.05) var darkness_range_multiplier := 0.25
## Flashlight: a narrow cone that brings its own light (not shortened by darkness).
@export_range(1.0, 120.0, 1.0, "suffix:°") var flashlight_cone_degrees := 30.0
@export_range(1.0, 100.0, 1.0, "suffix:m") var flashlight_range := 22.0
## AI spot range multiplier against someone whose flashlight is on.
@export_range(1.0, 5.0, 0.05) var flashlight_conspicuity := 1.5

@export_group("Weather")
## Range multiplier for each Weather (cones only; awareness is unaffected).
@export var weather_range: PackedFloat32Array = [1.0, 0.5, 0.75]

@export_group("Status effects")
@export_range(0.1, 1.0, 0.05) var pain_cone_multiplier := 0.8
## A head below this share of its HP counts as a head injury.
@export_range(0.0, 1.0, 0.05) var head_injury_threshold := 0.7
@export_range(0.1, 1.0, 0.05) var head_injury_cone_multiplier := 0.7
## Flashbang: blinds everyone within this radius who has a clear line to it.
@export_range(1.0, 50.0, 0.5, "suffix:m") var flashbang_radius := 15.0
## Blind time at point blank, looking at it; falls off with distance.
@export_range(0.0, 15.0, 0.1, "suffix:s") var flashbang_max_blind := 4.0
## Blind time multiplier when facing away from it.
@export_range(0.0, 1.0, 0.05) var flashbang_facing_away := 0.35

@export_group("Optics")
## One OpticProfile per Optic value, in order.
@export var optics: Array[OpticProfile] = []
## Seconds to raise or lower a sight: the cone, range and camera blend over this time.
@export_range(0.0, 2.0, 0.01, "suffix:s") var optic_transition_time := 0.3
## How quickly the camera follows the optic's zoom and lead (higher = snappier).
@export_range(0.5, 30.0, 0.5) var camera_follow_speed := 6.0

@export_group("Rendering")
## Visibility updates per second.
@export_range(5.0, 120.0, 1.0) var update_rate := 30.0
## Ray spacing along the edge of a vision cone (smaller = rounder, slower).
@export_range(0.5, 10.0, 0.5, "suffix:°") var arc_step_degrees := 2.0
## Areas seen before but not visible now: brightness and colour left.
@export_range(0.0, 1.0, 0.01) var memory_brightness := 0.3
@export_range(0.0, 1.0, 0.01) var memory_saturation := 0.15
## Areas never seen.
@export_range(0.0, 1.0, 0.01) var unseen_brightness := 0.03
## How dark dark rooms look (1 = black) where your flashlight isn't.
@export_range(0.0, 1.0, 0.05) var dark_room_shading := 0.6
## Pixels per side of the vision masks.
@export_range(256, 4096, 64) var mask_resolution := 1024
## Seconds a sound direction marker stays on screen.
@export_range(0.2, 10.0, 0.1, "suffix:s") var sound_marker_time := 1.5


func optic(kind: int) -> OpticProfile:
	return optics[kind] if kind >= 0 and kind < optics.size() else null


## Range multiplier at `light` (0-1).
func light_multiplier(light: float) -> float:
	return lerpf(darkness_range_multiplier, 1.0, clampf(light, 0.0, 1.0))
