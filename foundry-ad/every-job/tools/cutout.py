#!/usr/bin/env python3
"""Key the Muybridge horse + rider out of each gallop frame: dark silhouette, minus grid lines and numerals.
Writes assets/seq/horse/NNN.png (white silhouette, alpha = matte) next to the gallop sequence."""
import os, glob
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "seq", "gallop")
OUT = os.path.join(ROOT, "assets", "seq", "horse")
os.makedirs(OUT, exist_ok=True)

for f in sorted(glob.glob(os.path.join(SRC, "*.jpg"))):
    a = np.asarray(Image.open(f).convert("L")).astype(np.float32) / 255
    dark = a < 0.42
    h, w = a.shape
    inner = np.zeros_like(dark)
    inner[int(h * 0.15):int(h * 0.785), int(w * 0.075):int(w * 0.965)] = True
    dark &= inner
    # opening removes the thin grid lines and numerals, then grow back to the true silhouette edge
    core = ndimage.binary_opening(dark, structure=np.ones((7, 7)))
    lab, n = ndimage.label(core)
    if n == 0:
        continue
    sizes = ndimage.sum(core, lab, range(1, n + 1))
    keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 0.012 * sizes.max()])
    grown = ndimage.binary_dilation(keep, iterations=6) & dark
    grown = ndimage.binary_opening(grown, structure=np.ones((3, 3))) | keep
    grown = ndimage.binary_closing(grown, structure=np.ones((17, 5)))  # reconnect the rider's head (thin neck)
    # soft matte from the luminance inside a slightly grown region
    region = ndimage.binary_dilation(grown, iterations=2)
    matte = np.maximum(np.clip((0.55 - a) / 0.25, 0, 1), grown * 0.92) * region
    m = Image.fromarray((matte * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    rgba = Image.new("RGBA", m.size, (255, 255, 255, 0))
    rgba.putalpha(m)
    rgba.save(os.path.join(OUT, os.path.basename(f).replace(".jpg", ".png")))
print("done", len(os.listdir(OUT)))
