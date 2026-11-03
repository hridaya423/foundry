"""Builds js/data.js: the orange's 432 tiles, glyph masks, the QR matrix and the wordmark tiles."""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
COLS, ROWS = 88, 50
ORANGE_TILES = 432
ORANGE_CENTER = (COLS / 2 + 6, ROWS / 2 - 0.5)
ORANGE_DIAMETER = 24.0


def srgb_to_linear(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def orange_tiles():
    im = Image.open(ROOT / "assets/img/mandarin.jpg").convert("RGB")
    a = np.asarray(im).astype(float) / 255
    mx, mn = a.max(-1), a.min(-1)
    mask = ((mx - mn) / (mx + 1e-6) > 0.35) & (mx > 0.25)
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    size = max(x1 - x0, y1 - y0)
    px_per_tile = size / ORANGE_DIAMETER
    cx_img, cy_img = (x0 + x1) / 2, (y0 + y1) / 2
    shadow = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(px_per_tile * 2.2))
    shadow = np.asarray(shadow).astype(float) / 255
    sx, sy = int(px_per_tile * 1.2), int(px_per_tile * 1.8)
    shifted = np.zeros_like(shadow)
    shifted[sy:, sx:] = shadow[: shadow.shape[0] - sy, : shadow.shape[1] - sx]
    shadow = shifted
    tiles = []
    for row in range(ROWS):
        for col in range(COLS):
            ix0 = cx_img + (col - ORANGE_CENTER[0]) * px_per_tile
            iy0 = cy_img + (row - ORANGE_CENTER[1]) * px_per_tile
            ix1, iy1 = ix0 + px_per_tile, iy0 + px_per_tile
            sx0, sy0 = int(max(0, ix0)), int(max(0, iy0))
            sx1, sy1 = int(min(a.shape[1], ix1)), int(min(a.shape[0], iy1))
            if sx1 <= sx0 or sy1 <= sy0:
                tiles.append((row, col, 0.0, None, 0.0))
                continue
            m = mask[sy0:sy1, sx0:sx1]
            cover = m.mean() * ((sx1 - sx0) * (sy1 - sy0)) / (px_per_tile ** 2)
            color = a[sy0:sy1, sx0:sx1][m].mean(0) if m.any() else None
            sh = shadow[sy0:sy1, sx0:sx1].mean()
            tiles.append((row, col, cover, color, sh))
    ranked = sorted(tiles, key=lambda t: -t[2])
    chosen = {(t[0], t[1]) for t in ranked[:ORANGE_TILES]}
    front = []
    for row, col, cover, color, sh in tiles:
        if (row, col) in chosen:
            c = np.clip(color * 0.86, 0, 1)
            kind = 1
        else:
            c = np.array([0xC6, 0xBB, 0xAB]) / 255 * (1 - 0.42 * min(1.0, sh * 1.25))
            kind = 0
        lin = srgb_to_linear(c)
        front.append([kind, round(float(lin[0]), 4), round(float(lin[1]), 4), round(float(lin[2]), 4)])
    cut = ranked[ORANGE_TILES - 1][2]
    return front, float(cut)


GLYPHS = {
    "0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14], "2": [14, 17, 1, 2, 4, 8, 31],
    "3": [30, 1, 1, 14, 1, 1, 30], "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 16, 30, 1, 1, 30],
    "E": [31, 16, 16, 30, 16, 16, 31], "H": [17, 17, 17, 31, 17, 17, 17], "L": [16, 16, 16, 16, 16, 16, 31],
    "O": [14, 17, 17, 17, 17, 17, 14],
}


def tile_text(text, cols, rows, scale=1, dy=0):
    """The website's 5x7 tile font (anvil/app/foundry/story/tile-glyphs.ts), centred in a cols x rows grid."""
    width = (len(text) * 6 - 1) * scale
    height = 7 * scale
    x0 = (cols - width) // 2
    y0 = (rows - height) // 2 + dy
    grid = [[0] * cols for _ in range(rows)]
    for k, ch in enumerate(text):
        for y, bits in enumerate(GLYPHS[ch]):
            for x in range(5):
                if bits & (1 << (4 - x)):
                    for sy in range(scale):
                        for sx in range(scale):
                            grid[y0 + y * scale + sy][x0 + (k * 6 + x) * scale + sx] = 1
    return grid


def text_mask(text, font_path, cols, rows, box, weight=None, index=0, bold=0.0, threshold=0.45):
    size_px = 800
    font = ImageFont.truetype(str(font_path), size_px, index=index)
    if weight:
        font.set_variation_by_axes([weight])
    stroke = int(size_px * bold)
    bbox = font.getbbox(text, stroke_width=stroke)
    img = Image.new("L", (bbox[2] - bbox[0] + 80, bbox[3] - bbox[1] + 80), 0)
    ImageDraw.Draw(img).text((40 - bbox[0], 40 - bbox[1]), text, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
    img = img.crop(img.getbbox())
    bx0, by0, bw, bh = box
    scale = min(bw / img.width, bh / img.height) * 8
    tw, th = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    img = img.resize((tw, th), Image.LANCZOS)
    canvas = Image.new("L", (cols * 8, rows * 8), 0)
    canvas.paste(img, (round(bx0 * 8 + (bw * 8 - tw) / 2), round(by0 * 8 + (bh * 8 - th) / 2)))
    arr = np.asarray(canvas).astype(float) / 255
    cells = arr.reshape(rows, 8, cols, 8).mean(axis=(1, 3))
    return [[1 if v > threshold else 0 for v in r] for r in cells]


def qr_matrix():
    import segno

    qr = segno.make("https://foundry.hridya.tech", error="m", micro=False, boost_error=False)
    rows = [[1 if v else 0 for v in row] for row in qr.matrix]
    return {"version": qr.version, "error": qr.error, "matrix": rows}


def main():
    front, cut = orange_tiles()
    geist = ROOT / "assets/fonts/Geist-Variable.woff2"
    jp = ROOT / "assets/fonts/NotoSansJP-700-subset.woff2"
    try:
        probe = Image.new("L", (200, 200), 0)
        ImageDraw.Draw(probe).text((10, 10), "こ", font=ImageFont.truetype(str(jp), 120), fill=255)
        assert np.asarray(probe).max() > 0
        jp_weight, jp_index, jp_bold = None, 0, 0.0
    except Exception:
        jp = Path("/System/Library/Fonts/AquaKana.ttc")
        jp_weight, jp_index, jp_bold = None, 1, 0.0
    data = {
        "cols": COLS,
        "rows": ROWS,
        "orangeTiles": ORANGE_TILES,
        "orangeCut": round(cut, 3),
        "wall": front,
        "digits": tile_text("432", 24, 18),
        "hello": tile_text("HELLO", 48, 9),
        "japanese": text_mask("こんにちは", jp, 48, 9, (1, 0.5, 46, 8), weight=jp_weight, index=jp_index, bold=jp_bold),
        "qr": qr_matrix(),
        "wordmark": json.loads((ROOT / "assets/tile-layout.json").read_text()),
    }
    (ROOT / "js/data.js").write_text("window.DATA = " + json.dumps(data, separators=(",", ":")) + ";\n")
    kinds = sum(1 for f in front if f[0] == 1)
    print(f"wall {COLS}x{ROWS}, orange tiles {kinds}, edge coverage cut {cut:.3f}")
    for name in ("digits", "hello", "japanese"):
        m = data[name]
        if m:
            print(name)
            print("\n".join("".join("#" if v else "." for v in r) for r in m))
    q = data["qr"]
    print("qr version", q["version"], q["error"], len(q["matrix"]))


if __name__ == "__main__":
    main()
