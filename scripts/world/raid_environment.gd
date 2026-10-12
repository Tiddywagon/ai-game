class_name RaidEnvironment
extends Node
## A raid's time of day and weather (DESIGN.md §13.6): sets the sun, sky light, fog and rain to match,
## and tells VisionSystem, which shortens everyone's vision at night and in fog or rain.

## Sun energy, sun colour, sun pitch (degrees), ambient energy, ambient colour, background colour.
const TIME_LOOKS := {
	VisionConfig.TimeOfDay.DAY: [1.2, Color(1.0, 0.97, 0.9), -50.0, 0.5, Color(0.75, 0.78, 0.85), Color(0.1, 0.11, 0.1)],
	VisionConfig.TimeOfDay.DUSK: [0.55, Color(1.0, 0.62, 0.4), -18.0, 0.3, Color(0.62, 0.52, 0.58), Color(0.08, 0.06, 0.07)],
	VisionConfig.TimeOfDay.NIGHT: [0.1, Color(0.55, 0.65, 1.0), -60.0, 0.12, Color(0.35, 0.42, 0.7), Color(0.01, 0.012, 0.02)],
}
const FOG_DENSITY := {VisionConfig.Weather.CLEAR: 0.0, VisionConfig.Weather.FOG: 0.045, VisionConfig.Weather.RAIN: 0.012}
const RAIN_AREA := 36.0

@export var time_of_day := VisionConfig.TimeOfDay.DAY
@export var weather := VisionConfig.Weather.CLEAR
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment

var _rain: CPUParticles3D


func _ready() -> void:
	_rain = _make_rain()
	add_child(_rain)
	apply(time_of_day, weather)


func _process(_delta: float) -> void:
	# Rain falls around wherever the camera looks.
	var camera := get_viewport().get_camera_3d()
	if _rain.emitting and camera:
		var ground := camera.global_position - camera.global_basis.z * camera.global_position.y / maxf(camera.global_basis.z.y, 0.1)
		_rain.global_position = Vector3(ground.x, 12.0, ground.z)


func apply(new_time: VisionConfig.TimeOfDay, new_weather: VisionConfig.Weather) -> void:
	time_of_day = new_time
	weather = new_weather
	var look: Array = TIME_LOOKS[time_of_day]
	var dim := 0.75 if weather == VisionConfig.Weather.RAIN else 1.0
	if sun:
		sun.light_energy = look[0] * dim
		sun.light_color = look[1]
		sun.rotation_degrees.x = look[2]
	if world_environment and world_environment.environment:
		var environment := world_environment.environment
		environment.ambient_light_energy = look[3] * dim
		environment.ambient_light_color = look[4]
		environment.background_color = look[5]
		environment.fog_enabled = FOG_DENSITY[weather] > 0.0
		environment.fog_density = FOG_DENSITY[weather]
		environment.fog_light_color = Color(0.55, 0.57, 0.6) * (1.0 if time_of_day == VisionConfig.TimeOfDay.DAY else 0.35)
		environment.fog_light_energy = 1.0
	_rain.emitting = weather == VisionConfig.Weather.RAIN
	_rain.visible = _rain.emitting
	VisionSystem.set_conditions(time_of_day, weather)


func _make_rain() -> CPUParticles3D:
	var rain := CPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 1400
	rain.lifetime = 0.8
	rain.preprocess = 0.8
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(RAIN_AREA / 2.0, 0.5, RAIN_AREA / 2.0)
	rain.direction = Vector3.DOWN
	rain.spread = 4.0
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 19.0
	rain.gravity = Vector3.ZERO
	rain.local_coords = false
	rain.emitting = false
	rain.visible = false
	var streak := BoxMesh.new()
	streak.size = Vector3(0.015, 0.45, 0.015)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.7, 0.75, 0.85, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material = material
	rain.mesh = streak
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return rain
