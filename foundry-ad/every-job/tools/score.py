#!/usr/bin/env python3
"""The music and voice stems for "Every job.": one breathing B-flat drone, a sub kick, a little bass and the typewriter
as hi-hat, the 1860 phonautograph, and Armstrong. Every sound effect lives in tools/cues.py (real recordings, placed
by sound-layer/scripts/mix.py), so nothing here is a hit, a click or a whoosh.

usage: uv run tools/score.py        -> audio/music.wav, audio/voice.wav (48 kHz stereo float)
"""
# /// script
# dependencies = ["numpy", "scipy", "soundfile"]
# ///
import os, subprocess, sys
import numpy as np
from scipy import signal
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR, BPM = 48000, 120
BEAT = 60 / BPM
rng = np.random.default_rng(7)

# ------------------------------------------------------------------ edit cues (tools/timing.py is the source of truth)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from timing import TM, SEG_A, SEG_B
DUR = TM["end"]
N = int(SR * DUR)

PD = os.path.join(ROOT, "..", "research", "audio-pd")

# ------------------------------------------------------------------ helpers
def t2i(t): return int(round(t * SR))
def tt(d): return np.arange(int(d * SR)) / SR
def env_exp(d, tau): return np.exp(-tt(d) / tau)
def adsr(d, a, r):
    n = int(d * SR); e = np.ones(n); na, nr = int(a * SR), int(r * SR)
    if na: e[:na] = np.linspace(0, 1, na)
    if nr: e[-nr:] *= np.linspace(1, 0, nr)
    return e
def bp(x, lo, hi, o=2): return signal.sosfilt(signal.butter(o, [lo, hi], "bandpass", fs=SR, output="sos"), x)
def hp(x, f, o=2): return signal.sosfilt(signal.butter(o, f, "highpass", fs=SR, output="sos"), x)
def lp(x, f, o=2): return signal.sosfilt(signal.butter(o, f, "lowpass", fs=SR, output="sos"), x)
def noise(d): return rng.standard_normal(int(d * SR))
def saw(f, d, phase=0.0):
    ph = np.cumsum(np.broadcast_to(f, int(d * SR)) / SR) + phase
    return 2 * (ph % 1) - 1
def sine(f, d):
    return np.sin(2 * np.pi * np.cumsum(np.broadcast_to(f, int(d * SR)) / SR))


class Bus:
    def __init__(self): self.L = np.zeros(N); self.R = np.zeros(N)
    def add(self, x, t, gain=1.0, pan=0.0, width=0.0):
        i = t2i(t)
        if i >= N: return
        if i < 0: x = x[-i:]; i = 0
        x = x[: N - i] * gain
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        self.L[i:i + len(x)] += x * l * np.sqrt(2)
        if width:  # Haas width
            dly = int(width * SR); xr = np.concatenate([np.zeros(dly), x])[: len(x)]
            self.R[i:i + len(x)] += xr * r * np.sqrt(2)
        else:
            self.R[i:i + len(x)] += x * r * np.sqrt(2)


music, beds, voice = Bus(), Bus(), Bus()


# ------------------------------------------------------------------ instruments
def kick(gain=1.0):
    d = 0.5; f = 46 + 110 * np.exp(-tt(d) / 0.035)
    body = sine(f, d) * env_exp(d, 0.16)
    click = hp(noise(0.012), 2500) * np.linspace(1, 0, int(0.012 * SR)) * 0.4
    body[: len(click)] += click
    return np.tanh(body * 1.6) * gain

def clap():
    d = 0.25; x = np.zeros(int(d * SR))
    for k, o in enumerate([0, 0.009, 0.018, 0.028]):
        b = bp(noise(0.2), 900, 4000) * env_exp(0.2, 0.012 if k < 3 else 0.06)
        x[int(o * SR): int(o * SR) + len(b)] += b[: len(x) - int(o * SR)]
    return x * 0.8

def bass_note(n, d):
    f = 440 * 2 ** ((n - 69) / 12); x = saw(f, d) * 0.7 + sine(f / 2, d) * 0.6
    return np.tanh(lp(x, 420, 2) * 1.5) * adsr(d, 0.004, 0.03)

def drone(d, base=29.14, bright=1.0):
    """One low, breathing drone: B-flat, a fifth, slow beating, filtered air on top."""
    t_ = tt(d)
    x = sum(np.sin(2 * np.pi * base * m * t_ * (1 + 0.0015 * np.sin(2 * np.pi * 0.07 * (k + 1) * t_))) * a
            for k, (m, a) in enumerate([(1, 1.0), (2, 0.55), (3, 0.28), (1.5, 0.22), (4, 0.08)]))
    air = lp(hp(noise(d), 120), 700 * bright) * 0.35 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t_))
    return np.tanh((x * 0.5 + air) * 0.9) * 0.6


# ------------------------------------------------------------------ samples
def load(name, sr=SR):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(PD, name), "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                         capture_output=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)

