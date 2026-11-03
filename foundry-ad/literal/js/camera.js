import { lerp, prog, inOutCubic, inOutSine, outCubic, smooth, bezier } from "./ease.js";
import { SWAP, WORDMARK, INFO, LOOP_SWAP } from "./choreo.js";

const TM = window.TM;
const DEG = Math.PI / 180;
const C = INFO.CENTER;

const stopTile = WORDMARK[SWAP.stop];
const REST = { tx: C.x - 40, ty: C.y + 72, d: 2240, yaw: -7, pitch: 3.5 };

const shots = [
  [0, REST],
  [TM.remove.enter, { tx: C.x - 40, ty: C.y + 72, d: 2190, yaw: -6.6, pitch: 3.3 }, inOutSine],
  [TM.cascade[1], { tx: C.x - 24, ty: C.y + 96, d: 2000, yaw: -4.6, pitch: 2.4 }, inOutSine],
  [TM.calc.summon, { tx: C.x - 10, ty: C.y + 132, d: 2150, yaw: -4.2, pitch: 2.1 }, inOutSine],
  [TM.calc.enter, { tx: C.x - 10, ty: C.y + 132, d: 2150, yaw: -4, pitch: 2 }, inOutSine],
  [TM.square[1] + 0.25, { tx: C.x, ty: C.y + 10, d: 1500, yaw: -2.5, pitch: 1.5 }, inOutCubic],
  [TM.translate.summon, { tx: C.x, ty: C.y + 98, d: 1690, yaw: -2.2, pitch: 1.4 }, inOutSine],
  [TM.translate.enter, { tx: C.x, ty: C.y + 98, d: 1700, yaw: -2.1, pitch: 1.3 }, inOutSine],
  [TM.slide[1], { tx: C.x, ty: C.y + 30, d: 1990, yaw: -1.5, pitch: 1 }, inOutCubic],
  [TM.qr.summon, { tx: C.x, ty: C.y + 60, d: 2000, yaw: -1.2, pitch: 0.8 }, inOutSine],
  [TM.qr.enter, { tx: C.x, ty: C.y + 60, d: 2020, yaw: -1.1, pitch: 0.7 }, inOutSine],
  [TM.qrBuild[1], { tx: C.x, ty: C.y + 200, d: 3300, yaw: 0, pitch: 0 }, inOutCubic],
  [TM.drop - 0.02, { tx: C.x, ty: C.y + 200, d: 3200, yaw: 0, pitch: 0 }, inOutSine],
  [TM.drop + 1.1, { tx: C.x - 60, ty: C.y + 520, d: 1500, yaw: 3, pitch: 7 }, outCubic],
  [TM.land[0] + 0.4, { tx: 0, ty: 60, d: 3300, yaw: 1, pitch: 1.5 }, inOutCubic],
  [TM.land[1] + 0.3, { tx: 0, ty: 30, d: 3520, yaw: 0, pitch: 0 }, inOutSine],
  [TM.loop[0], { tx: 0, ty: 30, d: 3520, yaw: 0, pitch: 0 }, inOutSine],
];

function fromShots(t) {
  if (t <= shots[0][0]) return shots[0][1];
  for (let i = 1; i < shots.length; i++) {
    const [t1, s1, e] = shots[i];
    if (t <= t1) {
      const [t0, s0] = shots[i - 1];
      const u = (e || inOutCubic)(prog(t, t0, t1));
      return {
        tx: lerp(s0.tx, s1.tx, u),
        ty: lerp(s0.ty, s1.ty, u),
        d: Math.exp(lerp(Math.log(s0.d), Math.log(s1.d), u)),
        yaw: lerp(s0.yaw, s1.yaw, u),
        pitch: lerp(s0.pitch, s1.pitch, u),
      };
    }
  }
  return shots[shots.length - 1][1];
}

const DIVE_D = 40;
const EMERGE_D = DIVE_D * (23.6 / stopTile.width);
const diveIn = bezier(0.6, 0, 0.92, 1);
const diveOut = bezier(0.08, 0, 0.3, 1);
function loopShot(t) {
  const [a, b] = TM.loop;
  if (t < LOOP_SWAP) {
    const from = shots[shots.length - 1][1];
    const d = Math.exp(lerp(Math.log(from.d), Math.log(DIVE_D), diveIn(prog(t, a, LOOP_SWAP))));
    const k = (1 - smooth(prog(t, a, LOOP_SWAP))) * d / from.d;
    return {
      tx: stopTile.wx + (from.tx - stopTile.wx) * k,
      ty: stopTile.wy + (from.ty - stopTile.wy) * k,
      d,
      yaw: 0,
      pitch: 0,
    };
  }
  const d = Math.exp(lerp(Math.log(EMERGE_D), Math.log(REST.d), diveOut(prog(t, LOOP_SWAP, b))));
  const v = smooth(prog(t, LOOP_SWAP, b));
  const k = v * d / REST.d;
  return {
    tx: SWAP.hookPos.x + (REST.tx - SWAP.hookPos.x) * k,
    ty: SWAP.hookPos.y + (REST.ty - SWAP.hookPos.y) * k,
    d,
    yaw: lerp(0, REST.yaw, v),
    pitch: lerp(0, REST.pitch, v),
  };
}

export function camera(t) {
  const s = t >= TM.loop[0] ? loopShot(t) : fromShots(t);
  const yaw = s.yaw * DEG, pitch = s.pitch * DEG;
  const fov = 24;
  return {
    tx: s.tx, ty: s.ty, tz: 0,
    px: s.tx + s.d * Math.sin(yaw) * Math.cos(pitch),
    py: s.ty + s.d * Math.sin(pitch),
    pz: s.d * Math.cos(yaw) * Math.cos(pitch),
    dist: s.d,
    fov,
    roll: 0,
  };
}

const fast = [
  [TM.cascade[0], TM.cascade[1] + 0.3],
  [TM.square[0], TM.square[1]],
  [TM.digits, TM.digits + 0.6],
  [TM.slide[0], TM.slide[1]],
  [TM.hello, TM.hello + 0.7],
  [TM.japanese, TM.japanese + 0.8],
  [TM.qrBuild[0], TM.qrBuild[1] + 0.1],
  [TM.drop - 0.05, TM.land[1] + 0.6],
  [TM.loop[0] + 0.3, TM.loop[1] - 0.3],
];

export function samplesAt(t) {
  if (window.__DRAFT) return 1;
  if (t >= TM.drop - 0.05 && t <= TM.land[0] + 0.6) return 80;
  if (t >= TM.loop[0] + 0.3 && t <= LOOP_SWAP + 0.3) return 48;
  return fast.some(([a, b]) => t >= a && t <= b) ? 16 : 6;
}

const lensOn = (t) => smooth(prog(t, TM.drop - 0.1, TM.drop + 0.3) * (1 - prog(t, TM.land[0] - 0.4, TM.land[0] + 0.6)));

export function aperture(t) {
  return 10 * lensOn(t);
}

export function focusDepth(t) {
  const s = Math.max(0, t - TM.drop);
  return lensOn(t) * 1030 * (1 - Math.exp(-1.35 * s)) / 1.35;
}

export function shutter() {
  return 0.5 / 60;
}
