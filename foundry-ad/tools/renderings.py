"""The FORMAT beat: one marble head rendered five ways (photo, 1-bit dither, halftone, pixel, ASCII).

Writes assets/img/format/{photo,dither,halftone,pixel,ascii,cut}.png at 900x1200, plus cut.png (alpha cutout).
usage: .venv/bin/python tools/renderings.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/img/format")
W, H = 900, 1200
INK = (6, 5, 5)
WHITE = (244, 244, 242)


def load():
    src = Image.open(os.path.join(ROOT, "assets/img/bust.jpg")).convert("RGB")
    cut = Image.open(os.path.join(ROOT, "assets/img/bust-cut.png")).convert("RGBA")
    a = np.array(cut)[..., 3]
    ys, xs = np.nonzero(a > 128)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    bh = (ys.max() - ys.min()) * 1.12
    bw = bh * W / H
    box = (int(cx - bw / 2), int(cy - bh / 2), int(cx + bw / 2), int(cy + bh / 2))
    return src.crop(box).resize((W, H), Image.LANCZOS), cut.crop(box).resize((W, H), Image.LANCZOS)


def gray(img):
    g = np.asarray(img.convert("L"), np.float32) / 255
    lo, hi = np.percentile(g, 1), np.percentile(g, 99.5)
    return np.clip((g - lo) / (hi - lo), 0, 1) ** 1.1


def to_img(g):
    g = np.clip(g, 0, 1)[..., None]
    return Image.fromarray((np.array(INK) * (1 - g) + np.array(WHITE) * g).astype(np.uint8))


def atkinson(g, scale=3):
    small = np.array(Image.fromarray((g * 255).astype(np.uint8)).resize((W // scale, H // scale), Image.LANCZOS), np.float32) / 255
    h, w = small.shape
    for y in range(h):
        for x in range(w):
            old = small[y, x]
            new = 1.0 if old > 0.5 else 0.0
            err = (old - new) / 8
            small[y, x] = new
            for dx, dy in ((1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)):
                if 0 <= x + dx < w and 0 <= y + dy < h:
                    small[y + dy, x + dx] += err
    return np.array(Image.fromarray((small * 255).astype(np.uint8)).resize((W, H), Image.NEAREST), np.float32) / 255


def halftone(g, cell=15):
    im = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(im)
    for yi, y in enumerate(range(0, H, cell)):
        for x in range(-cell, W, cell):
            ox = x + (cell / 2 if yi % 2 else 0)
            cx, cy = ox + cell / 2, y + cell / 2
            v = g[min(H - 1, int(cy)), min(W - 1, max(0, int(cx)))]
            r = (v ** 0.9) * cell * 0.62
            if r > 0.4:
                d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE)
    return im


def pixel(g, block=36):
    small = Image.fromarray((g * 255).astype(np.uint8)).resize((W // block, H // block), Image.BOX)
    q = (np.round(np.asarray(small, np.float32) / 255 * 5) / 5)
    return np.array(Image.fromarray((q * 255).astype(np.uint8)).resize((W, H), Image.NEAREST), np.float32) / 255


def ascii_art(g, cw=15, ch=24):
    font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/IBMPlexMono-SemiBold.ttf"), 22)
    ramp = " .:-=+*#%@"
    im = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(im)
    for y in range(0, H, ch):
        for x in range(0, W, cw):
            v = g[min(H - 1, y + ch // 2), min(W - 1, x + cw // 2)]
            c = ramp[min(len(ramp) - 1, int(v ** 1.2 * len(ramp)))]
            if c != " ":
                d.text((x, y), c, font=font, fill=WHITE)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    photo, cut = load()
    g = gray(photo)
    to_img(g).save(os.path.join(OUT, "photo.png"))
    to_img(atkinson(g)).save(os.path.join(OUT, "dither.png"))
    halftone(g).save(os.path.join(OUT, "halftone.png"))
    to_img(pixel(g)).save(os.path.join(OUT, "pixel.png"))
    ascii_art(g).save(os.path.join(OUT, "ascii.png"))
    cg = gray(cut.convert("RGB"))
    rgba = np.dstack([np.asarray(to_img(cg)), np.asarray(cut)[..., 3]])
    Image.fromarray(rgba.astype(np.uint8), "RGBA").save(os.path.join(OUT, "cut.png"))
    print("ok", OUT)


main()
