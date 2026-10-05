#!/usr/bin/env python3
"""The score for "Humanity did the hard part.", built from the century's own sounds (anvil, typewriter, projector,
hooves, a steam whistle, the 1860 phonautograph, Armstrong) plus a little synthesis, placed to the frame by timing.py.

usage: ../.venv/bin/python tools/score.py        -> assets/audio/mix.wav (48 kHz stereo)
"""
import os, subprocess
import numpy as np
from scipy import signal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR, BPM = 48000, 120
BEAT = 60 / BPM
rng = np.random.default_rng(7)

# ------------------------------------------------------------------ edit cues (tools/timing.py is the source of truth)
import sys
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
def note(n): return 440 * 2 ** ((n - 69) / 12)
def sweep_lp(x, f0, f1):  # time-varying one-pole lowpass, frequency swept exponentially
    f = f0 * (f1 / f0) ** np.linspace(0, 1, len(x))
    a = np.exp(-2 * np.pi * f / SR); y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a[i]) * x[i] + a[i] * s; y[i] = s
    return y


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


music, sfx, voice = Bus(), Bus(), Bus()


# ------------------------------------------------------------------ instruments
def kick(gain=1.0):
    d = 0.5; f = 46 + 110 * np.exp(-tt(d) / 0.035)
    body = sine(f, d) * env_exp(d, 0.16)
    click = hp(noise(0.012), 2500) * np.linspace(1, 0, int(0.012 * SR)) * 0.4
    body[: len(click)] += click
    return np.tanh(body * 1.6) * gain

def boom(d=2.2):
    f = 38 + 60 * np.exp(-tt(d) / 0.08)
    x = sine(f, d) * env_exp(d, 0.7)
    x += lp(noise(d), 180) * env_exp(d, 0.25) * 0.9
    return np.tanh(x * 1.8)

def hat(d=0.05, bright=8000):
    return hp(noise(d), bright, 4) * env_exp(d, d / 4)

def clap():
    d = 0.25; x = np.zeros(int(d * SR))
    for k, o in enumerate([0, 0.009, 0.018, 0.028]):
        b = bp(noise(0.2), 900, 4000) * env_exp(0.2, 0.012 if k < 3 else 0.06)
        x[int(o * SR): int(o * SR) + len(b)] += b[: len(x) - int(o * SR)]
    return x * 0.8

def pluck(n, d=0.45, cutoff=5000):
    f = note(n); x = saw(f, d) * 0.6 + saw(f * 1.005, d) * 0.4
    return sweep_lp(x, cutoff, 300) * env_exp(d, 0.14)

def pad(notes, d, cutoff=1800, attack=0.4):
    x = np.zeros(int(d * SR))
    for n in notes:
        for det in (-0.08, 0.0, 0.07):
            x += saw(note(n + det), d, phase=rng.random()) / 3
    return lp(x / len(notes), cutoff, 2) * adsr(d, attack, min(0.6, d * 0.4))

def bass_note(n, d):
    f = note(n); x = saw(f, d) * 0.7 + sine(f / 2, d) * 0.6
    return np.tanh(lp(x, 420, 2) * 1.5) * adsr(d, 0.004, 0.03)

def click_key():
    d = 0.03; x = hp(noise(d), 2200, 2) * env_exp(d, 0.004)
    x += sine(2600 + rng.random() * 900, d) * env_exp(d, 0.003) * 0.3
    return x

def enter_hit():
    d = 0.35; x = hp(noise(0.02), 1500) * np.linspace(1, 0, int(0.02 * SR))
    x = np.pad(x, (0, int(d * SR) - len(x)))
    x += sine(90 * np.exp(-tt(d) / 0.08) + 50, d) * env_exp(d, 0.09) * 0.9
    return x

