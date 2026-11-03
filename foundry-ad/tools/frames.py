"""Seek the composition in headless Chrome and grab exact 1920x1080 frames plus a labeled contact sheet.

usage: python3 tools/frames.py <outdir> <t> [t ...]      t in seconds (2.25) or frames at 60fps (f135)
       python3 tools/frames.py <outdir> --range a b step
Needs `python3 -m http.server 8765` running in foundry-ad.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse(args):
    if args and args[0] == "--range":
        a, b, s = map(float, args[1:4])
        n = int(round((b - a) / s)) + 1
        return [round(a + i * s, 5) for i in range(n)]
    return [int(x[1:]) / 60 if x.startswith("f") else float(x) for x in args]


def main():
    out = sys.argv[1]
    times = parse(sys.argv[2:])
    os.makedirs(out, exist_ok=True)
    errors = []
    paths = []
    with sync_playwright() as p:
        b = p.chromium.launch(channel="chrome", args=["--autoplay-policy=no-user-gesture-required", "--use-angle=metal", "--enable-gpu"])
        pg = b.new_page(viewport={"width": 1920, "height": 1080}, device_scale_factor=1)
        pg.on("console", lambda m: errors.append(f"[{m.type}] {m.text}") if m.type in ("error", "warning") else None)
        pg.on("pageerror", lambda e: errors.append(f"[pageerror] {e}"))
        for attempt in range(4):
            pg.goto("http://127.0.0.1:8765/index.html", wait_until="load")
            try:
                pg.wait_for_function("!!(window.__timelines && window.__timelines.main)", timeout=12000)
                break
            except Exception:
                print("build stalled at", pg.evaluate("window.__buildStage"), "- reloading")
        else:
            print("\n".join(errors) or "no console errors")
            raise SystemExit("timeline never registered")
        for t in times:
            pg.evaluate(f"window.__dev.seek({t})")
            pg.wait_for_timeout(30)
            path = os.path.join(out, f"t{t:07.3f}.png")
            pg.screenshot(path=path)
            paths.append((t, path))
        b.close()
    for e in errors:
        print(e)
    cols = 4
    w, h = 480, 270
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * (h + 22)), (40, 40, 40))
    font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/IBMPlexMono-Medium.ttf"), 15)
    d = ImageDraw.Draw(sheet)
    for i, (t, path) in enumerate(paths):
        x, y = (i % cols) * w, (i // cols) * (h + 22)
        sheet.paste(Image.open(path).convert("RGB").resize((w, h), Image.LANCZOS), (x, y + 22))
        d.text((x + 6, y + 3), f"{t:.3f}s  f{round(t * 60)}", fill=(230, 230, 230), font=font)
    sheet.save(os.path.join(out, "sheet.jpg"), quality=90)
    print(os.path.join(out, "sheet.jpg"))


if __name__ == "__main__":
    main()
