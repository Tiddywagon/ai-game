"""Generates the placeholder audio in assets/audio: a seamless dark ambient menu loop, two UI sounds and the
360 trick-shot sting.

Usage: python3 tools/make_placeholder_audio.py assets/audio   (needs numpy and ffmpeg with libvorbis)
"""
import os, sys, wave, subprocess
import numpy as np

out_dir = sys.argv[1]
rng = np.random.default_rng(20261011)

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
def write_wav(path, samples, sr=44100):
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(data)

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
print("done")
