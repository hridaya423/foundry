#!/usr/bin/env python3
"""Cut each pick to one clean shot (no scene cut inside) and export it as a JPEG sequence + js/seq.js manifest.

usage: tools/seq.py            (all picks, and the Earthrise still)
       tools/seq.py name ...   (only these; "earthrise" is the still)
"""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOOT = os.path.join(ROOT, "..", "research", "footage")
OUT = os.path.join(ROOT, "assets", "seq")
FPS, WIDTH, MAXLEN = 30, 640, 2.4
CLEAN = "hqdn3d=3:3:10:10"     # the moon plates are 480-line film transfers: a temporal denoise before the upscale (a
SHARPEN = "cas=0.6"            # spatial one smears the regolith to plastic), a contrast-adaptive sharpen after it
FILL = {"flag"}                # 16 mm film transfers that drop a frame in ten (fill_skips)
SLOW_SCAN = {"step"}           # the 1969 broadcast: 10 fps slow-scan, each picture repeated three times (slow_scan)
SOFT = {"step"}                 # scaled up soft and unsharpened: a sharpen draws blocks on these
# the moon plates also get super-resolution: Real-ESRGAN's realesrgan-x4plus (the model for real photos, BSD-3, SOURCES.md)
# runs on the native frames after a temporal-only denoise (the step is a soft upscale: it goes in at half size). Each frame
# is then the plate's own clean upscale blended with the model's at that strength, the model's tone pulled onto the
# plate's; the grain over the moon (film.js) keeps the regolith from going plastic. name: (filters before the model, strength).
# The step is a blurred broadcast: the model drew hard, waxy edges on the ladder that the camera never saw, and the
# sharpen drew blocks. It is shown as what it is instead: brought down to the detail it has, scaled up soft and unsharpened,
# and the grain over it (film.js) is the texture
SR = {"flag": ("hqdn3d=0:0:6:6", 0.6)}
REALESRGAN = os.environ.get("REALESRGAN", os.path.expanduser("~/Honey/tools/realesrgan"))
SR_CACHE = os.path.expanduser("~/Honey/.cache/every-job-sr")   # the model's frames (2 GB, minutes to make): outside ~/Honey/anvil

# name: (source, around-time seconds)
PICKS = {
    "switchboard": ("tools/diplomats1965.mpeg", 320),
    "operator": ("tools/diplomats1965.mpeg", 358),
    "telegraph": ("tools/telegram1956.mpeg", 52),
    "sounder": ("tools/telegram1956.mpeg", 60),
    "ticker": ("tools/telegram1956.mpeg", 377),
    "teleprinter": ("tools/telegram1956.mpeg", 308),
    "keys": ("tools/telegram1956.mpeg", 412),
    "drawers": ("tools/library1951.m4v", 195),
    "cards": ("tools/library1951.m4v", 227),
    "card": ("tools/library1951.m4v", 258),
    "console": ("tools/computers1957.mp4", 437),
    "reels": ("tools/computers1957.mp4", 556),
    "typists": ("tools/secretary1941.mpeg", 50),
    "smith": ("blacksmith1893.mp4", 8),
    "forge": ("blacksmith1893.mp4", 5.0, 640),
    "pour": ("MasterHa1936_2.mpeg", 38.6, 1440),
    "ladle": ("MasterHa1936_2.mpeg", 299.6, 1440),
    "crucible": ("../../assets/v/crucible.mp4", 0.4),
    "liftoff": ("../../assets/v/app-liftoff.mp4", 0.7),
    "gallop": ("icons/Horse_in_Motion_-_Sallie_Gardner_(animation).webm", -1, 1440),
    "ladder": ("nasa-a11-broll.mp4", 1374.5, 1280),
    "aldrin": ("nasa-a11-broll.mp4", 1384, 1280),
    "eva": ("icons/Restored_Apollo_11_Moonwalk_-_Original_NASA_EVA_Mission_Video_-_Walking_on_the_Moon.webm", 1100, 1440, "crop=1440:1080:240:0"),
    "flag": ("nasa-a11-broll.mp4", 1456.8, 1920, "crop=696:468:8:12", 7.2, CLEAN),   # the flag goes in, they step back from it; the transfer's black border cut off
    "step": ("icons/Restored_Apollo_11_Moonwalk_-_Original_NASA_EVA_Mission_Video_-_Walking_on_the_Moon.webm", 1108.4, 1440,
             "crop=1440:1080:240:0", 3.6, "hqdn3d=4:4:8:8,scale=480:-2:flags=area"),
    "ignition": ("nasa-a11-broll.mp4", 708, 1280),
    "ascent": ("nasa-a11-broll.mp4", 864, 1280),
    "earthorbit": ("nasa-a11-broll.mp4", 1056, 1280),
    "splash": ("nasa-a11-broll.mp4", 1908, 1280),
    "crowd": ("nasa-a11-broll.mp4", 684, 1280),
    # the people his line reaches today: Artemis II, April 2026 (tools/artemis.sh). Each starts still, watching, and turns
    # after their line lands: the camera finds her head on his shoulder; her smile breaks
    "couple": ("artemis/couple.mp4", 0.55, 1920, "colorlevels=rimin=0.13:gimin=0.145:bimin=0.14", 2.0),
    "smile": ("artemis/smile.mp4", 0.6, 1920, "", 2.5),
    "moonface": ("icons/Le_Voyage_dans_la_Lune_(1902).webm", 368, 1440),
    "capsule": ("icons/Le_Voyage_dans_la_Lune_(1902).webm", 336, 1440),
    "train": ("icons/Arrival_of_a_Train_at_La_Ciotat_(The_Lumière_Brothers,_1895).webm", 14, 540),
    "arrival": ("icons/Arrival_of_a_Train_at_La_Ciotat_(The_Lumière_Brothers,_1895).webm", 9.2, 540, "", 3.2),
}