def whoosh(d=0.5, lo=300, hi=6000, up=True):
    x = noise(d); n = len(x)
    f = np.geomspace(lo, hi, n) if up else np.geomspace(hi, lo, n)
    y = np.zeros(n); seg = 1200
    for i in range(0, n, seg):  # piecewise bandpass sweep
        fc = f[min(n - 1, i + seg // 2)]
        y[i:i + seg] = bp(x[max(0, i - 2000): i + seg], fc * 0.7, min(fc * 1.4, SR / 2 - 100))[-len(x[i:i + seg]):]
    return y * np.sin(np.linspace(0, np.pi, n)) ** 2

def riser(d):
    t = tt(d); f = 200 * (12 ** (t / d))
    x = saw(f, d) * 0.25 + whoosh(d, 400, 12000) * 0.8
    return x * (t / d) ** 2

def bell(f, d=1.2, tau=0.4):
    x = np.zeros(int(d * SR))
    for r, a in [(1, 1), (2.76, 0.4), (5.4, 0.25), (8.93, 0.12)]:
        x += sine(f * r, d) * a * env_exp(d, tau / r ** 0.5)
    return x

def hoof():
    d = 0.12; return lp(noise(d), 500) * env_exp(d, 0.02) * 1.4 + sine(70, d) * env_exp(d, 0.03)

def roar(d, cutoff=700):
    b = np.cumsum(noise(d)); b -= signal.savgol_filter(b, 2001, 1) if len(b) > 2001 else b.mean()
    x = lp(b / (np.abs(b).max() + 1e-9), cutoff, 2)
    mod = 1 + 0.25 * np.sin(2 * np.pi * 3.1 * tt(d)) * np.sin(2 * np.pi * 0.7 * tt(d))
    return x * mod

def crackle(d, rate=60):
    x = np.zeros(int(d * SR))
    for _ in range(int(d * rate)):
        i = rng.integers(0, len(x) - 400); a = rng.random() ** 2
        x[i:i + 400] += hp(noise(400 / SR), 1500) * np.exp(-np.arange(400) / 40) * a
    return x



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

def repitch(x, ratio):  # resample: ratio > 1 = higher and shorter
    n = int(len(x) / ratio)
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)

def norm(x, peak=1.0): return x / (np.abs(x).max() + 1e-9) * peak

ANVIL_SRC = load("WWS_Blacksmith8217sanvil.ogg")
TYPE_SRC = load("WWS_Typewriter.ogg")
HORSE_SRC = load("Six_Horses_Galloping_By.ogg")
WHISTLE_SRC = load("WWS_SteamWhistle.ogg")
PROJ_SRC = load("WWS_CinemeccanicaprojectorVictoria9running.ogg")
TELE_SRC = load("WWS_Teleprintertyping.ogg")
PHONO_SRC = load("Au_Clair_de_la_Lune_(1860)_new.ogg")

ANVILS = [norm(cut(ANVIL_SRC, t - 0.004, 1.1)) for t in (63.63, 18.05, 78.95, 31.79)]
KEYS = [norm(cut(TYPE_SRC, t - 0.003, 0.11)) for t in (4.46, 4.88, 7.37, 8.24, 11.13, 14.04, 16.43, 16.78)]

def anvil_hit(k=0, pitch=1.0, sub=0.8):
    a = repitch(ANVILS[k % len(ANVILS)], pitch)
    d = max(len(a) / SR, 0.6)
    body_ = np.zeros(int(d * SR)); body_[: len(a)] += a * 0.8
    body_ += sine(48 + 70 * np.exp(-tt(d) / 0.04), d) * env_exp(d, 0.14) * sub   # weight under the steel
    return body_

def key(k): return KEYS[k % len(KEYS)] * (0.7 + 0.3 * rng.random())

def quindar(f=2525, d=0.25):
    return sine(f, d) * adsr(d, 0.004, 0.01) * 0.22

def reverb(x, secs=1.6, mix=0.25):
    n = int(secs * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * secs / 6.0))
    ir = lp(ir, 6000)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = signal.fftconvolve(x, ir)[: len(x)]
    return x * (1 - mix) + wet * mix

# key: B-flat minor, resolving to B-flat major (the anvil rings ~A#6)
BBM, GB, DB, AB = [58, 61, 65], [54, 58, 61], [61, 65, 68], [56, 60, 63]
ROOTS = [46, 42, 49, 44]

