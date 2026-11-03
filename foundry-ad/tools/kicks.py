"""Detect kick drums (40-120 Hz envelope peaks) and fit a straight beat grid to them.

usage: .venv/bin/python tools/kicks.py <audio> [start_s end_s]
"""
import subprocess
import sys

import numpy as np
from scipy import signal

SR = 44100
path = sys.argv[1]
a = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
b = float(sys.argv[3]) if len(sys.argv) > 3 else 1e9

raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                     capture_output=True, check=True).stdout
x = np.frombuffer(raw, dtype=np.float32)
sos = signal.butter(4, [40, 120], btype="band", fs=SR, output="sos")
env = np.abs(signal.sosfiltfilt(sos, x))
env = signal.sosfiltfilt(signal.butter(2, 25, fs=SR, output="sos"), env)
t = np.arange(len(env)) / SR
sel = (t >= a) & (t < b)
e = env.copy()
e[~sel] = 0
peaks, props = signal.find_peaks(e, distance=int(0.33 * SR), height=0.35 * e.max(), prominence=0.15 * e.max())
# onset = steepest rise before each peak (attack), more stable than the envelope maximum
d = np.diff(e, prepend=0)
onsets = []
for p in peaks:
    w = slice(max(0, p - int(0.06 * SR)), p)
    onsets.append((w.start + int(np.argmax(d[w]))) / SR)
onsets = np.array(onsets)
if len(onsets) > 3:
    period = np.median(np.diff(onsets))
    n = np.round((onsets - onsets[0]) / period)
    A = np.vstack([n, np.ones_like(n)]).T
    period, t0 = np.linalg.lstsq(A, onsets, rcond=None)[0]
    resid = onsets - (t0 + n * period)
    print(f"{path} [{a}-{b}] kicks={len(onsets)} bpm={60 / period:.3f} period={period:.5f} t0={t0:.4f} "
          f"resid_ms mean={1000 * np.abs(resid).mean():.1f} max={1000 * np.abs(resid).max():.1f}")
print("  kicks:", [round(float(o), 3) for o in onsets])
