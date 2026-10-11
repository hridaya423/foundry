#!/usr/bin/env python3
"""The music and voice stems for "Every job.": the score (an ElevenLabs take, tools/music.py, edited to picture here:
the valley cut out of it, the drop put on the enter, its own ending crested on "mankind"), the 1860 phonautograph,
the roar beds, and Armstrong. Every sound effect lives in tools/cues.py (real recordings, placed by
sound-layer/scripts/mix.py), so nothing here is a hit, a click or a whoosh.

usage: uv run tools/score.py                      -> audio/music.wav, audio/voice.wav (48 kHz stereo float)
       uv run tools/score.py preview TAKE END SKIP -> audio/music/preview-TAKE-END.wav (the edited score alone)
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

# ------------------------------------------------------------------ the score, edited to picture
# chosen by ear from audio/lab/musictakes.py's shortlist; SKIP is how far into its ending the leap starts, so the
# ending's crest lands on "mankind"
TAKE, END, SKIP = "take-16", "end-16-3", 1.6
if len(sys.argv) > 1 and sys.argv[1] == "preview":
    TAKE, END, SKIP = sys.argv[2], sys.argv[3], float(sys.argv[4])

def stereo(name):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, "audio", "music", name + ".mp3"), "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64).reshape(-1, 2)

def score():
    take, end = stereo(TAKE), stereo(END)
    LEAP, STALL, MC = dict(TM["music"])["leap"], TM["stall"], TM["meltCmd"]
    out = np.zeros((N, 2))
    out[:t2i(STALL)] = take[:t2i(STALL)]
    # the valley: the music tape-stops at the stall (speed falls to nothing over 0.45 s), then only a ringing in the ears
    n = int(0.45 * SR); pos = t2i(STALL) + np.cumsum(np.linspace(1, 0, n) ** 1.6)
    stop = np.stack([np.interp(pos, np.arange(len(take)), take[:, c]) for c in (0, 1)], axis=1) * np.linspace(1, 0, n)[:, None] ** 0.5
    out[t2i(STALL):t2i(STALL) + n] = stop
    ring = sine(3950, MC - STALL - 0.2) * 0.012 * adsr(MC - STALL - 0.2, 0.35, 0.0)
    out[t2i(STALL + 0.2):t2i(STALL + 0.2) + len(ring)] += ring[:, None] * [1, 0.85]                  # cut dead by the drop
    # the drop: the take's own downbeat (its biggest 100 ms energy rise near the planned drop, then the sharpest
    # attack inside that rise), put on the enter
    h = SR // 200; e = np.log(np.add.reduceat(take.mean(1) ** 2, np.arange(0, len(take), h)) + 1e-9)
    a_, b_ = int((MC - 0.3) * 200), int((MC + 1.4) * 200)
    i_ = a_ + int(np.argmax(e[a_ + 20:b_ + 20] - e[a_:b_]))
    DROP = (i_ + int(np.argmax(np.diff(e[i_:i_ + 21])))) / 200 - 0.004
    print(f"{TAKE}: drop found at {DROP:.3f} s, moved to {MC}")
    d = take[t2i(DROP):t2i(DROP) + t2i(LEAP - MC) + t2i(0.3)].copy(); d[:96] *= np.linspace(0, 1, 96)[:, None]
    out[t2i(MC):t2i(MC) + len(d)] += d[:N - t2i(MC)]
    # the leap: the ending, in the take's voice, crossfaded in over a quarter second
    xf = t2i(0.3); i0 = t2i(LEAP)
    out[i0:i0 + xf] *= np.linspace(1, 0, xf)[:, None]; out[i0 + xf:] = 0
    e = end[t2i(SKIP):][:N - i0].copy(); e[:xf] *= np.linspace(0, 1, xf)[:, None]
    out[i0:i0 + len(e)] += e
    # fader rides (dB re the drop), slow enough never to pump: the weight climbs into the stall (the take holds back
    # too long), the build climbs into the hush (it dips under the first kills and fades after its peak), and the
    # hush is quiet strings under Armstrong rather than a hole
    w = t2i(0.4); p = np.convolve(out[:, 0] ** 2 + out[:, 1] ** 2, np.ones(w) / w, "same")
    ref = 10 * np.log10(p[t2i(MC):t2i(MC + 0.5)].max() + 1e-12)
    g = np.zeros(N)
    for t0, t1, d0, d1, cap in ((3.0, STALL, -15, -13, 9), (dict(TM["music"])["build"], LEAP - 0.25, -9, -2, 9), (LEAP + 0.35, TM["vo"]["b"], -17, -17, 20)):
        a, b = t2i(t0), t2i(t1)
        g[a:b] = np.clip(np.linspace(d0, d1, b - a) - (10 * np.log10(p[a:b] + 1e-12) - ref), -6, cap)
    g[t2i(5.2):t2i(5.55)] = np.minimum(g[t2i(5.2):t2i(5.55)], 0)                                   # a pocket for the pull-back's whoosh
    g = lp(lp(g, 4, 1)[::-1], 4, 1)[::-1]                                                               # zero-phase
    g[t2i(STALL):t2i(MC)] = np.minimum(g[t2i(STALL):t2i(MC)], 0)                                   # never lift the valley
    out *= 10 ** (g / 20)[:, None]
    f = t2i(0.4); out[-f:] *= np.linspace(1, 0, f)[:, None]
    return out

SCORE = score()
if len(sys.argv) > 1 and sys.argv[1] == "preview":
    p = os.path.join(ROOT, "audio", "music", f"preview-{TAKE}-{END}.wav")
    sf.write(p, (SCORE / np.abs(SCORE).max() * 0.7).astype(np.float32), SR); print("wrote", p); sys.exit()
music.L += SCORE[:, 0]; music.R += SCORE[:, 1]

# the 1860 voice, faint, under the first strikes; the room
room = lp(noise(DUR), 300) * 0.015
music.add(room * adsr(DUR, 0.05, 0.6), 0.0, width=0.02)
music.add(norm(bp(cut(PHONO_SRC, 3.70, 1.4, 0.01, 0.4), 250, 3200), 0.05), 0.0)
MELT0, CAST = TM["meltCmd"], TM["cast"]                          # the drop is the enter: the fire catches on it
K = TM["kills"]
KK = {k["kind"]: k for k in K}

# ------------------------------------------------------------------ the beds: continuous roars are scenery, not events, so they live
# under the sound effects at a level set against the kill groove (real recordings cut by tools/sources.sh)
def own(name):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, "audio", "own", name + ".wav"), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)
s0, s1 = t2i(TM["settle"]), t2i(KK["translate"]["flash"])
GROOVE_RMS = np.sqrt(np.mean(music.L[s0:s1] ** 2))                # the score under the kills: what the beds sit against
def bed(name, t, db, ramp_db=0.0, pan=0.0):
    x = own(name); x = x / (np.sqrt(np.mean(x ** 2)) + 1e-12) * GROOVE_RMS * 10 ** (db / 20)
    beds.add(x * 10 ** (np.linspace(ramp_db, 0, len(x)) / 20), t, pan=pan, width=0.015)
IGN = TM["words1"][-1][1]
# a hero hit is levelled against what sustains under it (mix.py), so each roar is at full on its hit
bed("shuttle-roar", IGN, -1.0)                                   # the Saturn V lights; stops dead on the Act II cut
bed("train", KK["download"]["enter"] + 0.02, -6.0)               # the Lumiere train, out of the bar

# ---- the wall of sets, one event per set. The grid and the delays are the picture's (js/gl.js, js/film.js): set (i, j)
# is the tile i across, j down from ours (j < 0 is up the wall, which tilts away); the camera holds at zoom 0.15 on
# the plate centre, so about 14 x 12 sets are in frame. Nearer = louder, brighter, earlier; pan = the set's x on screen.
def h21(x, y):
    px, py = (x * 123.34) % 1, (y * 456.21) % 1
    d = px * (px + 45.32) + py * (py + 45.32); px += d; py += d
    return (px * py) % 1
WALL = [(i, j) for j in range(-6, 6) for i in range(-7, 7)]
BOXX, BOXW, ZOOM = 0.30, 0.52, 0.15
def set_pan(i): return float(np.clip(((BOXX + (i + 0.5) * BOXW) - 0.5) * ZOOM * 2.0, -0.95, 0.95))
def set_dist(i, j): return np.hypot(i, j * (1.25 if j < 0 else 1.0))       # up the wall is farther away
def stereo_add(x, t, gain, pan):
    i = t2i(t)
    if i >= N or gain <= 0: return
    x = x[: N - i] * gain; th = (pan + 1) * np.pi / 4
    beds.L[i:i + len(x)] += x * np.cos(th) * np.sqrt(2); beds.R[i:i + len(x)] += x * np.sin(th) * np.sqrt(2)
def unit(name): x = own(name); return x / (np.abs(x).max() + 1e-12)
def shift(x, semis):                                             # varispeed: pitch and length together, like a tape
    r = 2 ** (semis / 12); return np.interp(np.arange(int(len(x) / r)) * r, np.arange(len(x)), x)
def far(x, d):                                                   # distance: air takes the top off
    return lp(x, float(np.clip(14000 / (1 + 0.9 * d), 900, 14000)), 2) if d > 0.5 else x
vr = np.random.default_rng(11)                                   # its own stream: the score's rng stays as it was
STALL = TM["stall"]

# the stall: every set dies like a CRT losing power (gl.js: pd = (since stall - min(|cell|, 16) * 0.011 - h21(cell +
# 4.3) * 0.05) / 0.2: the raster collapses to a line by pd 0.3, the line to a dot by 0.62, the dot is gone by 1.0).
# Each death: the relay thunk, the static of the raster cut dead as it collapses, and the deflection whine falling
# from ~10 kHz to nothing with the dot. Ours is right in front of the lens; the wall behind it is a ripple outward.
TVOFF = [unit(f"tvoff-{k}") for k in (1, 2, 3, 4)]
def power_down(d, k):
    n = t2i(0.6); y = TVOFF[k % 4][:n].copy(); y = np.pad(y, (0, max(0, n - len(y))))
    lo = lp(y, 260, 2) * np.exp(-np.arange(n) / (0.12 * SR))                         # the thunk, and the cabinet
    gate = np.ones(n); a = t2i(0.06 + 0.01 * vr.random()); gate[a:] = 0.0; gate[a - 96:a] = np.linspace(1, 0, 96)
    hi = hp(y, 260, 2) * gate                                                         # static: cut dead when the raster goes
    T = 0.2 * (1 + 0.15 * vr.standard_normal()); tw = tt(T)
    f = (9000 + 2500 * vr.random()) * (300 / 9500) ** ((tw / T) ** 0.7)               # the whine collapses with the dot
    wh = (sine(f, T) + 0.25 * sine(2 * f, T)) * np.minimum(1, tw / 0.01) * (1 - tw / T) ** 1.5
    wh = np.pad(wh, (0, n - len(wh)))
    x = lo * 1.0 + hi * 0.8 + wh * 0.22 / (1 + d) ** 0.7                              # far whines blur into the ripple
    return far(x, d)
PD0 = {c: min(np.hypot(*c), 16) * 0.011 + h21(c[0] + 4.3, c[1] + 4.3) * 0.05 for c in WALL}
# before they die, the sets hum: one set's mains buzz and line whine from the Act II cut, straining as the apps pile on
# and the set overheats, then the whole wall's as the camera pulls back (wider, thicker). The stall cuts it with the
# picture, ours first: the silence after it is what makes the valley a valley
def buzz(d, f0=59.94):
    tw = tt(d); ph = 2 * np.pi * f0 * tw * (1 + 0.002 * np.sin(2 * np.pi * 0.3 * tw))
    x = np.abs(np.sin(ph)) - 2 / np.pi                                                # rectified: the transformer's 120 Hz buzz
    x = bp(x, 600, 3500, 2) + 0.15 * bp(noise(d), 1500, 6000, 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 7.3 * tw) ** 2)
    return x + 0.05 * sine(15734 / 2, d)                                              # the line whine, an octave down (audible)
A2, H0, W0, W1 = TM["act2"], TM["heat0"], TM["wall"][0], TM["wall"][1]
HUM_DB = -4.0                                                    # re the score under the kills
hd = STALL - A2 + 0.3
hum_db = np.interp(tt(hd) + A2, [A2, A2 + 0.2, H0, W0, W1, STALL], [-40, -16, -13, -9, -6, -6])
hum_off = np.clip((STALL + PD0[(0, 0)] + 0.06 - (tt(hd) + A2)) / 0.06, 0, 1)         # dies with ours, then the wall
for k, (pan, f0) in enumerate([(0.0, 59.94), (-0.7, 59.91), (0.7, 59.97)]):            # ours, then the wall either side
    wall_in = 1.0 if k == 0 else np.clip((tt(hd) + A2 - W0) / (W1 - W0), 0, 1)
    off = hum_off if k == 0 else np.clip((STALL + 0.14 - (tt(hd) + A2)) / 0.1, 0, 1)
    stereo_add(buzz(hd, f0) * 10 ** (hum_db / 20) * wall_in * off * (1.0 if k == 0 else 0.6), A2, GROOVE_RMS * 10 ** (HUM_DB / 20), pan)
POWER = 1.5                                                      # the wall dying, re the score under the kills
for n_, c in enumerate(sorted(WALL, key=lambda c: PD0[c])):
    d = set_dist(*c)
    g = 10 ** (2.0 / 20) if d == 0 else 0.42 / (1 + 0.55 * d) ** 1.3                 # ours alone carries the moment
    stereo_add(power_down(d, n_), STALL + PD0[c] + 0.012 * d, g * GROOVE_RMS * POWER, set_pan(c[0]) * (0.6 if d == 0 else 1))

# the drop: the ignition wave races outward from ours (film.js ignAt: ours on the enter, set (i, j) after
# h21(i + 1.7, j + 1.7) * 0.25 + hypot(i, j) * 0.07, burning through over 0.35 s); each screen bursts as the fire takes
# it (glass and an electrical crack), a little after its light, darker and later with distance. Ours is the melt hit.
IMPL = [hp(unit(f"implode-{k}"), 350, 2) for k in (1, 2, 3, 4)]   # glass and crack: the roar carries the low end
BURST = 0.11                                                     # into the burn, the tube lets go
def ign_at(i, j): return 0.0 if (i, j) == (0, 0) else h21(i + 1.7, j + 1.7) * 0.25 + np.hypot(i, j) * 0.07
for n_, c in enumerate(sorted(WALL, key=lambda c: ign_at(*c))):
    if c == (0, 0): continue
    d = set_dist(*c)
    x = far(shift(IMPL[n_ % 4], 2.5 * vr.standard_normal() - 0.6 * d), d)
    g = 0.9 / (1 + 0.5 * d) ** 1.4
    stereo_add(x, MELT0 + ign_at(*c) + BURST + 0.006 * d, g * GROOVE_RMS * 2.2, set_pan(c[0]))

# the roar: the fire's sound reaches us after its light (ROAR_LAG), swells, fills the room wide; as the river forms it
# narrows to the middle and focuses into one pour that builds into the slam, and stops dead with the cast
ROAR_LAG, RIV0, RIV1 = 0.22, TM["river"][0], TM["river"][1]
def lev(name): x = own(name); return x / (np.sqrt(np.mean(x ** 2)) + 1e-12) * GROOVE_RMS
R0, P0 = MELT0 + ROAR_LAG, RIV0 - 0.15
def layer(parts):                                                # [(mono, t, gain L, gain R)] -> stereo
    out = np.zeros((N, 2))
    for x, t, l, r in parts:
        i = t2i(t); x = x[: N - i]; out[i:i + len(x), 0] += x * l; out[i:i + len(x), 1] += x * r
    return out
v, fu, p1, p2 = lev("volcano"), lev("furnace"), lev("pour-1"), lev("pour-2")
FIRE = layer([(v, R0, 1.0, 0.0), (v[t2i(0.37):], R0, 0.0, 1.0),                   # a wall of fire: two stretches of the
              (fu, R0 + 0.05, 0.6, 0.0), (fu[t2i(0.21):], R0 + 0.05, 0.0, 0.6)])   # same fire, one each side, so it is wide
POUR = layer([(p1, P0, 0.7, 0.7), (p2, P0, 0.45, 0.45)])                           # one stream, in the middle
tg = np.arange(N) / SR
swell = np.clip((tg - R0) / 0.35, 0, 1) ** 0.8                                     # arrives, swells
fire_db = -3.0 * swell - 16 * (1 - swell) - 6.0 * np.clip((tg - RIV0) / (CAST - RIV0), 0, 1)  # gives way to the pour
pour_db = -14 + 17.0 * np.clip((tg - P0) / (CAST - P0), 0, 1) ** 1.6                          # builds into the slam
R = FIRE * (10 ** (fire_db / 20) * (tg >= R0))[:, None] + POUR * (10 ** (pour_db / 20) * (tg >= P0))[:, None]
width = 1 - np.clip((tg - RIV0) / (RIV1 - 0.25 - RIV0), 0, 1) ** 1.2                # wide -> mono as the river forms
M_, S_ = (R[:, 0] + R[:, 1]) / 2, (R[:, 0] - R[:, 1]) / 2 * width
stop = np.ones(N); c0 = t2i(CAST + 0.12); stop[c0:] = 0; stop[c0 - t2i(0.04):c0] = np.linspace(1, 0, t2i(0.04))   # full through the slam's window
beds.L += (M_ + S_) * stop * 10 ** (1.0 / 20); beds.R += (M_ - S_) * stop * 10 ** (1.0 / 20)

# the air of the room: a faint, wide, bright floor under everything (the new score is quiet in Act I and under
# Armstrong, and a sound effect over true digital silence is levelled against nothing: mix.py and qa.py both floor
# the bed at -60 dBFS, so small sounds there came out inaudible). It dies with the sets at the stall and comes back
# with the fire; the valley is true silence
def pink(n):
    f = np.fft.rfftfreq(n, 1 / SR); s = np.fft.rfft(vr.standard_normal(n)) / np.sqrt(np.maximum(f, 20))
    return np.fft.irfft(s, n)
AIR_DB = -38.0                                                   # re the score under the kills
air = [lp(hp(pink(N), 900, 2), 13000, 2) for _ in (0, 1)]
air = [a / np.sqrt(np.mean(a ** 2)) * GROOVE_RMS * 10 ** (AIR_DB / 20) for a in air]
ag = np.ones(N); a0, a1 = t2i(STALL + 0.05), t2i(STALL + 0.35); ag[a0:a1] = np.linspace(1, 0, a1 - a0); ag[a1:t2i(MELT0)] = 0
beds.L += air[0] * ag; beds.R += air[1] * ag
if os.environ.get("BEDS_DEBUG"):                                 # score and beds apart, for audio/lab/beds.py
    np.savez(os.path.join(ROOT, "audio", "lab", "beds-debug.npz"), music=np.stack([music.L, music.R], 1), beds=np.stack([beds.L, beds.R], 1))

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
def duck_curve(floor):
    g = np.ones(N)
    for c in TM["kills"]:  # the world waits while a command is typed
        a_, b_ = t2i(c["t0"] - 0.1), t2i(c["enter"])
        g[a_:b_] = np.minimum(g[a_:b_], np.linspace(1, floor, b_ - a_) ** 0.5)
    return lp(g, 40, 1)

# the score only leans back while a kill is typed (the build must keep building); the roars wait properly
dm, db_ = duck_curve(0.75), duck_curve(0.45)
room_ = lp(noise(DUR), 260) * 0.012 * np.where(np.arange(N) < t2i(TM["stall"] + 0.3), 1.0, 0.0)[:]   # the room dies with the stall
room_ = lp(room_, 20, 1) + lp(noise(DUR), 260) * 0.012 * (np.arange(N) >= t2i(TM["meltCmd"]))
mus = np.stack([music.L * dm + reverb(beds.L * db_, 1.2, 0.12) + room_,
                music.R * dm + reverb(beds.R * db_, 1.2, 0.12) + room_[::-1]], axis=1)
mus = np.tanh(mus * 1.1) / np.tanh(1.1)
mus[-int(0.25 * SR):] *= np.linspace(1, 0, int(0.25 * SR))[:, None]
os.makedirs(os.path.join(ROOT, "audio"), exist_ok=True)
for name, x in (("music", mus), ("voice", np.stack([voice.L, voice.R], axis=1))):
    out = os.path.join(ROOT, "audio", name + ".wav")
    sf.write(out, (x / (np.abs(x).max() + 1e-9) * 0.5).astype(np.float32), SR, subtype="FLOAT")
    print("wrote", out)
