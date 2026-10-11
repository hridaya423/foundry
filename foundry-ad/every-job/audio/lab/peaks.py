# /// script
# dependencies = ["numpy", "soundfile"]
# ///
"""Peak offset (2 ms RMS, the same measure mix.py aligns on), length, and key-stroke onsets of audio files.
usage: uv run audio/lab/peaks.py FILE [FILE ...]"""
import subprocess, sys
import numpy as np

SR = 48000
for f in sys.argv[1:]:
    x = np.frombuffer(subprocess.run(["ffmpeg", "-v", "error", "-i", f, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                                     capture_output=True).stdout, np.float32).astype(np.float64)
    n = int(0.002 * SR); env = np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same"))
    p = int(np.argmax(env)); e = env / (env.max() + 1e-12); hop = int(0.005 * SR)
    on = [round(i * 0.005, 3) for i in range(1, len(e) // hop) if e[i * hop] > 0.3 and e[(i - 1) * hop] <= 0.3]
    print(f"{f.split('/')[-1]:44s} len {len(x) / SR:5.2f}  peak {p / SR:5.3f}  onsets {on[:24]}")