def cuts(src, a, b):
    cmd = ["ffmpeg", "-v", "info", "-ss", str(a), "-t", str(b - a), "-i", src, "-an",
           "-vf", "select='gt(scene,0.28)',showinfo", "-f", "null", "-"]
    err = subprocess.run(cmd, capture_output=True, text=True).stderr
    return [a + float(m) for m in re.findall(r"pts_time:([0-9.]+)", err)]


def shot(src, t):
    if t < 0:
        return 0, 60
    a, b = max(0, t - 4), t + 6
    cs = [a] + cuts(src, a, b) + [b]
    for s, e in zip(cs, cs[1:]):
        if s <= t < e:
            s, e = s + 0.12, e - 0.12
            if e - s > MAXLEN:
                mid = min(max(t, s + MAXLEN / 2), e - MAXLEN / 2)
                s, e = mid - MAXLEN / 2, mid + MAXLEN / 2
            return s, e
    return t, t + MAXLEN


def fill_skips(d, ref=None):
    """The NASA b-roll transfer drops one film frame in ten, a stutter three times a second. Find each jump (a frame
    difference far above the shot's median; in `ref`'s frames when given, the plate before super-resolution, whose
    detail hides no jump) and put a motion-interpolated frame in the gap."""
    import tempfile
    import numpy as np
    from PIL import Image
    fs = sorted(f for f in os.listdir(d) if f.endswith(".jpg"))
    g = [np.asarray(Image.open(os.path.join(ref or d, f)).convert("L").resize((240, 176)), float) for f in fs]
    diff = [np.abs(b - a).mean() for a, b in zip(g, g[1:])]
    med = float(np.median(diff))
    out = []
    for i, f in enumerate(fs):
        out.append(os.path.join(d, f))
        if i < len(diff) and diff[i] > 1.8 * med:
            with tempfile.TemporaryDirectory() as tmp:
                for k, src in enumerate((fs[i], fs[i + 1], fs[i + 1])):    # minterpolate drops its last input frame
                    os.link(os.path.join(d, src), os.path.join(tmp, f"{k}.jpg"))
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", "1", "-i", os.path.join(tmp, "%d.jpg"), "-vf",
                                "minterpolate=fps=2:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1", "-q:v", "3",
                                os.path.join(tmp, "m%d.jpg")], check=True)
                mid = os.path.join(d, f"fill-{i:03d}.jpg"); os.replace(os.path.join(tmp, "m2.jpg"), mid); out.append(mid)
    tmp = [os.path.join(d, f"t{k:03d}.jpg") for k in range(len(out))]
    for a, b in zip(out, tmp): os.replace(a, b)
    for k, b in enumerate(tmp): os.replace(b, os.path.join(d, f"{k + 1:03d}.jpg"))
    return len(out) - len(fs)


