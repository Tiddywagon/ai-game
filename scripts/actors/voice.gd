class_name Voice
extends Node3D
## A PMC's voice (DESIGN.md §3): short placeholder radio barks on events (Factions.EVENTS: contact,
## hit, reload, grenade, enemy_down, mate_down, move, heal, extract), from its faction's lines and
## sounds (data/config/factions.json, assets/audio/voice/). Each line plays from the speaker on the
## Voice bus, heard within the hearing radius (hearing_radius(): measured from the player, whose
## TopDownCamera carries the audio listener); it's a noise AI hears close by (NoiseSystem, kind "voice":
## a talking squad gives itself away a little), and the player's sound markers point at a speaker they
## can't see within the hearing radius (PlayerVision). With Subtitles on, a line the player hears from
## someone they can see (or their own) shows as a subtitle (Settings.show_subtitle()); an unseen speaker
## shows nothing but its marker, so voices don't give away more than sound already does. A speaker waits
## speaker_cooldown seconds between lines and each event's own cooldown before repeating it, so it never
## spams.
## Actor.set_faction() gives an actor one; the actor's hits and reloads it hears itself, the rest the
## player and Bot call say() for.

## A line was said (and played).
signal spoke(event: StringName, line: Dictionary)

## The faction whose voice this is.
var faction: StringName = &""
## The actor speaking (the parent).
var actor: Actor
## Lines said so far: [{"event", "text", "subtitle"}] (tests, the debug overlay).
var said: Array[Dictionary] = []

var _player: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
## Game seconds since this voice started, the earliest it may speak again, and per event.
var _clock := 0.0
var _quiet_until := 0.0
var _event_quiet := {}


func _ready() -> void:
	name = "Voice"
	actor = get_parent() as Actor
	position = Vector3.UP * 1.5
	_rng.randomize()
	_player = AudioStreamPlayer3D.new()
	_player.name = "Speaker"
	_player.bus = &"Voice"
	_player.max_distance = hearing_radius()
	_player.unit_size = 6.0
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_player)
	if actor:
		actor.hurt.connect(func(_damage: float) -> void: say(&"hit"))
		actor.weapon.reload_started.connect(func(_duration: float) -> void: say(&"reload"))


func _physics_process(delta: float) -> void:
	_clock += delta


## True if it may say a line for `event` now: alive, a faction with lines for it, and past its cooldowns.
func can_say(event: StringName) -> bool:
	if actor == null or actor.is_dead or actor.health.is_dead or Factions.lines(faction, event).is_empty():
		return false
	return _clock >= _quiet_until and _clock >= float(_event_quiet.get(event, 0.0))


## Says a line for `event` (Factions.EVENTS) if it may (can_say()): plays it from the speaker, makes the
## noise, shows the subtitle to the player if they can hear and see the speaker. Returns the line
## ({"text", "subtitle"}), or {} if it stayed quiet.
func say(event: StringName) -> Dictionary:
	if not can_say(event):
		return {}
	var tuning := Factions.voice_config()
	var options := Factions.lines(faction, event)
	var line: Dictionary = options[_rng.randi_range(0, options.size() - 1)]
	_quiet_until = _clock + float(tuning.get("speaker_cooldown", 2.5))
	_event_quiet[event] = _clock + float(tuning.get("event_cooldowns", {}).get(String(event), 5.0))
	var stream := Factions.voice_stream(faction, event)
	if stream and _player.is_inside_tree():
		_player.stream = stream
		var jitter := float(tuning.get("pitch_jitter", 0.0))
		_player.pitch_scale = Factions.voice_pitch(faction) * (1.0 + _rng.randf_range(-jitter, jitter))
		_player.play()
	if actor.is_inside_tree():
		NoiseSystem.emit_noise(actor.global_position, float(tuning.get("noise_radius", 8.0)) * actor.health.noise_multiplier(), actor, &"voice")
	said.append({"event": event, "text": str(line.get("text", "")), "subtitle": str(line.get("subtitle", ""))})
	_show_subtitle(line, float(tuning.get("subtitle_seconds", 2.5)))
	spoke.emit(event, line)
	return line


## How far the player hears a voice line, in metres (factions.json "voice" hearing_radius; × their
## hearing for subtitles and sound markers).
static func hearing_radius() -> float:
	return float(Factions.voice_config().get("hearing_radius", 30.0))


## Seconds until it may speak at all again (0: now).
func cooldown_left() -> float:
	return maxf(_quiet_until - _clock, 0.0)


## The subtitle for `line` said by this voice's actor: "USEC: Contact front!", "BEAR: Kontakt! (Contact!)",
## "You: Reloading!".
func subtitle_text(line: Dictionary) -> String:
	var speaker := "You" if actor is Player else Factions.display_name(faction)
	var text := str(line.get("text", ""))
	if str(line.get("subtitle", "")) != "":
		text += " (%s)" % line.subtitle
	return "%s: %s" % [speaker, text]


## Whether the player hears this line well enough for a subtitle: their own, or within the hearing
## radius from someone they can see.
func player_hears() -> bool:
	if actor is Player:
		return true
	var player := get_tree().get_first_node_in_group("player") as Actor if is_inside_tree() else null
	if player == null or player.is_dead:
		return false
	var reach := hearing_radius() * player.hearing_multiplier()
	return player.global_position.distance_to(actor.global_position) <= reach and actor.is_seen()


func _show_subtitle(line: Dictionary, seconds: float) -> void:
	if player_hears():
		Settings.show_subtitle(subtitle_text(line), seconds)