def bar_chord(t):
    k = int(t // 2) % 4
    return [BBM, GB, DB, AB][k], ROOTS[k]

# ------------------------------------------------------------------ the machines, as instruments
def phone_ring(d=0.45):
    t_ = tt(d); x = (sine(1150, d) + sine(1370, d) * 0.7) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 22 * t_)))
    return hp(x, 600) * adsr(d, 0.004, 0.08) * 0.35
def telegraph(pattern=(0, 0.07, 0.2, 0.27)):
    d = 0.45; x = np.zeros(int(d * SR))
    for o in pattern:
        c = bp(noise(0.03), 1800, 5000) * env_exp(0.03, 0.004) + sine(950, 0.03) * env_exp(0.03, 0.006) * 0.6
        x[int(o * SR): int(o * SR) + len(c)] += c
    return x * 0.8
def drawer():
    d = 0.4; return lp(noise(d), 380) * env_exp(d, 0.05) * 1.6 + bp(noise(d), 900, 3000) * env_exp(d, 0.025) * 0.5 + sine(70, d) * env_exp(d, 0.06)
def beeps():
    d = 0.42; x = np.zeros(int(d * SR))
    for k, (o, f) in enumerate([(0, 1320), (0.1, 990), (0.2, 1760), (0.3, 1180)]):
        b = np.sign(sine(f, 0.07)) * adsr(0.07, 0.002, 0.01) * 0.18
        x[int(o * SR): int(o * SR) + len(b)] += b
    return lp(x, 6000)
def propeller(d=0.3):
    t_ = tt(d); x = saw(92, d) * (0.6 + 0.4 * np.sin(2 * np.pi * 31 * t_)); return lp(x, 900) * adsr(d, 0.02, 0.1) * 0.6
def ping(n):
    d = 0.5; f = note(n); x = sine(f, d) * env_exp(d, 0.18) + sine(f * 2, d) * env_exp(d, 0.06) * 0.3
    return x * 0.16
def tick_metal():
    d = 0.08; return bp(noise(d), 3000, 9000) * env_exp(d, 0.006) * 0.5 + sine(4200 + 800 * rng.random(), d) * env_exp(d, 0.01) * 0.2

def typing_burst(n=6, gap=0.07):
    x = np.zeros(int((n * gap + 0.15) * SR))
    for k in range(n):
        y = key(k); i = int(k * gap * SR); x[i:i + len(y)] += y
    return x

# ------------------------------------------------------------------ Act I: a typewriter strike per word, and that word's machine
room = lp(noise(DUR), 300) * 0.015
music.add(room * adsr(DUR, 0.05, 0.6), 0.0, width=0.02)
voice.add(norm(bp(cut(PHONO_SRC, 3.70, 1.4, 0.01, 0.4), 250, 3200), 0.16), 0.0)        # the 1860 voice, faint, under the first strikes
inst = {"typists": lambda: typing_burst(4, 0.06), "operator": phone_ring, "telegraph": telegraph, "console": beeps}
for w, t0, clip in TM["words1"]:
    strike = norm(KEYS[0] + 0, 1.0)
    sfx.add(strike * 1.2, t0, pan=0.0); sfx.add(lp(noise(0.06), 600) * env_exp(0.06, 0.012) * 1.2, t0)  # the type bar hits the platen
    music.add(kick(0.95), t0)
    if clip in inst: sfx.add(inst[clip](), t0 + 0.04, 0.85, pan=-0.3 + 0.6 * rng.random())
ign = TM["words1"][-1][1]
sfx.add(boom(2.2) * 1.0, ign)
r0 = None
def rocket(d):
    b = np.cumsum(noise(d)); b -= signal.savgol_filter(b, 4001, 1); b = b / (np.abs(b).max() + 1e-9)
    cr = np.zeros(int(d * SR))
    for _ in range(int(d * 160)):
        i = rng.integers(0, len(cr) - 800); cr[i:i + 800] += noise(800 / SR) * np.exp(-np.arange(800) / 120) * rng.random() ** 3
    return np.tanh((lp(b, 500, 2) * 2.2 + bp(cr, 400, 5000) * 0.9 + lp(noise(d), 90, 2) * 0.8) * 1.4)
