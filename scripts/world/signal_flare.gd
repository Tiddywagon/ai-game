extends Node3D
## A red signal flare fired from an extract (DESIGN.md §5, ExtractZone.fire_flare()): a pop and a hiss,
## a bright red light climbing into the sky, then fading out. Loud: AI hears it from NOISE_RADIUS. Raid
## events (RaidEvents) fire them too, in other colours (`color`).

const NOISE_RADIUS := 60.0
const COLOR := Color(1.0, 0.25, 0.15)
const RISE := 28.0
const RISE_TIME := 2.5
const BURN_TIME := 6.0
const SOUND := preload("res://assets/audio/sfx/flare.wav")

var color := COLOR


func _ready() -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 4.0
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = 22.0
	light.shadow_enabled = false
	add_child(light)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = SOUND
	sound.bus = &"Effects"
	sound.max_distance = NOISE_RADIUS
	add_child(sound)
	sound.play()
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y + RISE, RISE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(light, "light_energy", 0.0, BURN_TIME).set_delay(RISE_TIME)
	tween.parallel().tween_property(ball, "scale", Vector3.ONE * 0.2, BURN_TIME).set_delay(RISE_TIME)
	tween.tween_callback(queue_free)