def cut(x, t0, d, fade=0.004, fo=0.02):
    y = x[int(t0 * SR): int((t0 + d) * SR)].copy()
    a, b = int(fade * SR), int(fo * SR)
    y[:a] *= np.linspace(0, 1, a); y[-b:] *= np.linspace(1, 0, b)
    return y

def norm(x, peak=1.0): return x / (np.abs(x).max() + 1e-9) * peak

TYPE_SRC = load("WWS_Typewriter.ogg")
PHONO_SRC = load("Au_Clair_de_la_Lune_(1860)_new.ogg")
KEYS = [norm(cut(TYPE_SRC, t - 0.003, 0.11)) for t in (4.46, 4.88, 7.37, 8.24, 11.13, 14.04, 16.43, 16.78)]
def key(k): return KEYS[k % len(KEYS)] * (0.7 + 0.3 * rng.random())

def reverb(x, secs=1.6, mix=0.25):
    n = int(secs * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * secs / 6.0))
    ir = lp(ir, 6000)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = signal.fftconvolve(x, ir)[: len(x)]
    return x * (1 - mix) + wet * mix

# key: B-flat minor (the anvil rings ~A#6)
ROOTS = [46, 42, 49, 44]
def bar_root(t): return ROOTS[int(t // 2) % 4]

# ------------------------------------------------------------------ Act I: a kick under every typewriter strike, the drone breathing in
room = lp(noise(DUR), 300) * 0.015
music.add(room * adsr(DUR, 0.05, 0.6), 0.0, width=0.02)
music.add(norm(bp(cut(PHONO_SRC, 3.70, 1.4, 0.01, 0.4), 250, 3200), 0.16), 0.0)        # the 1860 voice, faint, under the first strikes
for w, t0, clip in TM["words1"][:-1]:                         # "job." is the ignition hit (tools/cues.py), not a kick
    music.add(kick(0.95), t0)
dr = drone(TM["meltCmd"]); music.add(dr * np.linspace(0.25, 0.75, len(dr)) * 0.45, 0.0, width=0.02)

# ------------------------------------------------------------------ Act II: the groove under the pile of apps
t = TM["act2"]
while t < TM["meltCmd"] - 0.4:
    music.add(kick(0.7), t); music.add(bass_note(bar_root(t) - 12, BEAT / 2 - 0.01) * 0.42, t + BEAT / 2); t += BEAT

# ------------------------------------------------------------------ the melt: the drone opens up under the fire
MELT0, CAST = TM["meltCmd"] + 0.05, TM["cast"]
d_ = CAST - MELT0 - 0.15; dr = drone(d_, bright=2.0); ev = adsr(d_, 0.4, 0.4); n_ = min(len(dr), len(ev))
music.add(dr[:n_] * ev[:n_] * 0.55, MELT0 + 0.15, width=0.02)                                     # swells in after the blast
# the casting: the drone darkens as the iron cools and hands over to the groove
d_ = TM["settle"] + 0.3 - CAST; dr = drone(d_, bright=0.6); ev = adsr(d_, 0.3, 0.4); n_ = min(len(dr), len(ev)); music.add(dr[:n_] * ev[:n_] * 0.6, CAST - 0.2, width=0.02)

# ------------------------------------------------------------------ the kills: the groove returns, a kick on every enter
K = TM["kills"]
KK = {k["kind"]: k for k in K}
def groove(t0, t1, g=1.0):
    t = t0
    while t < t1 - 1e-6:
        b = round(t / BEAT); music.add(kick(0.9 * g), t)
        music.add(bass_note(bar_root(t) - 12, BEAT / 2 - 0.01) * 0.5 * g, t + BEAT / 2)
        for o in (0.125, 0.375): music.add(key(b + 1) * 0.18 * g, t + o, pan=-0.3)
        if b % 2 == 1: music.add(clap(), t, 0.28 * g)
        t += BEAT
groove(TM["settle"], KK["translate"]["flash"])
for k in K:
    if k["kind"] != "translate": music.add(kick(0.9), k["enter"])                          # translate's enter is the Quindar tone
dr = drone(TM["end"] - KK["translate"]["flash"]); music.add(dr * 1.05, KK["translate"]["flash"], width=0.03)         # mix.py ducks it under him

# ------------------------------------------------------------------ the beds: continuous roars are scenery, not events, so they live
# under the sound effects at a level set against the kill groove (real recordings cut by tools/sources.sh)
def own(name):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, "audio", "own", name + ".wav"), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)
s0, s1 = t2i(TM["settle"]), t2i(KK["translate"]["flash"])
GROOVE_RMS = np.sqrt(np.mean(music.L[s0:s1] ** 2))
def bed(name, t, db, ramp_db=0.0, pan=0.0):
    x = own(name); x = x / (np.sqrt(np.mean(x ** 2)) + 1e-12) * GROOVE_RMS * 10 ** (db / 20)
    beds.add(x * 10 ** (np.linspace(ramp_db, 0, len(x)) / 20), t, pan=pan, width=0.015)
