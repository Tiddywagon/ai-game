extends Camera3D
## Slow cinematic pan for the main menu background (DESIGN.md §16): drifts side to side and back,
## always looking at the same part of the yard.

## How far the camera drifts each way from where it's placed.
@export var travel := Vector3(12.0, 0.0, -3.0)
## Seconds for one full back-and-forth.
@export var period := 100.0
## Point the camera looks at, and how far that point drifts along with the camera.
@export var look_target := Vector3(0.0, 4.0, -18.0)
@export var look_drift := Vector3(5.0, 0.0, 0.0)

var _start := Vector3.ZERO
var _time := 0.0


func _ready() -> void:
	_start = position
	# Moved every frame in _process, so physics interpolation must leave it alone.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_update()


func _process(delta: float) -> void:
	_time += delta
	_update()


func _update() -> void:
	var swing := sin(_time * TAU / period)
	position = _start + travel * swing
	look_at(look_target + look_drift * swing)
