#!/usr/bin/env python3
"""The score of "Every job.", composed in code on the picture's own times (tools/timing.py), and Armstrong.
D major, 120 BPM. Instruments: tools/synth.py (computed, no recordings). Every sound effect lives in tools/cues.py.

  Act I     an electric piano note per word, rising; "job." lands on a chord
  Act II    the apps pile up over the groove heard through a wall, opening as they burst; then everything stops (STALL)
  valley    silence: `melt them down` is typed into it
  the drop  its enter lands the groove, open: finger bass, Rhodes stabs, guitar chops, kick, snare, shaker (D, G, A)
  the kills the groove at full, ghost scratches added (G, A, Bm, A); it stops dead on the cut to the moon
  Armstrong a dark pad and a sparse felt piano under him, opening from "mankind." into the arrival
  the dive  the groove comes back on D with him finished; silence before the name
  the card  the name lands on the low drum (tools/sfx.py); a Dadd9 rings above it; the line lands on a high A

The groove is played, not sequenced: the odd 16ths swing late and every stroke but the downbeat drifts a few ms.

usage: uv run tools/score.py   -> audio/music.wav (score + Armstrong), audio/voice.wav (his line alone, same scale)
       STEMS=1 uv run tools/score.py   also writes each bus to /tmp/stem_*.wav, to listen to with earshot
"""
# /// script
# dependencies = ["numpy", "scipy", "soundfile", "pyloudnorm"]
# ///
import os, subprocess, sys
import numpy as np
from scipy import signal
import soundfile as sf
import pyloudnorm as pyln

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from timing import TM, SEG_A, SEG_B
import synth as S

SR = S.SR
N = int(SR * TM["end"])
def t2i(t): return int(round(t * SR))
def ramp(n, a, b): return np.linspace(a, b, max(n, 1))


class Bus:
    def __init__(self, wet): self.x = np.zeros((N + SR * 4, 2)); self.wet = wet
    def add(self, y, t, gain=1.0, p=0.0):
        y = (S.pan(y, p) if y.ndim == 1 else y) * gain
        i = t2i(t)
        if i < 0: y, i = y[-i:], 0
        y = y[:len(self.x) - i]; self.x[i:i + len(y)] += y


piano, pad, keys, gtr, bass, drums = Bus(0.32), Bus(0.38), Bus(0.22), Bus(0.16), Bus(0.0), Bus(0.06)
BUSES = {"keys": keys, "gtr": gtr, "bass": bass, "drums": drums}
ir = S.room_ir(rt60=2.3)
GAIN = {"piano": 1.0, "pad": 0.32, "keys": 0.5, "gtr": 0.45, "bass": 0.6, "drums": 0.55}
LV = TM["kills"][-1]["live"]
STALL, MELT, MOON, LEAP = TM["stall"], TM["meltCmd"], TM["kills"][-1]["enter"], dict(TM["music"])["leap"]
EARTH, ARRIVE, STOP, LOGO, END = LV["earth"], TM["arrive"], LV["stop"], TM["logo"], TM["end"]
KILLS = [c["enter"] for c in TM["kills"][:-1]]


# ------------------------------------------------------------------ Act I: an electric piano note per word, a chord on "job."
WORDS = TM["words1"]
for (w, t, _), n in zip(WORDS[:-1], ["D4", "F#4", "A4", "B4"]):
    keys.add(S.rhodes(n, 0.45, 0.4), t)
JOB = WORDS[-1][1]
for n in ["F#3", "A3", "E4", "A4", "D5"]: keys.add(S.rhodes(n, 0.7, 0.5), JOB)
bass.add(S.fbass("D2", 0.7, 0.8), JOB)

# ------------------------------------------------------------------ the groove: finger bass, rhodes, guitar, kit (Act II, the drop, the kills, the arrival)
CH = {"D": ("D2", ["F#3", "A3", "C#4", "E4"], ["A3", "D4", "F#4"]),
      "G": ("G1", ["F#3", "A3", "B3", "D4"], ["B3", "D4", "G4"]),
      "A": ("A1", ["E3", "A3", "C#4", "F#4"], ["A3", "C#4", "E4"]),
      "Bm": ("B1", ["F#3", "A3", "D4", "E4"], ["B3", "D4", "F#4"])}
