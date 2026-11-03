"""Assemble score + SFX + VO into the master mix, sample-accurate.

Music segments come from data/timing.json, effects from data/cues.json:
  {"src": "...", "at": seconds, "gain": dB, "from": s, "to": s, "fadeIn": s, "fadeOut": s,
   "lowpass": {"from": s, "hz": f}, "highpass": hz, "rate": playback-rate, "pan": -1..1}
Writes assets/audio/mix.wav (48 kHz stereo float, loudness-normalised to -14 LUFS / -1 dBTP).

usage: .venv/bin/python tools/mix.py [--no-norm]
"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy import signal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000
_cache = {}


def load(src):
    if src not in _cache:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, src), "-ac", "2", "-ar", str(SR),
                              "-f", "f32le", "-"], capture_output=True, check=True).stdout
        _cache[src] = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()
    return _cache[src]


def ramp(n, kind):
    x = np.linspace(0, 1, max(n, 1), dtype=np.float32)
    return np.sin(x * np.pi / 2) ** 2 if kind == "in" else np.cos(x * np.pi / 2) ** 2


def place(bus, seg):
    x = load(seg["src"])
    a = int(round(seg.get("from", 0) * SR))
    b = int(round(seg["to"] * SR)) if "to" in seg else len(x)
    y = x[a:b].copy()
    if seg.get("rate", 1) != 1:
        n = int(len(y) / seg["rate"])
        y = signal.resample(y, n, axis=0).astype(np.float32)
    if "highpass" in seg:
        y = signal.sosfiltfilt(signal.butter(2, seg["highpass"], "high", fs=SR, output="sos"), y, axis=0).astype(np.float32)
    if "lowpass" in seg:
        lp = seg["lowpass"]
        f = signal.sosfiltfilt(signal.butter(4, lp["hz"], "low", fs=SR, output="sos"), y, axis=0).astype(np.float32)
        k0 = int(lp.get("from", 0) * SR)
        k1 = k0 + int(0.06 * SR)
        w = np.zeros(len(y), np.float32)
        w[k0:k1] = np.linspace(0, 1, max(0, min(k1, len(y)) - k0))[: max(0, min(k1, len(y)) - k0)]
        w[k1:] = 1
        y = y * (1 - w[:, None]) + f * w[:, None]
    if seg.get("fadeIn"):
        n = min(len(y), int(seg["fadeIn"] * SR))
        y[:n] *= ramp(n, "in")[:, None]
    if seg.get("fadeOut"):
        n = min(len(y), int(seg["fadeOut"] * SR))
        y[len(y) - n:] *= ramp(n, "out")[:, None]
    pan = seg.get("pan", 0)
    if pan:
        y[:, 0] *= np.sqrt((1 - pan) / 2) * np.sqrt(2)
        y[:, 1] *= np.sqrt((1 + pan) / 2) * np.sqrt(2)
    y *= 10 ** (seg.get("gain", 0) / 20)
    s = int(round(seg["at"] * SR))
    if s < 0:
        y, s = y[-s:], 0
    e = min(len(bus), s + len(y))
    bus[s:e] += y[: e - s]


def main():
    timing = json.load(open(os.path.join(ROOT, "data/timing.json")))
    cues_path = os.path.join(ROOT, "data/cues.json")
    cues = json.load(open(cues_path)) if os.path.exists(cues_path) else []
    n = int(timing["duration"] * SR)
    music = np.zeros((n, 2), np.float32)
    fx = np.zeros((n, 2), np.float32)
    for seg in timing["music"]:
        place(music, seg)
    for c in cues:
        if c.get("off"):
            continue
        place(fx, c)
    mix = music + fx
    out = os.path.join(ROOT, "assets/audio")
    os.makedirs(out, exist_ok=True)
    raw = os.path.join(out, "mix-raw.wav")
    import soundfile as sf
    sf.write(raw, mix, SR, subtype="FLOAT")
    sf.write(os.path.join(out, "stem-music.wav"), music, SR, subtype="FLOAT")
    sf.write(os.path.join(out, "stem-fx.wav"), fx, SR, subtype="FLOAT")
    final = os.path.join(out, "mix.wav")
    if "--no-norm" in sys.argv:
        os.replace(raw, final)
        return
    # static gain to -14 LUFS, then a look-ahead brickwall at -1.5 dBFS (oversampled so true peak stays under -1)
    def integrated(path, pre=""):
        err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", pre + "ebur128=peak=true", "-f", "null", "-"],
                             capture_output=True, text=True).stderr
        tail = err[err.rindex("Summary:"):]
        i = float(tail.split("I:")[1].split("LUFS")[0])
        tp = float(tail.split("Peak:")[1].split("dBFS")[0])
        return i, tp

    i_in, tp_in = integrated(raw)
    gain = -14.0 - i_in
    for _ in range(3):
        af = (f"volume={gain:.3f}dB,aresample=192000,alimiter=limit=0.8414:attack=1:release=80:level=false,"
              f"aresample={SR}")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", af, "-c:a", "pcm_s24le", final], check=True)
        i_out, tp_out = integrated(final)
        if abs(i_out + 14.0) < 0.15:
            break
        gain += -14.0 - i_out
    print(f"mix: in {i_in:.2f} LUFS tp {tp_in:.2f} -> out {i_out:.2f} LUFS tp {tp_out:.2f} ({final})")


main()