r0 = rocket(TM["act2"] - ign + 0.1); sfx.add(r0 * adsr(len(r0) / SR, 0.02, 0.15) * 0.4, ign, width=0.02)
sfx.add(bell(note(91), 1.2, 0.4) * 0.12, ign + 0.42)                                     # the carriage bell: end of line
music.add(pad([46, 58, 61, 65], TM["act2"], 1500, 0.2) * 0.3, 0.0, width=0.02)

# ------------------------------------------------------------------ Act II: the I-beam, the pings, the noise, the wall
A2 = TM["act2"]
music.add(boom(1.0) * 0.35, A2)
l2 = TM["line2"]
for i in range(len(l2["text"])): sfx.add(key(i) * 0.5, l2["t0"] + i / l2["cps"])
penta = [70, 72, 75, 77, 80, 82, 84, 87, 89, 91]
for k, at in enumerate(TM["appT"]):
    sfx.add(ping(penta[k % len(penta)] + (12 if k > 12 else 0)), at, 1.0 if k < 3 else 0.7, pan=-0.7 + 1.4 * rng.random())
t = A2
while t < TM["meltCmd"] - 0.4:
    music.add(kick(0.7), t); chord, root = bar_chord(t); music.add(bass_note(root - 12, BEAT / 2 - 0.01) * 0.42, t + BEAT / 2); t += BEAT
WALL0, WALL1 = TM["wall"]
music.add(riser(TM["meltCmd"] - TM["heat0"]) * 0.55, TM["heat0"], width=0.012)
sfx.add(hp(noise(TM["meltCmd"] - TM["heat0"]), 2500) * np.linspace(0, 0.08, int((TM["meltCmd"] - TM["heat0"]) * SR)), TM["heat0"], width=0.01)  # the set straining
for k in range(90):                                                                      # the wall: every set pinging at once
    at = WALL0 + 0.15 + (WALL1 - WALL0 + 0.1) * rng.random()
    sfx.add(ping(penta[rng.integers(0, len(penta))] + 12 * rng.integers(0, 2)) * 0.35, at, pan=-0.9 + 1.8 * rng.random())
c0 = TM["cmd0"]
for i in range(len(c0["text"])): sfx.add(key(i + 2) * 0.9, c0["t0"] + i / c0["cps"], pan=-0.2 + 0.4 * rng.random())

# ------------------------------------------------------------------ `melt them down`: three frames of nothing, then fire
MC = TM["meltCmd"]; MELT0 = MC + 0.05
sfx.add(enter_hit() * 0.9, MC)
sfx.add(boom(2.8) * 1.15, MELT0); sfx.add(anvil_hit(0, 0.5, 1.4), MELT0, 0.9)
CAST = TM["cast"]
rr = rocket(CAST + 0.9 - MELT0); sfx.add(rr * adsr(len(rr) / SR, 0.03, 0.6) * 0.55, MELT0, width=0.02)
sfx.add(crackle(1.6, 140) * 0.45, MELT0 + 0.05, width=0.012)
sfx.add(whoosh(1.4, 5000, 140, up=False) * 1.0, TM["river"][0] + 0.2, width=0.012)
music.add(pad([34, 41, 46], CAST - MELT0, 400, 0.4) * 0.22, MELT0)

# ------------------------------------------------------------------ the casting
GLASS = TM["glass"]
sfx.add(boom(1.5) * 0.6, CAST); sfx.add(hp(noise(1.0), 3000) * adsr(1.0, 0.05, 0.5) * 0.14, CAST, width=0.02)
sfx.add(crackle(0.6, 140) * 0.4, CAST + 0.7, width=0.012)
for k in range(10): sfx.add(tick_metal() * 0.5, CAST + 1.0 + k * 0.06 + 0.03 * rng.random(), pan=-0.5 + rng.random())
for k in range(9): sfx.add(bell(note(82 + [0, 2, 5, 7, 9, 12, 14, 17, 19][k]), 0.9, 0.3) * 0.035, GLASS - 0.42 + k * 0.045, pan=-0.6 + 0.15 * k)
sfx.add(bell(note(94), 1.4, 0.5) * 0.06, GLASS); music.add(pad([46, 58, 61, 65], 0.8, 2200, 0.2) * 0.25, GLASS)
l3 = TM["line3"]
for i in range(len(l3["text"])): sfx.add(key(i) * 0.7, l3["t0"] + i / l3["cps"])