RIFF = [(0, 0, .42, 1.0), (3, 0, .1, .6), (6, 0, .14, .75), (8, 0, .36, .9), (11, 0, .1, .6), (14, 7, .12, .7)]
KEYS = [(3, .12, .38), (6, .25, .45), (10, .12, .38), (11, .25, .42)]
SWING = 0.022                                                    # 16th swing, ~59%
def groove(t0, t1, chord_at, energy_at, filt=None):
    """16ths from t0 to t1; `chord_at(t)` names the chord, `energy_at(t)` is 0 (bass, keys, kick, shaker in 8ths),
    1 (+ snare, shaker in 16ths, guitar chops) or 2 (+ ghost scratches)"""
    b = {k: Bus(w) for k, w in (("keys", .22), ("gtr", .16), ("bass", 0), ("drums", .06))} if filt else BUSES
    k, hum = 0, np.random.default_rng(int(t0 * 1000))
    while t0 + k * 0.125 < t1 - 0.01:
        g, i = t0 + k * 0.125, k % 16; c, e = chord_at(g), energy_at(g)
        t = g + (SWING if i % 2 else 0.0) + (hum.normal(0, 0.004) if i else 0.0)   # played: the odd 16ths late, never the downbeat
        root, keys, gtr = CH[c]
        new = k == 0 or chord_at(g - 0.125) != c
        for j, iv, d, v in RIFF:
            if j == i: b["bass"].add(S.fbass(midi(root, iv), d, v), t)
        if new: [b["keys"].add(S.rhodes(n, 0.45, 0.55), t, p=-0.2 + 0.13 * m) for m, n in enumerate(keys)]
        for j, d, v in KEYS:
            if j == i and not new: [b["keys"].add(S.rhodes(n, d, v), t, p=-0.2 + 0.13 * m) for m, n in enumerate(keys)]
        if i in (0, 8) or (e >= 1 and i == 10): b["drums"].add(S.kick(0.9 if i == 0 else 0.7), t)
        if e >= 1 and i in (4, 12): b["drums"].add(S.snare(0.5), t, p=0.05)
        if i % 2 == 0 or e >= 1: b["drums"].add(S.shaker(0.5 if i % 4 == 2 else 0.25 if i % 2 == 0 else 0.18), t, p=0.3)
        if e >= 1 and i in (4, 12): b["gtr"].add(S.strum(gtr, 0.11, 0.5, mute=0.25), t, p=0.45)
        if e >= 2 and i in (1, 2, 7, 9, 14, 15): b["gtr"].add(S.strum(gtr, 0.06, 0.22, mute=0.85, down=i % 2 == 0), t, p=0.45)
        k += 1
    if filt:
        mix = sum(S.reverb(x.x, ir, x.wet) * GAIN[n] for n, x in b.items())
        BUSES["drums"].x[:] += S.sweep_lp(mix, filt(np.arange(len(mix)) / SR)) / GAIN["drums"]
def midi(note, iv): return 69 + 12 * np.log2(S.hz(note) / 440) + iv

# ------------------------------------------------------------------ Act II: the pile, the groove heard through a wall; then it stalls
A2 = TM["act2"]
G2 = 2 / 60                                                     # Act II's grid sits two frames after the half-second
for i, at in enumerate(TM["appT"][:3]):                          # the three apps you can read: a note each
    keys.add(S.rhodes(["D5", "E5", "F#5"][i], 0.3, 0.45), at)
groove(A2 + G2, STALL, lambda t: "G" if t < TM["heat0"] else "A", lambda t: 0 if t < TM["burst"][0] else 1,
       filt=lambda t: np.interp(t, [0, TM["heat0"] - A2, STALL - A2], [350, 700, 4000]))

# ------------------------------------------------------------------ the drop: its enter lands the groove, open; D, G, A
groove(MELT, 12.0, lambda t: "D" if t < MELT + 2 else "G" if t < MELT + 4 else "A", lambda t: 2)

# ------------------------------------------------------------------ the kills: the groove at full; it stops dead on the moon
groove(12.0, MOON, lambda t: "G" if t < 14 else "A" if t < 16 else "Bm" if t < 17 else "A", lambda t: 2)

