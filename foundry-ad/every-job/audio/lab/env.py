# /// script
# dependencies = ["numpy", "soundfile"]
# ///
"""The sfx stem's 2 ms envelope (what qa.py syncs on) around a time, every 5 ms. usage: uv run audio/lab/env.py T [SPAN]"""
import sys
import numpy as np, soundfile as sf
SR = 48000
x = sf.read("audio/stems/sfx.wav")[0].mean(axis=1)
t, span = float(sys.argv[1]), float(sys.argv[2]) if len(sys.argv) > 2 else 0.1
n = int(0.002 * SR); env = np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same"))
a, b = int((t - span) * SR), int((t + span) * SR); top = env[a:b].max()
for i in range(a, b, int(0.005 * SR)):
    v = env[i:i + int(0.005 * SR)].max()
    print(f"{i / SR:7.3f} {20 * np.log10(v / top + 1e-12):6.1f} {'#' * int(max(0, 40 + 20 * np.log10(v / top + 1e-12)))}")
