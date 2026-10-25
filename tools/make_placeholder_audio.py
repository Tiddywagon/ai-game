"""Generates the placeholder audio in assets/audio: a seamless dark ambient menu loop, two UI sounds, the
360 trick-shot sting, the extraction sound, the signal flare, the raid event sounds (a plane
overhead for an airdrop, a truck's horn and engine, a weapon cache's klaxon), and the factions' radio
voice barks (assets/audio/voice/<voice id>_<event>.wav, one per faction and voice event in
data/config/factions.json: a squelch click, a buzzy "voice" in a radio band with a syllable rhythm per
event, and a noise tail; BEAR lower and harsher, USEC higher and cleaner).

Usage: python3 tools/make_placeholder_audio.py assets/audio   (needs numpy and ffmpeg with libvorbis)
       python3 tools/make_placeholder_audio.py assets/audio voice   (only the voice barks)
"""
import os, sys, wave, subprocess
import numpy as np

out_dir = sys.argv[1]
only = sys.argv[2] if len(sys.argv) > 2 else ""
rng = np.random.default_rng(20261011)


def write_wav(path, samples, sr=44100):
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(data)


# ---- Voice barks (DESIGN.md §3): one short radio "voice" per faction and event --------------------
# Placeholder speech: a buzzy glottal tone shaped into syllables (each event its own rhythm and pitch
# contour), through two formant band-passes and a radio band, between a squelch click and a hiss tail.
def voice_barks():
    import json
    here = os.path.dirname(os.path.abspath(__file__))
    factions = json.load(open(os.path.join(here, "..", "data", "config", "factions.json")))["factions"]
    sr = 22050
    vrng = np.random.default_rng(20261018)
    # Syllables per event: (length s, pitch at start, pitch at end) as multiples of the base pitch.
    rhythms = {
        "contact": [(0.12, 1.0, 1.1), (0.2, 1.25, 1.05)],
        "hit": [(0.16, 1.4, 1.0)],
        "reload": [(0.1, 1.05, 1.0), (0.1, 1.0, 0.95), (0.16, 0.95, 0.85)],
        "grenade": [(0.09, 1.3, 1.35), (0.15, 1.4, 1.2)],
        "enemy_down": [(0.14, 1.15, 1.05), (0.2, 1.0, 0.8)],
        "mate_down": [(0.18, 0.95, 0.9), (0.12, 0.9, 0.85), (0.24, 0.85, 0.7)],
        "move": [(0.1, 1.0, 1.05), (0.18, 1.1, 1.3)],
        "heal": [(0.16, 0.95, 0.95), (0.2, 0.9, 0.85)],
        "extract": [(0.12, 1.0, 1.0), (0.12, 1.05, 1.0), (0.2, 1.0, 0.9)],
    }
    # Timbre per voice id: base pitch (Hz), how square the buzz is (0 sine-like, 1 square), formants
    # (Hz), noise in the voice, radio band (Hz).
    timbres = {
        "bear": {"base": 108.0, "square": 0.75, "formants": (560.0, 1350.0), "noise": 0.22, "band": (350.0, 2600.0)},
        "usec": {"base": 142.0, "square": 0.3, "formants": (700.0, 1750.0), "noise": 0.1, "band": (420.0, 3400.0)},
    }

    def bandpass(x, low, high, taps=255):
        n = np.arange(taps) - (taps - 1) / 2
        def sinc_low(cut):
            return 2 * cut / sr * np.sinc(2 * cut / sr * n)
        kernel = (sinc_low(high) - sinc_low(low)) * np.hamming(taps)
        return np.convolve(x, kernel, mode="same")

    os.makedirs(f"{out_dir}/voice", exist_ok=True)
    for key, faction in factions.items():
        voice = faction.get("voice", {})
        vid = voice.get("id", key)
        timbre = timbres.get(vid, timbres["usec"])
        for event in voice.get("lines", {}):
            parts = []
            # Squelch: a short click and a burst of hiss as the radio keys up.
            click = int(0.03 * sr)
            tt = np.arange(click) / sr
            parts.append(np.sin(2 * np.pi * 1900 * tt) * np.exp(-tt / 0.006) * 0.5 + vrng.standard_normal(click) * 0.15 * np.exp(-tt / 0.01))
            for length, start, end in rhythms.get(event, [(0.2, 1.0, 1.0)]):
                count = int(length * sr)
                tt = np.arange(count) / sr
                pitch = timbre["base"] * np.linspace(start, end, count) * (1 + 0.02 * np.sin(2 * np.pi * 5.5 * tt))
                phase = 2 * np.pi * np.cumsum(pitch) / sr
                buzz = (1 - timbre["square"]) * (2 * (phase / (2 * np.pi) % 1.0) - 1) + timbre["square"] * np.sign(np.sin(phase))
                buzz = buzz + vrng.standard_normal(count) * timbre["noise"]
                env = np.minimum(1.0, tt / 0.015) * np.minimum(1.0, (length - tt) / 0.03)
                formed = sum(bandpass(buzz, f * 0.75, f * 1.3) * g for f, g in zip(timbre["formants"], (1.0, 0.6)))
                parts.append(formed * env)
                parts.append(vrng.standard_normal(int(0.035 * sr)) * 0.02)  # Gap between syllables.
            tail = int(0.12 * sr)
            tt = np.arange(tail) / sr
            parts.append(vrng.standard_normal(tail) * 0.25 * np.exp(-tt / 0.04))  # Release hiss.
            bark = bandpass(np.concatenate(parts), *timbre["band"])
            bark = np.tanh(bark / np.max(np.abs(bark)) * 1.8)  # A little radio overdrive.
            write_wav(f"{out_dir}/voice/{vid}_{event}.wav", bark / np.max(np.abs(bark)) * 0.75, sr)
    print("voice done")


