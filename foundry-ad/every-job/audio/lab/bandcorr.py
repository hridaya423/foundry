# /// script
# dependencies = ["numpy", "scipy", "soundfile"]
# ///
"""Correlation of sfx vs bed inside one band and window (negative = the two cancel there).
usage: uv run audio/lab/bandcorr.py T0 T1 LO HI"""
import sys
import numpy as np, soundfile as sf
from scipy import signal
SR = 48000
st = {k: sf.read(f"audio/stems/{k}.wav")[0].mean(axis=1) for k in ("music", "voice", "sfx")}
t0, t1, lo, hi = map(float, sys.argv[1:5])
sos = signal.butter(4, [lo, hi], "bandpass", fs=SR, output="sos")
a, b = int(t0 * SR), int(t1 * SR)
s = signal.sosfilt(sos, st["sfx"])[a:b]; m = signal.sosfilt(sos, st["music"] + st["voice"])[a:b]
print(f"corr {np.corrcoef(s, m)[0, 1]:+.3f}  sfx/bed {20 * np.log10(np.std(s) / np.std(m)):+.2f} dB")
