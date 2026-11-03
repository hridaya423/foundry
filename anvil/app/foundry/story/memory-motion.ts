import { tileText } from "./tile-glyphs";
import { toolsEnd } from "./tools-motion";
import { phase, type ShelfPose } from "./shelf-motion";

export const memoryStart = toolsEnd;
export const memorySettled = memoryStart + .18;
export const memoryValues = ["115.2", "620.2"] as const;
const headline = tileText("81%");
export const memoryTileCount = headline.points.length;

export function memoryTargets(width: number, height: number) {
  const mobile = width < 900;
  const cell = Math.min(width * (mobile ? .87 : .68) / headline.width, height * (mobile ? .18 : .22) / headline.height);
  return headline.points.map(point => ({ x: width * .5 + point.x * cell, y: height * .32 + point.y * cell, size: cell * .9, accent: true }));
}

export function writeMemoryTilePose(out: ShelfPose, index: number, progress: number, targets: ReturnType<typeof memoryTargets>) {
  if (progress <= memoryStart) return;
  const settle = phase(progress, memoryStart, memorySettled);
  const point = targets[index];
  if (!point) {
    const fade = 1 - phase(settle, 0, .35);
    out.sx *= fade;
    out.sy *= fade;
    return;
  }
  out.x += (point.x - out.x) * settle;
  out.y += (point.y - out.y) * settle;
  out.z *= 1 - settle;
  out.rx += (-.12 - out.rx) * settle;
  out.ry *= 1 - settle;
  out.rz *= 1 - settle;
  out.sx += (point.size / 24 - out.sx) * settle;
  out.sy += (point.size / 24 - out.sy) * settle;
}
