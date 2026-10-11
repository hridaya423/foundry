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
    # ride the build: the take dips under the first kills and fades after its peak, so a fader climbs it steadily
    # from -9 dB (re the drop) to -2 dB into the hush; within +9/-6 dB and slow enough never to pump
    B0, B1 = t2i(dict(TM["music"])["build"]), t2i(LEAP - 0.25)
    w = t2i(0.4); p = np.convolve(out[:, 0] ** 2 + out[:, 1] ** 2, np.ones(w) / w, "same")
    ref = 10 * np.log10(p[t2i(MC):t2i(MC + 0.5)].max() + 1e-12)
    have = 10 * np.log10(p[B0:B1] + 1e-12) - ref
    gdb = np.clip(np.linspace(-9, -2, B1 - B0) - have, -6, 9)
    g = np.zeros(N); g[B0:B1] = gdb; g[B1:] = gdb[-1] * 0
    g = lp(lp(g, 1.5, 1)[::-1], 1.5, 1)[::-1]                                                           # zero-phase, slow
    out *= 10 ** (g / 20)[:, None]
    # the leap: the ending, in the take's voice, crossfaded in over a quarter second
    xf = t2i(0.3); i0 = t2i(LEAP)
    out[i0:i0 + xf] *= np.linspace(1, 0, xf)[:, None]; out[i0 + xf:] = 0
    e = end[t2i(SKIP):][:N - i0].copy(); e[:xf] *= np.linspace(0, 1, xf)[:, None]
    out[i0:i0 + len(e)] += e
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
