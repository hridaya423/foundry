const W = 2304, H = 720, SCALE = 0.6;
const LW = 615, LH = 135;
const s = Math.min((W * SCALE) / LW, (H * SCALE) / LH);
const x0 = (W - LW * s) / 2, y0 = (H - LH * s) / 2;
const toUV = (x: number, y: number) => [(x0 + x * s) / W, 1 - (y0 + y * s) / H];
const [cu0, cv1] = toUV(50, 40), [cu1, cv0] = toUV(70, 100);
const [lu0, lv1] = toUV(-10, -10), [lu1, lv0] = toUV(LW + 10, LH + 10);

const hash = (a: number, b: number) => {
  const h = Math.sin(a * 127.1 + b * 311.7) * 43758.5453;
  return h - Math.floor(h);
};
const TILE = 48, GAP = 12;

const inCast = (u: number, v: number) => u >= cu0 && u <= cu1 && v >= cv0 && v <= cv1;

export default {
  columns: 384,
  rows: 60,
  charset: "quadrants",
  themes: {
    light: { ink: "#211d19", paper: "#f4ede2" },
    dark: { ink: "#eee7dd", paper: "#0f0d0c" },
  },
  image: { path: "lockup.svg", scale: SCALE },
  frames: 1,
  field: (u: number, v: number, { image }) => {
    if (image(u, v) > 0.5) return 1;
    const px = u * W, py = (1 - v) * H;
    const tx = Math.floor(px / TILE), ty = Math.floor(py / TILE);
    const fx = px - tx * TILE, fy = py - ty * TILE;
    if (fx >= TILE - GAP || fy >= TILE - GAP) return 0;
    const cx = (tx + 0.5) * TILE / W, cy = 1 - (ty + 0.5) * TILE / H;
    if ((tx + 1) * TILE > W || (ty + 1) * TILE > H) return 0;
    const pad = 0.02;
    if (cx > lu0 - pad && cx < lu1 + pad && cy > lv0 - pad * 4 && cy < lv1 + pad * 4) return 0;
    const edge = Math.abs(cx - 0.5) * 2;
    const p = Math.pow(Math.max(0, edge - 0.25) / 0.75, 1.6) * 0.75;
    return hash(tx, ty) < p ? 1 : 0;
  },
  color: (u: number, v: number, { theme }) => {
    if (inCast(u, v)) return [250, 100, 40];
    return theme === "dark" ? [238, 231, 221] : [33, 29, 25];
  },
};