# ------------------------------------------------------------------ Armstrong: dark and sparse, opening into the arrival
GRID = list(TM["pulse"])
pad.add(S.pad(["B2", "F#3", "B3", "D4"], 2.26, attack=0.8, release=0.6, cut=(380, 800)), LEAP, 0.9)
pad.add(S.pad(["G2", "D3", "B3", "D4"], EARTH - (LEAP + 2.26), attack=0.6, release=0.3, cut=(380, 900)), LEAP + 2.26, 0.9)
swell = np.linspace(0, 1, 60) ** 2
pad.add(S.pad(["A2", "E3", "A3", "C#4", "E4"], ARRIVE - EARTH, attack=0.5, release=0.05, cut=(500, 3200), bright=swell), EARTH, 0.6)
for at, n in zip(GRID[::4], ["B4", "A4", "G4", "F#4"]): piano.add(S.piano(n, 1.8, 0.3), at, p=0.1)
bass.add(S.bass("A1", ARRIVE - EARTH, 0.5), EARTH)

# ------------------------------------------------------------------ the arrival and the dive: the groove comes back on D
gtr.add(S.strum(["D3", "A3", "D4", "F#4", "A4"], STOP - ARRIVE, 0.55, spread=0.012), ARRIVE, p=0.3)
pad.add(S.pad(["D3", "A3", "D4", "F#4", "A4", "D5"], STOP - ARRIVE, attack=0.03, release=0.05, cut=(2200, 5200)), ARRIVE, 0.4)
drums.add(S.hat(0.3, open_=True), ARRIVE, p=0.2)
groove(ARRIVE, STOP, lambda t: "D", lambda t: 2)

# ------------------------------------------------------------------ the card: the name lands on the low drum (tools/sfx.py), the
# chord above it rings (Dadd9, nothing under A3: the drum is its root); the line on a high A
for n in ["A3", "F#4", "A4", "E5"]: keys.add(S.rhodes(n, END - LOGO - 1.0, 0.5), LOGO)
pad.add(S.pad(["D3", "A3", "E4", "F#4"], END - LOGO - 0.8, attack=0.8, release=1.4, cut=(500, 1100), bright=np.linspace(1, 0.3, 40)), LOGO, 0.45)
gtr.add(S.strum(["A3", "D4", "E4", "A4", "F#4"], END - LOGO - 1.0, 0.45, spread=0.018), LOGO, p=0.3)
keys.add(S.rhodes("A5", 2.0, 0.4), TM["press"])

# ------------------------------------------------------------------ mix the buses through one room; the stops cut the room too
score = np.zeros((N, 2))
for name, b in (("piano", piano), ("pad", pad), *BUSES.items()):
    y = S.reverb(b.x, ir, b.wet) if b.wet else b.x
    score += y[:N] * GAIN[name]
    if os.environ.get("STEMS"): sf.write(f"/tmp/stem_{name}.wav", (y[:N] * GAIN[name] * 0.3).astype(np.float32), SR)
score += 0.4 * np.stack([S.hp(score[:, c], 2500, 2) for c in (0, 1)], axis=1)     # presence and air: about +3 dB above 2.5 kHz
# the card ends on a held chord and a one-second fade, not a long decay
c0 = t2i(LOGO + 0.6)
env = np.sqrt(signal.sosfiltfilt(signal.butter(1, 2.0, "lowpass", fs=SR, output="sos"), score[c0:].mean(1) ** 2).clip(1e-12))
score[c0:] *= 10 ** (np.clip(20 * np.log10(env[:t2i(0.2)].mean() / env), 0.0, 10.0) / 20)[:, None]
gate = np.ones(N)
for a, b, fo in ((STALL, MELT, 0.08), (MOON, LEAP, 0.02), (STOP, LOGO, 0.03)):
    i, j, f = t2i(a), t2i(b), t2i(fo)
    gate[i:i + f] = np.minimum(gate[i:i + f], ramp(f, 1, 0)); gate[i + f:j] = 0
gate[-t2i(1.0):] *= ramp(t2i(1.0), 1, 0)
score *= gate[:, None]
score = np.tanh(score / np.abs(score).max() * 1.2) / np.tanh(1.2)

# ------------------------------------------------------------------ room for the enters: the key (tools/sfx.py) lives at
# 4-8 kHz, with the shaker; for 90 ms around each enter 3-12 kHz is carved to 3 dB under the quietest of them, so every
# enter sits at one level over the groove (mix.py holds one sound's gains within 2 dB). The bass gives way first: mix.py
# and qa.py filter from the window's start, so a loud low end there reads as a step, a click in every band
ENTERS = [MELT] + KILLS
lows = np.stack([S.lp(score[:, c], 220, 4) for c in (0, 1)], axis=1)
gl = sum(np.interp(np.arange(N) / SR, [e - 0.05, e - 0.02, e + 0.06, e + 0.12], [0.0, -12.0, -12.0, 0.0], left=0.0, right=0.0) for e in ENTERS)
score += lows * (10 ** (gl / 20) - 1)[:, None]
carve = signal.butter(4, [3000, 12000], "bandpass", fs=SR, output="sos")
probe = signal.butter(4, [4000, 8000], "bandpass", fs=SR, output="sos")
def level(e):   # as mix.py and qa.py read it: causal, over the key's 50 ms
    w = score[t2i(e - 0.002):t2i(e + 0.048)].mean(1)
    return 10 * np.log10(np.mean(signal.sosfilt(probe, w) ** 2) + 1e-20)
