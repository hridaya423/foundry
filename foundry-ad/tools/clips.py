"""Cut, retime (60 fps) and grade every footage clip the film uses into assets/v/.

Grades
  tube   monochrome archive on a CRT: 4:3, contrast, phosphor halation, beam scanlines, barrel, edge fringe
  flash  full-colour fire, overexposed (a16z flash frames)
  fire   monochrome world, fire kept and pushed into the molten palette
  mono   clean high-contrast monochrome with grain
usage: .venv/bin/python tools/clips.py [name ...]
"""
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = os.path.join(ROOT, "research/footage")
OUT = os.path.join(ROOT, "assets/v")

CLIPS = {
    # Act I, on the tube
    "tube-silhouette": dict(src="MasterHa1936_2.mpeg", t=37.40, d=0.75, grade="tube"),
    "tube-ladle": dict(src="MasterHa1936_2.mpeg", t=305.9, d=0.55, grade="tube"),
    "tube-smith": dict(src="blacksmith1893.mp4", t=3.105, d=1.0, grade="tube"),
    "tube-pour": dict(src="MasterHa1936_2.mpeg", t=38.0, d=1.15, grade="tube"),
    # Act I, full-frame flash cuts
    "flash-fireball": dict(src="nasa-a11-broll.mp4", t=708.0, d=0.2, grade="flash", size=(1920, 1080)),
    "flash-curtain": dict(src="nasa-a11-broll.mp4", t=806.0, d=0.12, grade="flash", size=(1920, 1080)),
    # Act III
    "app-liftoff": dict(src="nasa-a11-broll.mp4", t=821.3, d=1.55, grade="fire", size=(1920, 1080), zoom=1.08,
                        opts=dict(fire_lo=0.62, warm_gain=1.4)),
    "pour-ladle": dict(src="MasterHa1936_2.mpeg", t=299.0, d=1.2, grade="fire", size=(1280, 960)),
    "pour-streams": dict(src="MasterHa1936_2.mpeg", t=38.0, d=1.2, grade="fire", size=(1280, 960)),
    "orbit-earth": dict(src="nasa-reel1.mp4", t=2921.0, d=1.2, grade="mono", size=(1280, 720)),
    "interstage": dict(src="nasa-reel1.mp4", t=2944.0, d=1.2, grade="fire", size=(1280, 720)),
    "engines-pad": dict(src="nasa-a11-broll.mp4", t=788.0, d=1.0, grade="fire", size=(1280, 854), zoom=1.08,
                        opts=dict(fire_lo=0.55, warm_gain=1.8)),
    "crucible": dict(src="MasterHa1936_2.mpeg", t=12.4, d=1.0, grade="fire", size=(960, 960)),
}

rng = np.random.default_rng(7)


def src_filter(src, w, h, zoom=1.0):
    """ffmpeg chain: square pixels, crop to target aspect (centre, optionally zoomed past borders), scale, 60 fps."""
    ar = w / h
    return (f"setsar=1,scale=iw*sar:ih,crop='min(iw,ih*{ar})/{zoom}':'min(ih,iw/{ar})/{zoom}',"
            f"scale={w}:{h}:flags=lanczos,fps=60,format=rgb24")


def luma(x):
    return x[..., 0] * 0.299 + x[..., 1] * 0.587 + x[..., 2] * 0.114


def blur(img, r):
    from scipy.ndimage import uniform_filter
    out = img
    for _ in range(3):
        out = uniform_filter(out, size=(r, r, 1) if out.ndim == 3 else r, mode="nearest")
    return out


def contrast(y, lo, hi, gamma=1.0):
    return np.clip((y - lo) / (hi - lo), 0, 1) ** gamma


MOLTEN = np.array([1.0, 0.353, 0.122])   # #FF5A1F
HOT = np.array([1.0, 0.851, 0.682])      # #FFD9AE
DEEP = np.array([0.42, 0.06, 0.02])


def heat_map(v):
    """0..1 heat -> deep red -> molten -> white-hot."""
    v = v[..., None]
    a = np.clip(v / 0.55, 0, 1)
    b = np.clip((v - 0.55) / 0.45, 0, 1)
    return (DEEP * (1 - a) + MOLTEN * a) * (1 - b) + HOT * b


