import { phase, type ShelfLayout, type ShelfPose } from "./shelf-motion";

export const clipboardEnd = 1.45;
export const clipboardItems = [
  { id: "meeting", kind: "text", title: "Meet at 10", value: "Meet at 10. Bring the first draft.", time: "10:14" },
  { id: "coast", kind: "image", title: "Coast.jpg", value: "/assets/foundry/story/coast.jpg", time: "10:16" },
  { id: "orange", kind: "color", title: "#FA6428", value: "#FA6428", time: "10:18" },
  { id: "neural-network", kind: "link", title: "But what is a neural network?", value: "https://www.youtube.com/watch?v=aircAruvnKk", time: "10:21" },
  { id: "draft", kind: "text", title: "Build something great.", value: "Build something great. Keep the details simple.", time: "10:24" },
] as const;
export type ClipboardItem = (typeof clipboardItems)[number];

export function searchClipboard(query: string) {
  const needle = query.trim().toLowerCase();
  return clipboardItems.filter((item) => `${item.title} ${item.value} ${item.kind}`.toLowerCase().includes(needle));
}

export function clipboardFocus(progress: number) {
  return 4 * phase(progress, 1.12, 1.50);
}

export function clipboardCardPose(offset: number, width: number, height: number) {
  const mobile = width < 900;
  const distance = Math.abs(offset);
  return {
    x: width * ((mobile ? 0.5 : 0.32) + offset * (mobile ? 0.79 : 0.225)),
    y: height * ((mobile ? 0.47 : 0.54) + (mobile ? 0.018 : 0.07) * offset - 0.009 * offset * offset),
    scale: Math.max(0.56, 1 - distance * (mobile ? 0.14 : 0.09)),
    rotate: mobile ? offset * 5 : 9 - offset * 2.5,
    depth: mobile ? 0 : -12 + offset * 3,
    blur: Math.min(4, distance * 1.25),
    opacity: Math.max(0.2, 1 - distance * 0.17),
  };
}

function ribbonTravel(index: number, progress: number) {
  const elapsed = Math.max(0, progress - 1);
  const head = progress <= 1 ? (progress - .875) * 10 : 1.25 + .62 * elapsed + .3752 * (1 - Math.exp(-elapsed / .04));
  return Math.max(0, head - index * 1.4 / 48);
}

export function clipboardRibbonPoint(index: number, width: number, height: number, focus: number, progress = 1.2) {
  const mobile = width < 900;
  const travel = ribbonTravel(index, progress);
  const x = 1.2 - travel % 1.4;
  const y = mobile ? .65 + .055 * Math.sin(x * Math.PI * 1.3) : .64 + .12 * Math.sin((x - .12) * Math.PI * 1.25);
  const slope = mobile ? .055 * Math.PI * 1.3 * Math.cos(x * Math.PI * 1.3) : .12 * Math.PI * 1.25 * Math.cos((x - .12) * Math.PI * 1.25);
  return { x: x * width, y: y * height, angle: Math.atan2(height * slope, width), size: width * (mobile ? .021 : .024) };
}

export function writeClipboardTilePose(out: ShelfPose, ribbonIndex: number, progress: number, layout: ShelfLayout, focus: number) {
  if (progress <= .875) return;
  if (ribbonIndex < 0) {
    if (out.y > layout.height) return;
    const leave = phase(progress, 1, 1.12);
    out.y -= layout.height * .28 * leave;
    out.sx *= 1 - leave;
    out.sy *= 1 - leave;
    return;
  }
  const point = clipboardRibbonPoint(ribbonIndex, layout.width, layout.height, focus, progress);
  const travel = ribbonTravel(ribbonIndex, progress);
  const join = phase(travel, 0, .24);
  out.x += (point.x - out.x) * join;
  out.y += (point.y - out.y) * join;
  out.z = -8 * Math.sin(join * Math.PI);
  out.rx = -.2 * join;
  out.ry = 0;
  out.rz = point.angle * join;
  out.sx += (point.size / 24 - out.sx) * join;
  out.sy += (point.size / 24 - out.sy) * join;
}
