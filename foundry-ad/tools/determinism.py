"""Check that every frame is a pure function of time: shoot t, jump elsewhere, shoot t again, diff.

usage: python3 tools/determinism.py [step] [from] [to]     (default step 0.25s over the whole film)
Needs tools/serve.py running on 8765. Prints the frames whose two shots differ.
"""
import io
import sys

from PIL import Image, ImageChops
from playwright.sync_api import sync_playwright

DURATION = 15.0


def shot(pg, t):
    pg.evaluate(f"window.__dev.seek({t})")
    pg.wait_for_timeout(30)
    return Image.open(io.BytesIO(pg.screenshot())).convert("RGB")


def main():
    step = float(sys.argv[1]) if len(sys.argv) > 1 else 0.25
    t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    t1 = float(sys.argv[3]) if len(sys.argv) > 3 else DURATION
    times = [round(t0 + i * step, 4) for i in range(int(round((t1 - t0) / step)))]
    bad = []
    with sync_playwright() as p:
        b = p.chromium.launch(channel="chrome", args=["--autoplay-policy=no-user-gesture-required", "--use-angle=metal", "--enable-gpu"])
        pg = b.new_page(viewport={"width": 1920, "height": 1080}, device_scale_factor=1)
        pg.goto("http://127.0.0.1:8765/index.html", wait_until="load")
        pg.wait_for_function("!!(window.__timelines && window.__timelines.main)", timeout=60000)
        for i, t in enumerate(times):
            a = shot(pg, t)
            shot(pg, times[(i * 7 + 3) % len(times)])
            c = shot(pg, t)
            diff = ImageChops.difference(a, c).convert("L")
            hist = diff.histogram()
            changed = sum(hist[24:])
            if changed > 400:
                bad.append((t, changed, diff.getbbox()))
        b.close()
    for t, n, bbox in bad:
        print(f"{t:7.3f}s  {n:7d} px differ  bbox {bbox}")
    print(f"{len(bad)} / {len(times)} frames non-deterministic")


if __name__ == "__main__":
    main()