IGN = TM["words1"][-1][1]
# a hero hit is levelled against what sustains under it (mix.py), so each roar is at full on its hit
bed("shuttle-roar", IGN, -1.0)                                   # the Saturn V lights; stops dead on the Act II cut
CATCH = 0.008                                                    # the fire catches just after the blast (in phase with it below 250 Hz)
bed("volcano", MELT0 + CATCH, 2.0, ramp_db=-4.0)                 # every screen ignites; the river grows as the camera falls
bed("furnace", MELT0 + CATCH, -2.0, pan=-0.2)                    # the roar of the fire itself
bed("train", KK["download"]["enter"] + 0.02, -6.0)               # the Lumiere train, out of the bar

# ------------------------------------------------------------------ Armstrong: line A under the translate kill; line B lands on the logo
src = os.path.join(ROOT, "..", "research", "footage", "icons", "Armstrong_Small_Step.ogg")
def vo_piece(s0, s1):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-ss", str(s0), "-t", str(s1 - s0),
                          "-af", "afftdn=nf=-30,highpass=f=180,lowpass=f=4200,acompressor=threshold=-24dB:ratio=3:attack=5:release=120",
                          "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True).stdout
    x = np.frombuffer(raw, np.float32).astype(np.float64)
    fd = min(len(x) // 2, int(0.015 * SR)); x[:fd] *= np.linspace(0, 1, fd); x[-fd:] *= np.linspace(1, 0, fd)
    return x
va = vo_piece(*SEG_A)
vb = np.concatenate([np.concatenate([vo_piece(s0, s1), np.zeros(int(g * SR))]) for s0, s1, g in SEG_B])
pk = max(np.abs(va).max(), np.abs(vb).max())
# line B is the last thing said: lift it, and lift "mankind" more (its "-kind" falls away in the recording), with presence
gb = np.full(len(vb), 10 ** (3.0 / 20))
mk = int((TM["vo"]["mankind"] - TM["vo"]["b"] - 0.03) * SR)
ramp = np.linspace(0, 1, int(0.04 * SR))
lift = np.concatenate([np.zeros(mk), ramp, np.ones(max(0, len(vb) - mk - len(ramp)))])[: len(vb)]
gb *= 10 ** ((3.5 * lift + 2.5 * lift * np.linspace(0, 1, len(vb))) / 20)
vb = vb + bp(vb, 1800, 4500) * 0.45 * lift
vb = np.tanh(vb / pk * gb * 1.1) / 1.1 * pk
voice.add(va / pk * 0.92, TM["vo"]["a"]); voice.add(vb / pk * 0.92, TM["vo"]["b"])

# ------------------------------------------------------------------ stems (mix.py levels, ducks under Armstrong and masters)
def duck_curve():
    g = np.ones(N)
    for c in [TM["cmd0"]] + TM["kills"]:  # the world waits while a command is typed
        a_, b_ = t2i(c["t0"] - 0.1), t2i(c["enter"])
        g[a_:b_] = np.minimum(g[a_:b_], np.linspace(1, 0.45, b_ - a_) ** 0.5)
    a_, b_ = t2i(TM["meltCmd"]), t2i(TM["meltCmd"] + 0.05)  # three frames of nothing
    g[a_:b_] = 0.0
    return lp(g, 40, 1)

def sidechain():
    g = np.ones(N)
    for t in list(np.arange(TM["act2"], TM["meltCmd"] - 0.4, BEAT)) + list(np.arange(TM["settle"], KK["translate"]["flash"], BEAT)):
        i = t2i(t); n = int(0.2 * SR)
        g[i:i + n] = np.minimum(g[i:i + n], 1 - 0.55 * np.exp(-np.arange(n) / (0.05 * SR)))
    return g

dk, sc = duck_curve(), sidechain()
sil = np.ones(N); sil[t2i(TM["meltCmd"]):t2i(TM["meltCmd"] + 0.05)] = 0.0
q0 = t2i(TM["vo"]["end"]); sil[q0:] = np.minimum(sil[q0:], np.exp(-np.arange(N - q0) / (0.25 * SR)))   # after "mankind." the music lets go
sil = lp(sil, 30, 1)
room_ = lp(noise(DUR), 260) * 0.012
mus = np.stack([(reverb(music.L * dk * sc, 1.8, 0.22) + reverb(beds.L * dk, 1.2, 0.12)) * sil + room_,
                (reverb(music.R * dk * sc, 1.8, 0.22) + reverb(beds.R * dk, 1.2, 0.12)) * sil + room_[::-1]], axis=1)
mus = np.tanh(mus * 1.1) / np.tanh(1.1)
mus[-int(0.25 * SR):] *= np.linspace(1, 0, int(0.25 * SR))[:, None]
os.makedirs(os.path.join(ROOT, "audio"), exist_ok=True)
for name, x in (("music", mus), ("voice", np.stack([voice.L, voice.R], axis=1))):
    out = os.path.join(ROOT, "audio", name + ".wav")
    sf.write(out, (x / (np.abs(x).max() + 1e-9) * 0.5).astype(np.float32), SR, subtype="FLOAT")
    print("wrote", out)