for _ in range(4):
    lvl = [level(e) for e in ENTERS]
    g = sum(np.interp(np.arange(N) / SR, [e - 0.05, e - 0.02, e + 0.06, e + 0.09], [0.0, min(lvl) - 3.0 - l, min(lvl) - 3.0 - l, 0.0], left=0.0, right=0.0)
            for e, l in zip(ENTERS, lvl))
    cb = np.stack([signal.sosfiltfilt(carve, score[:, c]) for c in (0, 1)], axis=1)
    score += cb * (10 ** (g / 20) - 1)[:, None]
if os.environ.get("STEMS"): print("enter beds 4-8 kHz:", [round(level(e), 1) for e in ENTERS])

# ------------------------------------------------------------------ Armstrong: line A from the moon cut, line B into the Earth
def decode(path, args=()):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, *args, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)
src = os.path.join(ROOT, "..", "research", "footage", "icons", "Armstrong_Small_Step.ogg")
HUM = ",".join(f"bandreject=f={57.27 * k:.1f}:width_type=q:w=14" for k in range(2, 10))     # the downlink's 57.27 Hz hum
def vo_piece(s0, s1):
    x = decode(src, ["-ss", str(s0), "-t", str(s1 - s0), "-af",
                     f"afftdn=nf=-30,{HUM},highpass=f=180,lowpass=f=4200,acompressor=threshold=-24dB:ratio=3:attack=5:release=120"])
    fd = min(len(x) // 2, t2i(0.015)); x[:fd] *= ramp(fd, 0, 1); x[-fd:] *= ramp(fd, 1, 0)
    return x
PRE = TM["vo"]["a"] - TM["quindarIn"]                          # the channel opens with the Quindar tone, a breath before his first word
va = vo_piece(SEG_A[0] - PRE, SEG_A[1]); va[:t2i(PRE)] *= ramp(t2i(PRE), 0, 1) ** 2
vb = np.concatenate([np.concatenate([vo_piece(s0, s1), np.zeros(t2i(g))]) for s0, s1, g in SEG_B])
pk = max(np.abs(va).max(), np.abs(vb).max())
voice = np.zeros(N)
def put(x, t): i = t2i(t); voice[i:i + len(x)] += x[:N - i]
put(va / pk * 10 ** (-3.5 / 20), TM["quindarIn"]); put(vb / pk, TM["vo"]["b"])
q = decode(os.path.join(ROOT, "audio", "own", "quindar-in.wav"))
put(q / np.abs(q).max() * 10 ** (-17 / 20), TM["quindarIn"])

meter = pyln.Meter(SR)
vo = np.stack([voice, voice], axis=1)
under = meter.integrated_loudness(score[t2i(LEAP):t2i(EARTH)])
vo *= 10 ** ((under + 14.0 - meter.integrated_loudness(vo[t2i(TM["quindarIn"]):t2i(TM["vo"]["end"])])) / 20)
band = signal.butter(4, [1000, 4000], "bandpass", fs=SR, output="sos")
sp, bd = (signal.sosfilt(band, x.mean(1)) for x in (vo, score))
blk = SR * 2 // 5
m_ = [10 * np.log10(np.mean(sp[i:i + blk] ** 2) / (np.mean(bd[i:i + blk] ** 2) + 1e-20))
      for i in range(t2i(TM["vo"]["a"]), t2i(TM["vo"]["end"]) - blk, SR // 10) if np.mean(sp[i:i + blk] ** 2) > 1e-3 * np.max(sp ** 2)]
print(f"Armstrong over the score, 1-4 kHz: min {min(m_):.1f} dB, median {np.median(m_):.1f} dB")

mus = score + vo
k = 0.5 / np.abs(mus).max()
for name, x in (("music", mus * k), ("voice", vo * k)):
    out = os.path.join(ROOT, "audio", name + ".wav")
    sf.write(out, x.astype(np.float32), SR, subtype="FLOAT")
    print("wrote", out)
