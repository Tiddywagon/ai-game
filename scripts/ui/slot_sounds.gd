class_name SlotSounds
extends RefCounted
## The slot machine's sounds (DESIGN.md §6.7), synthesized in code as short 16-bit clips: the lever pull
## at the start of a spin, a tick as each symbol passes the line, a thunk as a reel stops, the tease's
## rising whine, and a win sting per rarity (more notes, higher and longer the rarer it is). Made once and
## kept.

const RATE := 22050
## The sting's notes (semitones above A3) for each rarity, Common to Legendary.
const STINGS := [[0, 7], [0, 4, 7], [0, 4, 7, 12], [0, 4, 7, 11, 14], [0, 4, 7, 12, 16, 19], [0, 4, 7, 12, 16, 19, 24, 28]]

static var _cache := {}


## The clip named `id`: "pull", "tick", "stop", "tease", or "sting_0" ... "sting_5" (by rarity).
static func clip(id: String) -> AudioStreamWAV:
	if not _cache.has(id):
		_cache[id] = _make(id)
	return _cache[id]


static func _make(id: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	match id:
		"pull":
			samples = _sweep(0.28, 180.0, 520.0, 0.35, 0.6)
		"tick":
			samples = _click(0.025, 2400.0, 0.35)
		"stop":
			samples = _click(0.12, 140.0, 0.8)
		"tease":
			samples = _sweep(0.9, 300.0, 1300.0, 0.25, 0.1)
		_:
			var rarity := clampi(int(id.trim_prefix("sting_")), 0, 5)
			samples = _arpeggio(STINGS[rarity], 0.07 + rarity * 0.012, 0.22 + rarity * 0.12)
	return _stream(samples)


static func _stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## A short knock: a decaying tone at `pitch` with a little noise.
static func _click(seconds: float, pitch: float, volume: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(seconds * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pitch)
	for i in count:
		var t := float(i) / RATE
		var decay := exp(-t * 6.0 / seconds)
		out.append((sin(TAU * pitch * t) * 0.7 + rng.randf_range(-0.3, 0.3)) * decay * volume)
	return out


## A tone gliding from `from` Hz to `to`, with a vibrato of `wobble` and noise share `noise`.
static func _sweep(seconds: float, from: float, to: float, noise: float, wobble: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(seconds * RATE)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(from + to)
	for i in count:
		var share := float(i) / count
		var pitch := lerpf(from, to, share) * (1.0 + sin(share * 40.0) * 0.02 * wobble)
		phase += TAU * pitch / RATE
		var envelope := minf(share * 12.0, 1.0) * (1.0 - share)
		out.append((sin(phase) * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise) * envelope * 0.45)
	return out


## Notes `steps` (semitones above A3) one after another, `gap` seconds apart, the last ringing `tail`.
static func _arpeggio(steps: Array, gap: float, tail: float) -> PackedFloat32Array:
	var total := gap * steps.size() + tail
	var out := PackedFloat32Array()
	out.resize(int(total * RATE))
	out.fill(0.0)
	for n in steps.size():
		var pitch := 220.0 * pow(2.0, float(steps[n]) / 12.0)
		var start := int(n * gap * RATE)
		var length := int((tail + gap) * RATE)
		for i in length:
			if start + i >= out.size():
				break
			var t := float(i) / RATE
			var tone := sin(TAU * pitch * t) + 0.35 * sin(TAU * pitch * 2.0 * t) + 0.15 * sin(TAU * pitch * 3.0 * t)
			out[start + i] += tone * exp(-t * 5.0) * minf(t * 200.0, 1.0) * 0.22
	return out
