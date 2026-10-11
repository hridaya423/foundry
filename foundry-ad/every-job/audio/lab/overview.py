# /// script
# dependencies = ["numpy", "scipy", "matplotlib"]
# ///
"""Spectrogram + level (dB, cyan) of whole files, to find usable sections by eye.
usage: uv run audio/lab/overview.py out.png FILE [FILE ...]"""
import os, subprocess, sys
import numpy as np
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt

SR = 16000
files = sys.argv[2:]
fig, ax = plt.subplots(len(files), 1, figsize=(16, 1.6 * len(files)), squeeze=False)
for a, f in zip(ax[:, 0], files):
    x = np.frombuffer(subprocess.run(["ffmpeg", "-v", "error", "-i", f, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                                     capture_output=True).stdout, np.float32)
    a.specgram(x, NFFT=1024, Fs=SR, noverlap=512, cmap="magma", vmin=-120); a.set_ylim(0, 8000)
    e = np.sqrt(np.convolve(x ** 2, np.ones(SR // 50) / (SR // 50), mode="same"))[::SR // 100]
    a2 = a.twinx(); a2.plot(np.arange(len(e)) / 100, 20 * np.log10(e + 1e-6), c="cyan", lw=.7); a2.set_ylim(-70, 0)
    step = 0.1 if len(x) / SR < 5 else 1 if len(x) / SR < 30 else 2
    a.set_title(os.path.basename(f), fontsize=8, loc="left"); a.set_xticks(np.arange(0, len(x) / SR, step)); a.tick_params(labelsize=6)
fig.tight_layout(); fig.savefig(sys.argv[1], dpi=70)
