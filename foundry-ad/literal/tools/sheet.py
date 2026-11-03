import sys
from pathlib import Path
from PIL import Image, ImageDraw

files = sorted(Path(sys.argv[1]).glob("t*.png")) if len(sys.argv) < 4 else [Path(p) for p in sys.argv[3:]]
out = sys.argv[2]
cols = 3 if len(files) > 4 else 2
w = 640
h = 360
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + 22)), "black")
d = ImageDraw.Draw(sheet)
for k, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS)
    x, y = (k % cols) * w, (k // cols) * (h + 22)
    sheet.paste(im, (x, y + 22))
    d.text((x + 6, y + 4), f.stem, fill="white")
sheet.save(out, quality=88)
print(out)