if only == "voice":
    voice_barks()
    sys.exit(0)

# ---- Menu ambience: 48 s seamless loop, 32 kHz stereo -------------------------------------
SR, LOOP = 32000, 48.0
n = int(SR * LOOP)
t = np.arange(n) / SR

def tone(freq_cycles, amp, phase=0.0):
    # freq given as whole cycles per loop so every partial lines up at the loop point
    return amp * np.sin(2 * np.pi * freq_cycles / LOOP * t + phase)

def lfo(period_s, lo, hi, phase=0.0):
    return lo + (hi - lo) * 0.5 * (1 + np.sin(2 * np.pi * t / period_s + phase))

drone = (
    tone(2640, 0.30) * lfo(16, 0.7, 1.0)                 # A1 55 Hz
    + tone(5280, 0.08) * lfo(24, 0.4, 1.0, 1.0)          # A2
    + (tone(3956, 0.12) + tone(3965, 0.12)) * lfo(48, 0.3, 1.0, 2.0)  # E2, slowly beating
    + tone(6279, 0.05) * lfo(24, 0.0, 1.0, 3.5)          # C3 minor third fading in and out
)

def one_pole_lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y

def wind(seed_offset):
    # Filter 2 extra seconds and crossfade the tail into the head for a seamless loop.
    extra = 2 * SR
    noise = np.random.default_rng(seed_offset).standard_normal(n + extra)
    cutoff = np.concatenate([lfo(12, 180, 520), lfo(12, 180, 520)[:extra]])
    w = one_pole_lowpass(one_pole_lowpass(noise, cutoff), cutoff)
    head, tail = w[:extra], w[n:n + extra]
    fade = np.linspace(0, 1, extra)
    w = w[:n].copy()
    w[:extra] = head * fade + tail * (1 - fade)
    return w / np.max(np.abs(w))

gust = lfo(16, 0.35, 1.0, 0.7) * lfo(48, 0.6, 1.0)
left = drone + 0.10 * wind(1) * gust
right = drone + 0.10 * wind(2) * gust

# Two distant metallic pings with a soft echo; their tails end well before the loop point.
for start, freq in ((7.0, 880.0), (31.0, 659.25)):
    for k, (delay, gain, pan) in enumerate(((0.0, 1.0, 0.3), (0.45, 0.45, 0.7), (0.9, 0.2, 0.4))):
        s = int((start + delay) * SR)
        length = int(4.5 * SR)
        tt = np.arange(length) / SR
        ping = (np.sin(2 * np.pi * freq * tt) + 0.35 * np.sin(2 * np.pi * freq * 2.76 * tt)) * np.exp(-tt / 1.1) * 0.045 * gain
        left[s:s + length] += ping * (1 - pan)
        right[s:s + length] += ping * pan

stereo = np.stack([left, right], axis=1)
stereo *= 0.33 / np.max(np.abs(stereo))  # quiet: about -10 dBFS peaks
pcm = (stereo * 32767).astype("<i2").tobytes()
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                "-c:a", "libvorbis", "-q:a", "3", f"{out_dir}/music/menu_ambient.ogg"], input=pcm, check=True)

# ---- UI sounds: 44.1 kHz mono WAV ------------------------------------------------------------
sr = 44100
tt = np.arange(int(0.045 * sr)) / sr
glide = 2600 - 900 * tt / tt[-1]
hover = np.sin(2 * np.pi * np.cumsum(glide) / sr) * np.exp(-tt / 0.009) * 0.22
hover[:40] += rng.standard_normal(40) * 0.05 * np.linspace(1, 0, 40)
write_wav(f"{out_dir}/ui/hover.wav", hover)

tt = np.arange(int(0.12 * sr)) / sr
click = (np.sin(2 * np.pi * 170 * tt) * np.exp(-tt / 0.035) * 0.45
         + np.sin(2 * np.pi * 1250 * tt) * np.exp(-tt / 0.006) * 0.25)
click[:60] += rng.standard_normal(60) * 0.12 * np.linspace(1, 0, 60)
write_wav(f"{out_dir}/ui/click.wav", click)

