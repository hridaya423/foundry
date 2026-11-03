"""Labeled contact sheet of a video segment, for studying references.

usage: python3 tools/refsheet.py <video> <out.jpg> <start> <dur> <fps> [cols] [width]
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    src, out, start, dur, fps = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
    cols = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    w = int(sys.argv[7]) if len(sys.argv) > 7 else 320
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(dur), "-i", src,
                        "-vf", f"fps={fps},scale={w}:-2", os.path.join(d, "%04d.png")], check=True)
        fs = sorted(os.listdir(d))
        ims = [Image.open(os.path.join(d, f)).convert("RGB") for f in fs]
    if not ims:
        raise SystemExit("no frames")
    h = ims[0].height
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (w + 4) + 4, rows * (h + 22) + 4), (24, 24, 24))
    font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/IBMPlexMono-Medium.ttf"), 13)
    dr = ImageDraw.Draw(sheet)
    for i, im in enumerate(ims):
        x, y = 4 + (i % cols) * (w + 4), 4 + (i // cols) * (h + 22)
        sheet.paste(im, (x, y + 18))
        dr.text((x + 2, y + 2), f"{start + i / fps:6.2f}s", fill=(255, 220, 90), font=font)
    sheet.save(out, quality=88)
    print(out, len(ims), "frames")


if __name__ == "__main__":
    main()