# ------------------------------------------------------------------ the kills: ping, burn, one line, the job done
K = TM["kills"]
def groove(t0, t1, g=1.0):
    t = t0
    while t < t1 - 1e-6:
        b = round(t / BEAT); music.add(kick(0.9 * g), t); chord, root = bar_chord(t)
        music.add(bass_note(root - 12, BEAT / 2 - 0.01) * 0.5 * g, t + BEAT / 2)
        for o in (0.125, 0.375): sfx.add(key(b + 1) * 0.18 * g, t + o, pan=-0.3)
        if b % 2 == 1: music.add(clap(), t, 0.28 * g)
        music.add(pluck(chord[b % 3] + 12, 0.3) * 0.13 * g, t, pan=0.35 if b % 2 else -0.35, width=0.012)
        t += BEAT
groove(TM["settle"], K[2]["enter"])
groove(K[3]["flash"], K[5]["end"] - 0.35, 0.8)
for k in K:
    sfx.add(ping(84), k["flash"], 0.9)                                                    # the old app, one last notification
    sfx.add(crackle(0.25, 200) * 0.5, k["enter"] - 0.2, width=0.01)                      # it burns
    for i in range(len(k["text"])): sfx.add(key(i + 3) * 0.75, k["t0"] + i / k["cps"], pan=-0.2 + 0.4 * rng.random())
    if k.get("paste"): sfx.add(key(2) * 0.9, k["pasteAt"]); sfx.add(key(5) * 0.7, k["pasteAt"] + 0.03)
    sfx.add(anvil_hit(1, 1.0, 0.6) * 0.62, k["enter"]); music.add(kick(0.9), k["enter"])
kg, kr, kt, kc, kw, kd = K
sfx.add(cut(HORSE_SRC, 7.0, kr["end"] - kg["enter"], 0.05, 0.3) * 0.7, kg["enter"], pan=-0.1, width=0.01)
sfx.add(whoosh(0.3, 800, 9000) * 0.6, kr["enter"]); sfx.add(whoosh(0.35, 200, 3000) * 0.8, kr["enter"] + 0.42, pan=0.6, width=0.01)
for i in range(22): sfx.add(tick_metal() * 0.6, kc["enter"] + i * 0.016 * (1 + i / 22), pan=-0.4)
for i in range(6): sfx.add(tick_metal() * 0.8 + 0, kw["enter"] + i * 0.07, pan=-0.5 + 0.2 * i)
sfx.add(norm(cut(WHISTLE_SRC, 1.55, 1.0, 0.01, 0.3), 0.55), kd["enter"] + 0.05, width=0.015)
sfx.add(lp(noise(kd["end"] - kd["enter"]), 260) * adsr(kd["end"] - kd["enter"], 0.15, 0.1) * 0.55, kd["enter"], width=0.02)
sfx.add(whoosh(0.4, 300, 7000) * 1.2, kd["end"] - 0.38, width=0.015)
music.add(pad([46, 53, 58, 61], kt["end"] - kt["enter"], 700, 0.5) * 0.18, kt["enter"], width=0.02)
voice.add(quindar(), TM["vo"]["a"] - 0.28)

# ------------------------------------------------------------------ the logo: back through the tiles; "...for mankind." lands on it
LOGO, END_ = TM["logo"], TM["end"]
sfx.add(whoosh(0.85, 6000, 200, up=False) * 0.6, LOGO, width=0.015)
land = TM["vo"]["mankind"]
sfx.add(anvil_hit(0, 0.5, 1.3) * 0.9, land)
music.add(pad([34, 46, 50, 53, 58, 62], END_ - land + 0.2, 2600, 0.05) * 0.5, land - 0.15, width=0.02)
music.add(boom(1.4) * 0.5, land)
for k in range(10):
    sfx.add(bell(note(82 + [0, 2, 4, 7, 9, 12, 14, 16, 19, 21][k]), 1.2, 0.35) * 0.028, land + 0.3 + k * 0.035, pan=-0.6 + 0.13 * k)

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
voice.add(va / pk * 0.92, TM["vo"]["a"]); voice.add(vb / pk * 0.92, TM["vo"]["b"])

