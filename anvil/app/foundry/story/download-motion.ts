import { memorySettled } from "./memory-motion";
import { bezier, phase, type ShelfLayout, type ShelfPose } from "./shelf-motion";

export const downloadStart = memorySettled + .26;
export const downloadSettled = downloadStart + .17;
export const storyEnd = downloadStart + .28;
export const arrowCells = [[0, -3], [0, -2], [-2, -2], [2, -2], [-1, -1], [1, -1], [0, 0]] as const;
const desktopTrail = [[.445, .55], [.463, .58], [.484, .615]];
const mobileTrail = [[.44, .47], [.465, .5], [.485, .53]];

export function downloadPoints(width: number, height: number) {
  const mobile = width < 900;
  const cell = Math.min(width * (mobile ? .032 : .013), height * .024);
  const trail = mobile ? mobileTrail : desktopTrail;
  return [...trail.map(([x, y]) => ({ x: x * width, y: y * height, cell })), ...arrowCells.map(([x, y]) => ({ x: width * .5 + x * cell, y: height * (mobile ? .6 : .714) + y * cell, cell }))];
}

export function writeDownloadTilePose(out: ShelfPose, index: number, progress: number, layout: ShelfLayout, points: ReturnType<typeof downloadPoints>) {
  if (progress <= downloadStart) return;
  const settle = phase(progress, downloadStart, downloadStart + .2);
  const point = points[index];
  if (!point) {
    out.y -= layout.height * phase(progress, downloadStart, downloadStart + .1);
    out.sx *= 1 - settle;
    out.sy *= 1 - settle;
    return;
  }
  out.x = bezier(out.x, layout.width * .04, point.x - layout.width * .08, point.x, settle);
  out.y = bezier(out.y, layout.height * .07, point.y - layout.height * .16, point.y, settle);
  out.z = out.z * (1 - settle) + Math.sin(settle * Math.PI) * point.cell * 3;
  out.rx += (-.15 - out.rx) * settle;
  out.ry *= 1 - settle;
  out.rz *= 1 - settle;
  out.sx += (point.cell * .9 / 24 - out.sx) * settle;
  out.sy += (point.cell * .9 / 24 - out.sy) * settle;
}
