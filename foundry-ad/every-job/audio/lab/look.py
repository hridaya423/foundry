# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Compare stills from tools/shots.sh: black level (2nd percentile luma), highlights (98th), how much of the frame
glows hot (warm and bright), how much of that heat keeps colour instead of clipping to white, and depth falloff
(top third vs middle third luma, for the wall). usage: uv run audio/lab/look.py DIR [DIR ...]"""
import glob, os, sys
import numpy as np
from PIL import Image

dirs = sys.argv[1:]
names = sorted({os.path.basename(p) for d in dirs for p in glob.glob(f"{d}/t*.png")}, key=lambda s: float(s[1:-4]))
print("time    " + "  ".join(f"{os.path.basename(d):>38s}" for d in dirs))
print("        " + "  ".join(f"{'black':>6s} {'high':>5s} {'hot%':>6s} {'hue-kept':>8s} {'top/mid':>7s}" for _ in dirs))
for n in names:
    row = []
    for d in dirs:
        p = f"{d}/{n}"
        if not os.path.exists(p): row.append(" " * 38); continue
        x = np.asarray(Image.open(p).convert("RGB"), np.float32) / 255
        y = x @ np.array([.2126, .7152, .0722], np.float32)
        hot = (x[..., 0] > 0.6) & (x[..., 0] - x[..., 2] > 0.25)
        kept = (hot & (x[..., 2] < 0.85)).sum() / max(1, hot.sum())
        h = y.shape[0] // 3
        row.append(f"{np.percentile(y, 2):6.3f} {np.percentile(y, 98):5.2f} {hot.mean() * 100:6.2f} {kept:8.2f} {y[:h].mean() / max(1e-3, y[h:2 * h].mean()):7.2f}")
    print(f"{n[1:-4]:>6s}  " + "  ".join(row))
