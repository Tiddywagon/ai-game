extends Node
## Autoload "NoiseSystem": sounds that AI can hear (DESIGN.md §4, §13). Footsteps, rolls and shots call
## emit_noise(); bots listen to noise_emitted and react if they're inside the radius. The player's
## vision shows sounds it can't see as direction markers at the screen edge (DESIGN.md §13.6).

## `kind` says what made it: &"footstep", &"roll", &"gunshot", &"flashbang" or &"other".
signal noise_emitted(position: Vector3, radius: float, source: Node, kind: StringName)


## Makes a noise at `position` that can be heard up to `radius` metres away.
func emit_noise(position: Vector3, radius: float, source: Node, kind := &"other") -> void:
	if radius > 0.0:
		noise_emitted.emit(position, radius, source, kind)