# ---- 360 trick-shot sting: a quick rising arpeggio (E5 B5 E6 G#6) with a shimmer on top -------
total = int(0.85 * sr)
sting = np.zeros(total)
for k, (freq, start) in enumerate([(659.25, 0.0), (987.77, 0.06), (1318.5, 0.12), (1661.2, 0.18), (3322.4, 0.18)]):
    tt = np.arange(int(0.65 * sr)) / sr
    env = np.minimum(1.0, tt / 0.004) * np.exp(-tt * 7.0)
    note = (np.sin(2 * np.pi * freq * tt) + 0.35 * np.sin(2 * np.pi * freq * 2 * tt) + 0.12 * np.sin(2 * np.pi * freq * 3.01 * tt)) * env
    gain = 0.05 if k == 4 else (0.28 if k == 3 else 0.22)
    s = int(start * sr)
    sting[s:s + len(tt)] += note[:total - s] * gain
os.makedirs(f"{out_dir}/sfx", exist_ok=True)
write_wav(f"{out_dir}/sfx/trick_sting.wav", sting / np.max(np.abs(sting)) * 0.85)

# ---- Extraction: a low swell into a settled major chord (A3 C#4 E4 A4) with a soft whoosh -------
total = int(2.2 * sr)
tt = np.arange(total) / sr
swell = np.minimum(1.0, tt / 0.6) * np.exp(-np.maximum(tt - 0.9, 0) * 2.2)
chord = sum(np.sin(2 * np.pi * f * tt + k) * a for k, (f, a) in enumerate([(220.0, 0.30), (277.18, 0.22), (329.63, 0.22), (440.0, 0.16), (880.0, 0.04)]))
noise = rng.standard_normal(total)
whoosh = np.convolve(noise, np.ones(40) / 40, mode="same") * np.exp(-((tt - 0.35) / 0.25) ** 2) * 0.5
extract = chord * swell + whoosh
write_wav(f"{out_dir}/sfx/extract.wav", extract / np.max(np.abs(extract)) * 0.8)

# ---- Signal flare: a sharp pop, then a hiss that fades as it climbs ------------------------------
total = int(2.4 * sr)
tt = np.arange(total) / sr
pop = np.sin(2 * np.pi * 95 * tt) * np.exp(-tt / 0.03) * 0.9
hiss = rng.standard_normal(total)
hiss = (hiss - np.convolve(hiss, np.ones(6) / 6, mode="same")) * np.minimum(1.0, tt / 0.05) * np.exp(-tt * 1.4) * 0.45
flare = pop + hiss
write_wav(f"{out_dir}/sfx/flare.wav", flare / np.max(np.abs(flare)) * 0.85)
print("done")

# ---- Raid events (DESIGN.md §5.2): an airdrop plane, a supply truck's horn, a weapon cache klaxon --------
total = int(7.0 * sr)
tt = np.arange(total) / sr
swell = np.exp(-((tt - 3.2) / 1.9) ** 2)  # Comes in, passes over, fades.
pitch = 1.0 + 0.06 * np.tanh((3.2 - tt) * 1.2)  # A slight Doppler drop as it passes.
phase = 2 * np.pi * np.cumsum(62.0 * pitch) / sr
engine = (np.sin(phase) + 0.6 * np.sin(2 * phase) + 0.3 * np.sin(3 * phase)) * (0.7 + 0.3 * np.sin(2 * np.pi * 11 * tt))
rumble = np.convolve(rng.standard_normal(total), np.ones(120) / 120, mode="same") * 3.0
plane = (engine * 0.5 + rumble) * swell
write_wav(f"{out_dir}/sfx/plane.wav", plane / np.max(np.abs(plane)) * 0.8)

total = int(3.0 * sr)
tt = np.arange(total) / sr
blasts = ((tt > 0.05) & (tt < 0.45)) | ((tt > 0.65) & (tt < 1.35))
horn = (np.sign(np.sin(2 * np.pi * 220 * tt)) * 0.5 + np.sign(np.sin(2 * np.pi * 277 * tt)) * 0.4) * blasts
horn = np.convolve(horn, np.ones(20) / 20, mode="same")
idle = np.sin(2 * np.pi * np.cumsum(38 + 4 * np.sin(2 * np.pi * 3 * tt)) / sr) * 0.35 * np.minimum(1.0, tt / 0.3)
truck = horn * 0.6 + idle
write_wav(f"{out_dir}/sfx/truck_horn.wav", truck / np.max(np.abs(truck)) * 0.8)

total = int(2.6 * sr)
tt = np.arange(total) / sr
two_tone = np.where((tt * 2.5) % 1.0 < 0.5, 660.0, 495.0)
klaxon = np.sign(np.sin(2 * np.pi * np.cumsum(two_tone) / sr)) * np.exp(-np.maximum(tt - 2.0, 0) * 6.0)
klaxon = np.convolve(klaxon, np.ones(12) / 12, mode="same")
write_wav(f"{out_dir}/sfx/klaxon.wav", klaxon / np.max(np.abs(klaxon)) * 0.7)
print("events done")

voice_barks()