def grade_tube(x, i, n, w, h):
    y = contrast(luma(x), 0.04, 0.92, 1.15)
    y = y * (0.96 + 0.04 * np.sin(i * 2.7))                      # phosphor flicker
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = (xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2)
    k = 0.06
    s = 1 + k * (nx * nx + ny * ny)
    sx = np.clip((nx * s / (1 + k)) * (w / 2) + w / 2, 0, w - 1).astype(np.int32)
    sy = np.clip((ny * s / (1 + k)) * (h / 2) + h / 2, 0, h - 1).astype(np.int32)
    y = y[sy, sx]
    glow = blur(np.clip(y - 0.55, 0, 1)[..., None], 19)[..., 0] * 1.4 + blur(np.clip(y - 0.7, 0, 1)[..., None], 61)[..., 0] * 1.1
    scan = 0.74 + 0.26 * np.cos(2 * np.pi * (yy + 0.5) / 4.0)
    y = y * scan + glow
    vig = np.clip(1 - 0.32 * (nx * nx + ny * ny) ** 1.4, 0, 1)
    y = y * vig
    g = rng.standard_normal((h, w)).astype(np.float32) * 0.035
    y = y + g
    out = np.stack([y, y, y], -1)
    # phosphor tint: faint cool white, warm halo
    out = out * np.array([0.96, 0.99, 1.0]) + glow[..., None] * np.array([0.05, 0.02, -0.02])
    # radial colour fringe at the edges
    r2 = (nx * nx + ny * ny)
    shift = (r2 * 3).astype(np.int32)
    out[..., 0] = np.take_along_axis(out[..., 0], np.clip(xx.astype(np.int32) + shift, 0, w - 1), 1)
    out[..., 2] = np.take_along_axis(out[..., 2], np.clip(xx.astype(np.int32) - shift, 0, w - 1), 1)
    return out


def grade_flash(x, i, n, w, h):
    lin = x ** 2.2 * 2.3
    lin = lin + blur(np.clip(lin - 0.8, 0, 4), 41) * 0.6
    out = 1 - np.exp(-lin * 1.4)
    sat = luma(out)[..., None]
    out = np.clip(sat + (out - sat) * 1.25, 0, 1)
    return out ** (1 / 2.2)


def grade_fire(x, i, n, w, h, fire_lo=0.45, warm_gain=2.5):
    y = luma(x)
    mx, mn = x.max(-1), x.min(-1)
    sat = (mx - mn) / (mx + 1e-4)
    wb = x / (x.reshape(-1, 3).mean(0) / x.mean() + 1e-4)          # grey-world: film-stock tint is not fire
    r, g, b = wb[..., 0], wb[..., 1], wb[..., 2]
    warm = np.clip((r - b) * warm_gain, 0, 1) * np.clip((r - g * 0.7) * warm_gain, 0, 1)
    fire = np.clip(warm * contrast(y, fire_lo, fire_lo + 0.4), 0, 1) ** 0.8
    if sat.mean() < 0.06:                                   # monochrome source: fire = the brightest highlights
        fire = contrast(y, 0.62, 0.97, 1.3)
    else:                                                   # colour source: blown-out exhaust is fire too
        fire = np.maximum(fire, contrast(y, 0.82, 0.98))
    fire = blur(fire[..., None], 5)[..., 0]
    mono = contrast(y, 0.05, 0.9, 1.1)
    base = np.stack([mono] * 3, -1)
    heat = heat_map(contrast(y, 0.35, 1.0, 1.6))
    out = base * (1 - fire[..., None]) + heat * fire[..., None]
    out = out + blur(fire[..., None] * heat, 31) * 0.35
    out = out + rng.standard_normal((h, w, 1)).astype(np.float32) * 0.025
    return out


def grade_mono(x, i, n, w, h):
    y = contrast(luma(x), 0.04, 0.9, 1.1)
    y = y + rng.standard_normal((h, w)).astype(np.float32) * 0.025
    return np.stack([y] * 3, -1)


GRADES = {"tube": grade_tube, "flash": grade_flash, "fire": grade_fire, "mono": grade_mono}


def make(name, spec):
    w, h = spec.get("size", (1440, 1080))
    n = int(round(spec["d"] * 60))
    cmd = ["ffmpeg", "-v", "error", "-ss", str(spec["t"]), "-i", os.path.join(F, spec["src"]), "-t", str(spec["d"] + 0.2),
           "-vf", src_filter(spec["src"], w, h, spec.get("zoom", 1.0)), "-f", "rawvideo", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    frames = np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)[:n].astype(np.float32) / 255
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", "60",
                            "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-pix_fmt", "yuv420p",
                            "-g", "1", "-movflags", "+faststart", os.path.join(OUT, name + ".mp4")], stdin=subprocess.PIPE)
    for i, fr in enumerate(frames):
        out = GRADES[spec["grade"]](fr, i, len(frames), w, h, **spec.get("opts", {}))
        enc.stdin.write((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8).tobytes())
    enc.stdin.close()
    enc.wait()
    print(f"{name}: {len(frames)} frames {w}x{h} {spec['grade']}")


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or list(CLIPS)
    for name in names:
        make(name, CLIPS[name])


main()