def slow_scan(d):
    """The broadcast repeats each slow-scan picture about three times, each copy with its own compression noise. Replace
    each run of repeats (a frame difference under half the shot's picture changes) with the run's mean: the same
    picture, cleaner, and still 30 frames a second."""
    import numpy as np
    from PIL import Image
    fs = sorted(f for f in os.listdir(d) if f.endswith(".jpg"))
    im = [np.asarray(Image.open(os.path.join(d, f)), np.float32) for f in fs]
    diff = np.array([np.abs(b - a).mean() for a, b in zip(im, im[1:])])
    cut = 0.5 * np.median(np.sort(diff)[-len(diff) // 3:])
    runs, run = [], [0]
    for i, x in enumerate(diff):
        if x > cut: runs.append(run); run = []
        run.append(i + 1)
    runs.append(run)
    for r in runs:
        m = np.clip(np.mean([im[i] for i in r], axis=0), 0, 255).astype(np.uint8)
        for i in r: Image.fromarray(m).save(os.path.join(d, fs[i]), quality=92)
    return len(runs)


def realesrgan(src, out):
    subprocess.run([os.path.join(REALESRGAN, "realesrgan-ncnn-vulkan"), "-m", os.path.join(REALESRGAN, "models"),
                    "-n", "realesrgan-x4plus", "-i", src, "-o", out, "-f", "png", "-t", "256"], check=True, capture_output=True)


def blend(base_path, up_path, strength, out_path, where=None):
    """the plate's own upscale with the model's at `strength`, the model's tone pulled onto the plate's (a wide blur of each);
    `where(base)` gives a 0-1 map of where the model may act"""
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    Image.MAX_IMAGE_PIXELS = None
    base = np.asarray(Image.open(base_path).convert("RGB"), np.float32)
    h, w = base.shape[:2]
    up = np.asarray(Image.open(up_path).convert("RGB").resize((w, h), Image.LANCZOS), np.float32)
    lo = lambda x: ndimage.gaussian_filter(x, (w / 100, w / 100, 0))
    if where: strength = strength * where(base)[..., None]
    x = base * (1 - strength) + up * (lo(base) + 4) / (lo(up) + 4) * strength
    Image.fromarray(np.clip(x, 0, 255).astype(np.uint8)).save(out_path, quality=90)


def super_res(name, path, s, e, pre, d):
    before, strength = SR[name]
    src, up = os.path.join(SR_CACHE, name, "in"), os.path.join(SR_CACHE, name, "out")
    os.makedirs(src, exist_ok=True); os.makedirs(up, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{s:.3f}", "-t", f"{e - s:.3f}", "-i", path, "-an", "-vf",
                    (pre + "," if pre else "") + f"yadif=deint=interlaced,scale=trunc(iw*sar/2)*2:ih,setsar=1,fps={FPS},{before}",
                    os.path.join(src, "%03d.png")], check=True)
    fs = sorted(f for f in os.listdir(d) if f.endswith(".jpg"))
    if sorted(os.listdir(up)) != [f[:-4] + ".png" for f in fs]:
        realesrgan(src, up)
    for f in fs:
        blend(os.path.join(d, f), os.path.join(up, f[:-4] + ".png"), strength, os.path.join(d, f))


def earth_disc(img):
    """the Earth's lit disc, pulled 10 px inside its limb: the model rings the limb, and it waxes the moon's grain away"""
    from scipy import ndimage
    m = ndimage.gaussian_filter(((img[..., 2] - img[..., 0]) > 20).astype("float32"), 10)
    return (m - 0.85).clip(0, 0.15) / 0.15


def earthrise():
    """Earthrise for the dive into the wordmark: the 2400 px scan at 4800 px, the model's at 0.6 on the Earth alone"""
    src, up, out = os.path.join(FOOT, "icons", "NASA-Apollo8-Dec24-Earthrise.jpg"), os.path.join(SR_CACHE, "earthrise.png"), \
        os.path.join(ROOT, "assets", "img", "earthrise.jpg")
    if not os.path.exists(up):
        realesrgan(src, up)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vf", "scale=4800:4800:flags=lanczos", "-q:v", "1", out], check=True)
    blend(out, up, 0.6, out, earth_disc)


def export(name, src, t, width=WIDTH, pre="", dur=None, clean=""):
    path = os.path.join(FOOT, src)
    s, e = (t, t + dur) if dur else shot(path, t)
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{s:.3f}", "-t", f"{e - s:.3f}", "-i", path, "-an",
                    "-vf", (pre + "," if pre else "") + f"yadif=deint=interlaced,scale=trunc(iw*sar/2)*2:ih,setsar=1,fps={FPS}"
                    + (f",{clean},scale={width}:-2:flags=bicubic" if name in SOFT else f",{clean},scale={width}:-2:flags=lanczos,{SHARPEN}"
                       if clean else f",scale={width}:-2:flags=lanczos"), "-q:v", "3",
                    os.path.join(d, "%03d.jpg")], check=True)
    ref = None
    if name in SR:
        import shutil, tempfile
        ref = tempfile.mkdtemp()
        for f in os.listdir(d): shutil.copy(os.path.join(d, f), ref)
        super_res(name, path, s, e, pre, d)
    if name in FILL: print(f"{name}: filled {fill_skips(d, ref)} dropped frames")
    if name in SLOW_SCAN: print(f"{name}: {slow_scan(d)} slow-scan pictures")
    if ref:
        shutil.rmtree(ref)
    n = len([f for f in os.listdir(d) if f.endswith(".jpg")])
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height",
                            "-of", "csv=p=0", os.path.join(d, "001.jpg")], capture_output=True, text=True).stdout
    w, h = map(int, probe.strip().split(","))
    print(f"{name:12s} {s:8.2f}-{e:8.2f}  {n} frames  {w}x{h}")
    return {"n": n, "w": w, "h": h, "src": src, "in": round(s, 3)}


def main():
    man_path = os.path.join(ROOT, "js", "seq.js")
    man = {}
    if os.path.exists(man_path):
        man = json.loads(open(man_path).read().split("=", 1)[1].rstrip(";\n"))
    want = sys.argv[1:] or list(PICKS) + ["earthrise"]
    for name in want:
        if name == "earthrise":
            earthrise(); continue
        man[name] = export(name, *PICKS[name])
    with open(man_path, "w") as f:
        f.write("// generated by tools/seq.py\nwindow.SEQ = " + json.dumps(man) + ";\n")


if __name__ == "__main__":
    main()