# ------------------------------------------------------------------ mix
def duck_curve():
    g = np.ones(N)
    for c in [TM["cmd0"]] + TM["kills"]:  # the world waits while a command is typed
        a_, b_ = t2i(c["t0"] - 0.1), t2i(c["enter"])
        g[a_:b_] = np.minimum(g[a_:b_], np.linspace(1, 0.45, b_ - a_) ** 0.5)
    vo_a = (TM["vo"]["a"], TM["vo"]["a"] + SEG_A[1] - SEG_A[0])
    vo_b = (TM["vo"]["b"], TM["vo"]["mankind"] + 0.95)
    for a0, a1 in (vo_a, vo_b):  # Armstrong owns the room
        a_, b_ = t2i(a0 - 0.12), t2i(a1 + 0.05)
        g[a_:b_] = np.minimum(g[a_:b_], 0.2)
    a_, b_ = t2i(TM["meltCmd"]), t2i(TM["meltCmd"] + 0.05)  # three frames of nothing
    g[a_:b_] = 0.0
    return lp(g, 40, 1)

def sidechain():
    g = np.ones(N)
    for t in list(np.arange(TM["act2"], TM["meltCmd"] - 0.4, BEAT)) + list(np.arange(TM["settle"], TM["kills"][2]["enter"], BEAT)):
        i = t2i(t); n = int(0.2 * SR)
        g[i:i + n] = np.minimum(g[i:i + n], 1 - 0.55 * np.exp(-np.arange(n) / (0.05 * SR)))
    return g

dk, sc = duck_curve(), sidechain()
_a, _b = t2i(TM["vo"]["a"]), t2i(TM["vo"]["a"] + 2.3)
_r = lambda x: 20 * np.log10(np.sqrt(np.mean(x[_a:_b] ** 2)) + 1e-9)
print(f"under Armstrong: voice {_r(voice.L):.1f} dB, music {_r(music.L * dk):.1f} dB, sfx {_r(sfx.L * 0.35):.1f} dB")
vo_gate = np.ones(N)
for a0, a1 in ((TM["vo"]["a"], TM["vo"]["a"] + SEG_A[1] - SEG_A[0]), (TM["vo"]["b"], TM["vo"]["mankind"] + 0.95)):
    vo_gate[t2i(a0 - 0.12):t2i(a1)] = 0.4
vo_gate = lp(vo_gate, 20, 1)
sil = np.ones(N); sil[t2i(TM["meltCmd"]):t2i(TM["meltCmd"] + 0.05)] = 0.0
mL = (reverb(music.L * dk * sc, 1.8, 0.22) + reverb(sfx.L * vo_gate, 1.2, 0.12) * 0.9) * sil + voice.L
mR = (reverb(music.R * dk * sc, 1.8, 0.22) + reverb(sfx.R * vo_gate, 1.2, 0.12) * 0.9) * sil + voice.R
mix = np.stack([mL, mR])
mix = np.tanh(mix * 1.1) / np.tanh(1.1)
mix[:, -int(0.25 * SR):] *= np.linspace(1, 0, int(0.25 * SR))
# loudness: RMS-matched to about -14 LUFS, then a peak ceiling at -1 dBFS
rms = np.sqrt(np.mean(mix ** 2)); mix *= 10 ** (-15 / 20) / (rms + 1e-9)
pk = np.abs(mix).max(); ceil = 10 ** (-2 / 20)
if pk > ceil: mix = np.tanh(mix / ceil) * ceil
os.makedirs(os.path.join(ROOT, "assets", "audio"), exist_ok=True)
out = os.path.join(ROOT, "assets", "audio", "mix.wav")
pcm = (np.clip(mix.T, -1, 1) * 32767).astype(np.int16)
import wave
with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print("wrote", out, f"peak {20*np.log10(np.abs(mix).max()):.1f} dBFS")
